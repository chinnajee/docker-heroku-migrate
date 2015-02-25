#!/bin/bash
# Backup Heroku MongoDB and Restore to Mongo container
cd /tmp/
mongodump -h kahana.mongohq.com:10033 -d <database_name> -u heroku -p <password>
mongorestore -h $MONGODB_PORT_27017_TCP_ADDR dump/<database_name>/

# Backup Heroku PostgreSQL and Restore to Postgres container
touch ~/.pgpass && chmod 0600 ~/.pgpass
echo "*:*:<database_name>:<username>:<password>" > ~/.pgpass
cd /tmp/
psql -h $POSTGRES_PORT_5432_TCP_ADDR -U postgres -c "CREATE DATABASE database_name;"
pg_dump -w -c -U <username> -h <host> datebase_name > pg.out
psql --dbname <database_name> -h $POSTGRES_PORT_5432_TCP_ADDR -U postgres -w < pg.out