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
SELECT
  schema_name,
  category,
  count(*)                        AS table_count,
  sum(seconds_taken)              AS total_seconds,
  sec_to_time(sum(seconds_taken)) AS total_time
FROM LOG_TABLE_CATEGORY_SUMMARY
GROUP BY schema_name, category;
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
+-------------+---------------+----------------+-------------------+----------------+---------------+--------------------------------+------------------------------+
| schema_name | imported_rows | remaining_rows | seconds_remaining | time_remaining | imported_time | imported_avg_seconds_per_table | imported_avg_rows_per_second |
+-------------+---------------+----------------+-------------------+----------------+---------------+--------------------------------+------------------------------+
| next        | 12,221,311    | 1,034,458      | 1,024             | 00:17:04.2744  | 03:21:41      | 29.88                          | 1,009.94                     |
+-------------+---------------+----------------+-------------------+----------------+---------------+--------------------------------+------------------------------+
```

## Other Notes
* GSQL does not allow concurrent imports. Ideally we would have been able to kick off as many as we liked.

## Summary of migrating a dev database to GSQL

* High level logged times
```
select * from MIGRATION_LOG where table_name = "";
+------+----------------------------+-------------+------------+----------+--------+-------------------------------------------------------------------------------------------------------------+
| ID   | CREATED                    | SCHEMA_NAME | TABLE_NAME | CATEGORY | ACTION | MESSAGE                                                                                                     |
+------+----------------------------+-------------+------------+----------+--------+-------------------------------------------------------------------------------------------------------------+
|    1 | 2017-11-14 12:53:16.000000 | next        |            | DUMP     | START  | Start dumping tables from database next into /cygdrive/c/p/google-db-migrate/tmp/google-migration-data/next |
|   22 | 2017-11-14 12:53:27.000000 | next        |            | UPLOAD   | START  | Start uploading dumps of database next from /cygdrive/c/p/google-db-migrate/tmp/google-migration-data/next  |
|   27 | 2017-11-14 12:53:32.000000 | next        |            | IMPORT   | START  | Start importing dumps into oliver-migration-test.next from gs://oliver-testing/next                         |
| 1146 | 2017-11-14 12:59:47.000000 | next        |            | DUMP     | END    | 538 tables dumped from database next into /cygdrive/c/p/google-db-migrate/tmp/google-migration-data/next    |
| 2438 | 2017-11-14 14:11:02.000000 | next        |            | UPLOAD   | END    | All dumps uploaded.                                                                                         |
| 3234 | 2017-11-14 17:33:32.000000 | next        |            | IMPORT   | END    | All dumps imported.                                                                                         |
+------+----------------------------+-------------+------------+----------+--------+-------------------------------------------------------------------------------------------------------------+
```

* Logged times by category
```
SELECT
  schema_name,
  category,
  count(*)                        AS table_count,
  sum(seconds_taken)              AS total_seconds,
  sec_to_time(sum(seconds_taken)) AS total_time
FROM LOG_TABLE_CATEGORY_SUMMARY
GROUP BY schema_name, category;
+-------------+-------------+-------------+---------------+------------+
| schema_name | category    | table_count | total_seconds | total_time |
+-------------+-------------+-------------+---------------+------------+
| next        | DUMP_DATA   |         538 |           339 | 00:05:39   |
| next        | IMPORT_DATA |         538 |         16105 | 04:28:25   |
| next        | UPLOAD_DATA |         538 |          3944 | 01:05:44   |
+-------------+-------------+-------------+---------------+------------+
```

* Speed near the end
```
+-------------+------------------+----------------+---------------+-------------------+----------------+---------------+--------------------------------+------------------------------+---------------------+
| schema_name | remaining_tables | remaining_rows | imported_rows | seconds_remaining | time_remaining | imported_time | imported_avg_seconds_per_table | imported_avg_rows_per_second | currently_importing |
+-------------+------------------+----------------+---------------+-------------------+----------------+---------------+--------------------------------+------------------------------+---------------------+
| next        |               35 | 465,336        | 12,790,433    | 543               | 00:09:02.9949  | 04:08:45      | 29.67                          | 856.98                       | workflow_task       |
+-------------+------------------+----------------+---------------+-------------------+----------------+---------------+--------------------------------+------------------------------+---------------------+
```

