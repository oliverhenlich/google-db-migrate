#!/usr/bin/env bash

source 1_common.sh

[ $# -lt 4 ] && echo "Usage: $(basename $0) <DB_HOST> <DB_USER> <DB> <DIR>  (user must be able to create a database)" && exit 1

echo
echo "Preparing for database migration."
echo "WARNING: This will perform the following actions:"
echo " - Check and create a working directory called '$DIR'"
echo " - Check and create a database called '$GOOGLE_MIGRATION_DB' in the source instance (${DB_HOST})"
echo " - Check and create a database called '$DB' in the target instance (${GSQL_INSTANCE})"
echo " - Dump and import the schema for '$DB' into the target instance (${GSQL_INSTANCE})"
echo ""
echo "Are you sure you want to continue?"
require_confirmation


echo "Ensuring working dir exists '$DIR'"
if [ ! -d "$DIR" ];
then
    echo "Creating working dir '$DIR'"
    mkdir -p ${DIR} --mode=u+rwx,g+rwxs,o+rwxs
fi
# TODO check it will be writable my mysql

if [ ! -d "$DATA_DIR" ];
then
    echo "Creating data dir '$DATA_DIR'"
    mkdir -p ${DATA_DIR} --mode=u+rwx,g+rwxs,o+rwxs
else
    echo "Data dir already exists '$DATA_DIR'. Exiting..."
    exit 1
fi
echo "Dumps for '$DB' will be written to '$DATA_DIR'"



echo "Creating database migration database $GOOGLE_MIGRATION_DB"
mysql --user=${DB_USER} --password=${DB_PASS} --host=${DB_HOST} -e "create database if not exists $GOOGLE_MIGRATION_DB"
echo "Created database migration database $GOOGLE_MIGRATION_DB"
echo


echo "Creating migration database schema"
mysql --user=${DB_USER} --password=${DB_PASS} --host=${DB_HOST} ${GOOGLE_MIGRATION_DB} < sql/google_migration_ddl.sql
echo "Created migration database schema"
echo


echo "Checking/creating GSQL database '$GSQL_INSTANCE.$DB'"
if [[ -z $(${GCLOUD} sql databases list --instance=${GSQL_INSTANCE} --filter="name=$DB" --format="value(extract(name))")  ]] ; then
    echo "GSQL database '$DB' does not exist. Creating..."
    ${GCLOUD} sql databases create ${DB} --instance=${GSQL_INSTANCE}, -i ${GSQL_INSTANCE}  --charset="utf8" --collation="utf8_general_ci"
    exit_on_error "Error creating GSQL db '$GSQL_INSTANCE.$DB'" ""
    echo "GSQL database '$DB' created"


#    # dump schema
#    echo "Dumping schema for '$DB'"
#    SCHEMA=${DATA_DIR}/schema.sql
#    SCHEMA_BASENAME=$(basename ${SCHEMA})
#    mysqldump --host=${DB_HOST} --user=${DB_USER} --password=${DB_PASS} ${DB} --no-data --skip-triggers --default-character-set='utf8' --no-create-db > ${SCHEMA}
#    exit_on_error "Error dumping schema '$DB'", ""
#    echo "Dumped schema for '$DB'"
#
#
#    #upload schema
#    SCHEMA_FIXED=$(fix_path ${SCHEMA})
#    echo "Starting upload of schema: '$SCHEMA'"
#    ${GSUTIL} -q cp ${SCHEMA_FIXED} gs://${GCS_BUCKET}/${DB}/$(basename ${SCHEMA})
#    exit_on_error "Error uploading schema '$DB'", ""
#
#    ${GSUTIL} -q acl ch -u ${GSQL_SERVICE_ACCOUNT}:R gs://${GCS_BUCKET}/${DB}/${SCHEMA_BASENAME}
#    exit_on_error "Error changing acl for 'gs://$GCS_BUCKET/$DB/$SCHEMA_BASENAME'", ""
#    echo "Finished upload of schema: $SCHEMA"
#
#
#    # import schema
#    echo "Starting import of schema '$SCHEMA_BASENAME' into ${GSQL_INSTANCE}/${DB}"
#    ${GCLOUD} --quiet sql instances import ${GSQL_INSTANCE} gs://${GCS_BUCKET}/${DB}/${SCHEMA_BASENAME} --database="$DB"
#    exit_on_error "Error importing schema '$DB'", ""
#    echo "Finished import of schema '$SCHEMA_BASENAME' into ${GSQL_INSTANCE}/${DB}"

else
    echo "GSQL database '$DB' already exists. Exiting..."
fi
echo


echo "Done"

