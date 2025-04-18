# koha-normalize-marc2db
koha-plugin to normalize MARC21 data to database tables

# example SQL

select biblionumber, f.sequence field_order, s.sequence subfield_order, tag, indicator1, indicator2, code, value from nm2db_fields f join nm2db_subfields s on f.id = s.field_id where biblionumber = 11 order by tag;
