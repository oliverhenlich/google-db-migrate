# noinspection SqlResolveForFile

--
-- Various queries to report on progress and status
--

-- Total time taken by category
select  schema_name, category, count(*) as table_count, sum(seconds_taken) as total_seconds, sec_to_time(sum(seconds_taken)) as total_time from log_table_category_summary group by schema_name, category;

-- Total rows to import
select schema_name, sum(rows) from MIGRATION_STATUS group by schema_name;

-- Total rows imported
select v.schema_name, sum(s.rows) from log_table_category_summary v inner join migration_status s on s.schema_name=v.schema_name and s.table_name=v.table_name where v.category='IMPORT_DATA' group by v.schema_name

-- % imported
select s1.schema_name,
        sum(s1.rows) as rows,
        (select sum(s.rows) from log_table_category_summary v inner join migration_status s on s.schema_name=v.schema_name and s.table_name=v.table_name where v.category='IMPORT' and v.schema_name=s1.schema_name group by v.schema_name) as rows_imported,
        ((sum(s1.rows)-(select sum(s.rows) from log_table_category_summary v inner join migration_status s on s.schema_name=v.schema_name and s.table_name=v.table_name where v.category='IMPORT' and v.schema_name=s1.schema_name group by v.schema_name))/sum(s1.rows)*100) as rows_imported_percent
from MIGRATION_STATUS s1
group by s1.schema_name;


-- Group by start/end pairs (only those with table names)
CREATE or replace VIEW log_table_category_summary as
SELECT
    start_log.schema_name,
    start_log.TABLE_NAME,
    start_log.CATEGORY,
    start_log.CREATED AS start_time,
    end_log.CREATED AS end_time,
    TIMESTAMPDIFF(SECOND, start_log.CREATED,  end_log.CREATED) as seconds_taken,
    TIMEDIFF(end_log.CREATED, start_log.CREATED) as time_taken
FROM
    MIGRATION_LOG AS start_log
INNER JOIN MIGRATION_LOG AS end_log ON (
            start_log.SCHEMA_NAME = end_log.SCHEMA_NAME
            and start_log.TABLE_NAME = end_log.TABLE_NAME
            and start_log.CATEGORY = end_log.CATEGORY
            AND end_log.CREATED >= start_log.CREATED)
WHERE start_log.ACTION = 'START' AND end_log.ACTION = 'END'
AND trim(start_log.TABLE_NAME) != "" AND trim(end_log.TABLE_NAME)  != ""
GROUP BY start_log.schema_name, start_log.TABLE_NAME, start_log.CATEGORY
order by start_log.CREATED;

-- Group by start/end pairs (all pairs)
CREATE or replace VIEW log_notable_category_summary as
  SELECT
    start_log.schema_name,
    start_log.TABLE_NAME,
    start_log.CATEGORY,
    start_log.CREATED AS start_time,
    end_log.CREATED AS end_time,
    TIMESTAMPDIFF(SECOND, start_log.CREATED,  end_log.CREATED) as seconds_taken,
    TIMEDIFF(end_log.CREATED, start_log.CREATED) as time_taken
  FROM
    MIGRATION_LOG AS start_log
    INNER JOIN MIGRATION_LOG AS end_log ON (
    start_log.SCHEMA_NAME = end_log.SCHEMA_NAME
    and start_log.TABLE_NAME = end_log.TABLE_NAME
    and start_log.CATEGORY = end_log.CATEGORY
    AND end_log.CREATED >= start_log.CREATED)
  WHERE start_log.ACTION = 'START' AND end_log.ACTION = 'END'
        AND trim(start_log.TABLE_NAME) = "" AND trim(end_log.TABLE_NAME) = ""
  GROUP BY start_log.schema_name, start_log.TABLE_NAME, start_log.CATEGORY
  order by start_log.CREATED;