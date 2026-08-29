-- ==============================================================================
-- MIGRATION: 20260905_maternal_td_deduction_flag_truthful.sql
--
-- Makes maternal_td_records.inventory_deducted mean what it says, and closes a
-- double-deduction hole that the untruthful flag was hiding.
--
-- WHAT WAS WRONG
--
--   sync_prenatal_td_to_maternal_records fires AFTER INSERT on
--   prenatal_checkups and writes the Td record with
--
--       inventory_deducted = true,  inventory_batch_id = NULL
--
--   It cannot possibly know that. The trigger runs while the checkup row is
--   being inserted; the app calls deduct_prenatal_encounter_inventory
--   afterwards, and only that call decides whether a vial is opened -- it is
--   skipped entirely when the midwife did not give the dose on site, and it
--   reports a warning instead of deducting when the shelf is empty. Until
--   20260901 it raised 42703 on every single call, so the flag was false in
--   reality for every row ever written by this trigger.
--
--   That is a clinical record asserting a vial left stock when none did.
--
-- THE PART THAT IS WORSE THAN A WRONG LABEL
--
--   administer_maternal_td_dose guards against deducting the same dose twice,
--   but it guards on inventory_batch_id, not on this boolean:
--
--       v_mode := CASE WHEN v_batch_id IS NOT NULL
--                      THEN 'already_deducted' ELSE 'no_deduction' END;
--
--   The sync trigger sets the flag true and leaves the batch NULL. So a dose
--   given at a prenatal checkup, whose stock deduct_prenatal_encounter_inventory
--   genuinely took, still looks unlinked to that guard -- and administering the
--   same dose through the drive path opens a SECOND vial for it. The record
--   claimed the deduction had happened while the only column that prevents a
--   repeat said it had not.
--
-- THE FIX
--
--   (1) The trigger records what is true when it runs: not deducted, no batch.
--
--   (2) A new trigger on inventory_transactions marks the record deducted at
--       the moment stock actually moves for it, stamping the batch as well --
--       which is what makes the existing guard work. Done here rather than
--       inside deduct_prenatal_encounter_inventory so that 340-line function
--       does not have to be restated for a two-column update, and so any
--       future writer of that ledger row gets the same treatment for free.
--
--       'Maternal Td Immunization' is written by two callers with different
--       meanings for reference_id -- an encounter id from the prenatal path, a
--       td_record id from administer_maternal_td_dose. Resolving the id as an
--       encounter is what tells them apart: a td_record id matches no encounter
--       and the trigger does nothing, which is correct, because that function
--       already sets both columns itself.
--
--   (3) Existing rows are corrected from the ledger. A row claiming a deduction
--       with no batch is false by the codebase's own definition of the flag;
--       where the ledger shows the stock really did move, the batch is filled in
--       and the claim stands.
--
-- Nothing reads this column in the app or the portal, so no screen changes.
--
-- Requires 20260819_td_canonical_sync.sql and 20260901_prenatal_deduction_column_fix.sql.
-- Safe to run more than once.
-- ==============================================================================


-- ---------------------------------------------------------------------------
-- 1. The sync trigger states the truth at the time it runs.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sync_prenatal_td_to_maternal_records()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $fn$
DECLARE
  v_dose TEXT;
  v_mother BIGINT;
  v_date DATE;
  v_facility BIGINT;
  v_recorded_by BIGINT;
  v_admin BIGINT;
  v_prot DATE;
  v_next DATE;
BEGIN
  v_dose := public.normalize_td_dose(NEW.td_vaccine_dose);
  IF v_dose IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT ce.mother_id,
         COALESCE(ce.encounter_datetime::DATE, ce.created_at::DATE, CURRENT_DATE),
         ce.facility_id,
         ce.recorded_by
    INTO v_mother, v_date, v_facility, v_recorded_by
  FROM public.clinical_encounters ce
  WHERE ce.encounter_id = NEW.encounter_id;

  IF v_mother IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT o_protection_until, o_next_due INTO v_prot, v_next
  FROM public.td_dose_schedule(v_dose, v_date);

  -- Only reference a real midwife row, otherwise leave NULL (avoids FK violation)
  SELECT midwife_id INTO v_admin FROM public.midwives WHERE midwife_id = v_recorded_by;

  INSERT INTO public.maternal_td_records (
    mother_id, dose_number, vaccination_date, facility_id, source,
    administered_by, inventory_deducted, protection_until, next_due_date, remarks
  ) VALUES (
    v_mother, v_dose, v_date, v_facility, 'bhc',
    v_admin,
    -- Not deducted, because nothing has been deducted yet. This trigger runs
    -- during the checkup insert; deduct_prenatal_encounter_inventory is called
    -- afterwards and may skip the dose or find no stock.
    -- trg_maternal_td_mark_deducted flips this when a vial actually moves.
    false,
    v_prot, v_next, 'Recorded during prenatal checkup'
  )
  ON CONFLICT (mother_id, dose_number) DO NOTHING;

  RETURN NEW;
END $fn$;

DROP TRIGGER IF EXISTS trg_sync_prenatal_td ON public.prenatal_checkups;
CREATE TRIGGER trg_sync_prenatal_td
AFTER INSERT OR UPDATE OF td_vaccine_dose ON public.prenatal_checkups
FOR EACH ROW
EXECUTE FUNCTION public.sync_prenatal_td_to_maternal_records();


