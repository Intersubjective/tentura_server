FROM postgis/postgis


# Copy the FDW library into the PostgreSQL library directory
#COPY your_fdw_library.so /usr/lib/postgresql/$PG_MAJOR/lib/your_fdw_library.so

# Copy the SQL script into the Docker-entrypoint-initdb.d directory
# This script will be run on every startup of the container, so you
# should make you SQL script idempotent.
#COPY your_sql_script.sql /docker-entrypoint-initdb.d/your_sql_script.sql
