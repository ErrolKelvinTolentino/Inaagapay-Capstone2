-- InaAgapay midwife dispensing and unusable-stock reporting
--
-- Connects the Flutter BHC inventory to the same batch ledger used by the
-- admin portal. The RPC is atomic, facility-scoped and retry-safe: a batch
-- deduction, transaction, structured report, audit row and notifications all
-- commit together or all roll back.
--
-- PRESENTATION AUTH NOTE: this repository currently uses a custom accounts
-- login over the public anon client. The actor id checks below match that
-- existing capstone model, but production should derive the actor from
-- auth.uid() with RLS instead of trusting a caller-supplied account id.

BEGIN;

UPDATE public.inventory_batches
SET status = 'active'
WHERE status IS NULL;

ALTER TABLE public.inventory_batches
  ALTER COLUMN status SET NOT NULL;

ALTER TABLE public.inventory_transactions
  ADD COLUMN IF NOT EXISTS client_operation_key VARCHAR(120),
  ADD COLUMN IF NOT EXISTS activity_reason VARCHAR(40),
  ADD COLUMN IF NOT EXISTS activity_notes TEXT,
  ADD COLUMN IF NOT EXISTS resulting_quantity_remaining INTEGER;

DO $migration$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.inventory_transactions'::regclass
      AND conname = 'inventory_transactions_operation_key_format_check'
  ) THEN
    ALTER TABLE public.inventory_transactions
      ADD CONSTRAINT inventory_transactions_operation_key_format_check
      CHECK (
        client_operation_key IS NULL OR (
          client_operation_key = btrim(client_operation_key)
          AND char_length(client_operation_key) BETWEEN 16 AND 120
          AND client_operation_key ~ '^[A-Za-z0-9._:-]+$'
        )
      ) NOT VALID;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.inventory_transactions'::regclass
      AND conname = 'inventory_transactions_resulting_quantity_check'
  ) THEN
    ALTER TABLE public.inventory_transactions
      ADD CONSTRAINT inventory_transactions_resulting_quantity_check
      CHECK (
        resulting_quantity_remaining IS NULL
        OR resulting_quantity_remaining >= 0
      ) NOT VALID;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.inventory_transactions'::regclass
      AND conname = 'inventory_transactions_activity_notes_length_check'
  ) THEN
    ALTER TABLE public.inventory_transactions
      ADD CONSTRAINT inventory_transactions_activity_notes_length_check
      CHECK (
        activity_notes IS NULL OR char_length(activity_notes) <= 1000
      ) NOT VALID;
  END IF;
END
$migration$;

ALTER TABLE public.inventory_transactions
  VALIDATE CONSTRAINT inventory_transactions_operation_key_format_check;
ALTER TABLE public.inventory_transactions
  VALIDATE CONSTRAINT inventory_transactions_resulting_quantity_check;
ALTER TABLE public.inventory_transactions
  VALIDATE CONSTRAINT inventory_transactions_activity_notes_length_check;

CREATE UNIQUE INDEX IF NOT EXISTS inventory_transactions_operation_key_uidx
  ON public.inventory_transactions (client_operation_key)
  WHERE client_operation_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.inventory_unusable_stock_reports (
  report_id BIGSERIAL PRIMARY KEY,
  transaction_id BIGINT NOT NULL UNIQUE
    REFERENCES public.inventory_transactions(transaction_id) ON DELETE CASCADE,
  batch_id BIGINT NOT NULL
    REFERENCES public.inventory_batches(batch_id) ON DELETE RESTRICT,
  facility_id BIGINT NOT NULL
    REFERENCES public.health_facilities(facility_id) ON DELETE RESTRICT,
  reason VARCHAR(40) NOT NULL
    CHECK (
      reason IN (
        'expired',
        'damaged',
        'broken_seal',
        'cold_chain_failure',
        'contaminated',
        'recalled',
        'other'
      )
    ),
  quantity_reported INTEGER NOT NULL CHECK (quantity_reported > 0),
  notes TEXT,
  reported_by BIGINT NOT NULL
    REFERENCES public.accounts(account_id) ON DELETE RESTRICT,
  reported_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $migration$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.inventory_unusable_stock_reports'::regclass
      AND conname = 'inventory_unusable_reports_notes_length_check'
  ) THEN
    ALTER TABLE public.inventory_unusable_stock_reports
      ADD CONSTRAINT inventory_unusable_reports_notes_length_check
      CHECK (notes IS NULL OR char_length(notes) <= 1000) NOT VALID;
  END IF;
