-- ==============================================================================
-- MIGRATION: 20260911_audit_dose_level_summary.sql
--
-- Makes the activity log tell the truth about a dose drawn from an open vial,
-- and stops it inventing a second plural.
--
-- THE BUG
--
--   The one-line summary the audit trail displays is built by
--   audit_inventory_transaction() as:
--
--       format('%s: %s of %s at %s', v_kind,
--              public.audit_qty(NEW.quantity, v_unit), v_item, v_where)
--
--   NEW.quantity counts WHOLE SEALED UNITS. Since 20260910, a midwife
--   dispensing in doses draws from the vial that is already open and breaks no
--   seal at all, so quantity is legitimately 0 and the ledger row carries the
--   real figure in dose_quantity instead. The summary read:
--
--       "Dispensed: 0 vialss of Tetanus Diphtheria (Td) Vaccine at
--        Pinagbarilan BHC (BHC)"
--
--   Two separate faults in one line:
--
--     1. "0 vials" says nothing left the shelf, on the audit record of an
--        act that gave a patient a dose. The narrative on the same row has
--        always said it properly -- "no whole unit moved - drawn from a vial
--        already open", with the dose count beside it -- but the summary is
--        what the log lists, exports and prints.
--
--     2. "vialss". audit_qty() appends 's' for any quantity other than 1,
--        without looking at what it is appending to. inventory_items
--        .unit_of_measure already holds the plural for this item, so the
--        function pluralised a plural. This affected every audit line for
--        every item whose unit is stored that way, not only this one.
--
-- THE FIX
--
--   audit_qty() singularises the unit before deciding, so 'vial' and 'vials'
--   both yield "1 vial" and "2 vials". Nothing else about it changes.
--
--   audit_inventory_transaction() reports the dose count when no whole unit
--   moved but doses did:
--
--       "Dispensed: 1 dose from an open vial of Tetanus Diphtheria (Td)
--        Vaccine at Pinagbarilan BHC (BHC)"
--
--   A movement that does break seals is untouched and still reads in units.
--
-- WHAT THIS DOES NOT DO
--
--   It does not rewrite the summaries already stored on existing audit_trail
--   rows. Those are the record of what was written at the time, and editing
--   them is not something an audit trail should permit; the narrative and the
--   "Quantity in doses" detail row on each of those entries already carry the
--   correct figure.
--
-- Both functions are replaced at their EXISTING signatures, so no second
-- overload is created and the grants already on them are preserved.
--
-- Requires 20260826_audit_trail_completeness.sql.
-- Safe to run more than once.
-- ==============================================================================


-- ---------------------------------------------------------------------------
-- 1. One plural, not two.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.audit_qty(p_qty NUMERIC, p_unit TEXT DEFAULT 'unit')
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $fn$
  -- The unit is singularised first because unit_of_measure is free text that
  -- may already be plural ('vials', 'tabs'). Deciding the plural from a known
  -- singular is the only way to get both "1 vial" and "2 vials" out of either
  -- spelling. A unit that is genuinely singular and ends in 's' is not a thing
  -- this catalogue holds.
  SELECT CASE
           WHEN p_qty IS NULL THEN NULL
           ELSE trim(to_char(abs(p_qty), 'FM999G999G990')) || ' ' ||
                regexp_replace(p_unit, 's$', '', 'i') ||
                CASE WHEN abs(p_qty) = 1 THEN '' ELSE 's' END
         END;
$fn$;


-- ---------------------------------------------------------------------------
-- 2. The movement summary, dose-aware.
--
-- Reproduced in full from 20260826 because CREATE OR REPLACE takes the whole
-- body. The only change is the v_summary assignment, marked below.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.audit_inventory_transaction()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_ctx       JSONB := public.audit_batch_context(NEW.batch_id);
  v_unit      TEXT;
  v_item      TEXT;
  v_where     TEXT;
  v_dir       TEXT;
  v_kind      TEXT;
  v_action    TEXT;
  v_summary   TEXT;
  v_narrative TEXT;
  v_rows      JSONB;
  v_counter   TEXT;
  v_transfer  public.inventory_transfers%ROWTYPE;
  v_ref       TEXT := COALESCE(NEW.reference_type, '');
  -- dose_quantity, notes and resulting_quantity_remaining arrive with 20260811
  -- / 20260822. Read through jsonb so this trigger also works on a database
  -- that has not applied them yet.
  v_json      JSONB := to_jsonb(NEW);
  v_doses     NUMERIC;
  v_balance   NUMERIC;
  v_note      TEXT;
  v_when      TIMESTAMPTZ;
