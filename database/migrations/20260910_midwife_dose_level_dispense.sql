-- ==============================================================================
-- MIGRATION: 20260910_midwife_dose_level_dispense.sql
--
-- Lets a midwife dispense in DOSES from a multi-dose vial instead of always
-- consuming a whole sealed one, and closes the batch it draws from off from
-- the open-vial bookkeeping this codebase otherwise takes seriously
-- everywhere else.
--
-- THE BUG
--
--   record_midwife_inventory_activity -- the RPC behind the mobile app's
--   Dispense Stock sheet -- has never known a batch has an open vial. It
--   compares p_quantity straight against inventory_batches.quantity_remaining
--   (sealed vials) and decrements that column by p_quantity. Nothing in it
--   reads or writes doses_remaining_in_open_vial, open_vials_count or
--   vial_opened_at.
--
--   So on a 10-dose BCG vial already sitting open with 9 doses left in it
--   (exactly the batch in the screenshot this was reported from), entering
--   "1" to record one dose given did not draw from those 9 doses. It broke a
--   BRAND NEW sealed vial, took its whole 10 doses as "1 unit dispensed," and
--   left the original 9 open doses sitting there -- untouched, uncounted,
--   invisible to this screen forever after, because nothing in this function
--   has ever had a way to reach them.
--
--   Every dispense through this screen, on every multi-dose item, has been
--   wasting a vial. dispense_stock_doses (20260822, revised 20260831) exists
--   and is exactly the open-vial-first algorithm this needed -- the admin
--   portal's Dispense Stock already uses it -- but this RPC predates it and
--   was never brought in line.
--
-- THE FIX
--
--   record_midwife_inventory_activity gains one new, defaulted parameter,
--   p_quantity_kind ('units' | 'doses', default 'units' -- so every existing
--   caller keeps its exact current behaviour unchanged). When a dispense asks
--   for 'doses', the same draw-from-open-vial-first, break-only-what-is-
--   needed algorithm dispense_stock_doses uses is applied here too: the open
--   vial is spent first, further seals are broken only for the shortfall, an
--   open vial past its shelf life is written off before anything is drawn
--   from it, and doses_remaining_in_open_vial / open_vials_count /
--   vial_opened_at are updated alongside quantity_remaining.
--
--   The algorithm is duplicated rather than shared by calling
--   dispense_stock_doses directly, because the two functions disagree on
--   purpose about what surrounds the mutation: this one enforces the FEFO
--   earlier-batch rule, the health-service-purpose reason, the retry-safe
--   client_operation_key dedup under an advisory lock, a low-stock
--   notification, and an audit_trail row -- none of which
--   dispense_stock_doses does or should do on the portal's behalf. Threading
--   a call through it and then reconciling which of ITS side effects to keep
--   would have been more fragile than the ~35 duplicated lines this took
--   instead. Both copies are named and shaped identically on purpose, so a
--   future change to one is easy to recognise as needing the other.
--
--   'unusable' (Report Unusable Stock) is untouched and stays unit-only
--   regardless of what is passed for p_quantity_kind: a vial reported
--   expired, damaged or recalled leaves the shelf as a vial, and the existing
--   rule already requires the full remaining batch for those reasons. There
--   is no sense in which "half a dose of a damaged vial" is a thing.
--
-- WHAT THIS DOES NOT TOUCH
--
--   dispense_stock_doses itself, or anything on the admin portal. Zero risk
--   to either.
--
-- Requires 20260811_midwife_inventory_stock_activity.sql,
-- 20260822_dose_accounting.sql and 20260831_dose_presentation_single_source.sql
-- (item_dose_presentation).
--
-- Safe to run more than once.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.record_midwife_inventory_activity(
  p_performed_by BIGINT,
  p_batch_id BIGINT,
  p_activity_type TEXT,
  p_quantity INTEGER,
  p_reason TEXT,
  p_operation_key TEXT,
  p_notes TEXT DEFAULT NULL,
  -- Only meaningful for a dispense; normalised back to 'units' for an
  -- unusable-stock report regardless of what is passed, since reporting a
  -- vial unusable is inherently about the whole vial. See the header of
  -- 20260910_midwife_dose_level_dispense.sql.
  p_quantity_kind TEXT DEFAULT 'units'
)
RETURNS TABLE (
  transaction_id BIGINT,
  batch_id BIGINT,
  quantity_changed INTEGER,
  quantity_remaining INTEGER,
  batch_status VARCHAR,
  logged_at TIMESTAMP WITHOUT TIME ZONE,
  report_id BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_activity_type TEXT := lower(btrim(coalesce(p_activity_type, '')));
  v_reason TEXT := lower(btrim(coalesce(p_reason, '')));
  v_operation_key TEXT := btrim(coalesce(p_operation_key, ''));
  v_notes TEXT := nullif(btrim(coalesce(p_notes, '')), '');
  v_today DATE := (now() AT TIME ZONE 'Asia/Manila')::date;
  v_facility_id BIGINT;
  v_facility_name TEXT;
  v_item_name TEXT;
  v_item_unit TEXT;
  v_minimum_stock INTEGER;
  v_stock_before INTEGER;
  v_stock_after INTEGER;
  v_new_remaining INTEGER;
  v_new_status VARCHAR;
  v_expected_transaction_type TEXT;
  v_reference TEXT;
  v_earlier_batch_number TEXT;
  v_batch public.inventory_batches%ROWTYPE;
  v_transaction public.inventory_transactions%ROWTYPE;
  v_existing public.inventory_transactions%ROWTYPE;
  v_report_id BIGINT;
  v_quantity_kind TEXT := lower(btrim(coalesce(p_quantity_kind, 'units')));
  -- Doses-mode working variables. Same names, same algorithm, as
  -- dispense_stock_doses (20260831_dose_presentation_single_source.sql):
  -- draw from the open vial first, break only as many further seals as the
  -- shortfall needs.
  v_pres          RECORD;
  v_dpu           INTEGER;
  v_shelf_hours   INTEGER;
  v_open          INTEGER;
  v_hours_open    NUMERIC;
  v_from_open     INTEGER;
  v_need          INTEGER;
  v_vials_opened  INTEGER;
  v_new_open      INTEGER;
  v_expired_doses INTEGER := 0;
  -- What inventory_transactions.dose_quantity gets. NULL in units-mode,
  -- exactly as every call before this migration left it, so the BEFORE
  -- INSERT trigger keeps auto-deriving it from quantity x doses_per_unit.
  v_dose_quantity INTEGER;
  v_quantity_phrase TEXT;
BEGIN
  PERFORM public.inventory_assert_actor(p_performed_by, 'midwife');

  v_facility_id := public.inventory_midwife_facility_id(p_performed_by);
  IF v_facility_id IS NULL THEN
    RAISE EXCEPTION 'The midwife has no active BHC assignment'
      USING ERRCODE = '42501';
  END IF;

  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'Quantity must be a positive whole number'
      USING ERRCODE = '22023';
  END IF;

  IF v_notes IS NOT NULL AND char_length(v_notes) > 1000 THEN
    RAISE EXCEPTION 'Notes must be 1000 characters or fewer'
      USING ERRCODE = '22023';
  END IF;

  IF v_activity_type NOT IN ('dispense', 'unusable') THEN
    RAISE EXCEPTION 'Activity type must be dispense or unusable'
      USING ERRCODE = '22023';
  END IF;

  IF v_quantity_kind NOT IN ('units', 'doses') THEN
    RAISE EXCEPTION 'Quantity kind must be units or doses'
      USING ERRCODE = '22023';
  END IF;
  IF v_activity_type <> 'dispense' THEN
    v_quantity_kind := 'units';
  END IF;

  IF char_length(v_operation_key) NOT BETWEEN 16 AND 120
     OR v_operation_key !~ '^[A-Za-z0-9._:-]+$' THEN
    RAISE EXCEPTION 'A valid client operation key is required'
      USING ERRCODE = '22023';
  END IF;

  v_expected_transaction_type := CASE
    WHEN v_activity_type = 'dispense' THEN 'dispense'
    ELSE 'expiry_disposal'
  END;

  -- Serialize retries using the same client operation key. If the first call
  -- committed but its response was lost, return that result without deducting
  -- the batch a second time.
  PERFORM pg_advisory_xact_lock(hashtext(v_operation_key)::BIGINT);

  SELECT transaction.*
    INTO v_existing
  FROM public.inventory_transactions AS transaction
  WHERE transaction.client_operation_key = v_operation_key;

  IF FOUND THEN
    IF v_existing.performed_by IS DISTINCT FROM p_performed_by
       OR v_existing.batch_id IS DISTINCT FROM p_batch_id
       OR v_existing.transaction_type IS DISTINCT FROM v_expected_transaction_type
       OR (v_quantity_kind = 'doses'
           AND abs(COALESCE(v_existing.dose_quantity, 0)) IS DISTINCT FROM p_quantity)
       OR (v_quantity_kind = 'units'
           AND abs(v_existing.quantity) IS DISTINCT FROM p_quantity)
       OR v_existing.activity_reason IS DISTINCT FROM v_reason
       OR v_existing.activity_notes IS DISTINCT FROM v_notes THEN
      RAISE EXCEPTION 'Operation key was already used for different stock activity'
        USING ERRCODE = '22023';
    END IF;

    SELECT report.report_id
      INTO v_report_id
    FROM public.inventory_unusable_stock_reports AS report
    WHERE report.transaction_id = v_existing.transaction_id;

    SELECT batch.status
      INTO v_new_status
    FROM public.inventory_batches AS batch
    WHERE batch.batch_id = v_existing.batch_id;

    RETURN QUERY
    SELECT
      v_existing.transaction_id,
      v_existing.batch_id,
      v_existing.quantity,
      coalesce(v_existing.resulting_quantity_remaining, 0),
      coalesce(v_new_status, 'active'::VARCHAR),
      v_existing.logged_at,
      v_report_id;
    RETURN;
  END IF;

  SELECT batch.*
    INTO v_batch
  FROM public.inventory_batches AS batch
  WHERE batch.batch_id = p_batch_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Inventory batch not found'
      USING ERRCODE = 'P0002';
  END IF;

  IF v_batch.facility_id IS DISTINCT FROM v_facility_id THEN
    RAISE EXCEPTION 'This batch does not belong to the midwife assigned BHC'
      USING ERRCODE = '42501';
  END IF;

  IF v_batch.status IS NULL OR v_batch.status = 'discarded' THEN
    RAISE EXCEPTION 'Inactive or discarded stock cannot be changed'
      USING ERRCODE = '22023';
  END IF;

  IF v_quantity_kind = 'units' THEN
    IF p_quantity > v_batch.quantity_remaining THEN
      RAISE EXCEPTION 'Only % unit(s) remain in this batch',
        v_batch.quantity_remaining
        USING ERRCODE = '22023';
    END IF;
  END IF;

  SELECT
    item.name,
    item.unit_of_measure,
    coalesce(item.minimum_stock_threshold, 50)
    INTO v_item_name, v_item_unit, v_minimum_stock
  FROM public.inventory_items AS item
  WHERE item.item_id = v_batch.item_id;

  IF v_item_name IS NULL THEN
    RAISE EXCEPTION 'Inventory item not found'
      USING ERRCODE = 'P0002';
  END IF;

  SELECT facility.name
    INTO v_facility_name
  FROM public.health_facilities AS facility
  WHERE facility.facility_id = v_facility_id;

  SELECT coalesce(sum(batch.quantity_remaining), 0)::INTEGER
    INTO v_stock_before
  FROM public.inventory_batches AS batch
  WHERE batch.item_id = v_batch.item_id
    AND batch.facility_id = v_facility_id
    AND batch.status = 'active'
    AND batch.expiration_date > v_today
    AND batch.quantity_remaining > 0;

  IF v_activity_type = 'dispense' THEN
    IF v_reason NOT IN (
      'prenatal_service',
      'immunization',
      'postpartum_service',
      'family_planning',
      'other_service'
    ) THEN
      RAISE EXCEPTION 'Choose a valid health-service purpose'
        USING ERRCODE = '22023';
    END IF;

    IF v_reason = 'other_service' AND v_notes IS NULL THEN
      RAISE EXCEPTION 'A note is required for another service purpose'
        USING ERRCODE = '22023';
    END IF;

    IF v_batch.status IS DISTINCT FROM 'active' THEN
      RAISE EXCEPTION 'Only active stock can be dispensed'
        USING ERRCODE = '22023';
    END IF;

    IF v_batch.expiration_date <= v_today THEN
      RAISE EXCEPTION 'Expired stock cannot be dispensed'
        USING ERRCODE = '22023';
    END IF;

    SELECT earlier.batch_number
      INTO v_earlier_batch_number
    FROM public.inventory_batches AS earlier
    WHERE earlier.item_id = v_batch.item_id
      AND earlier.facility_id = v_facility_id
      AND earlier.status = 'active'
      AND earlier.expiration_date > v_today
      AND earlier.quantity_remaining > 0
      AND earlier.expiration_date < v_batch.expiration_date
    ORDER BY earlier.expiration_date, earlier.batch_id
    LIMIT 1;

    IF v_earlier_batch_number IS NOT NULL THEN
      RAISE EXCEPTION 'Use earlier-expiring Batch % first',
        v_earlier_batch_number
        USING ERRCODE = '22023';
    END IF;

    IF v_quantity_kind = 'doses' THEN
      SELECT * INTO v_pres FROM public.item_dose_presentation(v_batch.item_id);
      v_dpu         := GREATEST(1, COALESCE(v_pres.doses_per_unit, 1));
      v_shelf_hours := COALESCE(v_pres.open_vial_shelf_hours, 0);

      IF v_dpu = 1 THEN
        -- A dose IS a unit on a single-dose presentation, so this is the
        -- whole-unit check below, reached by the other door.
        IF p_quantity > v_batch.quantity_remaining THEN
          RAISE EXCEPTION 'Only % unit(s) remain in this batch',
            v_batch.quantity_remaining
            USING ERRCODE = '22023';
        END IF;
        v_vials_opened := p_quantity;
        v_from_open    := 0;
        v_new_open     := 0;
      ELSE
        v_open := COALESCE(v_batch.doses_remaining_in_open_vial, 0);

        -- An open vial past its shelf life is waste, not stock. Write it off
        -- first so the doses about to be drawn cannot come out of a vial
        -- that should already have been discarded -- the same rule
        -- dispense_stock_doses applies for the portal.
        IF v_open > 0 AND v_batch.vial_opened_at IS NOT NULL
           AND v_shelf_hours > 0 THEN
          v_hours_open :=
            EXTRACT(EPOCH FROM (NOW() - v_batch.vial_opened_at)) / 3600;
          IF v_hours_open > v_shelf_hours THEN
            v_expired_doses := v_open;
            v_open := 0;

            INSERT INTO public.inventory_transactions (
              batch_id, facility_id, transaction_type, quantity,
              dose_quantity, reference_type, reference_id, notes,
              performed_by, logged_at
            ) VALUES (
              p_batch_id, v_facility_id, 'expiry_disposal', 0, -v_expired_doses,
              'Open Vial Expiry', p_batch_id,
              'Auto-discarded ' || v_expired_doses || ' dose(s) left in an open '
                || v_item_name || ' (Batch #' || v_batch.batch_number
                || ') past the ' || v_shelf_hours || 'h limit',
              p_performed_by, NOW()
            );
          END IF;
        END IF;

        v_from_open    := LEAST(v_open, p_quantity);
        v_need         := p_quantity - v_from_open;
        v_vials_opened := CEIL(v_need::NUMERIC / v_dpu)::INTEGER;

        IF v_batch.quantity_remaining < v_vials_opened THEN
          RAISE EXCEPTION
            'Batch % can supply at most % dose(s): % already open plus % sealed vial(s) of %',
            v_batch.batch_number,
            (v_open + v_batch.quantity_remaining * v_dpu),
            v_open, v_batch.quantity_remaining, v_dpu
            USING ERRCODE = '22023';
        END IF;

        v_new_open := (v_open - v_from_open) + (v_vials_opened * v_dpu) - v_need;
      END IF;

      v_new_remaining := v_batch.quantity_remaining - v_vials_opened;
      v_new_status    := v_batch.status;
      v_dose_quantity := -p_quantity;
      v_quantity_phrase := p_quantity || ' dose' ||
                            (CASE WHEN p_quantity = 1 THEN '' ELSE 's' END);
    ELSE
      v_new_remaining := v_batch.quantity_remaining - p_quantity;
      v_new_status := v_batch.status;
      v_dose_quantity := NULL;
      v_quantity_phrase := p_quantity || ' ' || v_item_unit;
    END IF;
    v_reference := format(
      'Mobile dispense - %s',
      initcap(replace(v_reason, '_', ' '))
    );
  ELSE
    IF v_reason NOT IN (
      'expired',
      'damaged',
      'broken_seal',
      'cold_chain_failure',
      'contaminated',
      'recalled',
      'other'
    ) THEN
      RAISE EXCEPTION 'Choose a valid unusable-stock reason'
        USING ERRCODE = '22023';
    END IF;

    IF v_reason <> 'expired' AND v_notes IS NULL THEN
      RAISE EXCEPTION 'A note is required for non-expiry unusable stock'
        USING ERRCODE = '22023';
    END IF;

    IF v_reason = 'expired' THEN
      IF v_batch.expiration_date > v_today THEN
        RAISE EXCEPTION 'This batch has not expired yet; choose another issue reason'
          USING ERRCODE = '22023';
      END IF;
      IF p_quantity <> v_batch.quantity_remaining THEN
        RAISE EXCEPTION 'An expired report must cover the full remaining batch'
          USING ERRCODE = '22023';
      END IF;
    ELSIF v_reason = 'recalled'
          AND p_quantity <> v_batch.quantity_remaining THEN
      RAISE EXCEPTION 'A recalled report must cover the full remaining batch'
        USING ERRCODE = '22023';
    ELSIF v_batch.expiration_date <= v_today THEN
      RAISE EXCEPTION 'This batch is expired; use the expired reason'
        USING ERRCODE = '22023';
    END IF;

    v_new_remaining := v_batch.quantity_remaining - p_quantity;
    v_new_status := CASE
      WHEN v_reason = 'expired' THEN 'discarded'
      WHEN v_new_remaining = 0 THEN 'discarded'
      ELSE v_batch.status
    END;
    v_reference := format(
      'BHC unusable report - %s',
      initcap(replace(v_reason, '_', ' '))
    );
    v_dose_quantity := NULL;
    v_quantity_phrase := p_quantity || ' ' || v_item_unit;
  END IF;

  UPDATE public.inventory_batches AS batch
  SET
    quantity_remaining = v_new_remaining,
    status = v_new_status,
    doses_remaining_in_open_vial = CASE WHEN v_quantity_kind = 'doses'
      THEN v_new_open ELSE batch.doses_remaining_in_open_vial END,
    open_vials_count = CASE WHEN v_quantity_kind = 'doses'
      THEN (CASE WHEN v_new_open > 0 THEN 1 ELSE 0 END)
      ELSE batch.open_vials_count END,
    vial_opened_at = CASE WHEN v_quantity_kind = 'doses' THEN
        (CASE WHEN v_new_open <= 0 THEN NULL
              WHEN v_vials_opened > 0 THEN NOW()
              ELSE batch.vial_opened_at END)
      ELSE batch.vial_opened_at END
  WHERE batch.batch_id = v_batch.batch_id;

  INSERT INTO public.inventory_transactions (
    batch_id,
    facility_id,
    transaction_type,
    quantity,
    dose_quantity,
    reference_type,
    performed_by,
    client_operation_key,
    activity_reason,
    activity_notes,
    resulting_quantity_remaining
  ) VALUES (
    v_batch.batch_id,
    v_facility_id,
    v_expected_transaction_type,
    -(CASE WHEN v_quantity_kind = 'doses' THEN v_vials_opened ELSE p_quantity END),
    v_dose_quantity,
    v_reference,
    p_performed_by,
    v_operation_key,
    v_reason,
    v_notes,
    v_new_remaining
  )
  RETURNING * INTO v_transaction;

  IF v_activity_type = 'unusable' THEN
    INSERT INTO public.inventory_unusable_stock_reports (
      transaction_id,
      batch_id,
      facility_id,
      reason,
      quantity_reported,
      notes,
      reported_by
    ) VALUES (
      v_transaction.transaction_id,
      v_batch.batch_id,
      v_facility_id,
      v_reason,
      p_quantity,
      v_notes,
      p_performed_by
    )
    RETURNING inventory_unusable_stock_reports.report_id INTO v_report_id;

    INSERT INTO public.notifications (account_id, title, message, type)
    SELECT
      account.account_id,
      'BHC unusable stock report',
      format(
        '%s reported %s %s of %s (Batch %s) as %s.',
        coalesce(v_facility_name, format('BHC #%s', v_facility_id)),
        p_quantity,
        v_item_unit,
        v_item_name,
        v_batch.batch_number,
        replace(v_reason, '_', ' ')
      ),
      'general'
    FROM public.accounts AS account
    WHERE account.account_type = 'admin'
      AND account.status = 'active';
  END IF;

  SELECT coalesce(sum(batch.quantity_remaining), 0)::INTEGER
    INTO v_stock_after
  FROM public.inventory_batches AS batch
  WHERE batch.item_id = v_batch.item_id
    AND batch.facility_id = v_facility_id
    AND batch.status = 'active'
    AND batch.expiration_date > v_today
    AND batch.quantity_remaining > 0;

  IF v_stock_before > v_minimum_stock
     AND v_stock_after <= v_minimum_stock THEN
    INSERT INTO public.notifications (account_id, title, message, type)
    VALUES (
      p_performed_by,
      'Low stock after activity',
      format(
        '%s now has %s usable %s at %s. Consider requesting replenishment.',
        v_item_name,
        v_stock_after,
        v_item_unit,
        coalesce(v_facility_name, format('BHC #%s', v_facility_id))
      ),
      'general'
    );
  END IF;

  INSERT INTO public.audit_trail (
    account_id,
    action,
    table_name,
    row_id,
    description,
    old_data,
    new_data
  ) VALUES (
    p_performed_by,
    CASE
      WHEN v_activity_type = 'dispense'
        THEN 'dispense_bhc_inventory'
      ELSE 'report_bhc_unusable_stock'
    END,
    'inventory_batches',
    v_batch.batch_id::TEXT,
    format(
      '%s %s of "%s" from batch %s at %s',
      CASE
        WHEN v_activity_type = 'dispense' THEN 'Dispensed'
        ELSE 'Reported unusable'
      END,
      v_quantity_phrase,
      v_item_name,
      v_batch.batch_number,
      coalesce(v_facility_name, format('BHC #%s', v_facility_id))
    ),
    jsonb_build_object(
      'quantity_remaining', v_batch.quantity_remaining,
      'status', v_batch.status
    ),
    jsonb_build_object(
      'quantity_remaining', v_new_remaining,
      'status', v_new_status,
      'transaction_id', v_transaction.transaction_id,
      'reason', v_reason,
      'report_id', v_report_id
    )
  );

  RETURN QUERY
  SELECT
    v_transaction.transaction_id,
    v_transaction.batch_id,
    v_transaction.quantity,
    v_new_remaining,
    v_new_status,
    v_transaction.logged_at,
    v_report_id;
END;
$fn$;

NOTIFY pgrst, 'reload schema';
