-- ==============================================================================
-- MIGRATION: 20260830_dose_traceability.sql
--
-- Makes a single dose answerable for itself: which vial it came out of, how many
-- doses that vial had left afterwards, which patient received it, who gave it,
-- and when.
--
-- 20260822_dose_accounting.sql taught the ledger to count doses. It stopped one
-- step short of tracing them:
--
--  (1) NO DOSE LEVEL WAS EVER RECORDED
--      resulting_quantity_remaining is UNITS. For a 10-dose Td vial it reads
--      the same before and after nine of the ten doses, because no whole vial
--      moved. inventory_batches.doses_remaining_in_open_vial holds the answer,
--      but only for right now - the moment the next dose is drawn the previous
--      level is gone. A midwife asking "the vial says 3 left, when did it go
--      from 7 to 3 and who drew them?" had nothing to read.
--
--      resulting_open_vial_doses below is the dose-level counterpart of
--      resulting_quantity_remaining. Every RPC that moves stock already updates
--      inventory_batches before it writes its ledger row, so a BEFORE INSERT
--      trigger can stamp the post-movement level without a single RPC being
--      rewritten - which matters, because the portal and these migrations
--      deploy separately and the app has to work either side of that gap.
--
--  (2) THE PATIENT WAS AN OPAQUE NUMBER
--      A dispense row carries reference_type = 'Child Immunization' and
--      reference_id = 57. 57 is an immunization_record_id. Naming the child
--      behind it takes a three-table join that neither the portal nor the app
--      performs, so both render "#57" and the trail stops there.
--
--      inventory_dose_ledger resolves it - child or mother, with the BHC
--      patient number the midwife's paper chart is filed under (NAK-000 /
--      INA-000) - alongside the batch, the item, the dose maths and the name of
--      whoever performed the movement.
--
-- Requires 20260822_dose_accounting.sql (dose_quantity, doses_per_unit).
-- Safe to run more than once.
-- ==============================================================================


-- ---------------------------------------------------------------------------
-- 1. resulting_open_vial_doses
-- ---------------------------------------------------------------------------
ALTER TABLE public.inventory_transactions
  ADD COLUMN IF NOT EXISTS resulting_open_vial_doses INTEGER;

COMMENT ON COLUMN public.inventory_transactions.resulting_open_vial_doses IS
  'Doses left in this batch open vial immediately after this movement. The '
  'dose-level counterpart of resulting_quantity_remaining, which counts whole '
  'units and therefore does not move when a dose is drawn from an open vial. '
  'Zero on single-dose presentations and on rows that emptied the vial.';


-- ---------------------------------------------------------------------------
-- 2. Stamp it from the batch
--
-- Fires BEFORE INSERT, and every writer updates inventory_batches first, so the
-- row it reads is already the post-movement state. Two writers are the
-- exception - dispense_stock_doses and sync_prenatal_dispense write their
-- open-vial write-off row before the batch UPDATE that clears the pool - and
-- both are discards, which always empty the vial. Forcing 0 on a discard is
-- therefore exact rather than a guess.
--
-- Named to sort after trg_inventory_transactions_dose_quantity so the two run
-- in a predictable order; they are independent, but a reader should not have to
-- work that out.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.inventory_transactions_fill_open_vial_level()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $fn$
DECLARE
  v_ref TEXT := COALESCE(NEW.reference_type, '');
BEGIN
  IF NEW.resulting_open_vial_doses IS NOT NULL THEN
    RETURN NEW;
  END IF;

  IF v_ref IN ('Open Vial Discard', 'Open Vial Expiry', 'open_vial_expired') THEN
    NEW.resulting_open_vial_doses := 0;
  ELSE
    SELECT COALESCE(b.doses_remaining_in_open_vial, 0)
      INTO NEW.resulting_open_vial_doses
      FROM public.inventory_batches b
     WHERE b.batch_id = NEW.batch_id;
  END IF;

  RETURN NEW;
END
$fn$;

DROP TRIGGER IF EXISTS trg_inventory_transactions_open_vial_level
  ON public.inventory_transactions;

CREATE TRIGGER trg_inventory_transactions_open_vial_level
  BEFORE INSERT ON public.inventory_transactions
  FOR EACH ROW
  EXECUTE FUNCTION public.inventory_transactions_fill_open_vial_level();


