-- =====================================================================
-- Make issuing respect a partially approved quantity
--
-- Run this AFTER 20260806_inventory_audit_fixes.sql.
-- Safe to run more than once.
--
-- WHY
--
-- 20260806 added inventory_stock_requests.approved_quantity so an admin can
-- approve less than a midwife requested. But issue_inventory_transfer() still
-- required the issued quantity to equal requested_quantity exactly:
--
--     IF p_quantity <> v_request.requested_quantity THEN
--       RAISE EXCEPTION 'A linked request must be issued in its full requested
--                        quantity (%)', v_request.requested_quantity;
--
-- A partially approved request could therefore be approved but never issued —
-- every attempt failed and the BHC waited on stock that could not be sent.
--
-- This replaces the function so the check compares against the approved
-- quantity, falling back to requested_quantity when no partial approval was
-- recorded. Behaviour for fully approved requests is unchanged.
--
-- Only the quantity check differs from the original in
-- 20260803_inventory_distribution_workflow.sql. The signature is identical, so
-- CREATE OR REPLACE updates it in place and existing callers keep working.
-- =====================================================================

BEGIN;

DO $preflight$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'inventory_stock_requests'
      AND column_name = 'approved_quantity'
  ) THEN
    RAISE EXCEPTION
      'Prerequisite missing: inventory_stock_requests.approved_quantity does not exist. Run database/migrations/20260806_inventory_audit_fixes.sql first, then re-run this file.';
  END IF;
END
$preflight$;

CREATE OR REPLACE FUNCTION public.issue_inventory_transfer(
  p_source_batch_id BIGINT,
  p_destination_facility_id BIGINT,
  p_quantity INTEGER,
  p_issued_by BIGINT,
  p_request_id BIGINT DEFAULT NULL,
  p_remarks TEXT DEFAULT NULL
)
RETURNS public.inventory_transfers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_source public.inventory_batches%ROWTYPE;
  v_request public.inventory_stock_requests%ROWTYPE;
  v_transfer public.inventory_transfers%ROWTYPE;
  v_item_name TEXT;
  v_facility_name TEXT;
  v_expected_quantity INTEGER;
BEGIN
  PERFORM public.inventory_assert_actor(p_issued_by, 'admin');

  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'Issue quantity must be greater than zero'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_source
  FROM public.inventory_batches
  WHERE batch_id = p_source_batch_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Source batch not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_source.facility_id IS NOT NULL THEN
    RAISE EXCEPTION 'Stock can only be issued from the central warehouse'
      USING ERRCODE = '22023';
  END IF;
  IF v_source.status <> 'active' OR v_source.expiration_date < CURRENT_DATE THEN
    RAISE EXCEPTION 'Source batch is not active and usable'
      USING ERRCODE = '22023';
  END IF;
  IF v_source.quantity_remaining < p_quantity THEN
    RAISE EXCEPTION 'Insufficient central stock: only % available',
      v_source.quantity_remaining USING ERRCODE = '22023';
  END IF;

  SELECT name INTO v_facility_name
  FROM public.health_facilities
  WHERE facility_id = p_destination_facility_id
    AND facility_type = 'BHC';
  IF v_facility_name IS NULL THEN
    RAISE EXCEPTION 'Destination BHC not found' USING ERRCODE = '23503';
  END IF;

  IF p_request_id IS NOT NULL THEN
    SELECT * INTO v_request
    FROM public.inventory_stock_requests
    WHERE request_id = p_request_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Linked stock request not found' USING ERRCODE = 'P0002';
    END IF;
    IF v_request.status <> 'approved' THEN
      RAISE EXCEPTION 'Only approved requests can be issued'
        USING ERRCODE = '22023';
    END IF;
    IF v_request.facility_id <> p_destination_facility_id
       OR v_request.item_id <> v_source.item_id THEN
      RAISE EXCEPTION 'Batch item or destination does not match the stock request'
        USING ERRCODE = '22023';
    END IF;

    -- CHANGED: honour a partial approval when one was recorded.
    v_expected_quantity := coalesce(v_request.approved_quantity,
                                    v_request.requested_quantity);

    IF p_quantity <> v_expected_quantity THEN
      RAISE EXCEPTION 'A linked request must be issued in its approved quantity (%)',
        v_expected_quantity
        USING ERRCODE = '22023';
    END IF;
  END IF;

  INSERT INTO public.inventory_transfers (
    request_id,
    source_batch_id,
    destination_facility_id,
    quantity_issued,
    status,
    remarks,
    issued_by
  ) VALUES (
    p_request_id,
    p_source_batch_id,
    p_destination_facility_id,
    p_quantity,
    'pending_receipt',
    nullif(btrim(coalesce(p_remarks, '')), ''),
    p_issued_by
  )
  RETURNING * INTO v_transfer;

  UPDATE public.inventory_batches
  SET quantity_remaining = quantity_remaining - p_quantity
  WHERE batch_id = p_source_batch_id;

  SELECT name INTO v_item_name
  FROM public.inventory_items
  WHERE item_id = v_source.item_id;

  INSERT INTO public.inventory_transactions (
    batch_id,
    facility_id,
    transaction_type,
    quantity,
    reference_type,
    reference_id,
    performed_by
  ) VALUES (
    p_source_batch_id,
    NULL,
    'transfer',
    -p_quantity,
    'Issued to ' || v_facility_name || ' — pending receipt',
    v_transfer.transfer_id,
    p_issued_by
  );

  IF p_request_id IS NOT NULL THEN
    UPDATE public.inventory_stock_requests
    SET status = 'issued'
    WHERE request_id = p_request_id;
  END IF;

  INSERT INTO public.notifications (account_id, title, message, type)
  SELECT
    m.account_id,
    'Incoming stocks from RHU Main',
    format('%s units of %s are waiting for your receipt confirmation.',
      p_quantity, v_item_name),
    'general'
  FROM public.midwives m
  JOIN public.health_facilities hf ON hf.facility_id = m.assigned_bhc_id
  JOIN public.accounts a ON a.account_id = m.account_id
  WHERE hf.facility_id = p_destination_facility_id
    AND a.status = 'active';

  INSERT INTO public.audit_trail (
    account_id,
    action,
    table_name,
    description,
    new_data
  ) VALUES (
    p_issued_by,
    'issue_inventory_transfer',
    'inventory_transfers',
    format('Issued %s units of "%s" to %s; pending receipt',
      p_quantity, v_item_name, v_facility_name),
    to_jsonb(v_transfer)
  );

  RETURN v_transfer;
END;
$$;

GRANT EXECUTE ON FUNCTION public.issue_inventory_transfer(
  BIGINT, BIGINT, INTEGER, BIGINT, BIGINT, TEXT
) TO anon, authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
