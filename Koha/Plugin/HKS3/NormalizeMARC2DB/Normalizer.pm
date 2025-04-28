package Koha::Plugin::HKS3::NormalizeMARC2DB::Normalizer;
use Modern::Perl;
use MARC::Record;

use C4::Context;

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

1;