-- ---------------------------------------------------------------------------
-- 3. Backfill what history can honestly support
--
-- Only the newest row of each batch can be filled in: it is the one whose
-- aftermath is still on inventory_batches. Every earlier row's dose level was
-- overwritten by the movements that followed it and cannot be recovered, so it
-- stays NULL and the UIs render an em dash rather than a fabricated number.
-- ---------------------------------------------------------------------------
WITH latest AS (
  SELECT DISTINCT ON (batch_id) transaction_id, batch_id
    FROM public.inventory_transactions
   ORDER BY batch_id, logged_at DESC, transaction_id DESC
)
UPDATE public.inventory_transactions t
   SET resulting_open_vial_doses = COALESCE(b.doses_remaining_in_open_vial, 0)
  FROM latest l
  JOIN public.inventory_batches b ON b.batch_id = l.batch_id
 WHERE t.transaction_id = l.transaction_id
   AND t.resulting_open_vial_doses IS NULL;


-- ---------------------------------------------------------------------------
-- 4. inventory_dose_ledger
--
-- One row per stock movement, with everything a transparency question needs
-- already resolved. A view rather than columns on the table: the patient is
-- derivable from what is already stored, and denormalising it would mean
-- rewriting six RPCs and keeping them in step forever.
--
-- Patient resolution follows reference_type:
--
--   Child Immunization        reference_id -> immunization_records -> children
--   Maternal Td Immunization  ambiguous, see below
--   Prenatal Encounter        reference_id -> clinical_encounters -> mothers
--
-- The Td case is ambiguous by history: 20260821's path writes a
-- maternal_td_records.td_record_id, 20260823's writes a
-- clinical_encounters.encounter_id, and the two id spaces overlap. The join
-- below disambiguates on inventory_batch_id - a Td record only matches when it
-- points back at the same batch this row moved - and falls back to the
-- encounter reading otherwise.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.inventory_dose_ledger AS
SELECT
  t.transaction_id,
  t.batch_id,
  t.facility_id,
  t.transaction_type,
  t.quantity,
  t.dose_quantity,
  t.resulting_quantity_remaining,
  t.resulting_open_vial_doses,
  t.reference_type,
  t.reference_id,
  t.notes,
  t.activity_reason,
  t.activity_notes,
  -- Carried so the view is a drop-in replacement for the base table: the portal
  -- tells a BHC unusable-stock report apart from an ordinary disposal by the
  -- presence of this key, and a view that dropped it would silently relabel
  -- every one of those rows.
  t.client_operation_key,
  t.performed_by,
  t.logged_at,

  -- Batch
  b.batch_number,
  b.expiration_date,
  b.manufacturer,
  b.status                                    AS batch_status,
  b.vial_opened_at,

  -- Catalogue
  i.item_id,
  i.name                                      AS item_name,
  i.generic_name,
  i.unit_of_measure,
  GREATEST(1, COALESCE(i.doses_per_unit, 1))  AS doses_per_unit,
  COALESCE(i.open_vial_shelf_hours, 0)        AS open_vial_shelf_hours,
  i.item_type,

  -- Who performed it
  NULLIF(BTRIM(CONCAT_WS(' ', act.first_name, act.last_name)), '')
                                              AS performed_by_name,
  act.account_type                            AS performed_by_role,

  -- Who received it — as a chart number, never as a name.
  --
  -- This view exists for stock accountability, and that purpose is served in
  -- full by the number the physical chart is filed under. A name would be
  -- personal information carried past the point of necessity: the ledger is
  -- read by RHU and municipal officers who have no treatment relationship with
  -- the patient, and it exports to CSV, which leaves the system's access
  -- controls behind entirely.
  --
  -- 20260826_audit_trail_completeness.sql already set this rule for the audit
  -- trail — mothers are logged as 'Patient #<id>', their email nulled, and
  -- clinical values left in the snapshots "shown only to accounts cleared to
  -- read patient data". This view follows the same rule rather than opening a
  -- second door onto the same people.
  --
  -- Anyone who needs the name looks the number up in Patient Records, where
  -- that access is actually governed.
  CASE
    WHEN ch.child_id  IS NOT NULL THEN 'child'
    WHEN mo.mother_id IS NOT NULL THEN 'mother'
  END                                         AS patient_kind,
  ch.child_id                                 AS patient_child_id,
  mo.mother_id                                AS patient_mother_id,
  CASE
    -- The BHC chart number, when the patient has one.
    WHEN ch.child_id IS NOT NULL AND ch.child_number IS NOT NULL
      THEN 'NAK-' || LPAD(ch.child_number::TEXT, 3, '0')
    -- A mother's number is the one her chart at THIS facility is filed under.
    -- A number from a different BHC would be a real number pointing at the
    -- wrong patient, so it is not borrowed.
    WHEN mo.mother_id IS NOT NULL AND fa.patient_number IS NOT NULL
      THEN 'INA-' || LPAD(fa.patient_number::TEXT, 3, '0')
    -- No chart number yet: fall back to the internal id, in the same shape the
    -- audit trail uses. Still a pseudonym, and it keeps the trail unbroken
    -- instead of reading as though nobody received the dose.
    WHEN ch.child_id  IS NOT NULL THEN 'Child #'   || ch.child_id
    WHEN mo.mother_id IS NOT NULL THEN 'Patient #' || mo.mother_id
  END                                         AS patient_number

