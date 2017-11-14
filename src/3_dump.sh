#!/usr/bin/env bash

source 1_common.sh

[ $# -lt 4 ] && echo "Usage: $(basename $0) <DB_HOST> <DB_USER> <DB> <DIR> (user must be able to read data)" && exit 1

pre_flight_checks

# Control what will be dumped
TABLES_SELECTOR_FULL=" ;"
TABLES_SELECTOR_NOBLOB=" and (table_name not like 'attachment_body' and table_name not like 'image_body' and table_name not like 'message_body');"
TABLES_SELECTOR_TEST=" and (table_name like 'image_body' or table_name like 'site_user') ;"
TABLES_SELECTOR=${TABLES_SELECTOR_FULL}
TABLES_SQL="select '$DB', TT.TABLE_NAME from INFORMATION_SCHEMA.TABLES TT where table_schema='$DB' $TABLES_SELECTOR"

# Populate status table with all the tables to be migrated
STATUS_POPULATION_SQL="insert into $MIGRATION_STATUS_TABLE (SCHEMA_NAME, TABLE_NAME)  $TABLES_SQL"
mysql -NBA --host=${DB_HOST} --user=${DB_USER} --password=${DB_PASS} --database=${GOOGLE_MIGRATION_DB} -e "$STATUS_POPULATION_SQL"
exit_on_error "Error populating $MIGRATION_STATUS_TABLE", ""

# Can only log this once status table is populated (fk on schema_name)
log "$DB" "" "DUMP" "START" "Start dumping tables from database $DB into $DATA_DIR"

# Only dump table that are not dumped yet or are still in the process of being dumped
TABLES_SQL="select table_name from $MIGRATION_STATUS_TABLE where schema_name = '$DB' and DUMPING != 'Y' and DUMPED = 'N'"

TABLE_COUNT=0
for TABLE in $(mysql -NBA --host=${DB_HOST} --user=${DB_USER} --password=${DB_PASS} --database=${GOOGLE_MIGRATION_DB} -e "$TABLES_SQL")
do
    #TABLE_DATA=${DATA_DIR}/${TABLE}.csv
    TABLE_DATA=${DATA_DIR}/${TABLE}.sql
    TABLE_DATA_GZ=${TABLE_DATA}.gz

    log "$DB" "$TABLE" "DUMP_DATA" "START" "Dumping table: $TABLE data to $TABLE_DATA_GZ"
    update_status "$DB" "$TABLE" "Y" "N" "" "" "" "" "" "" "" ""

    ROW_COUNT=$(mysql -ss --host=${DB_HOST} --user=${DB_USER} --password=${DB_PASS} --database=${DB} -e"select count(*) from $TABLE")
    exit_on_error "Error getting rows for $TABLE", "$TABLE"
    update_status "$DB" "$TABLE" "" "" "" "" "" "" "" "" "" "$ROW_COUNT"

    # create csv dump
    #TABLE_DATA=$(fix_path ${TABLE_DATA})
    #DUMP_SQL=" SELECT * FROM $TABLE INTO OUTFILE '$TABLE_DATA' CHARACTER SET 'utf8' FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '\"' ESCAPED BY '\"' "
    #mysql -NBA --host=${DB_HOST} --user=${DB_USER} --password=${DB_PASS} ${DB}  -e "$DUMP_SQL"

    # create sql dump
    mysqldump --host=${DB_HOST} --user=${DB_USER} --password=${DB_PASS} ${DB} ${TABLE} --skip-triggers --default-character-set='utf8' --hex-blob | gzip -8 > ${TABLE_DATA_GZ}
    exit_on_error "Error dumping data for $TABLE", "$TABLE"
    update_status "$DB" "$TABLE" "N" "Y" "N" "Y" "" "" "" "" "" ""
    log "$DB" "$TABLE" "DUMP_DATA" "END" "Dumped table: $TABLE data to $(basename ${TABLE_DATA_GZ})"


    #log "$DB" "$TABLE" "DUMP_COMPRESS" "START" "Compressing $TABLE_DATA"
    #update_status "$DB" "$TABLE" "" "" "Y" "N" "" "" "" "" "" ""
    #gzip -8 ${TABLE_DATA}
    #exit_on_error "Error compressing data for $TABLE", "$TABLE"
    #update_status "$DB" "$TABLE" "" "" "N" "Y" "" "" "" "" "" ""
    #log "$DB" "$TABLE" "DUMP_COMPRESS" "END" "Compressed $TABLE_DATA"

    TABLE_COUNT=$(( TABLE_COUNT + 1 ))
done

log "$DB" "" "DUMP" "END" "$TABLE_COUNT tables dumped from database $DB into $DATA_DIR"

