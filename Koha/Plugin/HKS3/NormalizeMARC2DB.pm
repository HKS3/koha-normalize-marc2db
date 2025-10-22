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

use Koha::Plugin::HKS3::NormalizeMARC2DB::Normalizer;
use Koha::Plugin::HKS3::NormalizeMARC2DB::Jobs::NormalizeAll;
use Koha::Plugin::HKS3::NormalizeMARC2DB::Jobs::UpdateChangedMetadata;
use Koha::Plugin::HKS3::NormalizeMARC2DB::Jobs::VerifyAll;

our $VERSION = "0.95";

our $metadata = {
    name            => 'Normalize MARC to DB',
    author          => 'Mark Hofstetter, Tadeusz Sosnierz',
    description     => 'Normalize MARC XML into Database tables',
    namespace       => 'marc2db',
    date_authored   => '2025-04-01',
    date_updated    => '2025-10-13',
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
                Koha::Plugin::HKS3::NormalizeMARC2DB::Jobs::NormalizeAll->new->enqueue()
            },
            NormalizeAllNoAuths => sub {
                Koha::Plugin::HKS3::NormalizeMARC2DB::Jobs::NormalizeAll->new->enqueue({
                    skip_authorities => 1,
                })
            },
            VerifyAll => sub {
                Koha::Plugin::HKS3::NormalizeMARC2DB::Jobs::VerifyAll->new->enqueue()
            },
            UpdateChangedMetadata => sub {
                Koha::Plugin::HKS3::NormalizeMARC2DB::Jobs::UpdateChangedMetadata->new->enqueue()
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

    C4::Context->dbh->do( "
    CREATE TABLE IF NOT EXISTS nm2db_records (
        id INT AUTO_INCREMENT PRIMARY KEY,
        changed BOOL default false,
        type enum('biblio', 'authority') default 'biblio',
        biblionumber int(11),
        authid BIGINT(20) unsigned,
        FOREIGN KEY (biblionumber) REFERENCES biblio(biblionumber) ON DELETE CASCADE,
        FOREIGN KEY (authid) REFERENCES auth_header(authid) ON DELETE CASCADE,
        CONSTRAINT UC_Biblio UNIQUE (biblionumber),
        CONSTRAINT UC_Auth UNIQUE (authid),
        CONSTRAINT CHK_Biblio_Or_Auth CHECK (biblionumber is null or authid is null),
        CONSTRAINT CHK_Biblio_Correct_Type CHECK (if(biblionumber is not null, type = 'biblio', true)),
        CONSTRAINT CHK_Auth_Correct_Type CHECK (if(authid is not null, type = 'authority', true))
    ); ");

    C4::Context->dbh->do( "
    CREATE TABLE IF NOT EXISTS nm2db_fields (
        id INT AUTO_INCREMENT PRIMARY KEY,
        record_id INT,
        tag CHAR(6) NOT NULL,
        indicator1 CHAR(1),
        indicator2 CHAR(1),
        sequence INT DEFAULT 0,
        FOREIGN KEY (record_id) REFERENCES nm2db_records(id) ON DELETE CASCADE
    ); ");

    C4::Context->dbh->do( "
    CREATE TABLE IF NOT EXISTS nm2db_subfields (
        id INT AUTO_INCREMENT PRIMARY KEY,
        field_id INT NOT NULL,
        code CHAR(1),
        value TEXT,
        sequence INT DEFAULT 0,
        FOREIGN KEY (field_id) REFERENCES nm2db_fields(id) ON DELETE CASCADE
    ); ");

    # MySQL Warning: Specified key was too long; max key length is 3072 bytes
    C4::Context->dbh->do("    
        create index nm2db_subfields_value_ind on nm2db_subfields(value);
    ");

    C4::Context->dbh->do("    
        create index nm2db_subfields_code_ind on nm2db_subfields(code);
    ");

    C4::Context->dbh->do("    
        create index nm2db_fields_tag_ind on nm2db_fields (tag);
    ");

    C4::Context->dbh->do("    
        create index nm2db_record_biblionumber_ind on nm2db_records (biblionumber);
    ");

    C4::Context->dbh->do("    
        create index nm2db_record_authid_ind on nm2db_records (authid);
    ");

    return 1;
}

sub uninstall {
    my ($self) = @_;
    my $dbh = C4::Context->dbh;
    $dbh->do("DROP TABLE IF EXISTS nm2db_subfields, nm2db_fields, nm2db_records");
    return 1;
}

sub after_biblio_action {
    my ($self, $params) = @_;

    my $action = $params->{action};
    my $biblio_id = $params->{biblio_id};

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
