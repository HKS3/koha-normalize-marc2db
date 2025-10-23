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

---
CREATE or replace TABLE nm2db_change_queue (
  record_id INT PRIMARY KEY,
  last_modified TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
---
CREATE OR REPLACE PROCEDURE nm2db_enqueue_change(p_record_id INT)
BEGIN
  IF p_record_id IS NOT NULL THEN
    INSERT IGNORE INTO nm2db_change_queue (record_id)
    VALUES (p_record_id);
  END IF;
END
---
CREATE OR REPLACE TRIGGER nm2db_fields_ai
AFTER INSERT ON nm2db_fields
FOR EACH ROW
BEGIN
  CALL nm2db_enqueue_change(NEW.record_id);
END
---
CREATE OR REPLACE TRIGGER nm2db_fields_au
AFTER UPDATE ON nm2db_fields
FOR EACH ROW
BEGIN
  CALL nm2db_enqueue_change(NEW.record_id);
END
---
CREATE OR REPLACE TRIGGER nm2db_fields_ad
AFTER DELETE ON nm2db_fields
FOR EACH ROW
BEGIN
  CALL nm2db_enqueue_change(OLD.record_id);
END
---
CREATE OR REPLACE TRIGGER nm2db_fields_ai
AFTER INSERT ON nm2db_fields
FOR EACH ROW
BEGIN
  CALL nm2db_enqueue_change(NEW.record_id);
END
---
CREATE OR REPLACE TRIGGER nm2db_fields_au
AFTER UPDATE ON nm2db_fields
FOR EACH ROW
BEGIN
  CALL nm2db_enqueue_change(NEW.record_id);
END
---
CREATE OR REPLACE TRIGGER nm2db_fields_ad
AFTER DELETE ON nm2db_fields
FOR EACH ROW
BEGIN
  CALL nm2db_enqueue_change(OLD.record_id);
END
---
CREATE OR REPLACE TRIGGER nm2db_subfields_ai
AFTER INSERT ON nm2db_subfields
FOR EACH ROW
BEGIN
  DECLARE v_record_id INT;

  SELECT record_id
    INTO v_record_id
    FROM nm2db_fields
   WHERE id = NEW.field_id;

  CALL nm2db_enqueue_change(v_record_id);
END
---
CREATE OR REPLACE TRIGGER nm2db_subfields_au
AFTER UPDATE ON nm2db_subfields
FOR EACH ROW
BEGIN
  DECLARE v_record_id INT;

  SELECT record_id
    INTO v_record_id
    FROM nm2db_fields
   WHERE id = NEW.field_id;

  CALL nm2db_enqueue_change(v_record_id);
END
---
CREATE OR REPLACE TRIGGER nm2db_subfields_ad
AFTER DELETE ON nm2db_subfields
FOR EACH ROW
BEGIN
  DECLARE v_record_id INT;

  SELECT record_id
    INTO v_record_id
    FROM nm2db_fields
   WHERE id = OLD.field_id;

  CALL nm2db_enqueue_change(v_record_id);
END
