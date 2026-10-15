package Koha::Plugin::HKS3::NormalizeMARC2DB;
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# This program comes with ABSOLUTELY NO WARRANTY;

use Modern::Perl;
use base qw(Koha::Plugins::Base);
use C4::Context;
use MARC::Record;
use MARC::Field;
use MARC::File::XML (BinaryEncoding => 'utf8');
use XML::Twig;

use Koha::Logger;

use Koha::Plugin::HKS3::NormalizeMARC2DB::Normalizer;
use Koha::Plugin::HKS3::NormalizeMARC2DB::Jobs::NormalizeAll;
use Koha::Plugin::HKS3::NormalizeMARC2DB::Jobs::UpdateChangedMetadata;
use Koha::Plugin::HKS3::NormalizeMARC2DB::Jobs::VerifyAll;

our $VERSION = "1.0.6";

our $metadata = {
    name            => 'Normalize MARC to DB',
    author          => 'Mark Hofstetter, Tadeusz Sosnierz',
    description     => 'Normalize MARC XML into Database tables',
    namespace       => 'marc2db',
    date_authored   => '2025-04-01',
    date_updated    => '2026-10-15',
    minimum_version => '23.11',
    maximum_version => undef,
    version         => $VERSION,
};

sub new {
    my ( $class, $args ) = @_;
    
    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    my $self = $class->SUPER::new($args);
    $self->{cgi} = CGI->new();

    return $self;
}

sub background_tasks {
    return {
        normalizeall => 'Koha::Plugin::HKS3::NormalizeMARC2DB::Jobs::NormalizeAll',
        verifyall => 'Koha::Plugin::HKS3::NormalizeMARC2DB::Jobs::VerifyAll',
        updatechangedmetadata => 'Koha::Plugin::HKS3::NormalizeMARC2DB::Jobs::UpdateChangedMetadata',
    };
}

sub template_include_paths {
    my ($self) = @_;
    return [
        $self->mbf_path('templates'),
    ];
}

sub tool {
    my ( $self ) = @_;
    my $cgi = CGI->new;
    my $dbh = C4::Context->dbh;

    if ($self->{cgi}->param('run') && $self->{cgi}->param('run') eq 'ResetForceNormalize') {
        $self->store_data({
	    force_normalize_phase         => 'biblio',
	    force_normalize_biblionumber  => 0,
	    force_normalize_authid        => 0,
        });
    } elsif ($self->{cgi}->param('run')) {

        my $limit = $self->{cgi}->param('limit');
        die 'Limit must be a positive integer'
            unless defined $limit && $limit =~ /\A[1-9]\d*\z/;

        my %normalize_args = (
            limit            => $limit,
            force            => $self->{cgi}->param('force') ? 1 : 0,
            skip_authorities => $self->{cgi}->param('skip_authorities') ? 1 : 0,
        );
        my %jobs = (
            NormalizeAll => sub {
                Koha::Plugin::HKS3::NormalizeMARC2DB::Jobs::NormalizeAll->new->enqueue(\%normalize_args)
            },
            NormalizeAllNoAuths => sub {
                Koha::Plugin::HKS3::NormalizeMARC2DB::Jobs::NormalizeAll->new->enqueue({
                    %normalize_args,
                    skip_authorities => 1,
                })
            },
            VerifyAll => sub {
                Koha::Plugin::HKS3::NormalizeMARC2DB::Jobs::VerifyAll->new->enqueue({})
            },
            UpdateChangedMetadata => sub {
                Koha::Plugin::HKS3::NormalizeMARC2DB::Jobs::UpdateChangedMetadata->new->enqueue({})
            },
            ViewChangedMetadata => sub {
                Koha::Plugin::HKS3::NormalizeMARC2DB::Jobs::UpdateChangedMetadata->new->enqueue({
                    dry_run => 1,
                })
            },
        );
        my $job = $jobs{$self->{cgi}->param('run')};
        if (!$job) {
            die "Invalid job name";
        }
        my $id = $job->();
        print $self->{cgi}->redirect("/cgi-bin/koha/admin/background_jobs.pl?op=view&id=$id");
    } 
    my $template = $self->get_template({ file => 'tool.tt' });

    $template->param(
        force_normalize_phase => $self->retrieve_data('force_normalize_phase') || 'biblio',
        force_normalize_biblionumber => $self->retrieve_data('force_normalize_biblionumber') || 0,
        force_normalize_authid => $self->retrieve_data('force_normalize_authid') || 0,
        lowest_unindexed_biblionumber => $self->retrieve_data('lowest_unindexed_biblionumber') || 0,
        lowest_unindexed_authid => $self->retrieve_data('lowest_unindexed_authid') || 0,
    );
    $self->output_html($template->output);

}

sub install {
    my ($self) = @_;

    use Try::Tiny;
    try {
        my @files = qw(sql/tables.sql sql/view.sql sql/change_queue.sql);
        for my $file (@files) {
            my @stmts = split "\n---\n", $self->mbf_read($file);
            C4::Context->dbh->do($_) for @stmts;
        }
    } catch {
        warn "Died: $_";
        die $_;
    };

    return 1;
}

