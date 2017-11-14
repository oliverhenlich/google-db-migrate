#!/usr/bin/env bash

source 1_common.sh

[ $# -lt 4 ] && echo "Usage: $(basename $0) <DB_HOST> <DB_USER> <DB> <DIR>" && exit 1

pre_flight_checks

GCS_DUMP_PATH="gs://${GCS_BUCKET}/${DB}"

log "$DB" "" "UPLOAD" "START" "Start uploading dumps of database $DB from $DATA_DIR"

while [ true ]
do
    # Query to determine if an upload is already in progress
    PROCESSING_COUNT_SQL="select count(*) from $MIGRATION_STATUS_TABLE where SCHEMA_NAME='$DB' and ERROR='N' and UPLOADING='Y'"
    PROCESSING_COUNT=$(mysql -NBA --host=${DB_HOST} --user=${DB_USER} --password=${DB_PASS} --database=${GOOGLE_MIGRATION_DB} -e "${PROCESSING_COUNT_SQL}")
    exit_on_error "Error counting in progress uploads", ""

    if [ ${PROCESSING_COUNT} -eq 0 ] ;
    then
        # Query to find the next dump to upload
        TABLE_SQL="select TABLE_NAME from $MIGRATION_STATUS_TABLE where SCHEMA_NAME='$DB' and ERROR='N' and  DUMPED='Y' and COMPRESSED='Y' and UPLOADING='N' and UPLOADED='N' limit 1"
        TABLE=$(mysql -NBA --host=${DB_HOST} --user=${DB_USER} --password=${DB_PASS} --database=${GOOGLE_MIGRATION_DB} -e "${TABLE_SQL}")
        exit_on_error "Error getting next table to upload", ""

        if [ -n "$TABLE" ] ;
        then
            printf "\n"

            #TABLE_DATA=${DATA_DIR}/${TABLE}.csv
            TABLE_DATA=${DATA_DIR}/${TABLE}.sql
            TABLE_DATA_GZ=${TABLE_DATA}.gz
            TABLE_DATA_GZ=$(fix_path ${TABLE_DATA_GZ})
            TABLE_DATA_GZ_BASENAME=$(basename ${TABLE_DATA_GZ})

            # upload data
            log "$DB" "$TABLE" "UPLOAD_DATA" "START" "Starting upload of data: $TABLE_DATA_GZ_BASENAME"
            update_status "$DB" "$TABLE" "" "" "" "" "Y" "N" "" "" "" ""
            ${GSUTIL} -q cp ${TABLE_DATA_GZ} ${GCS_DUMP_PATH}/${TABLE_DATA_GZ_BASENAME}
            log_and_continue_on_error "Error uploading data '$TABLE_DATA_GZ'", "$TABLE"

            ${GSUTIL} -q acl ch -u ${GSQL_SERVICE_ACCOUNT}:R ${GCS_DUMP_PATH}/${TABLE_DATA_GZ_BASENAME}
            log_and_continue_on_error "Error changing acl for $GCS_DUMP_PATH/$TABLE_DATA_GZ_BASENAME" "$TABLE"

            log "$DB" "$TABLE" "UPLOAD_DATA" "END" "Finished uploading of data: $TABLE_DATA_GZ_BASENAME"
            update_status "$DB" "$TABLE" "" "" "" "" "N" "Y" "" "" "" ""
        fi
    fi

    # Query to determine if we are done
    REMAINING_SQL="select count(*) from MIGRATION_STATUS where SCHEMA_NAME='$DB' and UPLOADED='N';"
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
log "$DB" "" "UPLOAD" "END" "All dumps uploaded."