FROM public.inventory_transactions t
LEFT JOIN public.inventory_batches b ON b.batch_id = t.batch_id
LEFT JOIN public.inventory_items   i ON i.item_id  = b.item_id
LEFT JOIN public.accounts        act ON act.account_id = t.performed_by

-- Child immunisation -> the child
LEFT JOIN public.immunization_records ir
       ON t.reference_type = 'Child Immunization'
      AND ir.immunization_record_id = t.reference_id
LEFT JOIN public.children ch
       ON ch.child_id = ir.child_id

-- Maternal Td recorded against a Td record (batch must agree, see above)
LEFT JOIN public.maternal_td_records td
       ON t.reference_type = 'Maternal Td Immunization'
      AND td.td_record_id = t.reference_id
      AND td.inventory_batch_id = t.batch_id

-- Maternal Td or supplements recorded against a prenatal encounter
LEFT JOIN public.clinical_encounters ce
       ON t.reference_type IN ('Maternal Td Immunization', 'Prenatal Encounter')
      AND ce.encounter_id = t.reference_id
      AND td.td_record_id IS NULL

LEFT JOIN public.mothers mo
       ON mo.mother_id = COALESCE(td.mother_id, ce.mother_id)

-- LATERAL, not a plain join. facility_assignments has carried duplicate active
-- rows for the same account and facility before now - 20260821_dedupe_facility_
-- assignments.sql exists because of it - and a duplicate on a plain join would
-- silently emit the same stock movement twice, inflating every dose total read
-- off this view. LIMIT 1 makes the row count of the view exactly the row count
-- of inventory_transactions, whatever that table holds.
LEFT JOIN LATERAL (
  SELECT f.patient_number
    FROM public.facility_assignments f
   WHERE f.account_id  = mo.account_id
     AND f.facility_id = t.facility_id
     AND f.is_active   = true
     AND f.patient_number IS NOT NULL
   ORDER BY f.assigned_at DESC NULLS LAST, f.facility_assignment_id DESC
   LIMIT 1
) fa ON true;

COMMENT ON VIEW public.inventory_dose_ledger IS
  'Every inventory movement with its batch, dose maths, performing account and '
  'receiving patient already resolved. The patient is identified by BHC chart '
  'number only (NAK-000 / INA-000, falling back to an internal id) - never by '
  'name, matching the rule 20260826_audit_trail_completeness.sql set for the '
  'audit trail. Read-only trace for the admin portal ledger and the BHC dose '
  'history.';


-- ---------------------------------------------------------------------------
-- 5. Indexes for the lookups the view performs per row
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_inventory_transactions_reference
  ON public.inventory_transactions (reference_type, reference_id)
  WHERE reference_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_inventory_transactions_batch_logged
  ON public.inventory_transactions (batch_id, logged_at DESC);


-- ---------------------------------------------------------------------------
-- 6. Grants
-- ---------------------------------------------------------------------------
GRANT SELECT ON public.inventory_dose_ledger TO anon, authenticated, service_role;
