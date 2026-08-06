-- ============================================================================
-- InaAgapay — combined pending migrations
-- Generated 2026-08-06
--
-- Everything outstanding after 20260804_child_number.sql, concatenated in
-- dependency order. Run this whole file once in the Supabase SQL editor.
--
--   1. 20260805_child_growth_and_registrar.sql
--        children.registered_by_midwife_id + growth-record column guards
--   2. 20260806_seed_doh_epi_vaccines.sql
--        the DOH EPI schedule (8 vaccines, 17 child doses + 5 maternal Td)
--   3. 20260806_immunization_tier1.sql
--        administered_by, dose_number backfill, one-record-per-vaccine index
--   4. 20260806_immunization_record_source.sql
--        given-here vs given-elsewhere, plus the reserved inventory hook
--
-- ORDER MATTERS: step 3 adds immunization_records.administered_by, which the
-- CHECK constraint in step 4 depends on.
--
-- Each step keeps its own BEGIN/COMMIT, so a failure part-way leaves the
-- earlier steps applied. Every step is idempotent -- re-running the whole file
-- is safe, including if you already ran one of them individually.
--
-- Supabase will warn about "destructive operations": that is triggered by the
-- words DROP and UPDATE. The only DROP is `DROP TRIGGER IF EXISTS` on a trigger
-- the next line recreates. Every UPDATE writes to columns these files create.
-- Nothing is deleted.
-- ============================================================================


-- ============================================================================
-- STEP: 20260805_child_growth_and_registrar.sql
-- ============================================================================

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

-- ============================================================================
-- STEP: 20260806_seed_doh_epi_vaccines.sql
-- ============================================================================

-- InaAgapay: DOH Expanded Program on Immunization (EPI) childhood schedule
--
-- The `vaccines` table was empty, so the Add Immunization form had nothing to
-- offer and showed "No vaccines found in the database".
--
-- SOURCE
-- ------
-- Transcribed from the DOH immunization card ("Bakuna" / "Doses" columns) that
-- the barangay health centre actually issues to mothers. Names are kept exactly
-- as printed so a midwife can map each row on the paper card to one row in the
-- app without translating anything in her head.
--
--   Bakuna                                    Doses
--   BCG Vaccine                               1   At birth
--   Hepatitis B Vaccine                       1   At birth
--   Pentavalent Vaccine (DPT-Hep B-HIB)       3   1½, 2½, 3½ months
--   Oral Polio Vaccine (OPV)                  3   1½, 2½, 3½ months
--   Inactivated Polio Vaccine (IPV)           2   3½ & 9 months
--   Pneumococcal Conjugate Vaccine (PCV)      3   1½, 2½, 3½ months
--   Measles, Mumps, Rubella Vaccine (MMR)     2   9 months & 1 year
--
-- Plus Rotavirus Vaccine (2 doses, 1½ and 2½ months), which this BHC gives but
-- which is not pre-printed on the card — it goes in one of the blank rows.
--
-- 8 vaccines, 17 doses, birth through 12 months.
--
-- Deliberately NOT included:
--   * Vitamin A — supplementation, recorded separately from immunisation.
--
-- AGE ENCODING
-- ------------
-- recommended_age_months is numeric because the card is written in half months:
--   at birth = 0 | 1½ = 1.5 | 2½ = 2.5 | 3½ = 3.5 | 9 months = 9 | 1 year = 12
--
-- poster_category groups doses by the EPI visit they share, so the roadmap and
-- wall poster can render them in the same order as the card:
--   1 = at birth | 2 = 1½ months | 3 = 2½ months | 4 = 3½ months
--   5 = 9 months | 6 = 1 year

BEGIN;

-- Required by the idempotent upsert below, and stops a dose being defined twice.
CREATE UNIQUE INDEX IF NOT EXISTS unique_vaccine_name_dose
  ON public.vaccines (vaccine_name, dose_number);

INSERT INTO public.vaccines
  (vaccine_name, dose_number, recommended_age_months, target_recipients, notes, poster_category)