sub upgrade {
    my ($self) = @_;

    my $dbh = C4::Context->dbh;
    local $dbh->{RaiseError} = 1;
    my ($locked) = $dbh->selectrow_array(
        q{SELECT GET_LOCK(CONCAT('nm2db_upgrade:', MD5(DATABASE())), 0)}
    );
    die 'Cannot upgrade NormalizeMARC2DB: another upgrade is running'
        unless $locked;

    my $success = eval { $self->_upgrade_schema($dbh); 1 };
    my $error = $@;
    my $released = eval {
        $dbh->selectrow_array(q{SELECT RELEASE_LOCK(CONCAT('nm2db_upgrade:', MD5(DATABASE())))});
        1;
    };
    die $error unless $success;
    die $@ unless $released;

    return 1;
}

sub _upgrade_schema {
    my ($self, $dbh) = @_;
    my @tables = qw(nm2db_records nm2db_fields nm2db_subfields);

    for my $table (@tables) {
        die "Cannot upgrade NormalizeMARC2DB: table $table is missing"
            unless _table_collation($dbh, $table);
    }

    # A legacy latin1 index prefix of 3072 bytes exceeds InnoDB's 3072-byte
    # limit after the value column is converted to utf8mb4. Drop it before
    # the conversion and recreate the current 768-character index afterwards.
    my ($value_index_exists, $value_index_prefix)
        = _index_prefix($dbh, 'nm2db_subfields', 'nm2db_subfields_value_ind');
    if ($value_index_exists && (!defined $value_index_prefix || $value_index_prefix != 768)) {
        $dbh->do('ALTER TABLE nm2db_subfields DROP INDEX nm2db_subfields_value_ind');
    }

    for my $table (@tables) {
        my ($legacy_columns) = $dbh->selectrow_array(
            q{SELECT COUNT(*) FROM information_schema.COLUMNS
              WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?
                AND COLLATION_NAME IS NOT NULL AND COLLATION_NAME <> 'utf8mb4_unicode_ci'},
            undef, $table,
        );
        next if _table_collation($dbh, $table) eq 'utf8mb4_unicode_ci' && !$legacy_columns;
        $dbh->do("ALTER TABLE $table CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci");
    }

    ($value_index_exists, $value_index_prefix)
        = _index_prefix($dbh, 'nm2db_subfields', 'nm2db_subfields_value_ind');
    if (!$value_index_exists || !defined $value_index_prefix || $value_index_prefix != 768) {
        $dbh->do('ALTER TABLE nm2db_subfields DROP INDEX nm2db_subfields_value_ind')
            if $value_index_exists;
        $dbh->do('ALTER TABLE nm2db_subfields ADD INDEX nm2db_subfields_value_ind (value(768))');
    }

    # Never use CREATE OR REPLACE TABLE here: it would discard queued edits.
    $dbh->do($self->mbf_read('sql/change_queue.sql'));

    if (($self->retrieve_data('schema_version') || '') ne '1.0.5') {
        my ($has_changed) = $dbh->selectrow_array(
            q{SELECT COUNT(*) FROM information_schema.COLUMNS
              WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'nm2db_records'
                AND COLUMN_NAME = 'changed'}
        );
        if ($has_changed) {
            $dbh->do(q{INSERT INTO nm2db_change_queue (record_id)
                       SELECT id FROM nm2db_records WHERE changed = 1
                       ON DUPLICATE KEY UPDATE record_id = VALUES(record_id)});
        }
        $dbh->do($self->mbf_read('sql/view.sql'));
    } else {
        my ($has_view) = $dbh->selectrow_array(
            q{SELECT COUNT(*) FROM information_schema.TABLES
              WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'nm2db_v_record'}
        );
        $dbh->do($self->mbf_read('sql/view.sql')) unless $has_view;
    }

    $self->store_data({ schema_version => '1.0.5' });

    return 1;
}

sub _table_collation {
    my ($dbh, $table) = @_;

    return $dbh->selectrow_array(
        q{
            SELECT TABLE_COLLATION
            FROM information_schema.TABLES
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = ?
        },
        undef,
        $table,
    );
}

sub _index_prefix {
    my ($dbh, $table, $index) = @_;

    my ($prefix, $exists) = $dbh->selectrow_array(
        q{
            SELECT SUB_PART, 1
            FROM information_schema.STATISTICS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = ?
              AND INDEX_NAME = ?
            ORDER BY SEQ_IN_INDEX
            LIMIT 1
        },
        undef,
        $table,
        $index,
    );

    return ($exists, $prefix);
}

sub uninstall {
    my ($self) = @_;
    C4::Context->dbh->do("DROP TABLE IF EXISTS nm2db_subfields, nm2db_fields, nm2db_records, nm2db_change_queue");
    C4::Context->dbh->do("DROP VIEW IF EXISTS nm2db_v_record");
    return 1;
}

sub after_biblio_action {
    my ($self, $params) = @_;

    my $action = $params->{action};
    my $biblio_id = $params->{payload}->{biblio_id};

    if ($action eq 'add' || $action eq 'modify' || $action eq 'create') {
        Koha::Plugin::HKS3::NormalizeMARC2DB::Normalizer->normalize_biblio($biblio_id);
    }

    return;
}

sub after_authority_action {
    my ($self, $params) = @_;

    my $action = $params->{action};
    my $authority_id = $params->{authority_id};

    if ($action eq 'add' || $action eq 'modify' || $action eq 'create') {
        Koha::Plugin::HKS3::NormalizeMARC2DB::Normalizer->normalize_authority($authority_id);
    }

    return;
}

1;
