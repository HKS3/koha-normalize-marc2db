# koha-normalize-marc2db
koha-plugin to normalize MARC21 data to database tables

# example SQL

select biblionumber, f.sequence field_order, s.sequence subfield_order, tag, indicator1, indicator2, code, value from nm2db_fields f join nm2db_subfields s on f.id = s.field_id where biblionumber = 11 order by tag;

select biblionumber, tag, indicator1, indicator2, code, value from nm2db_fields f join nm2db_subfields s on f.id = s.field_id where record_identifier = 11 order by tag;


# space ie storage requirements

SELECT  
(select count(*) from biblio) number_of_biblios,
table_name,     
ROUND(data_length / 1024 / 1024, 2) AS data_mb,     
ROUND(index_length / 1024 / 1024, 2) AS index_mb,     
ROUND((data_length + index_length) / 1024 / 1024, 2) AS total_mb FROM      
information_schema.tables WHERE 
(table_name LIKE 'nm2db%' or table_name = 'biblio_metadata') ORDER BY     
total_mb DESC

+-------------------+-----------------+---------+----------+----------+
| number_of_biblios | table_name      | data_mb | index_mb | total_mb |
+-------------------+-----------------+---------+----------+----------+
|             83609 | biblio_metadata |  193.70 |    10.09 |   203.80 |
|             83609 | nm2db_subfields |   79.61 |    69.19 |   148.80 |
|             83609 | nm2db_fields    |   45.58 |    40.09 |    85.67 |
+-------------------+-----------------+---------+----------+----------+

not surprisingly it uses about the same amount of space as biblio_metadata, although with the indices it uses more

create index nm2db_subfields_ind on nm2db_subfields(value);
create index nm2db_fields_ind on nm2db_fields (biblionumber, tag);

