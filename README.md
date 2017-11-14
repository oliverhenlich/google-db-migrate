# google-db-migrate

Tool to migrate a mysql database to Google CloudSQL (GSQL).

## Overview
This tools processes tables of a database individually.
The goal was to be able to begin uploading a complete table dump as soon as it is ready
and then to subsequently also being importing it into GSQL.

This tool creates a database called `google_migration` which is used for:
* Tracking the status of each table (`migration_status`).
* Logging each operation (`migration_log`).


## Usage
* `2_prepare.sh` - prepare GSQL database and local environment
* `3_dump.sh` - begins dumping all tables from chosen database
* `4_upload.sh` - begins uploading dumps to GCS (start this anytime after `3_dump.sh` has begun)
* `5_import.sh` - begins importing dumps into GSQL (start this anytime after `3_dump.sh` has begun)


## Reporting
Use the SQL statements in `src/sql/reports.sql`.

For example, to see a summary of all operations:
```
select schema_name, category, count(*) as table_count, sum(seconds_taken) as total_seconds, sec_to_time(sum(seconds_taken)) as total_time
from log_table_category_summary
group by schema_name, category;
```

Which gives an output like:
```
+-------------+-------------+-------------+---------------+------------+
| schema_name | category    | table_count | total_seconds | total_time |
+-------------+-------------+-------------+---------------+------------+
| next        | DUMP_DATA   |         538 |           339 | 00:05:39   |
| next        | IMPORT_DATA |          48 |          1679 | 00:27:59   |
| next        | UPLOAD_DATA |         176 |          1516 | 00:25:16   |
+-------------+-------------+-------------+---------------+------------+
```

Another example is to determine how far through the import we are and an estimate of how much longer it will take gives an output like:
```
+-------------+----------------+---------------+---------------+--------------------------------+------------------------------+-------------------+----------------+
| schema_name | remaining_rows | imported_rows | imported_time | imported_avg_seconds_per_table | imported_avg_rows_per_second | seconds_remaining | time_remaining |
+-------------+----------------+---------------+---------------+--------------------------------+------------------------------+-------------------+----------------+
| next        | 1,251,748      | 12,004,021    | 03:13:57      | 29.54                          | 1,031.54                     | 1,213             | 00:20:13.4760  |
+-------------+----------------+---------------+---------------+--------------------------------+------------------------------+-------------------+----------------+
```

## Other Notes
* GSQL does not allow concurrent imports. Ideally we would have been able to kick off as many as we liked.
