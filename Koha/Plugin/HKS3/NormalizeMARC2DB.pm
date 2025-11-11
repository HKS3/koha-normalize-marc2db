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

our $VERSION = "0.98";

our $metadata = {
    name            => 'Normalize MARC to DB',
    author          => 'Mark Hofstetter, Tadeusz Sosnierz',
    description     => 'Normalize MARC XML into Database tables',
    namespace       => 'marc2db',
    date_authored   => '2025-04-01',
    date_updated    => '2025-10-28',
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

    if ($self->{cgi}->param('run')) {
        my %jobs = (
            NormalizeAll => sub {
                Koha::Plugin::HKS3::NormalizeMARC2DB::Jobs::NormalizeAll->new->enqueue({})
            },
            NormalizeAllNoAuths => sub {
                Koha::Plugin::HKS3::NormalizeMARC2DB::Jobs::NormalizeAll->new->enqueue({
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
    } else {
        my $template = $self->get_template({ file => 'tool.tt' });
        $self->output_html($template->output);
    }
}

sub install {
    my ($self) = @_;

    use Try::Tiny;
    try {
        my @files = qw(sql/tables.sql sql/view-trigger.sql);
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
    use Data::Dumper;
    Koha::Logger->get->warn($action);
     Koha::Logger->get->warn($biblio_id);

    if ($action eq 'add' || $action eq 'modify' || $action eq 'create') {
        Koha::Plugin::HKS3::NormalizeMARC2DB::Normalizer->normalize_biblio($biblio_id);
    } elsif ($action eq 'delete') {
        $self->delete_normalized_biblio($biblio_id);
    }

    return;
}

sub after_authority_action {
    my ($self, $params) = @_;

    my $action = $params->{action};
    my $authority_id = $params->{authority_id};

    if ($action eq 'add' || $action eq 'modify' || $action eq 'create') {
        Koha::Plugin::HKS3::NormalizeMARC2DB::Normalizer->normalize_authority($authority_id);
    } elsif ($action eq 'delete') {
        $self->delete_normalized_authority($authority_id);
    }

    return;
}

sub delete_normalized_biblio {
    my ($self, $biblionumber) = @_;
    my $dbh = C4::Context->dbh;
    $dbh->do("delete from nm2db_fields where biblionumber= ?", undef, $biblionumber);
}

1;
