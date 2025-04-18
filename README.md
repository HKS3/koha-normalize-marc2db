# koha-normalize-marc2db
koha-plugin to normalize MARC21 data to database tables

This plugin (Koha::Plugin::HKS3::NormalizeMARC2DB) aims to normalize MARC21 XML metadata from the biblio_metadata.metadata table into structured MySQL database tables. Currently, MARC21 XML is stored as a single XML blob, making advanced querying, reporting, and integration difficult.

This plugin introduces an automatic normalization step triggered by the after_biblio_action hook whenever metadata is added or modified. It splits MARC XML into normalized relational tables fully supporting repeatable fields, subfields, and indicators.

Advantages:

Significantly simplifies complex querying and reporting of MARC21 data.

Enhances data integrity and consistency.

Facilitates integration with external reporting tools, analytics, and applications.

Improves database performance for MARC metadata queries.

Provides clear and structured access to MARC data elements.

This approach aligns with best practices for database normalization and can substantially enhance Koha's extensibility and interoperability.

see https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=39557

# example SQL

select biblionumber, f.sequence field_order, s.sequence subfield_order, tag, indicator1, indicator2, code, value from nm2db_fields f join nm2db_subfields s on f.id = s.field_id where biblionumber = 11 order by tag;

# disk space ie storage requirements

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

