package Koha::Plugin::HKS3::NormalizeMARC2DB;

use Modern::Perl;
use base qw(Koha::Plugins::Base);
use C4::Context;
use MARC::Record;
use MARC::File::XML (BinaryEncoding => 'utf8');

our $VERSION = "1.0";
our $metadata = {
    name            => 'Normalize MARC to DB',
    author          => 'Mark Hofstetter',
    description     => 'Normalize MARC XML into MySQL tables',
    date_authored   => '2025-04-01',
    date_updated    => '2025-04-01',
    minimum_version => '20.11',
    maximum_version => undef,
    version         => $VERSION,
};

sub install {
    my ($self) = @_;
    my $dbh = C4::Context->dbh;
    C4::Context->dbh->do( "
   CREATE TABLE IF NOT EXISTS nm2db_records (
    id INT AUTO_INCREMENT PRIMARY KEY,
    record_identifier VARCHAR(255),
    created TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ); ");

    C4::Context->dbh->do( "
    CREATE TABLE IF NOT EXISTS nm2db_fields (
        id INT AUTO_INCREMENT PRIMARY KEY,
        record_id INT NOT NULL,
        tag CHAR(3) NOT NULL,
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

    my $action = $params->{action};             # 'add', 'modify', 'delete'
    my $biblio_id = $params->{biblio_id};       # ID of the affected biblio

    # Trigger normalization only for add or modify actions
    if ($action eq 'add' || $action eq 'modify') {
        $self->normalize_biblio($biblio_id);
    }

    return;
}


sub normalize_biblio {
    my ($self, $biblionumber) = @_;
    my $dbh = C4::Context->dbh;

    my ($marcxml) = $dbh->selectrow_array("SELECT metadata FROM biblio_metadata WHERE biblionumber=?", undef, $biblionumber);
    return unless $marcxml;

    my $record = MARC::Record->new_from_xml($marcxml, 'UTF-8');
    # delete cascading
    $dbh->do("delete from nm2db_records where record_identifier = ?", undef, $biblionumber) ;
    $dbh->do("INSERT INTO nm2db_records (record_identifier) VALUES (?)", undef, $biblionumber);
    my $record_id = $dbh->{mysql_insertid};

    my $field_seq = 0;
    foreach my $field ($record->fields()) {
        $field_seq++;
        my ($tag, $ind1, $ind2) = ($field->tag, $field->indicator(1), $field->indicator(2));

        $dbh->do("INSERT INTO nm2db_fields (record_id, tag, indicator1, indicator2, sequence)
                  VALUES (?, ?, ?, ?, ?)",
                  undef, $record_id, $tag, $ind1, $ind2, $field_seq);
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

1;