-- ---------------------------------------------------------------------------
-- 2. Mark it deducted when stock actually moves.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.maternal_td_mark_deducted()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_mother BIGINT;
  v_dose   TEXT;
  v_date   DATE;
BEGIN
  IF COALESCE(NEW.reference_type, '') <> 'Maternal Td Immunization'
     OR NEW.reference_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- See the header: resolving reference_id as an encounter is what separates
  -- the prenatal path from administer_maternal_td_dose, which stamps both
  -- columns itself. That function writes a td_record_id here, and the two
  -- sequences are independent, so an id alone can match the wrong row --
  -- hence matching the whole event below: mother, dose and date together.
  SELECT ce.mother_id,
         public.normalize_td_dose(pc.td_vaccine_dose),
         COALESCE(ce.encounter_datetime::date, ce.created_at::date)
    INTO v_mother, v_dose, v_date
    FROM public.clinical_encounters ce
    JOIN public.prenatal_checkups pc ON pc.encounter_id = ce.encounter_id
   WHERE ce.encounter_id = NEW.reference_id;

  IF v_mother IS NULL OR v_dose IS NULL THEN
    RETURN NULL;
  END IF;

  UPDATE public.maternal_td_records
     SET inventory_batch_id = COALESCE(inventory_batch_id, NEW.batch_id),
         inventory_deducted = true
   WHERE mother_id        = v_mother
     AND dose_number      = v_dose
     AND vaccination_date = v_date;

  RETURN NULL;
END $fn$;

DROP TRIGGER IF EXISTS trg_maternal_td_mark_deducted
  ON public.inventory_transactions;

CREATE TRIGGER trg_maternal_td_mark_deducted
  AFTER INSERT ON public.inventory_transactions
  FOR EACH ROW
  EXECUTE FUNCTION public.maternal_td_mark_deducted();


-- ---------------------------------------------------------------------------
-- 3. Correct the rows already written, from the ledger.
--
-- 3a. The stock really did move: fill in the batch the claim was missing.
-- ---------------------------------------------------------------------------
-- reference_id is only an encounter id when the prenatal path wrote the row.
-- administer_maternal_td_dose puts a td_record_id there, and those two
-- sequences are independent -- id 7 exists in both tables. Joining on the id
-- alone would hand a batch to whichever encounter happened to share a number.
--
-- So the match has to hold on the whole event, not the id: same mother, same
-- dose, and the same date. A collision surviving all three is the same
-- vaccination described twice, which is the case this is trying to fix anyway.
WITH moved AS (
  SELECT DISTINCT ON (ce.mother_id, public.normalize_td_dose(pc.td_vaccine_dose))
         ce.mother_id                                 AS mother_id,
         public.normalize_td_dose(pc.td_vaccine_dose) AS dose_number,
         COALESCE(ce.encounter_datetime::date,
                  ce.created_at::date)                AS given_on,
         t.batch_id                                   AS batch_id
    FROM public.inventory_transactions t
    JOIN public.clinical_encounters ce ON ce.encounter_id = t.reference_id
    JOIN public.prenatal_checkups   pc ON pc.encounter_id = ce.encounter_id
   WHERE t.reference_type = 'Maternal Td Immunization'
     AND public.normalize_td_dose(pc.td_vaccine_dose) IS NOT NULL
   ORDER BY ce.mother_id,
            public.normalize_td_dose(pc.td_vaccine_dose),
            t.logged_at DESC
)
UPDATE public.maternal_td_records r
   SET inventory_batch_id = COALESCE(r.inventory_batch_id, moved.batch_id),
       inventory_deducted = true
  FROM moved
 WHERE r.mother_id        = moved.mother_id
   AND r.dose_number      = moved.dose_number
   AND r.vaccination_date = moved.given_on;


-- ---------------------------------------------------------------------------
-- 3b. Everything still claiming a deduction with no batch behind it is false.
--     administer_maternal_td_dose defines the flag as (batch IS NOT NULL); this
--     brings the rows the sync trigger wrote into line with that definition.
-- ---------------------------------------------------------------------------
UPDATE public.maternal_td_records
   SET inventory_deducted = false
 WHERE inventory_deducted = true
   AND inventory_batch_id IS NULL;


-- ---------------------------------------------------------------------------
-- 4. What the column now means.
-- ---------------------------------------------------------------------------
COMMENT ON COLUMN public.maternal_td_records.inventory_deducted IS
  'True only once stock has actually moved for this dose, which is also when '
  'inventory_batch_id is set. Never written optimistically: the prenatal sync '
  'trigger records false and trg_maternal_td_mark_deducted flips it when the '
  'ledger row appears. administer_maternal_td_dose guards repeat deductions on '
  'inventory_batch_id, so the two must agree.';


-- ---------------------------------------------------------------------------
-- 5. What changed. Run alone afterwards; it reports, it does not write.
-- ---------------------------------------------------------------------------
SELECT count(*) FILTER (WHERE inventory_deducted AND inventory_batch_id IS NOT NULL)
         AS deducted_with_batch,
       count(*) FILTER (WHERE NOT inventory_deducted)
         AS not_deducted,
       count(*) FILTER (WHERE inventory_deducted AND inventory_batch_id IS NULL)
         AS still_inconsistent
  FROM public.maternal_td_records;
