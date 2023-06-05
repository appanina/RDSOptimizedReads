#!/bin/bash
#PGHOSTS="saz-ebs.xxxxxxxxxxx.us-west-2.rds.amazonaws.com saz-local.xxxxxxxxxxx.us-west-2.rds.amazonaws.com"
mkdir -p $HOME/LocalStorageForRPG/log
export NUM_CONCURRENT_SESSIONS=$1
export BMDB=$2
export PGHOST=$3
export LOG=$HOME/LocalStorageForRPG/logs
export PGPORT=5444
export PGDATABASE=postgres
export PGUSER=postgres
export PGPASSWORD=MyPassword123
export RDSID=${PGHOST%%.*}
exec >$LOG/$NUM_CONCURRENT_SESSIONS-$RDSID-EBSvsLocal-IndexTempTable-"$(date +"%d-%m-%Y-%H%M%S")".log 2>&1
# RESET pg_stat_statements and pg_stat_* data
echo "Running test with volume of $BM_DATA_VOL records with concurrency of $NUM_CONCURRENT_SESSIONS on RDS instance: $PGHOST"
psql -h $PGHOST -U $PGUSER -p $PGPORT -d $PGDATABASE <<EOF
\c $BMDB 
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
SELECT pg_stat_statements_reset();
SELECT pg_stat_reset();
SELECT current_timestamp AS BEGIN_CLOCK;
EOF
# Run benchmarks
echo "Cleaning up before loading"
echo "Dropping indexes"
for i in $(eval echo {1..$NUM_CONCURRENT_SESSIONS}); do
	nohup psql -h $PGHOST -U $PGUSER -p $PGPORT -d $BMDB -c "DROP INDEX ix_pad_k_c_sbtest$i" &
done
wait
echo "Creating indexes"
for i in $(eval echo {1..$NUM_CONCURRENT_SESSIONS}); do
	echo "Running session $i/$NUM_CONCURRENT_SESSIONS"
	nohup psql -h $PGHOST -U $PGUSER -p $PGPORT -d $BMDB -c "CREATE INDEX ix_pad_k_c_sbtest$i ON sbtest$i(pad,k,c)" &
done
wait
echo "Creating temporary tables"
for i in $(eval echo {1..$NUM_CONCURRENT_SESSIONS}); do
	echo "Running session $i/$NUM_CONCURRENT_SESSIONS"
	nohup psql -h $PGHOST -U $PGUSER -p $PGPORT -d $BMDB -c "CREATE TEMPORARY TABLE temp_sbtest$i AS SELECT * FROM sbtest$i" &
done
wait
# Get performance results
echo "Getting performance results"
echo "Mean execution times for $PGHOST per concurrency $NUM_CONCURRENT_SESSIONS"
psql -h $PGHOST -U $PGUSER -p $PGPORT -d $BMDB <<EOF
SELECT current_timestamp AS END_CLOCK;
WITH results AS (
    SELECT
        substring(query, 1, 22) AS SQL_type,
        round(mean_exec_time::numeric / 1000 / 60, 2) AS avg_ex_time_in_min,
        (local_blks_read + local_blks_written + temp_blks_read + temp_blks_written) * 8 * 1024 AS total_disk_temp_io_per_sql_type
    FROM
        pg_stat_statements
    WHERE
        query ILIKE ANY (ARRAY['%CREATE INDEX ix_pad_k_c_sbtest%',
            '%CREATE TEMPORARY TABLE%'])
    ORDER BY
        query DESC
)
SELECT
    CASE WHEN SQL_type ILIKE '%CREATE INDEX%' THEN
        'CREATE INDEX'
    WHEN SQL_type ILIKE '%TEMPORARY TABLE%' THEN
        'CREATE TEMPORARY TABLE'
    END SQL_type,
    ROUND(AVG(avg_ex_time_in_min), 1) AS "time taken in minutes ",
    pg_size_pretty(SUM(total_disk_temp_io_per_sql_type)) AS "total disk usage of temp per SQL type"
FROM
    results
GROUP BY
    SQL_type;
EOF
echo "++++++++++++++++++++++++++++++++++++++++++++++++"
echo " Capturing performance stats for concurrency $NUM_CONCURRENT_SESSIONS on host $PGHOST"
echo "++++++++++++++++++++++++++++++++++++++++++++++++"
psql -h $PGHOST -U $PGUSER -p $PGPORT -d $BMDB <<EOF
INSERT INTO t_bm_stats_pss SELECT c1.*,'q1',$NUM_CONCURRENT_SESSIONS FROM pg_stat_statements c1 WHERE query ILIKE ANY (ARRAY['%CREATE INDEX ix_pad_k_c_sbtest%','%CREATE TEMPORARY TABLE%']);
EOF
