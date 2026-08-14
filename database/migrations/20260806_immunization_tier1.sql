-- InaAgapay: immunization correctness fixes (Tier 1)
--
-- Three problems, all in the same family as the growth-record bug:
--
-- 1. The app wrote `recorded_by_midwife_id` to immunization_records and to
--    ultrasounds. Neither table declares that column -- the canonical names are
--    immunization_records.administered_by and (new here) ultrasounds.recorded_by.
--    Depending on whether the column was ever added ad hoc to the live database,
--    those inserts have either been failing outright or storing attribution in a
--    column nothing reads. This migration handles both cases: it guarantees the
--    canonical column exists and copies any values across from the stray one.
--
-- 2. dose_number was never supplied on insert. The column defaults to 1, so a
--    Pentavalent 3 has been stored as dose 1 -- dose tracking, prerequisite
--    checks and coverage reports have all been reading that default.
--
-- 3. Nothing prevented the same vaccine being recorded twice for one child.
--
-- Nothing is dropped. The stray column, if present, is left in place so this
-- migration stays reversible and no data is lost.

BEGIN;

-- 1. Attribution -------------------------------------------------------------

ALTER TABLE public.immunization_records
  ADD COLUMN IF NOT EXISTS administered_by BIGINT
    REFERENCES public.midwives(midwife_id) ON DELETE SET NULL;

ALTER TABLE public.ultrasounds
  ADD COLUMN IF NOT EXISTS recorded_by BIGINT
    REFERENCES public.midwives(midwife_id) ON DELETE SET NULL;

-- Copy across anything the app previously wrote to the stray column.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = 'immunization_records'
       AND column_name = 'recorded_by_midwife_id'
  ) THEN
    EXECUTE '
      UPDATE public.immunization_records
         SET administered_by = recorded_by_midwife_id
       WHERE administered_by IS NULL
         AND recorded_by_midwife_id IS NOT NULL';
    RAISE NOTICE 'Backfilled immunization_records.administered_by from recorded_by_midwife_id.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = 'ultrasounds'
       AND column_name = 'recorded_by_midwife_id'
  ) THEN
    EXECUTE '
      UPDATE public.ultrasounds
         SET recorded_by = recorded_by_midwife_id
       WHERE recorded_by IS NULL
         AND recorded_by_midwife_id IS NOT NULL';
    RAISE NOTICE 'Backfilled ultrasounds.recorded_by from recorded_by_midwife_id.';
  END IF;
END;
$$;

-- 2. Dose numbers ------------------------------------------------------------
--
-- Every existing record carries the default of 1. Restore the real dose from
-- the vaccine each record points at.

UPDATE public.immunization_records ir
   SET dose_number = v.dose_number
  FROM public.vaccines v
 WHERE ir.vaccine_id = v.vaccine_id
   AND v.dose_number IS NOT NULL
   AND ir.dose_number IS DISTINCT FROM v.dose_number;

-- 3. One record per vaccine per child ----------------------------------------
--
-- Attempted rather than forced: if the data already contains duplicates the
-- index cannot be built, and failing the whole migration over it would block
-- the two fixes above. In that case this reports the problem and moves on.

DO $$
BEGIN
  BEGIN
    CREATE UNIQUE INDEX IF NOT EXISTS unique_immunization_per_child
      ON public.immunization_records (child_id, vaccine_id);
    RAISE NOTICE 'Unique index on (child_id, vaccine_id) is in place.';
  EXCEPTION
    WHEN unique_violation OR duplicate_table THEN
      RAISE WARNING
        'Could not create unique_immunization_per_child: duplicate rows exist. '
        'Run the SELECT in the comment below, resolve them, then re-run this file.';
  END;
END;
$$;

-- Duplicates, if the index above could not be created:
--
--   SELECT child_id, vaccine_id, count(*), array_agg(immunization_record_id)
--     FROM public.immunization_records
--    GROUP BY child_id, vaccine_id
--   HAVING count(*) > 1;

COMMIT;
