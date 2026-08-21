-- ==============================================================================
-- MIGRATION: 20260822_dose_accounting.sql
--
-- Makes the "one unit holds many doses" model hold on the admin portal's own
-- dispense path, and gives the ledger a column that means doses so the DOH
-- wastage figures stop mixing two units of measure.
--
--  (1) THE PORTAL DISPENSED WHOLE VIALS
--      admin-web's Dispense / Adjust Stock wrote
--          quantity_remaining = quantity_remaining - n
--      straight onto inventory_batches. For a 10-dose Td vial, dispensing "1"
--      destroyed one sealed vial and never touched doses_remaining_in_open_vial,
--      open_vials_count or vial_opened_at. Nine doses left the system with no
--      record that they ever existed, and the open-vial tracker never saw the
--      vial. Meanwhile deduct_immunization_stock, called from the mobile app,
--      opened the vial properly and tracked the remainder - so the two paths
--      disagreed about what "1" meant for the same batch.
--
--      dispense_stock_doses() below is the portal's counterpart to that RPC:
--      it takes DOSES, draws them from the open vial first, breaks as many
--      seals as it still needs, and leaves the remainder open and tracked. It
--      runs in one statement, so a concurrent dispense cannot interleave.
--
--  (2) quantity MEANT UNITS IN SOME ROWS AND DOSES IN OTHERS
--      inventory_transactions.quantity holds units for receipts, issues,
--      adjustments and batch disposals; it holds DOSES for open-vial discards
--      and open-vial expiries; and for a dose drawn from an already-open vial
--      deduct_immunization_stock writes 0, because no whole unit moved.
--
--      Anything that added those rows up produced a number that means nothing.
--      The portal's "Total Administered Doses" counted every open-vial dose as
--      zero, and its DOH wastage rate divided discarded doses by handled units.
--
--      dose_quantity is the signed dose count for every movement. Writers that
--      know the answer set it; a BEFORE INSERT trigger derives it for the ones
--      that do not, so no existing RPC has to be rewritten to benefit.
--
-- Requires 20260821_inventory_and_td_fixes.sql, which declares
-- resolve_actor_account_id() and widens the status / transaction_type CHECKs.
--
-- Safe to run more than once.
-- ==============================================================================


-- ---------------------------------------------------------------------------
-- 1. dose_quantity
-- ---------------------------------------------------------------------------
ALTER TABLE public.inventory_transactions
  ADD COLUMN IF NOT EXISTS dose_quantity INTEGER,
  -- Columns dispense_stock_doses writes to. Present on most databases already;
  -- guarded here so this file does not fail on one that skipped 20260811 or
  -- 20260819.
  ADD COLUMN IF NOT EXISTS notes TEXT,
  ADD COLUMN IF NOT EXISTS resulting_quantity_remaining INTEGER;

ALTER TABLE public.inventory_items
  ADD COLUMN IF NOT EXISTS doses_per_unit INTEGER DEFAULT 1,
  ADD COLUMN IF NOT EXISTS open_vial_shelf_hours INTEGER DEFAULT 6;

ALTER TABLE public.inventory_batches
  ADD COLUMN IF NOT EXISTS doses_remaining_in_open_vial INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS open_vials_count INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS vial_opened_at TIMESTAMPTZ;

COMMENT ON COLUMN public.inventory_transactions.dose_quantity IS
  'Signed clinical doses moved by this transaction. Negative for stock leaving. '
  'quantity stays in whole units; this column is always doses, so the two can be '
  'summed independently. Populated by the writer when it knows, otherwise derived '
  'by inventory_transactions_fill_dose_quantity().';


-- ---------------------------------------------------------------------------
-- 2. Doses per unit for a batch
--
-- Reads through to the catalogue item. Kept as a function because three
-- different places need it and inventory_batches has no copy of its own.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.batch_doses_per_unit(p_batch_id BIGINT)
RETURNS INTEGER
LANGUAGE sql
STABLE
AS $fn$
  SELECT GREATEST(1, COALESCE(i.doses_per_unit, 1))
    FROM public.inventory_batches b
    JOIN public.inventory_items i ON i.item_id = b.item_id
   WHERE b.batch_id = p_batch_id;
