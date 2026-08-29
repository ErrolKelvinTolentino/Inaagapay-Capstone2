-- ==============================================================================
-- MIGRATION: 20260903_drop_legacy_given_medication_deduct_trigger.sql
--
-- Removes trg_deduct_inventory_medication and the function behind it,
-- deduct_inventory_on_given_medication(). Both have stood in the base schema
-- since active-draftschema.sql and no migration has ever touched them.
--
-- WHAT IT DID
--
--   AFTER INSERT ON given_medications, when NEW.inventory_batch_id was set:
--     * quantity_remaining = quantity_remaining - NEW.quantity, with no FEFO,
--       no facility check and no guard against going negative beyond the
--       table CHECK;
--     * one inventory_transactions row carrying no facility_id, no
--       performed_by, no notes, no resulting_quantity_remaining, and
--       reference_type = 'given_medication'.
--
--   That reference_type is recognised by nothing. inventory_dose_ledger
--   (20260830) joins only 'Child Immunization', 'Maternal Td Immunization' and
--   'Prenatal Encounter'; InventoryLedgerRow.isAdministration in the app tests
--   the same three. A movement written by this trigger is invisible in both the
--   dose ledger and the midwife inventory UI, and audit_inventory_transaction
--   attributes it to "System" because performed_by is null.
--
-- WHY IT IS SAFE TO REMOVE
--
--   The trigger has been inert, by accident rather than design. The only writer
--   to given_medications is _insertSupplementRecords in
--   add_prenatal_checkup_screen.dart, which inserts encounter_id, mother_id,
--   facility_id, name, quantity and date_given -- never inventory_batch_id. The
--   deduction is done by deduct_prenatal_encounter_inventory, which attaches the
--   batch afterwards with an UPDATE. This trigger fires on INSERT only, so it
--   never saw it. Every other reference to the table in the app and the portal
--   is a read, and no SQL function inserts into it.
--
--   So the trigger deducts nothing today. What it is, is a second uncoordinated
--   deduction path waiting for the first caller that happens to set a batch id
--   on insert -- at which point that dispense comes off the shelf twice, once
--   properly and once invisibly.
--
-- Section 1 reports anything it wrote historically before section 2 removes it.
-- Dropping a trigger needs no audit_trail row; the audit triggers cover data,
-- not schema.
--
-- Safe to run more than once.
-- ==============================================================================


-- ---------------------------------------------------------------------------
-- 1. Did it ever fire? Run alone first; it changes nothing.
--
-- Rows here were deducted by the trigger, not by any RPC. Expected: none. If
-- any come back, that stock left the shelf without appearing in the dose ledger
-- or the inventory UI, and those batches want reconciling before you drop it.
-- ---------------------------------------------------------------------------
SELECT t.transaction_id,
       t.logged_at,
       t.batch_id,
       b.batch_number,
       i.name AS item,
       t.quantity,
       t.reference_id AS given_medication_id
  FROM public.inventory_transactions t
  LEFT JOIN public.inventory_batches b ON b.batch_id = t.batch_id
  LEFT JOIN public.inventory_items   i ON i.item_id  = b.item_id
 WHERE t.reference_type = 'given_medication'
 ORDER BY t.logged_at DESC;


-- ---------------------------------------------------------------------------
-- 2. Remove it.
--
-- The function goes too. Leaving it behind leaves the trigger one CREATE
-- TRIGGER away from coming back, and nothing else calls it.
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_deduct_inventory_medication ON public.given_medications;

DROP FUNCTION IF EXISTS public.deduct_inventory_on_given_medication();


-- ---------------------------------------------------------------------------
-- 3. Confirm.
--
-- Both counts must come back 0.
-- ---------------------------------------------------------------------------
SELECT (SELECT count(*) FROM pg_trigger
         WHERE tgname = 'trg_deduct_inventory_medication'
           AND NOT tgisinternal)                              AS trigger_remaining,
       (SELECT count(*) FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public'
           AND p.proname = 'deduct_inventory_on_given_medication') AS function_remaining;
