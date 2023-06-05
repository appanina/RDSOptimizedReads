#!/bin/bash
mkdir -p $HOME/LocalStorageForRPG/log
export LD_LIBRARY_PATH=/rdsdbbin/postgres-15/lib
export PGHOSTS="saz-ebs.xxxxxxxxxxx.us-west-2.rds.amazonaws.com saz-local.xxxxxxxxxxx.us-west-2.rds.amazonaws.com"
export LOG=$HOME/LocalStorageForRPG/logs
export PGPORT=5444
export PGDATABASE=postgres
export PGUSER=postgres
export PGPASSWORD=MyPassword123
export BMDB=$3
export BM_DATA_VOL=$2
export NUM_CONCURRENT_SESSIONS=$1
exec >$LOG/$NUM_CONCURRENT_SESSIONS-$BM_DATA_VOL-$BMDB-EBSvsLocal-LoadData-"$(date +"%d-%m-%Y-%H%M%S")".log 2>&1
# RESET pg_stat_statements and pg_stat_* data
echo "Running test with volume of $BM_DATA_VOL records with concurrency of $NUM_CONCURRENT_SESSIONS on RDS instances: $PGHOSTS"
# Checking if loading is needed
echo "Checking if loading is needed"
for PGHOST in $PGHOSTS; do
	echo "Checking for $PGHOST"
	IS_LOADING_NEEDED=$(psql -h $PGHOST -p $PGPORT -U $PGUSER -d $BMDB -AXqtc "SELECT DISTINCT reltuples::bigint AS rows FROM pg_class WHERE relname ILIKE 'sbtest%' AND relkind = 'r' ORDER BY reltuples::bigint DESC LIMIT 1")
	echo "Records found $IS_LOADING_NEEDED"
	if [[ $IS_LOADING_NEEDED -ne $BM_DATA_VOL || $IS_LOADING_NEEDED -eq *"ERROR"* ]]; then
		echo "The number of records specified to load into $PGHOST are $BM_DATA_VOL have NOT matched with number of records in database $BMDB:$IS_LOADING_NEEDED, loading is needed OR database does not exist"
		# Cleaning up existing database
		echo "Cleaning up existing database on RDS instance: $PGHOST before proceeding with loading"
		psql -h $PGHOST -U $PGUSER -p $PGPORT -d $PGDATABASE <<EOF
DROP DATABASE $BMDB;
CREATE DATABASE $BMDB;
\c $BMDB 
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
SELECT pg_stat_statements_reset();
SELECT pg_stat_reset();
EOF
		# Loading data
		echo "Loading data into $PGHOST using sysbench"
		nohup sysbench --db-driver=pgsql --report-interval=0 --oltp-table-size=$BM_DATA_VOL --oltp-tables-count=$NUM_CONCURRENT_SESSIONS --threads=$NUM_CONCURRENT_SESSIONS --time=60 --pgsql-host=$PGHOST --pgsql-port=$PGPORT --pgsql-user=$PGUSER --pgsql-db=$BMDB /usr/share/sysbench/tests/include/oltp_legacy/parallel_prepare.lua run &
	else
		echo "The number of records specified to load into $PGHOST are $BM_DATA_VOL have matched with number of records in database $BMDB:$IS_LOADING_NEEDED, no loading is needed, proceed to run benchmarks"
	fi
done
wait
echo "                                          "
echo "------------------------------------------"
echo "            Post-initilization steps      "
echo "------------------------------------------"
for PGHOST in $PGHOSTS; do
	echo "Running post-initilization steps"
	psql -h $PGHOST -p $PGPORT -U $PGUSER -d $BMDB <<EOF
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE TABLE IF NOT EXISTS t_bm_stats_pss AS SELECT * FROM pg_stat_statements WHERE 1=0;
ALTER TABLE t_bm_stats_pss ADD COLUMN IF NOT EXISTS bm_query VARCHAR;
ALTER TABLE t_bm_stats_pss ADD COLUMN IF NOT EXISTS concurrency INT;
ALTER TABLE t_bm_stats_pss ADD COLUMN IF NOT EXISTS bm_timestamp timestamp with time zone DEFAULT CURRENT_TIMESTAMP;
\dt+ sbtest*
SELECT current_timestamp AS END_CLOCK;
EOF
done
for PGHOST in $PGHOSTS; do
	echo "Number of records loaded per table into $PGHOST"
	psql -h $PGHOST -p $PGPORT -U $PGUSER -d $BMDB <<EOF
(WITH q1 AS
     (SELECT relname AS TABLE_NAME,
             TO_CHAR(reltuples::bigint, 'fm999G999G999') AS ROWS
      FROM pg_class
      WHERE relname ILIKE '%sbtest%'
        AND length(relname) = 7
        AND relkind = 'r'
      ORDER BY relname) SELECT *
   FROM q1)
UNION ALL
  (WITH q2 AS
     (SELECT relname AS TABLE_NAME,
             TO_CHAR(reltuples::bigint, 'fm999G999G999') AS ROWS
      FROM pg_class
      WHERE relname ILIKE '%sbtest%'
        AND length(relname) = 8
        AND relkind = 'r'
      ORDER BY relname) SELECT *
   FROM q2);
EOF
done
