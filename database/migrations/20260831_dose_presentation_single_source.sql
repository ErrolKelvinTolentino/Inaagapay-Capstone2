-- ==============================================================================
-- MIGRATION: 20260831_dose_presentation_single_source.sql
--
-- Makes "how many doses are in one unit of this item" a question with exactly
-- one answer, and makes an item that has never been told the answer visible so
-- somebody can supply it.
--
-- THE FORK
--
--   deduct_immunization_stock (20260821) substitutes DOH defaults when the
--   catalogue row says 1:
--
--       BCG      -> 20 doses,  6h open-vial shelf life
--       OPV      -> 20 doses,  672h (28 days)
--       Measles  -> 10 doses,  6h
--
--   dispense_stock_doses (20260822) and batch_doses_per_unit (20260822) do
--   NOT. They read inventory_items.doses_per_unit straight.
--
--   So for a BCG item left at the default of 1, the same batch is two
--   different things depending on which door the stock leaves by:
--
--     * the app opens a 20-dose vial and tracks 19 remaining;
--     * the portal's Dispense destroys a whole sealed vial to give one dose;
--     * a receipt of 5 vials writes dose_quantity = 5, not 100, because the
--       trigger derives it from batch_doses_per_unit.
--
--   The DOH wastage rate divides doses discarded by doses handled. With the
--   denominator understated twentyfold, that figure is not slightly off - it
--   is meaningless. 20260822 was written to end exactly this class of
--   disagreement; the fallback layer quietly reintroduced it one level down.
--
-- THE FIX
--
--   item_dose_presentation() is the one place the question is answered. The
--   DOH defaults move into it, so every caller - the trigger, the portal RPC,
--   the app RPC - gets the same number for the same item. batch_doses_per_unit
--   now delegates to it, which repoints the dose_quantity trigger without that
--   trigger being touched.
--
--   The defaults stay a fallback and not a fix: inventory_items_needing_dose_config
--   lists every item that is relying on one, so the catalogue can be corrected
--   and the guesswork retired. A guessed number that nobody can see is worse
--   than a wrong number somebody can.
--
-- Requires 20260822_dose_accounting.sql.
-- Safe to run more than once.
-- ==============================================================================


-- ---------------------------------------------------------------------------
-- 1. The single source of truth
--
-- Returns the configured presentation when the catalogue has one, and the DOH
-- standard presentation when it does not, plus a flag saying which of the two
-- the caller just received. That flag is what makes the guess auditable.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.item_dose_presentation(p_item_id BIGINT)
RETURNS TABLE (
  doses_per_unit        INTEGER,
  open_vial_shelf_hours INTEGER,
  is_assumed            BOOLEAN
)
LANGUAGE plpgsql
STABLE
AS $fn$
DECLARE
  v_item    public.inventory_items%ROWTYPE;
  v_name    TEXT;
  v_dpu     INTEGER;
  v_hours   INTEGER;
BEGIN
  SELECT * INTO v_item FROM public.inventory_items WHERE item_id = p_item_id;

  IF NOT FOUND THEN
    RETURN QUERY SELECT 1, 0, false;
    RETURN;
  END IF;

  v_dpu   := GREATEST(1, COALESCE(v_item.doses_per_unit, 1));
  v_hours := COALESCE(v_item.open_vial_shelf_hours, 0);

  -- Configured. The catalogue wins, always - including a deliberate 1 for a
  -- single-dose BCG presentation, which does exist and which a name-matching
  -- default would otherwise override.
  IF v_dpu > 1 THEN
    RETURN QUERY SELECT v_dpu, NULLIF(v_hours, 0), false;
    RETURN;
  END IF;

  -- Not configured. Fall back to the DOH standard presentation.
  --
  -- Matched on the catalogue name, the generic name AND the names of any
  -- vaccines linked to this item. That last one is what actually closes the
  -- fork: deduct_immunization_stock matches on vaccines.vaccine_name, so an
  -- item called "Tuberculosis Vaccine" linked to a vaccine called "BCG" would
  -- otherwise still be 20 doses to the app and 1 to everyone else. Reading
  -- both sides here means there is no name the app can see that this cannot.
  v_name := LOWER(
    COALESCE(v_item.name, '') || ' ' ||
    COALESCE(v_item.generic_name, '') || ' ' ||
    COALESCE(
      (SELECT string_agg(vx.vaccine_name, ' ')
         FROM public.vaccines vx
        WHERE vx.inventory_item_id = p_item_id),
      '')
  );

  IF v_name LIKE '%bcg%' THEN
    RETURN QUERY SELECT 20, 6, true;
  ELSIF v_name LIKE '%opv%' OR v_name LIKE '%oral polio%' THEN
    RETURN QUERY SELECT 20, 672, true;   -- 28 days, multi-dose vial policy
  ELSIF v_name LIKE '%measles%' OR v_name LIKE '%mmr%' OR v_name LIKE '%rubella%' THEN
    RETURN QUERY SELECT 10, 6, true;
  ELSIF v_name LIKE '%td %' OR v_name LIKE '%tetanus%' OR v_name LIKE '%td vaccine%' THEN
    RETURN QUERY SELECT 10, 672, true;
  END IF;

  -- Genuinely single-dose, or not a vaccine at all.
  RETURN QUERY SELECT 1, NULLIF(v_hours, 0), false;