$fn$;


-- ---------------------------------------------------------------------------
-- 3. Derive dose_quantity for writers that do not set it
--
-- The rules are the ones the existing RPCs already follow:
--
--   * open-vial discards and expiries already write DOSES into quantity, so the
--     two columns agree;
--   * a clinical administration record moves exactly one dose, whether it came
--     from an open vial (quantity 0) or broke a fresh seal (quantity -1);
--   * everything else moves whole units, so doses = units x doses_per_unit.
--
-- A writer that sets dose_quantity itself always wins. dispense_stock_doses
-- does exactly that, because it is the one caller that can move a partial unit
-- and a whole one in the same row.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.inventory_transactions_fill_dose_quantity()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $fn$
DECLARE
  v_ref TEXT := COALESCE(NEW.reference_type, '');
BEGIN
  IF NEW.dose_quantity IS NOT NULL THEN
    RETURN NEW;
  END IF;

  IF v_ref IN ('Open Vial Discard', 'Open Vial Expiry', 'open_vial_expired') THEN
    -- quantity is already a dose count on these rows.
    NEW.dose_quantity := NEW.quantity;

  ELSIF v_ref IN ('Child Immunization', 'Maternal Td Immunization') THEN
    -- One patient, one dose. quantity is 0 when the dose came out of a vial
    -- that was already open, and -1 when this administration broke the seal.
    NEW.dose_quantity := -1;

  ELSE
    NEW.dose_quantity := NEW.quantity * public.batch_doses_per_unit(NEW.batch_id);
  END IF;

  RETURN NEW;
END
$fn$;

DROP TRIGGER IF EXISTS trg_inventory_transactions_dose_quantity
  ON public.inventory_transactions;

CREATE TRIGGER trg_inventory_transactions_dose_quantity
  BEFORE INSERT ON public.inventory_transactions
  FOR EACH ROW
  EXECUTE FUNCTION public.inventory_transactions_fill_dose_quantity();


-- ---------------------------------------------------------------------------
-- 4. Backfill the rows already on file
--
-- Best effort, and it says so: the same rules as the trigger, applied to
-- history. Rows written before doses_per_unit was configured for their item
-- read as single-dose, which is exactly what the portal already assumed of
-- them, so no displayed figure moves backwards.
-- ---------------------------------------------------------------------------
UPDATE public.inventory_transactions t
   SET dose_quantity = CASE
         WHEN COALESCE(t.reference_type, '') IN
              ('Open Vial Discard', 'Open Vial Expiry', 'open_vial_expired')
           THEN t.quantity
         WHEN COALESCE(t.reference_type, '') IN
              ('Child Immunization', 'Maternal Td Immunization')
           THEN -1
         ELSE t.quantity * public.batch_doses_per_unit(t.batch_id)
       END
 WHERE t.dose_quantity IS NULL;


