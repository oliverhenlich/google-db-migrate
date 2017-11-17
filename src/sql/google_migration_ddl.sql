CREATE TABLE IF NOT EXISTS MIGRATION_STATUS (
  ID          BIGINT          NOT NULL AUTO_INCREMENT,
  SCHEMA_NAME VARCHAR(255)    NOT NULL,
  TABLE_NAME  VARCHAR(255)    NOT NULL,
  DUMPING     ENUM ('Y', 'N') NOT NULL DEFAULT 'N',
  DUMPED      ENUM ('Y', 'N') NOT NULL DEFAULT 'N',
  COMPRESSING ENUM ('Y', 'N') NOT NULL DEFAULT 'N',
  COMPRESSED  ENUM ('Y', 'N') NOT NULL DEFAULT 'N',
  UPLOADING   ENUM ('Y', 'N') NOT NULL DEFAULT 'N',
  UPLOADED    ENUM ('Y', 'N') NOT NULL DEFAULT 'N',
  IMPORTING   ENUM ('Y', 'N') NOT NULL DEFAULT 'N',
  IMPORTED    ENUM ('Y', 'N') NOT NULL DEFAULT 'N',
  ERROR       ENUM ('Y', 'N') NOT NULL DEFAULT 'N',
  ROWS        BIGINT          NOT NULL DEFAULT 0,
  PRIMARY KEY (ID),
  CONSTRAINT UK_table UNIQUE (SCHEMA_NAME, TABLE_NAME)
)
  ENGINE = InnoDB;

create index IDX_MIGRATION_STATUS_1 on MIGRATION_STATUS (SCHEMA_NAME, TABLE_NAME);


CREATE TABLE IF NOT EXISTS MIGRATION_LOG (
  ID          BIGINT       NOT NULL AUTO_INCREMENT,
  CREATED     DATETIME(6)  NOT NULL,
  SCHEMA_NAME VARCHAR(255) NOT NULL,
  TABLE_NAME  VARCHAR(255) NOT NULL,
  CATEGORY    VARCHAR(255) NOT NULL,
  ACTION      VARCHAR(255) NOT NULL,
  MESSAGE     VARCHAR(1000),
  PRIMARY KEY (ID),
  FOREIGN KEY (SCHEMA_NAME) REFERENCES MIGRATION_STATUS (SCHEMA_NAME)
)
  ENGINE = InnoDB;


create index IDX_MIGRATION_LOG_1 on MIGRATION_LOG (SCHEMA_NAME, TABLE_NAME);
create index IDX_MIGRATION_LOG_2 on MIGRATION_LOG (CATEGORY);
create index IDX_MIGRATION_LOG_3 on MIGRATION_LOG (ACTION);

