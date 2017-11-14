# noinspection SqlResolveForFile

--
-- Various queries to report on progress and status
--

-- Total time taken by category
SELECT
  schema_name,
  category,
  count(*)                        AS table_count,
  sum(seconds_taken)              AS total_seconds,
  sec_to_time(sum(seconds_taken)) AS total_time
FROM LOG_TABLE_CATEGORY_SUMMARY
GROUP BY schema_name, category;

-- Total rows to import
SELECT
  schema_name,
  sum(rows)
FROM MIGRATION_STATUS
GROUP BY schema_name;

-- Total rows imported
SELECT
  v.schema_name,
  sum(s.rows)
FROM LOG_TABLE_CATEGORY_SUMMARY v
  INNER JOIN MIGRATION_STATUS s
    ON s.schema_name = v.schema_name AND s.table_name = v.table_name
WHERE v.category = 'IMPORT_DATA'
GROUP BY v.schema_name;

-- Time taken for importing so far
SELECT
  ss.schema_name,
  ss.table_name,
  ss.seconds_taken,
  s.rows,
  (ss.seconds_taken / s.rows)
FROM LOG_TABLE_CATEGORY_SUMMARY ss
  INNER JOIN MIGRATION_STATUS s
    ON s.schema_name = ss.schema_name AND s.table_name = ss.table_name
WHERE ss.category = 'IMPORT_DATA'
ORDER BY ss.seconds_taken;

-- Records remaining to be imported and an estimate of how long it will take
SELECT
  status.schema_name,
  count(*)                                                                      AS remaining_tables,
  format(sum(status.rows), 0)                                                   AS remaining_rows,
  format(imported_summary.imported_rows, 0)                                     AS imported_rows,
--   format((sum(status.rows) / imported_summary.imported_avg_rows_per_second), 0) AS seconds_remaining,
--   sec_to_time(sum(status.rows) / imported_summary.imported_avg_rows_per_second) AS time_remaining,
  format((count(*) * imported_avg_seconds), 0)                                   AS seconds_remaining,
       sec_to_time((count(*) * imported_avg_seconds))                        AS time_remaining,
  sec_to_time(imported_summary.imported_seconds)                                AS imported_time,
  format(imported_avg_seconds, 2)                                               AS imported_avg_seconds_per_table,
  format(imported_avg_rows_per_second, 2)                                       AS imported_avg_rows_per_second,
  (select s2.TABLE_NAME from MIGRATION_STATUS s2 where s2.schema_name = status.schema_name and s2.IMPORTING = 'Y' order by id limit 1) as currently_importing
FROM (
       SELECT
         ss.schema_name                      AS imported_schema,
         sum(s.rows)                         AS imported_rows,
         sum(ss.seconds_taken)               AS imported_seconds,
         sec_to_time(sum(seconds_taken))     AS imported_time,
         avg(ss.seconds_taken)               AS imported_avg_seconds,
         sum(s.rows) / sum(ss.seconds_taken) AS imported_avg_rows_per_second
       FROM LOG_TABLE_CATEGORY_SUMMARY ss
         INNER JOIN MIGRATION_STATUS s
           ON s.schema_name = ss.schema_name AND s.table_name = ss.table_name
       GROUP BY ss.schema_name, ss.CATEGORY
       HAVING ss.category = 'IMPORT_DATA'
     ) AS imported_summary
  INNER JOIN MIGRATION_STATUS status ON imported_summary.imported_schema = status.schema_name
WHERE status.imported = 'N'
GROUP BY status.schema_name;

-- Total records already imported
SELECT
  ss.schema_name,
  sum(s.rows)                         AS rows_imported,
  sum(ss.seconds_taken)               AS imported_seconds,
  sec_to_time(sum(seconds_taken))     AS imported_time,
  avg(ss.seconds_taken)               AS imported_avg_seconds,
  sum(s.rows) / sum(ss.seconds_taken) AS imported_avg_rows_per_second
FROM LOG_TABLE_CATEGORY_SUMMARY ss
  INNER JOIN MIGRATION_STATUS s
    ON s.schema_name = ss.schema_name AND s.table_name = ss.table_name
GROUP BY ss.schema_name, ss.category
HAVING ss.category = 'IMPORT_DATA';

-- Group by start/end pairs (only those with table names)
CREATE OR REPLACE VIEW LOG_TABLE_CATEGORY_SUMMARY AS
  SELECT
    start_log.schema_name,
    start_log.TABLE_NAME,
    start_log.CATEGORY,
    start_log.CREATED                                         AS start_time,
    end_log.CREATED                                           AS end_time,
    TIMESTAMPDIFF(SECOND, start_log.CREATED, end_log.CREATED) AS seconds_taken,
    TIMEDIFF(end_log.CREATED, start_log.CREATED)              AS time_taken
  FROM
    MIGRATION_LOG AS start_log
    INNER JOIN MIGRATION_LOG AS end_log ON (
    start_log.SCHEMA_NAME = end_log.SCHEMA_NAME
    AND start_log.TABLE_NAME = end_log.TABLE_NAME
    AND start_log.CATEGORY = end_log.CATEGORY
    AND end_log.CREATED >= start_log.CREATED)
  WHERE start_log.ACTION = 'START' AND end_log.ACTION = 'END'
        AND trim(start_log.TABLE_NAME) != "" AND trim(end_log.TABLE_NAME) != ""
  GROUP BY start_log.schema_name, start_log.TABLE_NAME, start_log.CATEGORY
  ORDER BY start_log.CREATED;

-- Group by start/end pairs (all pairs)
CREATE OR REPLACE VIEW LOG_NOTABLE_CATEGORY_SUMMARY AS
  SELECT
    start_log.schema_name,
    start_log.TABLE_NAME,
    start_log.CATEGORY,
    start_log.CREATED                                         AS start_time,
    end_log.CREATED                                           AS end_time,
    TIMESTAMPDIFF(SECOND, start_log.CREATED, end_log.CREATED) AS seconds_taken,
    TIMEDIFF(end_log.CREATED, start_log.CREATED)              AS time_taken
  FROM
    MIGRATION_LOG AS start_log
    INNER JOIN MIGRATION_LOG AS end_log ON (
    start_log.SCHEMA_NAME = end_log.SCHEMA_NAME
    AND start_log.TABLE_NAME = end_log.TABLE_NAME
    AND start_log.CATEGORY = end_log.CATEGORY
    AND end_log.CREATED >= start_log.CREATED)
  WHERE start_log.ACTION = 'START' AND end_log.ACTION = 'END'
        AND trim(start_log.TABLE_NAME) = "" AND trim(end_log.TABLE_NAME) = ""
  GROUP BY start_log.schema_name, start_log.TABLE_NAME, start_log.CATEGORY
  ORDER BY start_log.CREATED;