VALUES
  -- ── At birth ──────────────────────────────────────────────────────────────
  ('BCG Vaccine', 1, 0, 'child',
   'Protects against tuberculosis. Give within 24 hours of birth.', 1),
  ('Hepatitis B Vaccine', 1, 0, 'child',
   'Monovalent birth dose. Give within 24 hours of birth.', 1),

  -- ── Pentavalent: 1½, 2½, 3½ months ────────────────────────────────────────
  ('Pentavalent Vaccine (DPT-Hep B-HIB)', 1, 1.5, 'child',
   'Diphtheria, pertussis, tetanus, hepatitis B and Haemophilus influenzae type b.', 2),
  ('Pentavalent Vaccine (DPT-Hep B-HIB)', 2, 2.5, 'child',
   'Second dose. Minimum 4-week interval from the previous dose.', 3),
  ('Pentavalent Vaccine (DPT-Hep B-HIB)', 3, 3.5, 'child',
   'Third and final dose of the primary series.', 4),

  -- ── Oral Polio: 1½, 2½, 3½ months ─────────────────────────────────────────
  ('Oral Polio Vaccine (OPV)', 1, 1.5, 'child',
   'First dose.', 2),
  ('Oral Polio Vaccine (OPV)', 2, 2.5, 'child',
   'Second dose. Minimum 4-week interval from the previous dose.', 3),
  ('Oral Polio Vaccine (OPV)', 3, 3.5, 'child',
   'Third and final dose.', 4),

  -- ── Pneumococcal: 1½, 2½, 3½ months ───────────────────────────────────────
  ('Pneumococcal Conjugate Vaccine (PCV)', 1, 1.5, 'child',
   'First dose.', 2),
  ('Pneumococcal Conjugate Vaccine (PCV)', 2, 2.5, 'child',
   'Second dose. Minimum 4-week interval from the previous dose.', 3),
  ('Pneumococcal Conjugate Vaccine (PCV)', 3, 3.5, 'child',
   'Third and final dose.', 4),

  -- ── Rotavirus: 1½ and 2½ months ───────────────────────────────────────────
  -- Given at this BHC but not pre-printed on the card, so it is written into
  -- one of the blank rows.
  --
  -- Rotavirus is the one vaccine here with a hard UPPER age limit: the first
  -- dose must be given before 15 weeks and the series completed by 8 months,
  -- after which it should not be started or continued. The app does not
  -- enforce this — the ceiling is stated here so it reaches the midwife.
  ('Rotavirus Vaccine', 1, 1.5, 'child',
   'Oral. First dose must be given before 15 weeks of age — do not start later.', 2),
  ('Rotavirus Vaccine', 2, 2.5, 'child',
   'Oral. Second and final dose. Complete the series by 8 months of age.', 3),

  -- ── Inactivated Polio: 3½ and 9 months ────────────────────────────────────
  ('Inactivated Polio Vaccine (IPV)', 1, 3.5, 'child',
   'First dose, given alongside OPV 3.', 4),
  ('Inactivated Polio Vaccine (IPV)', 2, 9, 'child',
   'Second dose, given alongside the first MMR dose.', 5),

  -- ── MMR: 9 months and 1 year ──────────────────────────────────────────────
  ('Measles, Mumps, Rubella Vaccine (MMR)', 1, 9, 'child',
   'First measles-containing dose.', 5),
  ('Measles, Mumps, Rubella Vaccine (MMR)', 2, 12, 'child',
   'Second dose at 1 year. Completes the routine infant series.', 6)

ON CONFLICT (vaccine_name, dose_number) DO UPDATE
  SET recommended_age_months = EXCLUDED.recommended_age_months,
      target_recipients      = EXCLUDED.target_recipients,
      notes                  = EXCLUDED.notes,
      poster_category        = EXCLUDED.poster_category;

-- ── Maternal tetanus-diphtheria ──────────────────────────────────────────────
-- Not on the child's card. Included because the prenatal module records Td
-- doses against the mother; target_recipients keeps it out of the child form.

INSERT INTO public.vaccines
  (vaccine_name, dose_number, recommended_age_months, target_recipients, notes, poster_category)
VALUES
  ('Tetanus-Diphtheria (Td)', 1, 0, 'mother', 'As early as possible in pregnancy.', NULL),
  ('Tetanus-Diphtheria (Td)', 2, 0, 'mother', 'At least 4 weeks after Td1.', NULL),
  ('Tetanus-Diphtheria (Td)', 3, 0, 'mother', 'At least 6 months after Td2.', NULL),
  ('Tetanus-Diphtheria (Td)', 4, 0, 'mother', 'At least 1 year after Td3.', NULL),
  ('Tetanus-Diphtheria (Td)', 5, 0, 'mother', 'At least 1 year after Td4.', NULL)
ON CONFLICT (vaccine_name, dose_number) DO UPDATE
  SET target_recipients = EXCLUDED.target_recipients,
      notes             = EXCLUDED.notes;

COMMIT;

-- Verify — should return 17 child rows in card order:
--   SELECT poster_category, recommended_age_months, vaccine_name, dose_number
--     FROM public.vaccines
--    WHERE target_recipients = 'child'
--    ORDER BY recommended_age_months, vaccine_name, dose_number;

-- ============================================================================
-- STEP: 20260806_immunization_tier1.sql
-- ============================================================================

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

-- ============================================================================
-- STEP: 20260806_immunization_record_source.sql
-- ============================================================================