BEGIN
  v_doses   := COALESCE(public.audit_bigint(v_json->>'dose_quantity'), NEW.quantity);
  v_balance := public.audit_bigint(v_json->>'resulting_quantity_remaining');
  v_note    := nullif(btrim(COALESCE(v_json->>'notes', '')), '');
  v_when    := COALESCE(public.audit_utc(NEW.logged_at), now());

  v_unit  := COALESCE(v_ctx->>'unit', 'unit');
  v_item  := COALESCE(v_ctx->>'item_name', 'Stock item');
  v_where := COALESCE(public.audit_facility_label(NEW.facility_id), v_ctx->>'facility_label');
  v_dir   := CASE WHEN COALESCE(NEW.quantity, 0) < 0 THEN 'out'
                  WHEN COALESCE(NEW.quantity, 0) > 0 THEN 'in'
                  ELSE 'internal' END;

  -- Name the movement the way a storekeeper would.
  v_kind := CASE
    WHEN v_ref IN ('Open Vial Discard', 'Open Vial Expiry', 'open_vial_expired')
      THEN 'Open-vial discard'
    WHEN v_ref = 'Child Immunization'         THEN 'Dose given to a child'
    WHEN v_ref = 'Maternal Td Immunization'   THEN 'Td dose given to a mother'
    WHEN v_ref ILIKE 'Prenatal%'              THEN 'Dispensed at a prenatal encounter'
    WHEN NEW.transaction_type = 'transfer' AND v_dir = 'out' THEN 'Dispatched to another facility'
    WHEN NEW.transaction_type = 'transfer' AND v_dir = 'in'  THEN 'Received from another facility'
    WHEN NEW.transaction_type = 'receipt'         THEN 'Stock received into the facility'
    WHEN NEW.transaction_type = 'expiry_disposal' THEN 'Disposed of'
    WHEN NEW.transaction_type = 'dispense'        THEN 'Dispensed'
    WHEN NEW.transaction_type = 'adjustment'      THEN 'Stock adjustment'
    ELSE initcap(replace(COALESCE(NEW.transaction_type, 'movement'), '_', ' '))
  END;

  v_action := 'inventory_movement_' || COALESCE(NEW.transaction_type, 'other');

  -- The other end of the movement, when there is one.
  IF NEW.transaction_type = 'transfer' AND NEW.reference_id IS NOT NULL THEN
    SELECT * INTO v_transfer FROM public.inventory_transfers
     WHERE transfer_id = NEW.reference_id;
    IF FOUND THEN
      v_counter := CASE WHEN v_dir = 'out'
                        THEN public.audit_facility_label(v_transfer.destination_facility_id)
                        ELSE COALESCE(
                               (public.audit_batch_context(v_transfer.source_batch_id))->>'facility_label',
                               'another facility')
                   END;
    END IF;
  END IF;

  -- A dose drawn from a vial that was ALREADY OPEN moves no whole unit, so
  -- NEW.quantity is 0 and this line used to read "Dispensed: 0 vials of ...",
  -- which states the opposite of what happened. The narrative below has always
  -- described the case correctly; the one-line summary -- the part the activity
  -- log actually displays -- did not. Report the doses when they are the whole
  -- of the movement.
  v_summary := CASE
    WHEN COALESCE(NEW.quantity, 0) = 0 AND COALESCE(v_doses, 0) <> 0
      THEN format('%s: %s from an open vial of %s at %s',
                  v_kind, public.audit_qty(v_doses, 'dose'), v_item, v_where)
    ELSE format('%s: %s of %s at %s',
                v_kind, public.audit_qty(NEW.quantity, v_unit), v_item, v_where)
  END;

  v_narrative := format(
    'A stock movement was posted to the ledger. %s. Item: %s, from batch %s%s. '
    'Quantity moved: %s (%s), which is %s in clinical terms. The movement was recorded %s %s. '
    '%s%sThe batch holds %s after this movement. Recorded by %s on %s.%s',
    v_kind,
    v_item,
    COALESCE(v_ctx->>'batch_number', 'unrecorded'),
    COALESCE(', expiring ' || public.audit_date((v_ctx->>'expiration_date')::date), ''),
    public.audit_qty(NEW.quantity, v_unit),
    CASE v_dir WHEN 'out' THEN 'leaving stock'
               WHEN 'in'  THEN 'entering stock'
               ELSE 'no whole unit moved - drawn from a vial already open' END,
    public.audit_qty(v_doses, 'dose'),
    CASE v_dir WHEN 'in' THEN 'into' ELSE 'at' END,
    v_where,
    CASE WHEN v_counter IS NOT NULL
         THEN format('The other end of this movement is %s. ', v_counter) ELSE '' END,
    CASE WHEN nullif(v_ref, '') IS NOT NULL
         THEN format('Reference recorded against it: "%s". ', v_ref) ELSE '' END,
    COALESCE(public.audit_qty(COALESCE(v_balance, (v_ctx->>'remaining')::numeric), v_unit),
             'an unrecorded balance'),
    COALESCE((public.audit_actor(NEW.performed_by))->>'name', 'System'),
    public.audit_ts(v_when),
    COALESCE(' Note: ' || v_note || '.', '')
  );

  v_rows := public.audit_kv('Movement', v_kind)
         || public.audit_kv('Ledger entry', '#' || NEW.transaction_id)
         || public.audit_kv('Item', v_item)
         || public.audit_kv('Item type', initcap(replace(COALESCE(v_ctx->>'item_type', ''), '_', ' ')))
         || public.audit_kv('Batch', v_ctx->>'batch_number')
         || public.audit_kv('Batch expiry', public.audit_date((v_ctx->>'expiration_date')::date))
         || public.audit_kv('Manufacturer', v_ctx->>'manufacturer')
         || public.audit_kv('Location', v_where)
         || public.audit_kv('Direction',
              CASE v_dir WHEN 'out' THEN 'Stock left this facility'
                         WHEN 'in'  THEN 'Stock entered this facility'
                         ELSE 'Drawn from an already-open vial - no whole unit moved' END)
         || public.audit_kv('Other end of the movement', v_counter)
         || public.audit_kv('Quantity in units', public.audit_qty(NEW.quantity, v_unit))
         || public.audit_kv('Quantity in doses', public.audit_qty(v_doses, 'dose'))
         || public.audit_kv('Balance in batch after',
              public.audit_qty(COALESCE(v_balance, (v_ctx->>'remaining')::numeric), v_unit))
         || public.audit_kv('Reference', nullif(v_ref, ''))
         || public.audit_kv('Linked record id', NEW.reference_id::text)
         || public.audit_kv('Note', v_note)
         || public.audit_kv('Recorded by', (public.audit_actor(NEW.performed_by))->>'name')
         || public.audit_kv('Recorded on', public.audit_ts(v_when));

  PERFORM public.audit_write(
    NEW.performed_by, v_action, 'inventory_transactions', NEW.transaction_id::text,
    public.audit_batch_label(v_ctx), v_summary, v_narrative,
    public.audit_section('Stock movement', v_rows),
    jsonb_build_object(
      'transaction_id', NEW.transaction_id, 'batch_id', NEW.batch_id,
      'item_id', v_ctx->>'item_id', 'facility_id', NEW.facility_id,
      'reference_type', nullif(v_ref, ''), 'reference_id', NEW.reference_id,
      'transfer_id', CASE WHEN NEW.transaction_type = 'transfer' THEN NEW.reference_id END),
    NULL, to_jsonb(NEW),
    CASE
      WHEN NEW.transaction_type = 'expiry_disposal' THEN 'warning'
      WHEN v_ref IN ('Open Vial Discard', 'Open Vial Expiry', 'open_vial_expired') THEN 'warning'
      WHEN NEW.transaction_type = 'adjustment' THEN 'warning'
      WHEN NEW.transaction_type = 'transfer' THEN 'notice'
      ELSE 'info'
    END,
    'movement'
  );

  RETURN NULL;
END
$fn$;

NOTIFY pgrst, 'reload schema';
