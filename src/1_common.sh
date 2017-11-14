#!/usr/bin/env bash

# Get the linux environment (needed in some cases because of cygwin paths)
unameOut="$(uname -s)"
case "${unameOut}" in
    Linux*)     machine=Linux;;
    Darwin*)    machine=Mac;;
    CYGWIN*)    machine=Cygwin;;
    MINGW*)     machine=MinGw;;
    *)          machine="UNKNOWN:${unameOut}"
esac
ENVIRONMENT=${machine}

# Mandatory parameters for all scripts
DB_HOST=$1
DB_USER=$2
DB=$3
DIR=$4
DB_PASS=

# Derived variables
DATA_DIR=

# Commands
GSUTIL=gsutil
GCLOUD=gcloud


# Google constants
GCS_BUCKET="oliver-testing"
GSQL_INSTANCE="oliver-migration-test"
GSQL_SERVICE_ACCOUNT="czcbemok4nbvdlyeekcdqtzoea@speckle-umbrella-10.iam.gserviceaccount.com"


# Migration database constants
GOOGLE_MIGRATION_DB=GOOGLE_MIGRATION
MIGRATION_STATUS_TABLE=MIGRATION_STATUS
MIGRATION_LOG_TABLE=MIGRATION_LOG



function init() {

    read_db_password

    echo "Initialising..."

    # Derived variables
    DATA_DIR=${DIR}/${DB}

    # Fix paths to commands (because of cygwin)
    if [ "$ENVIRONMENT" == "Cygwin" ]; then
        GSUTIL="gsutil.cmd"
        GCLOUD="gcloud.cmd"
    fi

    # Check that mysql will be able to write to the dir
    if [ "$machine" == "Linux" ]; then
        DIR_PERMISSIONS=$(stat -c %a "$DIR")
        if [ ${DIR_PERMISSIONS} != 777 ]; then
            echo "Insufficient permissions for $DIR. Mysql needs to be able to write to it."
            exit
        fi
    fi

    # Get the service account of the GSQL instance
    GSQL_SERVICE_ACCOUNT=$(${GCLOUD} sql instances describe ${GSQL_INSTANCE} --format="value(serviceAccountEmailAddress)" | tr -d '\n' | tr -d '\r')
    if [[ -z "${GSQL_SERVICE_ACCOUNT}"  ]] ; then
        echo "Could not determine service account for $GSQL_INSTANCE. Exiting..."
        exit 1
    fi

    # Check source database access
    mysql -NBA --user=${DB_USER} --password=${DB_PASS} --host=${DB_HOST} ${DB} -e "select 1 into @tmp;"
    exit_on_error "Cannot connect to $DB_HOST.$DB" ""


    echo "Local properties"
    echo "SOURCE_HOST          : $DB_HOST"
    echo "SOURCE_USER          : $DB_USER"
    echo "SOURCE_DB            : $DB"
    echo "DATA_DIR             : $DATA_DIR"
    echo
    echo "Google properties"
    echo "GCS_BUCKET           : $GCS_BUCKET"
    echo "GSQL_INSTANCE        : $GSQL_INSTANCE"
    echo "GSQL_SERVICE_ACCOUNT : $GSQL_SERVICE_ACCOUNT"
    echo
    echo "Initialised"
}

function pre_flight_checks() {
    echo "Performing checks"

    # check data dir exists
    if [ ! -d "$DATA_DIR" ];
    then
        echo "Dump dir does not exist. Have you run prepare? '$DATA_DIR'. Exiting..."
        exit 1
    fi

    # check GSQL db exists
    if [[ -z $(${GCLOUD} sql databases list --instance=${GSQL_INSTANCE} --filter="name=$DB" --format="value(extract(name))")  ]] ; then
        exit_on_error "GSQL database does not exist. Have you run prepare? $DB. Exiting..." ""
        exit 1
    fi

    echo "Checks complete"
}



function read_db_password() {
    echo -n "Enter source database password for user $DB_USER: "
    read -s DB_PASS
    echo
}

function ask_yes_or_no() {
    read -p "$1 ([y]es or [n]o): "
    case $(echo $REPLY | tr '[A-Z]' '[a-z]') in
        y|yes) echo "yes" ;;
        *)     echo "no" ;;
    esac
}

function require_confirmation() {
    if [[ "no" == $(ask_yes_or_no "Enter [y]es to continue: ") ]]
    then
        exit 0
    fi
}

