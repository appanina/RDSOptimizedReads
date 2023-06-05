#!/bin/bash
mkdir -p $HOME/LocalStorageForRPG/log
export LOG=$HOME/LocalStorageForRPG/logs
export BMDB=$1
export PGHOSTS="saz-ebs.xxxxxxxxxxx.us-west-2.rds.amazonaws.com saz-local.xxxxxxxxxxx.us-west-2.rds.amazonaws.com"
export PGPORT=5444
export PGDATABASE=postgres
export PGUSER=postgres
export PGPASSWORD=MyPassword123
exec >$LOG/main-EBSvsLocal-"$(date +"%d-%m-%Y-%H%M%S")".log 2>&1
echo "++++++++++++++++++++++++++++++++"
echo "BEGIN TIME"
echo "++++++++++++++++++++++++++++++++"
date
for PGHOST in $PGHOSTS; do
	echo "++++++++++++++++++++++++++++++++"
	echo "Cleaning up perf stats in RDS instance: $PGHOST"
	echo "++++++++++++++++++++++++++++++++"
	psql -h $PGHOST -U $PGUSER -p $PGPORT -d $BMDB <<EOF
SELECT pg_stat_statements_reset();
CREATE TABLE IF NOT EXISTS t_bm_stats_pss_bkp AS SELECT * FROM t_bm_stats_pss;
TRUNCATE TABLE t_bm_stats_pss;
EOF
done
echo "++++++++++++++++++++++++++++++++"
echo "Dropping indexes"
echo "++++++++++++++++++++++++++++++++"
for PGHOST in $PGHOSTS; do
        for i in {1..16}; do
                nohup psql -h $PGHOST -U $PGUSER -p $PGPORT -d $BMDB -c "DROP INDEX ix_pad_k_c_sbtest$i" &
                done
done
wait
for PGHOST in $PGHOSTS; do
	echo "++++++++++++++++++++++++++++++++"
	echo "Core parameter settings of RDS instance: $PGHOST"
	echo "++++++++++++++++++++++++++++++++"
	psql -h $PGHOST -U $PGUSER -p $PGPORT -d $BMDB <<EOF
SELECT name,setting,unit FROM pg_settings WHERE name IN ('checkpoint_timeout','max_wal_size','wal_compression','shared_buffers','work_mem','maintenance_work_mem','temp_tablespaces','temp_buffers','huge_pages','max_parallel_workers_per_gather','max_parallel_workers');
EOF
done
echo "++++++++++++++++++++++++++++++++"
echo "Proceeding with benchmarks"
echo "++++++++++++++++++++++++++++++++"
echo "++++++++++++++++++++++++++++++++"
echo "Running query"
echo "++++++++++++++++++++++++++++++++"
nohup $HOME/LocalStorageForRPG/main_run_query_q2.sh $BMDB &
wait
echo "++++++++++++++++++++++++++++++++"
echo "Running for indexes and temp tables"
echo "++++++++++++++++++++++++++++++++"
nohup $HOME/LocalStorageForRPG/main_CrIndTempTable_benchmarks.sh $BMDB &
wait
echo "++++++++++++++++++++++++++++++++"
echo "END TIME"
echo "++++++++++++++++++++++++++++++++"
date
echo "++++++++++++++++++++++++++++++++"
echo "All runs are complete, proceed to verify"
echo "++++++++++++++++++++++++++++++++"
for PGHOST in $PGHOSTS; do
	echo "++++++++++++++++++++++++++++++++"
	echo "Mean execution times for $PGHOST:"
	echo "++++++++++++++++++++++++++++++++"
	psql -h $PGHOST -U $PGUSER -p $PGPORT -d $BMDB <<EOF
SELECT *
FROM
  (WITH q AS
     (SELECT calls,
             substring(query, 1, 22) AS query,
             round(mean_exec_time::numeric / 1000 / 60, 2) AS avg_ex_time_in_min,
             (local_blks_read + local_blks_written + temp_blks_read + temp_blks_written) * 8 * 1024 AS total_disk_temp_io_per_sql_type
      FROM t_bm_stats_pss
      WHERE query ILIKE '%EXPLAIN (analyze, buffers )%' ) SELECT 'query' AS SQL_type,
                                                                 calls AS concurrency,
                                                                 ROUND(AVG(avg_ex_time_in_min), 1) AS "time taken in minutes ",
                                                                 pg_size_pretty(SUM(total_disk_temp_io_per_sql_type)) AS "total disk usage of temp per SQL type"
   FROM q
   GROUP BY SQL_type,
            concurrency
   ORDER BY SQL_type,
            concurrency) a
UNION ALL
SELECT *
FROM
  (WITH results AS
     (SELECT substring(query, 1, 22) AS SQL_type,
             concurrency,
             round(mean_exec_time::numeric / 1000 / 60, 2) AS avg_ex_time_in_min,
             (local_blks_read + local_blks_written + temp_blks_read + temp_blks_written) * 8 * 1024 AS total_disk_temp_io_per_sql_type
      FROM t_bm_stats_pss
      WHERE query ILIKE ANY (ARRAY['%CREATE INDEX ix_pad_k_c_sbtest%',
                                   '%CREATE TEMPORARY TABLE%'])
      ORDER BY query DESC) SELECT CASE
                                      WHEN SQL_type ILIKE '%CREATE INDEX%' THEN 'CREATE INDEX'
                                      WHEN SQL_type ILIKE '%TEMPORARY TABLE%' THEN 'CREATE TEMPORARY TABLE'
                                  END SQL_type,
                                  concurrency,
                                  ROUND(AVG(avg_ex_time_in_min), 1) AS "time taken in minutes ",
                                  pg_size_pretty(SUM(total_disk_temp_io_per_sql_type)) AS "total disk usage of temp per SQL type"
   FROM results
   GROUP BY SQL_type,
            concurrency
   ORDER BY SQL_type,
            concurrency) b;
EOF
done
