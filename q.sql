EXPLAIN (analyze, buffers ) SELECT c1.pad,sum(c1.c),avg(c1.k) FROM (SELECT pad,length(c) AS c,k FROM sbtest1) AS c1 GROUP BY c1.pad ORDER BY 3;