END
$migration$;

ALTER TABLE public.inventory_unusable_stock_reports
  VALIDATE CONSTRAINT inventory_unusable_reports_notes_length_check;

CREATE INDEX IF NOT EXISTS idx_inventory_unusable_reports_facility_date
  ON public.inventory_unusable_stock_reports(facility_id, reported_at DESC);
CREATE INDEX IF NOT EXISTS idx_inventory_unusable_reports_batch
  ON public.inventory_unusable_stock_reports(batch_id, reported_at DESC);

COMMENT ON TABLE public.inventory_unusable_stock_reports IS
  'Structured BHC reports for expired, damaged, recalled or otherwise unusable batch quantities.';
COMMENT ON COLUMN public.inventory_transactions.client_operation_key IS
  'Client-generated retry key preventing a duplicate mobile stock deduction.';
COMMENT ON COLUMN public.inventory_transactions.resulting_quantity_remaining IS
  'Batch balance immediately after this atomic mobile stock activity.';

CREATE OR REPLACE FUNCTION public.record_midwife_inventory_activity(
  p_performed_by BIGINT,
  p_batch_id BIGINT,
  p_activity_type TEXT,
  p_quantity INTEGER,
  p_reason TEXT,
  p_operation_key TEXT,
  p_notes TEXT DEFAULT NULL
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
AS $function$
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
       OR abs(v_existing.quantity) IS DISTINCT FROM p_quantity
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

  IF p_quantity > v_batch.quantity_remaining THEN
    RAISE EXCEPTION 'Only % unit(s) remain in this batch',
      v_batch.quantity_remaining
      USING ERRCODE = '22023';
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

    v_new_remaining := v_batch.quantity_remaining - p_quantity;
    v_new_status := v_batch.status;
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
  END IF;

  UPDATE public.inventory_batches AS batch
  SET
    quantity_remaining = v_new_remaining,
    status = v_new_status
  WHERE batch.batch_id = v_batch.batch_id;

  INSERT INTO public.inventory_transactions (
    batch_id,
    facility_id,
    transaction_type,
    quantity,
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
    -p_quantity,
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
      '%s %s %s of "%s" from batch %s at %s',
      CASE
        WHEN v_activity_type = 'dispense' THEN 'Dispensed'
        ELSE 'Reported unusable'
      END,
      p_quantity,
      v_item_unit,
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
$function$;

-- Make the report table participate in the existing sanitized refresh feed
-- without publishing its row contents through Realtime.
DO $migration$
BEGIN
  IF to_regprocedure('public.emit_admin_change_event()') IS NOT NULL THEN
    DROP TRIGGER IF EXISTS trg_admin_live_inventory_unusable_stock_reports
      ON public.inventory_unusable_stock_reports;
    CREATE TRIGGER trg_admin_live_inventory_unusable_stock_reports
    AFTER INSERT OR UPDATE OR DELETE
      ON public.inventory_unusable_stock_reports
    FOR EACH STATEMENT EXECUTE FUNCTION public.emit_admin_change_event();
  END IF;
END
$migration$;

ALTER TABLE public.inventory_unusable_stock_reports DISABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.inventory_unusable_stock_reports FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.record_midwife_inventory_activity(
  BIGINT, BIGINT, TEXT, INTEGER, TEXT, TEXT, TEXT
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_midwife_inventory_activity(
  BIGINT, BIGINT, TEXT, INTEGER, TEXT, TEXT, TEXT
) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;
