# koha-normalize-marc2db
koha-plugin to normalize MARC21 data to database tables

This plugin (Koha::Plugin::HKS3::NormalizeMARC2DB) aims to normalize MARC21 XML metadata from the biblio_metadata.metadata amd auth_header.marcxml columns into structured MySQL database tables. Currently, MARC21 XML is stored as a single XML blob, making advanced querying, reporting, and integration difficult.

This plugin introduces an automatic normalization step triggered by the after_biblio_action and after_auth_action and after_authority_action hooks whenever metadata is added or modified. It splits MARC XML into normalized relational tables fully supporting repeatable fields, subfields, and indicators.

Advantages:

Significantly simplifies complex querying and reporting of MARC21 data.

Enhances data integrity and consistency.

Facilitates integration with external reporting tools, analytics, and applications.

Improves database performance for MARC metadata queries.

Provides clear and structured access to MARC data elements.

This approach aligns with best practices for database normalization and can substantially enhance Koha's extensibility and interoperability.

see https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=39557

# Installation and usage

please download the koha plugin as kpz here https://github.com/HKS3/koha-normalize-marc2db/tags use the latest version

after installing an enabling the plugin you may have to restart koha (depening on you version and settings)

after installing you have to run the plugin tool ONCE to normalize all biblio and authority data to the tables. Go to the Plugins page and under Action choose "Run Tool"

![image](https://github.com/user-attachments/assets/61503e27-c615-4e2b-beaa-b5e4ef029591)

this may take quite a long time if you have many records, but only needs to be done once.

# example SQL (using ktd)

Get all Field + Subfields of a given biblionumber

```
select r.biblionumber, f.sequence field_order, s.sequence subfield_order, tag, indicator1, indicator2, code, value from nm2db_fields f
    join nm2db_subfields s on f.id = s.field_id
    join nm2db_records r on r.id = f.record_id
    where r.biblionumber = 11 order by tag
;
```

(part) of the result

```
+---------+-----------+--------+------------+------------+------+--------------------------------+
| f_order | sub_order | tag    | indicator1 | indicator2 | code | substr(value,1,30)             |
+---------+-----------+--------+------------+------------+------+--------------------------------+
|       1 |         1 | 001    | NULL       | NULL       |      | 12011929                       |
|       2 |         1 | 005    | NULL       | NULL       |      | 20200421093816.0               |
|       3 |         1 | 008    | NULL       | NULL       |      | 000518s2000    ch a     b    0 |
|       4 |         1 | 010    |            |            | a    |    00041664                    |
|       5 |         1 | 020    |            |            | a    | 1565924193                     |
|       6 |         1 | 040    |            |            | a    | DLC                            |
...
|      12 |         1 | 250    |            |            | a    | 2nd ed.                        |
|      13 |         1 | 260    |            |            | a    | Beijing ;                      |
|      13 |         2 | 260    |            |            | a    | Cambridge, Mass. :             |
|      13 |         3 | 260    |            |            | b    | O'Reilly,                      |
|      13 |         4 | 260    |            |            | c    | 2000.                          |
|      14 |         1 | 300    |            |            | a    | xv, 451 p.                     |
|      14 |         2 | 300    |            |            | b    | ill.                           |
|      14 |         3 | 300    |            |            | c    | 24 cm.                         |
|      15 |         1 | 504    |            |            | a    | Includes bibliographical refer |
|      16 |         1 | 650    |            | 0          | a    | Perl (Computer program languag |
```
but you could also do things which would be rather hard with xpath, for example give me the 10 bibliorecords with the most fields
```
select r.biblionumber, count(*) c from nm2db_fields f
    join nm2db_subfields s on f.id = s.field_id
    join nm2db_records r on r.id = f.record_id
    group by record_id order by c desc limit 10
;
+--------------+-----+
| biblionumber | c   |
+--------------+-----+
|          248 | 189 |
|          188 | 183 |
|          235 | 163 |
|          233 | 152 |
|          208 | 145 |
|          247 | 140 |
|          209 | 126 |
|           48 | 124 |
|          169 | 119 |
|          174 | 117 |
+--------------+-----+
```
or get the 10 (via 440a) most referenced Series
```
MariaDB [koha_kohadev]> select value, count(*) c from nm2db_fields f join nm2db_subfields s on f.id = s.field_id where tag = '440' and code = 'a' group by value order by c desc limit 10;
+----------------------------------------------------+---+
| value                                              | c |
+----------------------------------------------------+---+
| Penguin classics                                   | 6 |
| Loeb classical library ;                           | 3 |
| Scriptorum classicorum bibliotheca Oxoniensis      | 3 |
| Cambridge Greek and Latin classics                 | 2 |
| Oxford world's classics                            | 2 |
| Directors' Cuts                                    | 2 |
| SUNY series in contemporary continental philosophy | 1 |
| Classic commentaries on Greek and Latin texts      | 1 |
| Maynooth medieval Irish texts,                     | 1 |
| Pitt Press series                                  | 1 |
+----------------------------------------------------+---+
10 rows in set (0.002 sec)
```


# disk space ie storage requirements
```
SELECT  
(select count(*) from biblio) number_of_biblios,
table_name,     
ROUND(data_length / 1024 / 1024, 2) AS data_mb,     
ROUND(index_length / 1024 / 1024, 2) AS index_mb,     
ROUND((data_length + index_length) / 1024 / 1024, 2) AS total_mb FROM      
information_schema.tables WHERE 
(table_name LIKE 'nm2db%' or table_name = 'biblio_metadata') ORDER BY     
total_mb DESC
```

```
+-------------------+-----------------+---------+----------+----------+
| number_of_biblios | table_name      | data_mb | index_mb | total_mb |
+-------------------+-----------------+---------+----------+----------+
|             83609 | biblio_metadata |  193.70 |    10.09 |   203.80 |
|             83609 | nm2db_subfields |   79.61 |    69.19 |   148.80 |
|             83609 | nm2db_fields    |   45.58 |    40.09 |    85.67 |
+-------------------+-----------------+---------+----------+----------+
```
not surprisingly it uses about the same amount of space as biblio_metadata
```
create index nm2db_subfields_ind on nm2db_subfields(value);
create index nm2db_fields_ind on nm2db_fields (biblionumber, tag);
```
