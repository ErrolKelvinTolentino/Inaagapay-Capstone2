-- InaAgapay: child registrar attribution + growth record column guards
--
-- Two unrelated but small changes, kept together because both are additive
-- column guards on the child module.
--
-- 1. children.registered_by_midwife_id
--    Records which midwife registered the child, mirroring the existing
--    mothers.registered_by_midwife_id convention. Answers the panel's
--    "who created this record" requirement for children.
--
-- 2. child_growth_records.recorded_by / measurement_date
--    Defensive guards. The app's growth insert previously wrote a column named
--    `recorded_by_midwife_id`, which does not exist on this table -- the insert
--    failed and the error was swallowed, so growth records never saved. The app
--    now writes `recorded_by` and `measurement_date`; these guards make sure
--    both columns exist regardless of which schema revision the database is on.

BEGIN;

-- 1. Who registered the child ------------------------------------------------

ALTER TABLE public.children
  ADD COLUMN IF NOT EXISTS registered_by_midwife_id BIGINT
    REFERENCES public.midwives(midwife_id) ON DELETE SET NULL;

-- Existing children predate this column. There is no reliable way to infer the
-- registrar after the fact, so they stay NULL and the profile shows "Not
-- recorded" rather than naming the wrong midwife.

-- 2. Growth record columns ---------------------------------------------------

ALTER TABLE public.child_growth_records
  ADD COLUMN IF NOT EXISTS recorded_by BIGINT
    REFERENCES public.midwives(midwife_id) ON DELETE SET NULL;

ALTER TABLE public.child_growth_records
  ADD COLUMN IF NOT EXISTS measurement_date DATE;

ALTER TABLE public.child_growth_records
  ADD COLUMN IF NOT EXISTS weight_for_age_zscore NUMERIC;

ALTER TABLE public.child_growth_records
  ADD COLUMN IF NOT EXISTS height_for_age_zscore NUMERIC;

ALTER TABLE public.child_growth_records
  ADD COLUMN IF NOT EXISTS bmi_for_age_zscore NUMERIC;

-- Backfill measurement_date for any rows that predate the app writing it, so
-- the column is usable for ordering and charting. created_at is the closest
-- available proxy for when the measurement was taken.
UPDATE public.child_growth_records
   SET measurement_date = created_at::date
 WHERE measurement_date IS NULL
   AND created_at IS NOT NULL;

COMMIT;
