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
use Try::Tiny qw(catch try);
use MARC::Record;
use MARC::Field;
use MARC::File::XML (BinaryEncoding => 'utf8');
use XML::Twig;

our $VERSION = "0.10";

our $metadata = {
    name            => 'Normalize MARC to DB',
    author          => 'Mark Hofstetter',
    description     => 'Normalize MARC XML into MySQL tables',
    date_authored   => '2025-04-01',
    date_updated    => '2025-04-18',
    minimum_version => '23.11',
    maximum_version => undef,
    version         => $VERSION,
    # Job to process all biblio records
    jobs            => [
        {
            name        => 'Normalize all MARC biblio',
            module      => __PACKAGE__,
            function    => 'job_normalize_all',
            description => 'Regenerate normalized MARC data for all biblios',
        },
    ],
};

sub new {
    my ( $class, $args ) = @_;
    
    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    my $self = $class->SUPER::new($args);
    $self->{cgi} = CGI->new();

    return $self;
}

sub install {
    my ($self) = @_;

    C4::Context->dbh->do( "
    CREATE TABLE IF NOT EXISTS nm2db_fields (
        id INT AUTO_INCREMENT PRIMARY KEY,
        biblionumber INT NOT NULL,        
        tag CHAR(6) NOT NULL,
        indicator1 CHAR(1),
        indicator2 CHAR(1),
        sequence INT DEFAULT 0,
        FOREIGN KEY (biblionumber) REFERENCES biblio(biblionumber) ON DELETE CASCADE
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

    C4::Context->dbh->do("    
        create index nm2db_subfields_ind on nm2db_subfields(value);
    ");

    C4::Context->dbh->do("    
        create index nm2db_fields_ind on nm2db_fields (biblionumber, tag);
    ");

    return 1;
}

sub uninstall {
    my ($self) = @_;
    my $dbh = C4::Context->dbh;
    $dbh->do("DROP TABLE IF EXISTS nm2db_subfields, nm2db_fields");
    return 1;
}


sub after_biblio_action {
    my ($self, $params) = @_;

    my $action = $params->{action};
    my $biblio_id = $params->{biblio_id};

    if ($action eq 'add' || $action eq 'modify' || $action eq 'create') {
        $self->normalize_biblio($biblio_id);
    } elsif ($action eq 'delete') {
        $self->delete_normalized_biblio($biblio_id);
    }

    return;
}

sub delete_normalized_biblio {
    my ($self, $biblionumber) = @_;
    my $dbh = C4::Context->dbh;
    $dbh->do("delete from nm2db_fields where biblionumber= ?", undef, $biblionumber);
}

sub normalize_biblio {
    my ($self, $biblionumber) = @_;
    my $dbh = C4::Context->dbh;

    my ($marcxml) = $dbh->selectrow_array("SELECT metadata FROM biblio_metadata WHERE biblionumber=?", undef, $biblionumber);
    return unless $marcxml;

    my $record;
    eval {
        $record = MARC::Record->new_from_xml($marcxml, 'UTF-8');    
    };
    
    return unless $record;

    # delete cascading
    $dbh->do("delete from nm2db_fields where biblionumber= ?", undef, $biblionumber) ;

    $dbh->do("INSERT INTO nm2db_fields (biblionumber, tag, indicator1, indicator2, sequence)
            VALUES (?, ?, ?, ?, ?)",
            undef, $biblionumber, 'leader', undef, undef, 0);
    my $field_id = $dbh->{mysql_insertid};

    $dbh->do("INSERT INTO nm2db_subfields (field_id, code, value, sequence)
                VALUES (?, ?, ?, ?)",
                undef, $field_id, '', $record->leader(), 1);

    my $field_seq = 0;
    
    foreach my $field ($record->fields()) {
        $field_seq++;
        my ($tag, $ind1, $ind2) = ($field->tag, $field->indicator(1), $field->indicator(2));

        $dbh->do("INSERT INTO nm2db_fields (biblionumber, tag, indicator1, indicator2, sequence)
                VALUES (?, ?, ?, ?, ?)",
                undef, $biblionumber, $tag, $ind1, $ind2, $field_seq);
        my $field_id = $dbh->{mysql_insertid};

        my $subfield_seq = 0;
        if ($field->is_control_field()) {
            $dbh->do("INSERT INTO nm2db_subfields (field_id, code, value, sequence)
                    VALUES (?, ?, ?, ?)",
                    undef, $field_id, '', $field->data(), 1);
        } else {
            foreach my $subfield ($field->subfields()) {
                $subfield_seq++;
                my ($code, $value) = @$subfield;
                $dbh->do("INSERT INTO nm2db_subfields (field_id, code, value, sequence)
                        VALUES (?, ?, ?, ?)",
                        undef, $field_id, $code, $value, $subfield_seq);
            }
        }
    }

    return 1;
}


sub generate_marcxml {
    my ($self, $biblionumber) = @_;
    my $dbh = C4::Context->dbh;
    my $record = MARC::Record->new();

    my $fields_sth = $dbh->prepare(
        "SELECT id, tag, indicator1, indicator2 FROM nm2db_fields
         WHERE biblionumber = ?
         ORDER BY sequence"
    );
    $fields_sth->execute($biblionumber);

    while (my $f = $fields_sth->fetchrow_hashref) {
        my $field_id = $f->{id};
        my $tag      = $f->{tag};
        my $ind1     = defined $f->{indicator1} ? $f->{indicator1} : ' ';
        my $ind2     = defined $f->{indicator2} ? $f->{indicator2} : ' ';

        if ( $tag eq 'leader' || $tag < '010' ) {
            
            # control field
            my ($value) = $dbh->selectrow_array(
                "SELECT value FROM nm2db_subfields
                 WHERE field_id = ? AND sequence = 1",
                undef, $field_id
            );            
            
            if ($tag eq 'leader') {
                $record->leader($value);
            } else {
                $record->append_fields(MARC::Field->new($tag, $value));
            }
        } else {
            # data field
            my $subf_sth = $dbh->prepare(
                "SELECT code, value FROM nm2db_subfields
                 WHERE field_id = ?
                 ORDER BY sequence"
            );
            $subf_sth->execute($field_id);
            my @subfields;
            while (my ($code, $value) = $subf_sth->fetchrow_array) {
                push @subfields, $code => $value;
            }
            $record->append_fields(
                MARC::Field->new($tag, $ind1, $ind2, @subfields)
            );
        }
    }

    return $record->as_xml_record;
}

# Job to normalize all existing biblio records
sub job_normalize_all {
    my ($self) = @_;
    my $dbh = C4::Context->dbh;
    my $sth = $dbh->prepare("SELECT biblionumber FROM biblio");
    $sth->execute;
    while (my ($biblionumber) = $sth->fetchrow_array) {
        try {
            $self->normalize_biblio($biblionumber);
        }
        catch {
            warn "Error normalizing biblionumber $biblionumber: $_";
        };
    }
    return 1;
}

1;
