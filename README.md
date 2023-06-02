# RDSOptimizedReads
This is a repository of scripts used to demonstrate the performance of Optimized Reads feature by Amazon Relational Database Service (RDS) for PostgreSQL.

## Introduction
When you use an [RDS instance class](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.DBInstanceClass.html) that supports local SSD disks for your RDS PostgreSQL instance, Amazon RDS automatically leverages the local storage for tempotary work area for improving performance of operations that heavily rely on it.

With storage directly attached locally to the RDS instance in an Optimized RDS instance configuration, RDS avoids network latencies and bandwidth constraints added by Amazon Elastic Block Store (EBS) in a Non-Optimized RDS instance configuration for temporary work area.

Read [Introducing Optimized Reads for Amazon RDS for PostgreSQL](https://aws.amazon.com/blogs/database/introducing-optimized-reads-for-amazon-rds-for-postgresql/) for more information. 

## Evaluating the performance
### Create RDS instances
Run below commands to create both, a Optimized Reads RDS instance and Non-Optimized Reads RDS instance.```AWS_ACCOUNT_NUMBER``` is your [AWS account identification number](https://docs.aws.amazon.com/accounts/latest/reference/manage-acct-identifiers.html#FindAccountId-root) where RDS instance is created. 
```
aws rds create-db-instance --db-instance-identifier saz-local --backup-retention-period 0 --db-instance-class db.m5d.4xlarge --no-deletion-protection --db-subnet-group-name myrds-subnetgroup1 --vpc-security-group-ids sg-xxxxxxxxxxxxxxxxxxxx --engine postgres --engine-version 14.7 --master-username postgres --master-user-password MySuperXXXXXX --allocated-storage 2048 --iops 5000 --port 5444 --region us-west-2 --monitoring-interval 1 --monitoring-role-arn arn:aws:iam::AWS_ACCOUNT_NUMBER:role/rds-monitoring-role --enable-performance-insights --output table
```
```
aws rds create-db-instance --db-instance-identifier saz-ebs --backup-retention-period 0 --db-instance-class db.m5.4xlarge --no-deletion-protection --db-subnet-group-name myrds-subnetgroup1 --vpc-security-group-ids sg-xxxxxxxxxxxxxxxxxxxx --engine postgres --engine-version 14.7 --master-username postgres --master-user-password MySuperXXXXXX --allocated-storage 2048 --iops 5000 --port 5444 --region us-west-2 --monitoring-interval 1 --monitoring-role-arn arn:aws:iam::AWS_ACCOUNT_NUMBER:role/rds-monitoring-role --enable-performance-insights --output table
```

### Loading test data
Run the following script to load the data, <number_of_records> defines volume of data to be loaded abd into sbtest database and <number_of_tables> defines number of tables.
```
nohup ./LoadData.sh <number_of_tables> <number_of_records> sbtest &
```
For example, following scripts loads 10 million records into each table, for 16 tables.
```
nohup ./LoadData.sh 16 10000000 sbtest &
```

### Testing
Run the following script to do the testing.
```
nohup ./main.sh sbtest &
```

All performance test scripts run in a loop and run sessions simlteneously based on the concurrency level. Concurrency defines number of sessions running in parallel wherein each session runs same statement on a separate table.
```
{1 2 4 8 12 16}
```
For example, a concurrency of two for queries executes the same query on seperate tables, sbtest1 and sbtest2, simlteneously in two separate sessions. 

#### If you want to test for a sepcific scenario separately, you can do the following:

Run the following script for queries.
```
nohup ./main_run_query_q2.sh sbtest &
```

Run the following script for indexes and temporary tables.
```
nohup ./main_CrIndTempTable_benchmarks.sh sbtest & 
```

### Reviewing results
The results are catpured per each session, recorded into a table called ```t_bm_stats_pss```, and also found at the end of the log in ```main-EBSvsLocal-"$(date +"%d-%m-%Y-%H%M%S")".log```.
