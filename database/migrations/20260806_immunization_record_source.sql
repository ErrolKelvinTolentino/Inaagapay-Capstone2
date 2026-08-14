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
