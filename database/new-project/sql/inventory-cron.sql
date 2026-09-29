-- Read only. Run only when pg_cron is installed (the scripts check first).
\o cron_jobs.csv
SELECT jobid, jobname, schedule, command, active
  FROM cron.job
 ORDER BY jobid;
\o
