-- Read only. Run only when Supabase Storage tables exist (the scripts check first).
\o storage_buckets.csv
SELECT b.id AS bucket, b.public,
       (SELECT count(*) FROM storage.objects o WHERE o.bucket_id = b.id) AS objects
  FROM storage.buckets b
 ORDER BY 1;
\o