-- ---------------------------------------------------------------------------
-- 5. dispense_stock_doses
--
-- The portal's dispense path. Takes doses, not units.
--
-- Scoped to one batch on purpose: the officer picked that batch in the form,
-- and silently spilling into another one would contradict the screen. Within
-- the batch it is FEFO by construction - there is one open-vial pool, and it
-- is drawn down before any seal is broken.
--
-- Single-dose items fall through to a plain unit deduction, so the caller can
-- route every dispense here without branching.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.dispense_stock_doses(
  p_batch_id  BIGINT,
  p_doses     INTEGER,
  p_actor     BIGINT DEFAULT NULL,
  p_reference TEXT   DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_batch          public.inventory_batches%ROWTYPE;
  v_item           public.inventory_items%ROWTYPE;
  v_dpu            INTEGER;
  v_shelf_hours    INTEGER;
  v_open           INTEGER;
  v_hours_open     NUMERIC;
  v_from_open      INTEGER;
  v_need           INTEGER;
  v_vials_opened   INTEGER;
  v_new_open       INTEGER;
  v_new_remaining  INTEGER;
  v_expired_doses  INTEGER := 0;
  v_actor          BIGINT;
  v_note           TEXT;
BEGIN
  IF p_doses IS NULL OR p_doses <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Enter a dose count greater than zero');
  END IF;

  SELECT * INTO v_batch
    FROM public.inventory_batches
   WHERE batch_id = p_batch_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Batch #' || p_batch_id || ' not found');
  END IF;

  IF v_batch.status <> 'active' THEN
    RETURN jsonb_build_object('success', false,
      'error', 'Batch ' || v_batch.batch_number || ' is ' || v_batch.status
               || ' and cannot be dispensed from');
  END IF;

  SELECT * INTO v_item FROM public.inventory_items WHERE item_id = v_batch.item_id;

  v_dpu         := GREATEST(1, COALESCE(v_item.doses_per_unit, 1));
  v_shelf_hours := COALESCE(v_item.open_vial_shelf_hours, 0);
  v_actor       := public.resolve_actor_account_id(p_actor);

  -- ---------------- single-dose presentation: one dose is one unit ----------
  IF v_dpu = 1 THEN
    IF COALESCE(v_batch.quantity_remaining, 0) < p_doses THEN
      RETURN jsonb_build_object('success', false,
        'error', 'Only ' || COALESCE(v_batch.quantity_remaining, 0)
                 || ' unit(s) remain in batch ' || v_batch.batch_number);
    END IF;

    v_new_remaining := v_batch.quantity_remaining - p_doses;

    UPDATE public.inventory_batches
       SET quantity_remaining = v_new_remaining,
           status = CASE WHEN v_new_remaining <= 0 THEN 'depleted' ELSE status END
     WHERE batch_id = p_batch_id;

    INSERT INTO public.inventory_transactions (
      batch_id, facility_id, transaction_type, quantity, dose_quantity,
      reference_type, reference_id, notes, performed_by,
      resulting_quantity_remaining, logged_at
    ) VALUES (
      p_batch_id, v_batch.facility_id, 'dispense', -p_doses, -p_doses,
      COALESCE(NULLIF(p_reference, ''), 'Portal Dispense'), p_batch_id,
      'Dispensed ' || p_doses || ' single-dose unit(s) of ' || COALESCE(v_item.name, 'item')
        || ' from Batch #' || v_batch.batch_number,
      v_actor, v_new_remaining, NOW()
    );

    RETURN jsonb_build_object(
      'success', true, 'mode', 'single_dose',
      'doses_dispensed', p_doses, 'doses_from_open', 0,
      'vials_opened', 0, 'units_consumed', p_doses, 'doses_left_open', 0,
      'units_remaining', v_new_remaining, 'doses_per_unit', 1,
      'expired_doses_discarded', 0,
      'message', 'Dispensed ' || p_doses || ' unit(s)'
    );
  END IF;

  -- ---------------- multi-dose presentation --------------------------------
  v_open := COALESCE(v_batch.doses_remaining_in_open_vial, 0);

  -- An open vial past its shelf life is waste, not stock. Write it off first so
  -- the doses about to be drawn cannot come out of a vial that should have been
  -- discarded hours ago.
  IF v_open > 0 AND v_batch.vial_opened_at IS NOT NULL AND v_shelf_hours > 0 THEN
    v_hours_open := EXTRACT(EPOCH FROM (NOW() - v_batch.vial_opened_at)) / 3600;
    IF v_hours_open > v_shelf_hours THEN
      v_expired_doses := v_open;
      v_open := 0;

      INSERT INTO public.inventory_transactions (
        batch_id, facility_id, transaction_type, quantity, dose_quantity,
        reference_type, reference_id, notes, performed_by, logged_at
      ) VALUES (
        p_batch_id, v_batch.facility_id, 'expiry_disposal', 0, -v_expired_doses,
        'Open Vial Expiry', p_batch_id,
        'Auto-discarded ' || v_expired_doses || ' dose(s) left in an open '
          || COALESCE(v_item.name, 'vial') || ' (Batch #' || v_batch.batch_number
          || ') past the ' || v_shelf_hours || 'h limit',
        v_actor, NOW()
      );
    END IF;
  END IF;

  v_from_open    := LEAST(v_open, p_doses);
  v_need         := p_doses - v_from_open;
  v_vials_opened := CEIL(v_need::NUMERIC / v_dpu)::INTEGER;

  IF COALESCE(v_batch.quantity_remaining, 0) < v_vials_opened THEN
    RETURN jsonb_build_object('success', false,
      'error', 'Batch ' || v_batch.batch_number || ' can supply at most '
               || (v_open + COALESCE(v_batch.quantity_remaining, 0) * v_dpu)
               || ' dose(s): ' || v_open || ' already open plus '
               || COALESCE(v_batch.quantity_remaining, 0) || ' sealed vial(s) of ' || v_dpu);
  END IF;

  v_new_open      := (v_open - v_from_open) + (v_vials_opened * v_dpu) - v_need;
  v_new_remaining := v_batch.quantity_remaining - v_vials_opened;

  UPDATE public.inventory_batches
     SET quantity_remaining           = v_new_remaining,
         doses_remaining_in_open_vial = v_new_open,
         -- One pooled dose counter per batch, so at most one vial is partly
         -- used at any moment however many seals this call broke.
         open_vials_count             = CASE WHEN v_new_open > 0 THEN 1 ELSE 0 END,
         vial_opened_at               = CASE
                                          WHEN v_new_open <= 0    THEN NULL
                                          WHEN v_vials_opened > 0 THEN NOW()
                                          ELSE vial_opened_at
                                        END,
         status = CASE WHEN v_new_remaining <= 0 AND v_new_open <= 0
                       THEN 'depleted' ELSE status END
   WHERE batch_id = p_batch_id;

  v_note := 'Dispensed ' || p_doses || ' dose(s) of ' || COALESCE(v_item.name, 'item')
            || ' from Batch #' || v_batch.batch_number || ': '
            || v_from_open || ' from the open vial, '
            || v_vials_opened || ' seal(s) broken, '
            || v_new_open || ' dose(s) left open';

  INSERT INTO public.inventory_transactions (
    batch_id, facility_id, transaction_type, quantity, dose_quantity,
    reference_type, reference_id, notes, performed_by,
    resulting_quantity_remaining, logged_at
  ) VALUES (
    p_batch_id, v_batch.facility_id, 'dispense', -v_vials_opened, -p_doses,
    COALESCE(NULLIF(p_reference, ''), 'Portal Dispense'), p_batch_id,
    v_note, v_actor, v_new_remaining, NOW()
  );

  RETURN jsonb_build_object(
    'success',         true,
    'mode',            CASE WHEN v_vials_opened = 0 THEN 'open_vial_dose' ELSE 'new_vial_opened' END,
    'doses_dispensed', p_doses,
    'doses_from_open', v_from_open,
    'vials_opened',    v_vials_opened,
    'units_consumed',  v_vials_opened,
    'doses_left_open', v_new_open,
    'units_remaining', v_new_remaining,
    'doses_per_unit',  v_dpu,
    'expired_doses_discarded', v_expired_doses,
    'message',         v_note
  );
END
$fn$;


-- ---------------------------------------------------------------------------
-- 6. Grants
-- ---------------------------------------------------------------------------
GRANT EXECUTE ON FUNCTION public.batch_doses_per_unit(BIGINT)
  TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.dispense_stock_doses(BIGINT, INTEGER, BIGINT, TEXT)
  TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.dispense_stock_doses(BIGINT, INTEGER, BIGINT, TEXT) IS
  'Dispenses N clinical doses from one batch: open vial first, then breaks seals. '
  'The admin portal counterpart to deduct_immunization_stock.';
