#!/bin/bash
mkdir -p $HOME/LocalStorageForRPG/log
export PGHOSTS="saz-ebs.xxxxxxxxxxx.us-west-2.rds.amazonaws.com saz-local.xxxxxxxxxxx.us-west-2.rds.amazonaws.com"
export LOG=$HOME/LocalStorageForRPG/logs
export BMDB=$1
exec >$LOG/main-EBSvsLocal-Queries-q2-"$(date +"%d-%m-%Y-%H%M%S")".log 2>&1
echo "++++++++++++++++++++++++++++++++"
echo "BEGIN TIME"
echo "++++++++++++++++++++++++++++++++"
date
for i in 1 2 4 8 12 16; do
	for PGHOST in $PGHOSTS; do
		echo "Running on with concurrency $i on $PGHOST"
		nohup $HOME/LocalStorageForRPG/run_sb_query_q2.sh $i $BMDB $PGHOST &
	done
	wait
done
wait
echo "++++++++++++++++++++++++++++++++"
echo "END TIME"
echo "++++++++++++++++++++++++++++++++"
date
