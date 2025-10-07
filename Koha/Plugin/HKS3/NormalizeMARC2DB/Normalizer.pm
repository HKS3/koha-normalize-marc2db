package Koha::Plugin::HKS3::NormalizeMARC2DB::Normalizer;
use Modern::Perl;
use MARC::Record;

use C4::Context;

sub normalize_authority {
    my ($self, $authid) = @_;
    my $dbh = C4::Context->dbh;

    my ($marcxml) = $dbh->selectrow_array("SELECT marcxml FROM auth_header WHERE authid=?", undef, $authid);
    return unless $marcxml;

    my $record;
    eval {
        $record = MARC::Record->new_from_xml($marcxml, 'UTF-8');
    };

    return unless $record;

    # ensure we have a record entry
    $dbh->do('insert into nm2db_records (authid, type) values (?, "authority") on duplicate key update changed = false', undef, $authid);
    my ($record_id) = $dbh->selectrow_array('select id from nm2db_records where authid = ?', undef, $authid);

    return $self->normalize_record($record_id, $record);
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

    # ensure we have a record entry
    $dbh->do('insert into nm2db_records (biblionumber) values (?) on duplicate key update changed = false', undef, $biblionumber);
    my ($record_id) = $dbh->selectrow_array('select id from nm2db_records where biblionumber = ?', undef, $biblionumber);

    return $self->normalize_record($record_id, $record);
}

sub normalize_record {
    my ($self, $record_id, $record) = @_;
    my $dbh = C4::Context->dbh;
    $dbh->begin_work();

    # delete cascading
    $dbh->do("delete from nm2db_fields where record_id = ?", undef, $record_id);

    my $insert_into_fields_sth = $dbh->prepare(
        "INSERT INTO nm2db_fields (record_id, tag, indicator1, indicator2, sequence) VALUES (?, ?, ?, ?, ?)"
    );
    $insert_into_fields_sth->execute($record_id, 'leader', undef, undef, 0);
    my $field_id = $dbh->{mysql_insertid};

    my $insert_into_subfields_sth = $dbh->prepare(
        "INSERT INTO nm2db_subfields (field_id, code, value, sequence) VALUES (?, ?, ?, ?)"
    );
    $insert_into_subfields_sth->execute($field_id, '', $record->leader(), 1);

    my $field_seq = 0;
    
    foreach my $field ($record->fields()) {
        $field_seq++;
        my ($tag, $ind1, $ind2) = ($field->tag, $field->indicator(1), $field->indicator(2));

        $insert_into_fields_sth->execute($record_id, $tag, $ind1, $ind2, $field_seq);
        my $field_id = $dbh->{mysql_insertid};

        my $subfield_seq = 0;
        if ($field->is_control_field()) {
            $insert_into_subfields_sth->execute($field_id, '', $field->data(), 1);
        } else {
            foreach my $subfield ($field->subfields()) {
                $subfield_seq++;
                my ($code, $value) = @$subfield;
                $insert_into_subfields_sth->execute($field_id, $code, $value, $subfield_seq);
            }
        }
    }
    $dbh->commit();

    return 1;
}

sub generate_marcxml {
    my ($self, $record_id) = @_;
    my $dbh = C4::Context->dbh;
    my $record = MARC::Record->new();

    my $fields_sth = $dbh->prepare(
        "SELECT id, tag, indicator1, indicator2 FROM nm2db_fields
         WHERE record_id = ?
         ORDER BY sequence"
    );
    $fields_sth->execute($record_id);

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

1;
