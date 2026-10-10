CREATE TABLE IF NOT EXISTS nm2db_records (
    id INT AUTO_INCREMENT PRIMARY KEY,
    type enum('biblio', 'authority') default 'biblio',
    biblionumber int(11),
    authid BIGINT(20) unsigned,
    FOREIGN KEY (biblionumber) REFERENCES biblio(biblionumber) ON DELETE CASCADE,
    FOREIGN KEY (authid) REFERENCES auth_header(authid) ON DELETE CASCADE,
    CONSTRAINT UC_Biblio UNIQUE (biblionumber),
    CONSTRAINT UC_Auth UNIQUE (authid),
    CONSTRAINT CHK_Biblio_Or_Auth CHECK (biblionumber is null or authid is null),
    CONSTRAINT CHK_Biblio_Correct_Type CHECK (if(biblionumber is not null, type = 'biblio', true)),
    CONSTRAINT CHK_Auth_Correct_Type CHECK (if(authid is not null, type = 'authority', true))
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
---
CREATE TABLE IF NOT EXISTS nm2db_fields (
    id INT AUTO_INCREMENT PRIMARY KEY,
    record_id INT,
    tag CHAR(6) NOT NULL,
    indicator1 CHAR(1),
    indicator2 CHAR(1),
    sequence INT DEFAULT 0,
    FOREIGN KEY (record_id) REFERENCES nm2db_records(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
---
CREATE TABLE IF NOT EXISTS nm2db_subfields (
    id INT AUTO_INCREMENT PRIMARY KEY,
    field_id INT NOT NULL,
    code CHAR(1),
    value TEXT,
    sequence INT DEFAULT 0,
    FOREIGN KEY (field_id) REFERENCES nm2db_fields(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
---
-- Keep the index within InnoDB's 3072-byte key limit for utf8mb4.
create index nm2db_subfields_value_ind on nm2db_subfields(value(768));
---
create index nm2db_subfields_code_ind on nm2db_subfields(code);
---
create index nm2db_fields_tag_ind on nm2db_fields (tag);
---
create index nm2db_record_biblionumber_ind on nm2db_records (biblionumber);
---
create index nm2db_record_authid_ind on nm2db_records (authid);