function exit_on_error() {
    EXIT_CODE=$?
    [ $# -lt 2 ] && echo "Usage: exit_on_error <MESSAGE> <TABLE>" && exit 1

    if [ ${EXIT_CODE} -ne 0 ] ;
    then
        echo "Last command failed [$1]"

        if [ -n "$2" ]; then
            update_status "$DB" "$2" "" "" "" "" "" "" "" "" "Y" ""
        fi

        echo "Exiting..."
        exit 1
    fi
}

function log_and_continue_on_error() {
    EXIT_CODE=$?
    [ $# -lt 2 ] && echo "Usage: log_and_continue_on_error <MESSAGE> <TABLE>" && exit 1

    if [ ${EXIT_CODE} -ne 0 ] ;
    then
        echo "Last command failed [$1]"

        if [ -n "$2" ]; then
            # reset all 'in progress' flags and set error to Y
            update_status "$DB" "$2" "N" "" "N" "" "N" "" "N" "" "Y" ""
        fi
    fi
}

function datetime() {
 echo $(date --iso-8601=seconds)
}

function log() {
    [ $# -lt 5 ] && echo "Usage: log <SCHEMA> <TABLE> <CATEGORY> <ACTION> <MESSAGE>" && exit 1

    local LOCAL_SCHEMA=$1
    local LOCAL_TABLE=$2
    local LOCAL_CATEGORY=$3
    local LOCAL_ACTION=$4
    local LOCAL_MESSAGE=$5

    echo $(datetime) "| $LOCAL_MESSAGE "

    local LOCAL_SQL="insert into $MIGRATION_LOG_TABLE (CREATED, SCHEMA_NAME, TABLE_NAME, CATEGORY, ACTION, MESSAGE) values (now(), '$LOCAL_SCHEMA', '$LOCAL_TABLE', '$LOCAL_CATEGORY', '$LOCAL_ACTION', '$LOCAL_MESSAGE'); "

    mysql -NBA --host=${DB_HOST} --user=${DB_USER} --password=${DB_PASS} --database=${GOOGLE_MIGRATION_DB} -e "$LOCAL_SQL"
    exit_on_error "Error inserting $MIGRATION_LOG_TABLE", "$LOCAL_TABLE"
}

function update_status() {
    [ $# -lt 12 ] && echo "Usage: update_status <SCHEMA> <TABLE> <DUMPING> <DUMPED> <COMPRESSING> <COMPRESSED> <UPLOADING> <UPLOADED> <IMPORTING> <IMPORTED> <ERROR> [ROWS]" && exit 1

    local LOCAL_SCHEMA=$1
    local LOCAL_TABLE=$2
    local LOCAL_DUMPING=$3
    local LOCAL_DUMPED=$4
    local LOCAL_COMPRESSING=$5
    local LOCAL_COMPRESSED=$6
    local LOCAL_UPLOADING=$7
    local LOCAL_UPLOADED=$8
    local LOCAL_IMPORTING=$9
    local LOCAL_IMPORTED=${10}
    local LOCAL_ERROR=${11}
    local LOCAL_ROWS=${12}

    local LOCAL_SQL="update $MIGRATION_STATUS_TABLE set "

    if [[ (-z "$LOCAL_SCHEMA") || (-z "$LOCAL_TABLE") ]] ; then
        echo "SCHEMA and TABLE params must not be empty"
    fi

    if [ -n "$LOCAL_DUMPING" ]; then
        LOCAL_SQL="$LOCAL_SQL DUMPING='$LOCAL_DUMPING', "
    else
        LOCAL_SQL="$LOCAL_SQL DUMPING=DUMPING, "
    fi
    if [ -n "$LOCAL_DUMPED" ]; then
        LOCAL_SQL="$LOCAL_SQL DUMPED='$LOCAL_DUMPED', "
    else
        LOCAL_SQL="$LOCAL_SQL DUMPED=DUMPED, "
    fi

    if [ -n "$LOCAL_COMPRESSING" ]; then
        LOCAL_SQL="$LOCAL_SQL COMPRESSING='$LOCAL_COMPRESSING', "
    else
        LOCAL_SQL="$LOCAL_SQL COMPRESSING=COMPRESSING, "
    fi
    if [ -n "$LOCAL_COMPRESSED" ]; then
        LOCAL_SQL="$LOCAL_SQL COMPRESSED='$LOCAL_COMPRESSED', "
    else
        LOCAL_SQL="$LOCAL_SQL COMPRESSED=COMPRESSED, "
    fi

    if [ -n "$LOCAL_UPLOADING" ]; then
        LOCAL_SQL="$LOCAL_SQL UPLOADING='$LOCAL_UPLOADING', "
    else
        LOCAL_SQL="$LOCAL_SQL UPLOADING=UPLOADING, "
    fi
    if [ -n "$LOCAL_UPLOADED" ]; then
        LOCAL_SQL="$LOCAL_SQL UPLOADED='$LOCAL_UPLOADED', "
    else
        LOCAL_SQL="$LOCAL_SQL UPLOADED=UPLOADED, "
    fi
    
    if [ -n "$LOCAL_IMPORTING" ]; then
        LOCAL_SQL="$LOCAL_SQL IMPORTING='$LOCAL_IMPORTING', "
    else
        LOCAL_SQL="$LOCAL_SQL IMPORTING=IMPORTING, "
    fi
    if [ -n "$LOCAL_IMPORTED" ]; then
        LOCAL_SQL="$LOCAL_SQL IMPORTED='$LOCAL_IMPORTED', "
    else
        LOCAL_SQL="$LOCAL_SQL IMPORTED=IMPORTED, "
    fi

    if [ -n "$LOCAL_ERROR" ]; then
        LOCAL_SQL="$LOCAL_SQL ERROR='$LOCAL_ERROR', "
    else
        LOCAL_SQL="$LOCAL_SQL ERROR=ERROR, "
    fi

    if [ -n "$LOCAL_ROWS" ]; then
        LOCAL_SQL="$LOCAL_SQL ROWS=$LOCAL_ROWS "
    else
        LOCAL_SQL="$LOCAL_SQL ROWS=ROWS "
    fi


    LOCAL_SQL="$LOCAL_SQL where schema_name='$LOCAL_SCHEMA' and table_name='$LOCAL_TABLE';"


    mysql -NBA --host=${DB_HOST} --user=${DB_USER} --password=${DB_PASS} --database=${GOOGLE_MIGRATION_DB} -e "$LOCAL_SQL"
    exit_on_error "Error updating $MIGRATION_STATUS_TABLE", ""
}

function fix_path() {
    [ $# -lt 1 ] && echo "Usage: fix_path <FILE_PATH>" && exit 1

    local FILE_PATH=$1
    if [ "$ENVIRONMENT" == "Cygwin" ]; then
        FILE_PATH=$(echo ${FILE_PATH} | sed 's/\/cygdrive\/c\//c:\//')
    fi
    echo ${FILE_PATH}
}


init