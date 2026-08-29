-- ==============================================================================
-- MIGRATION: 20260902_backfill_undeducted_prenatal_supplements.sql
--
-- Posts the stock movements that deduct_prenatal_encounter_inventory owed but
-- never wrote. Until 20260901_prenatal_deduction_column_fix.sql that RPC raised
-- 42703 on every call, so every prenatal checkup that dispensed Ferrous or
-- Calcium saved the clinical record, handed the tablets over, and left the
-- shelf count untouched. As of 2026-08-29 that is 4 given_medications rows,
-- 150 units, dispensed between 2026-08-19 and 2026-08-29.
--
-- WHY REPLAY RATHER THAN ADJUST
--
--   A blind 'adjustment' row per batch would fix the counts and nothing else:
--   no medication name, no mother, no encounter, and given_medications.
--   inventory_batch_id would stay NULL -- which is the only thing that tells a
--   reconciled row from a still-pending one. Replaying through the RPC writes
--   a 'Prenatal Encounter' row the dose ledger (20260830) and the midwife
--   inventory UI both recognise, and stamps the batch id so this file cannot
--   act on the same row twice.
--
-- WHAT IT DELIBERATELY DOES NOT DO
--
--   p_deduct_td is FALSE. The maternal Td path is separate:
--   sync_prenatal_td_to_maternal_records already wrote a maternal_td_records
--   row for these checkups with inventory_deducted = true, and Td stock may
--   also have moved through administer_maternal_td_dose. Replaying Td here
--   could deduct a vial twice. Td is reconciled separately, by hand, against
--   maternal_td_records.
--
--   logged_at is NOW(), not the original date_given. These rows record when
--   the correction was posted, which is the truth. The dispense date stays on
--   given_medications.date_given.
--
-- IDEMPOTENT BY CONSTRUCTION
--
--   Only encounters whose given_medications rows ALL still have a NULL
--   inventory_batch_id are touched. A successful deduction stamps that column,
--   so a second run selects nothing. An encounter that was partly satisfied
--   (one supplement in stock, one not) is skipped from then on rather than
--   half-replayed -- deliberately conservative: re-running must never risk
--   deducting the same tablets twice. Those are listed by the audit query at
--   the foot of this file so they can be settled by hand.
--
-- Requires 20260901_prenatal_deduction_column_fix.sql.
-- ==============================================================================


-- ---------------------------------------------------------------------------
-- 1. What this will act on. Run alone first; it changes nothing.
-- ---------------------------------------------------------------------------
SELECT gm.encounter_id,
       MIN(gm.date_given)                          AS dispensed_on,
       string_agg(gm.given_medication_name || ' x' || gm.quantity, ', '
                  ORDER BY gm.given_medication_name) AS pending,
       SUM(gm.quantity)                            AS units
  FROM public.given_medications gm
 WHERE gm.encounter_id IS NOT NULL
   AND gm.quantity > 0
 GROUP BY gm.encounter_id
HAVING count(*) FILTER (WHERE gm.inventory_batch_id IS NOT NULL) = 0
 ORDER BY gm.encounter_id;


-- ---------------------------------------------------------------------------
-- 2. The replay.
--
-- Wrap in BEGIN / ROLLBACK to rehearse it; BEGIN / COMMIT to keep it. Read
-- every `result` before committing: a "warnings" entry means that medication
-- could not be fully covered from the shelf and the shortfall is still owed.
-- ---------------------------------------------------------------------------
BEGIN;

SELECT e.encounter_id,
       e.units_pending,
       public.deduct_prenatal_encounter_inventory(
         e.encounter_id,
         e.facility_id,
         NULL,      -- performed_by: resolve_actor_account_id() leaves it NULL,
                    -- so the ledger reads "System" rather than naming a midwife
                    -- who did not post this correction.
         FALSE      -- p_deduct_td: see the header.
       ) AS result
  FROM (
    SELECT gm.encounter_id,
           max(gm.facility_id) AS facility_id,
           sum(gm.quantity)    AS units_pending
      FROM public.given_medications gm
     WHERE gm.encounter_id IS NOT NULL
       AND gm.quantity > 0
     GROUP BY gm.encounter_id
    HAVING count(*) FILTER (WHERE gm.inventory_batch_id IS NOT NULL) = 0
  ) e
 ORDER BY e.encounter_id;

COMMIT;

-- To rehearse instead, replace the COMMIT above with ROLLBACK. Do not leave
-- the transaction unterminated: the Supabase SQL editor discards an open
-- transaction when the connection is returned to the pool, so the deduction
-- reports success and is then thrown away.



-- ---------------------------------------------------------------------------
-- 3. After committing: what is left owed.
--
-- Rows still NULL here were not covered -- the item is missing from the
-- catalogue, or the shelf was empty. They need stock received, or a manual
-- adjustment, before they can be settled.
-- ---------------------------------------------------------------------------
SELECT gm.encounter_id,
       gm.given_medication_name,
       gm.quantity,
       gm.date_given,
       CASE WHEN gm.encounter_id IS NULL
            THEN 'no encounter_id - cannot be replayed, settle by hand'
            ELSE 'not covered from stock'
       END AS reason
  FROM public.given_medications gm
 WHERE gm.inventory_batch_id IS NULL
   AND gm.quantity > 0
 ORDER BY gm.date_given, gm.encounter_id;