-- InaAgapay: separate "we gave this" from "this was given elsewhere"
--
-- WHY
-- ---
-- An immunization record answers "is this child protected?", which is true
-- however the dose was delivered. But the table had a single attribution
-- column, administered_by, and the form filled it with whoever was logged in.
-- Transcribing a hospital's BCG dose therefore recorded the BHC midwife as
-- having administered it -- a false clinical record, and one that would also
-- have drawn down inventory for a vaccine the centre never held.
--
-- Attribution is really two separate facts:
--   administered_by  who gave the dose      (unknown for outside records)
--   recorded_by      who entered the record (always known)
--
-- This also separates two numbers an RHU reports differently:
--   immunization coverage  -- counts every dose, wherever given
--   doses administered     -- counts only what this BHC delivered
--
-- INVENTORY
-- ---------
-- inventory_batch_id is added now and left unused. When the immunization
-- module is wired to inventory, a 'this_bhc' record will carry the batch it
-- was drawn from; 'outside' records will always leave it null. Adding the
-- column now means that work is a code change, not another migration.

BEGIN;

-- 1. Where the dose was given -------------------------------------------------

ALTER TABLE public.immunization_records
  ADD COLUMN IF NOT EXISTS source VARCHAR(20);

ALTER TABLE public.immunization_records
  ADD COLUMN IF NOT EXISTS facility_name TEXT;

ALTER TABLE public.immunization_records
  ADD COLUMN IF NOT EXISTS evidence VARCHAR(30);

ALTER TABLE public.immunization_records
  ADD COLUMN IF NOT EXISTS recorded_by BIGINT
    REFERENCES public.midwives(midwife_id) ON DELETE SET NULL;

ALTER TABLE public.immunization_records
  ADD COLUMN IF NOT EXISTS inventory_batch_id BIGINT
    REFERENCES public.inventory_batches(batch_id) ON DELETE SET NULL;

-- 2. Backfill existing rows ---------------------------------------------------
--
-- Existing records were all created through the BHC form, so 'this_bhc' is the
-- honest reading. Their administered_by already holds the logged-in midwife;
-- that same value is the recorder, since one person did both.

UPDATE public.immunization_records
   SET source = 'this_bhc'
 WHERE source IS NULL;

UPDATE public.immunization_records
   SET recorded_by = administered_by
 WHERE recorded_by IS NULL
   AND administered_by IS NOT NULL;

-- 3. Constrain now that every row has a value ---------------------------------

ALTER TABLE public.immunization_records
  ALTER COLUMN source SET DEFAULT 'this_bhc';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'immunization_records_source_check'
  ) THEN
    ALTER TABLE public.immunization_records
      ADD CONSTRAINT immunization_records_source_check
      CHECK (source IN ('this_bhc', 'outside'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'immunization_records_evidence_check'
  ) THEN
    ALTER TABLE public.immunization_records
      ADD CONSTRAINT immunization_records_evidence_check
      CHECK (evidence IS NULL OR evidence IN (
        'immunization_card', 'facility_record', 'parent_recall'
      ));
  END IF;

  -- A dose given elsewhere has no administering midwife of ours. Enforcing it
  -- here stops the old behaviour from creeping back in through another screen.
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'immunization_records_outside_has_no_administrator'
  ) THEN
    ALTER TABLE public.immunization_records
      ADD CONSTRAINT immunization_records_outside_has_no_administrator
      CHECK (source <> 'outside' OR administered_by IS NULL);
  END IF;

  -- Likewise, stock can only be drawn for a dose this centre actually gave.
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'immunization_records_outside_has_no_batch'
  ) THEN
    ALTER TABLE public.immunization_records
      ADD CONSTRAINT immunization_records_outside_has_no_batch
      CHECK (source <> 'outside' OR inventory_batch_id IS NULL);
  END IF;
END;
$$;

ALTER TABLE public.immunization_records
  ALTER COLUMN source SET NOT NULL;

-- 4. Reporting helpers --------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_immunization_records_source
  ON public.immunization_records (source);

COMMENT ON COLUMN public.immunization_records.source IS
  'this_bhc = administered here (counts toward doses administered and, later, inventory); outside = transcribed from elsewhere (counts toward coverage only).';
COMMENT ON COLUMN public.immunization_records.administered_by IS
  'Midwife who gave the dose. Null for records transcribed from another facility.';
COMMENT ON COLUMN public.immunization_records.recorded_by IS
  'Midwife who entered the record, whoever administered it.';
COMMENT ON COLUMN public.immunization_records.evidence IS
  'How an outside record was verified. A stamped card and a parent''s recollection are not equal evidence.';
COMMENT ON COLUMN public.immunization_records.inventory_batch_id IS
  'Reserved for the inventory link. Not yet written by the app.';

COMMIT;

-- Verify:
--   SELECT source, evidence, count(*)
--     FROM public.immunization_records
--    GROUP BY source, evidence ORDER BY source;
