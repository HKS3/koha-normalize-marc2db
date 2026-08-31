CREATE OR REPLACE VIEW nm2db_v_record AS
SELECT
    r.id                    AS record_id,
    r.type                  AS record_type,    
    r.biblionumber          AS biblionumber,
    r.authid                AS authid,
    ah.authtypecode         AS authtypecode,
    f.id                    AS field_id,
    f.tag                   AS tag,
    f.indicator1            AS ind1,
    f.indicator2            AS ind2,
    f.sequence              AS field_seq,
    s.id                    AS subfield_id,
    s.code                  AS code,
    s.value                 AS value,
    s.sequence              AS subfield_seq
FROM nm2db_records r
LEFT JOIN biblio b
       ON b.biblionumber = r.biblionumber
LEFT JOIN auth_header ah
       ON ah.authid = r.authid
LEFT JOIN nm2db_fields f
       ON f.record_id = r.id
LEFT JOIN nm2db_subfields s
       ON s.field_id = f.id;