END
$fn$;

COMMENT ON FUNCTION public.item_dose_presentation(BIGINT) IS
  'The one answer to "how many doses in one unit, and how long once opened". '
  'Prefers the catalogue; falls back to the DOH standard presentation and says '
  'so via is_assumed. Every dose calculation must go through this.';


-- ---------------------------------------------------------------------------
-- 2. Point batch_doses_per_unit at it
--
-- This is what the dose_quantity trigger calls, so redefining it here corrects
-- every future ledger row without altering the trigger. Receipts of an
-- unconfigured BCG batch stop recording 5 doses where 100 moved.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.batch_doses_per_unit(p_batch_id BIGINT)
RETURNS INTEGER
LANGUAGE sql
STABLE
AS $fn$
  SELECT COALESCE(
    (SELECT p.doses_per_unit
       FROM public.inventory_batches b
       CROSS JOIN LATERAL public.item_dose_presentation(b.item_id) p
      WHERE b.batch_id = p_batch_id),
    1);
$fn$;


-- ---------------------------------------------------------------------------
-- 3. Point dispense_stock_doses at it
--
-- Only the two lines that resolve the presentation change; the dispensing
-- logic below them is 20260822's and is left alone. Redeclared in full because
-- CREATE OR REPLACE FUNCTION has no way to patch a body.
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
  v_pres           RECORD;
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

  -- The one change that matters: the presentation now comes from the shared
  -- function rather than straight off the catalogue row, so this path and
  -- deduct_immunization_stock can no longer disagree about the same vial.
  SELECT * INTO v_pres FROM public.item_dose_presentation(v_batch.item_id);
  v_dpu         := GREATEST(1, COALESCE(v_pres.doses_per_unit, 1));
  v_shelf_hours := COALESCE(v_pres.open_vial_shelf_hours, 0);

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
      'presentation_assumed', COALESCE(v_pres.is_assumed, false),
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
    'presentation_assumed', COALESCE(v_pres.is_assumed, false),
    'message',         v_note
  );
END
$fn$;


-- ---------------------------------------------------------------------------
-- 4. What still needs configuring
--
-- One row per catalogue item that is running on an assumed presentation, with
-- the number being assumed and how much stock is riding on the assumption. The
-- portal reads this to raise it; without a surface like this the guess is
-- invisible and nobody ever corrects the catalogue.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.inventory_items_needing_dose_config AS
SELECT
  i.item_id,
  i.name,
  i.generic_name,
  i.item_type,
  i.unit_of_measure,
  COALESCE(i.doses_per_unit, 1)          AS configured_doses_per_unit,
  p.doses_per_unit                       AS assumed_doses_per_unit,
  p.open_vial_shelf_hours                AS assumed_shelf_hours,
  COALESCE(SUM(b.quantity_remaining), 0) AS units_on_hand,
  COUNT(b.batch_id) FILTER (WHERE b.status = 'active' AND b.quantity_remaining > 0)
                                         AS active_batches
FROM public.inventory_items i
CROSS JOIN LATERAL public.item_dose_presentation(i.item_id) p
LEFT JOIN public.inventory_batches b
       ON b.item_id = i.item_id
      AND b.status = 'active'
WHERE p.is_assumed = true
  AND COALESCE(i.is_archived, false) = false
GROUP BY i.item_id, i.name, i.generic_name, i.item_type, i.unit_of_measure,
         i.doses_per_unit, p.doses_per_unit, p.open_vial_shelf_hours;

COMMENT ON VIEW public.inventory_items_needing_dose_config IS
  'Catalogue items whose dose presentation is being assumed from their name '
  'because doses_per_unit was never set. Every row here is stock whose dose '
  'figures rest on a guess; setting doses_per_unit removes it from the list.';


-- ---------------------------------------------------------------------------
-- 5. Repair the ledger rows the fork already produced
--
-- Only rows whose dose figure was derived by the trigger from the old, wrong
-- doses_per_unit. Administrations are excluded: those are one dose each by
-- definition, the trigger already wrote -1, and that was never affected.
-- Open-vial discards and expiries are excluded for the same reason - quantity
-- was already a dose count on those rows.
-- ---------------------------------------------------------------------------
UPDATE public.inventory_transactions t
   SET dose_quantity = t.quantity * public.batch_doses_per_unit(t.batch_id)
 WHERE COALESCE(t.reference_type, '') NOT IN (
         'Child Immunization', 'Maternal Td Immunization',
         'Open Vial Discard', 'Open Vial Expiry', 'open_vial_expired')
   AND t.dose_quantity IS DISTINCT FROM
       t.quantity * public.batch_doses_per_unit(t.batch_id);


-- ---------------------------------------------------------------------------
-- 6. Grants
-- ---------------------------------------------------------------------------
GRANT EXECUTE ON FUNCTION public.item_dose_presentation(BIGINT)
  TO anon, authenticated, service_role;
GRANT SELECT ON public.inventory_items_needing_dose_config
  TO anon, authenticated, service_role;
