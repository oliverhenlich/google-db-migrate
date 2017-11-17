#!/usr/bin/env bash

source 1_common.sh

[ $# -lt 4 ] && echo "Usage: $(basename $0) <DB_HOST> <DB_USER> <DB> <DIR>" && exit 1

pre_flight_checks

GCS_DUMP_PATH="gs://${GCS_BUCKET}/${DB}"

log "$DB" "" "IMPORT" "START" "Start importing dumps into $GSQL_INSTANCE.$DB from $GCS_DUMP_PATH"

while [ true ]
do
    # Query to determine if an import is already in progress
    PROCESSING_COUNT_SQL="select count(*) from $MIGRATION_STATUS_TABLE where SCHEMA_NAME='$DB' and ERROR='N' and IMPORTING='Y'"
    PROCESSING_COUNT=$(mysql -NBA --host=${DB_HOST} --user=${DB_USER} --password=${DB_PASS} --database=${GOOGLE_MIGRATION_DB} -e "${PROCESSING_COUNT_SQL}")
    exit_on_error "Error counting in progress imports", ""

    if [ ${PROCESSING_COUNT} -eq 0 ] ;
    then
        # Query to find the next dump to import
        TABLE_SQL="select TABLE_NAME from $MIGRATION_STATUS_TABLE where SCHEMA_NAME='$DB' and ERROR='N' and DUMPED='Y' and COMPRESSED='Y' and UPLOADED='Y' and IMPORTING='N' and IMPORTED='N' order by ROWS asc limit 1"
        TABLE=$(mysql -NBA --host=${DB_HOST} --user=${DB_USER} --password=${DB_PASS} --database=${GOOGLE_MIGRATION_DB} -e "${TABLE_SQL}")
        exit_on_error "Error getting next table to import", ""

        if [ -n "$TABLE" ] ;
        then
            printf "\n"

            #TABLE_DATA=${DATA_DIR}/${TABLE}.csv
            TABLE_DATA=${DATA_DIR}/${TABLE}.sql
            TABLE_DATA_GZ=${TABLE_DATA}.gz
            TABLE_DATA_GZ=$(fix_path ${TABLE_DATA_GZ})
            TABLE_DATA_GZ_BASENAME=$(basename ${TABLE_DATA_GZ})

            # import data
            log "$DB" "$TABLE" "IMPORT_DATA" "START" "Starting import of data: $TABLE_DATA_GZ_BASENAME"
            update_status "$DB" "$TABLE" "" "" "" "" "" "" "Y" "" "" ""

            # check import file exists
            ${GSUTIL} -q stat ${GCS_DUMP_PATH}/${TABLE_DATA_GZ_BASENAME}
            # todo eval

            # upload csv dump
            # Broken, see https://stackoverflow.com/questions/41567642/insert-null-in-google-cloud-sql-using-csv-import
            #${GCLOUD} --quiet beta sql import csv ${GSQL_INSTANCE} gs://${GCS_BUCKET}/${DB}/${TABLE_DATA_GZ_BASENAME} --database="$DB" --table="$TABLE"

            # upload sql dump
            ${GCLOUD} --quiet sql instances import ${GSQL_INSTANCE} ${GCS_DUMP_PATH}/${TABLE_DATA_GZ_BASENAME} --database=${DB}
            log_and_continue_on_error "Error importing data for $TABLE" "$TABLE"

            log "$DB" "$TABLE" "IMPORT_DATA" "END" "Finished import of data: $TABLE_DATA_GZ_BASENAME"
            update_status "$DB" "$TABLE" "" "" "" "" "" "" "N" "Y" "" ""
        fi
    fi

    # Note: Either sleep because another import is already in progress, there is nothing to do or an import has just completed.
    #       In the case of a just completed import sleep because sometimes it failed because it thought something was still in progress.

    # Query to determine if we are done
    REMAINING_SQL="select count(*) from MIGRATION_STATUS where SCHEMA_NAME='$DB' and IMPORTED='N';"
    REMAINING_COUNT=$(mysql -NBA --host=${DB_HOST} --user=${DB_USER} --password=${DB_PASS} --database=${GOOGLE_MIGRATION_DB} -e "$REMAINING_SQL")
    exit_on_error "Error counting remaining tables", ""

    if [ ${REMAINING_COUNT} -eq 0 ] ;
    then
        break;
    else
        sleep 1
        printf "."
    fi
done
log "$DB" "" "IMPORT" "END" "All dumps imported."

