#!/bin/bash
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
exec >$LOG/$NUM_CONCURRENT_SESSIONS-$RDSID-EBSvsLocal-queries-q2-"$(date +"%d-%m-%Y-%H%M%S")".log 2>&1
echo "Running test with concurrency of $NUM_CONCURRENT_SESSIONS on RDS instance: $PGHOST"
echo "Cleaning up first"
psql -h $PGHOST -U $PGUSER -p $PGPORT -d $PGDATABASE <<EOF
\c $BMDB
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
SELECT pg_stat_statements_reset();
SELECT pg_stat_reset();
SELECT current_timestamp AS BEGIN_CLOCK;
EOF
# Running queries
echo "Proceeding to run queries"
echo "Running query"
nohup pgbench -h $PGHOST -p $PGPORT -U $PGUSER $BMDB -f $HOME/LocalStorageForRPG/q.sql -n -P 900 -t 1 -c $NUM_CONCURRENT_SESSIONS &
wait
echo "Exeuction of queries is complete"
#Get performance stats
echo "Extracting performance results"
echo "Overall performance of queries on $PGHOST with concurrency:$NUM_CONCURRENT_SESSIONS"
psql -h $PGHOST -U $PGUSER -p $PGPORT -d $BMDB <<EOF
SELECT current_timestamp AS END_CLOCK;
WITH q AS (
    SELECT
        calls,
        query,
        round(mean_exec_time::numeric / 1000 / 60, 2) AS avg_ex_time_in_min,
        (local_blks_read + local_blks_written + temp_blks_read + temp_blks_written) * 8 * 1024 AS total_disk_temp_io_per_sql_type
    FROM
        pg_stat_statements
    WHERE
        query ILIKE '%sbtest%'
)
SELECT
    calls AS concurrency,
    ROUND(AVG(avg_ex_time_in_min), 1) AS "time taken in minutes ",
    pg_size_pretty(SUM(total_disk_temp_io_per_sql_type)) AS "total disk usage of temp per SQL type"
FROM
    q
GROUP BY concurrency;
EOF
echo "++++++++++++++++++++++++++++++++++++++++++++++++"
echo " Capturing performance stats for concurrency $NUM_CONCURRENT_SESSIONS on host $PGHOST"
echo "++++++++++++++++++++++++++++++++++++++++++++++++"
psql -h $PGHOST -U $PGUSER -p $PGPORT -d $BMDB <<EOF
INSERT INTO t_bm_stats_pss SELECT c1.*,'q1',$NUM_CONCURRENT_SESSIONS FROM pg_stat_statements c1 WHERE query ILIKE '%EXPLAIN (analyze, buffers )%'; 
EOF
