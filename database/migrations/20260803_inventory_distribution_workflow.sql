-- InaAgapay inventory distribution workflow
--
-- Adds structured BHC stock requests and RHU -> BHC transfers. Stock is
-- deducted from RHU when issued, but is not credited to the BHC until a
-- midwife confirms receipt through receive_inventory_transfer().
--
-- CAPSTONE/DEMO AUTH NOTE: the existing applications use a custom accounts
-- login over the public anon client instead of Supabase Auth. These RPCs match
-- that existing model by validating the supplied active account and role, but
-- the account id is not a production-grade authorization credential. Before a
-- real deployment, migrate accounts to Supabase Auth, enable RLS, derive the
-- actor from auth.uid(), and remove anon access to sensitive account data.

BEGIN;

-- The inventory page already renders "transfer" movements, but the original
-- database check constraint did not allow the value.
ALTER TABLE public.inventory_transactions
  DROP CONSTRAINT IF EXISTS inventory_transactions_transaction_type_check;

ALTER TABLE public.inventory_transactions
  ADD CONSTRAINT inventory_transactions_transaction_type_check
  CHECK (
    transaction_type IN (
      'receipt',
      'dispense',
      'adjustment',
      'expiry_disposal',
      'transfer'
    )
  );

CREATE TABLE IF NOT EXISTS public.inventory_stock_requests (
  request_id BIGSERIAL PRIMARY KEY,
  facility_id BIGINT NOT NULL
    REFERENCES public.health_facilities(facility_id) ON DELETE RESTRICT,
  item_id BIGINT NOT NULL
    REFERENCES public.inventory_items(item_id) ON DELETE RESTRICT,
  requested_quantity INTEGER NOT NULL CHECK (requested_quantity > 0),
  reason TEXT NOT NULL CHECK (btrim(reason) <> ''),
  remarks TEXT,
  status VARCHAR(20) NOT NULL DEFAULT 'pending'
    CHECK (
      status IN (
        'pending',
        'approved',
        'rejected',
        'issued',
        'received',
        'completed',
        'cancelled'
      )
    ),
  requested_by BIGINT NOT NULL
    REFERENCES public.accounts(account_id) ON DELETE RESTRICT,
  reviewed_by BIGINT
    REFERENCES public.accounts(account_id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ,
  admin_remarks TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.inventory_transfers (
  transfer_id BIGSERIAL PRIMARY KEY,
  request_id BIGINT UNIQUE
    REFERENCES public.inventory_stock_requests(request_id) ON DELETE SET NULL,
  source_batch_id BIGINT NOT NULL
    REFERENCES public.inventory_batches(batch_id) ON DELETE RESTRICT,
  destination_facility_id BIGINT NOT NULL
    REFERENCES public.health_facilities(facility_id) ON DELETE RESTRICT,
  quantity_issued INTEGER NOT NULL CHECK (quantity_issued > 0),
  status VARCHAR(24) NOT NULL DEFAULT 'pending_receipt'
    CHECK (status IN ('pending_receipt', 'received', 'cancelled')),
  remarks TEXT,
  issued_by BIGINT NOT NULL
    REFERENCES public.accounts(account_id) ON DELETE RESTRICT,
  issued_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  received_by BIGINT
    REFERENCES public.accounts(account_id) ON DELETE SET NULL,
  received_at TIMESTAMPTZ,
  destination_batch_id BIGINT
    REFERENCES public.inventory_batches(batch_id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_inventory_stock_requests_facility_status
  ON public.inventory_stock_requests(facility_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_inventory_stock_requests_item
  ON public.inventory_stock_requests(item_id);
CREATE INDEX IF NOT EXISTS idx_inventory_stock_requests_requested_by
  ON public.inventory_stock_requests(requested_by, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_inventory_transfers_destination_status
  ON public.inventory_transfers(destination_facility_id, status, issued_at DESC);
CREATE INDEX IF NOT EXISTS idx_inventory_transfers_source_batch
  ON public.inventory_transfers(source_batch_id);

CREATE OR REPLACE FUNCTION public.inventory_touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_inventory_stock_requests_updated_at
  ON public.inventory_stock_requests;
CREATE TRIGGER trg_inventory_stock_requests_updated_at
BEFORE UPDATE ON public.inventory_stock_requests
FOR EACH ROW EXECUTE FUNCTION public.inventory_touch_updated_at();

DROP TRIGGER IF EXISTS trg_inventory_transfers_updated_at
  ON public.inventory_transfers;
CREATE TRIGGER trg_inventory_transfers_updated_at
BEFORE UPDATE ON public.inventory_transfers
FOR EACH ROW EXECUTE FUNCTION public.inventory_touch_updated_at();

-- Midwife assignments and inventory batches use the same canonical
-- health_facilities identifier.
CREATE OR REPLACE FUNCTION public.inventory_midwife_facility_id(
  p_account_id BIGINT
)
RETURNS BIGINT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_facility_id BIGINT;
BEGIN
  SELECT hf.facility_id
    INTO v_facility_id
  FROM public.accounts a
  JOIN public.midwives m ON m.account_id = a.account_id
  JOIN public.health_facilities hf ON hf.facility_id = m.assigned_bhc_id
  WHERE a.account_id = p_account_id
    AND a.account_type = 'midwife'
    AND a.status = 'active'
    AND hf.facility_type = 'BHC'
  ORDER BY hf.facility_id
  LIMIT 1;

  RETURN v_facility_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.inventory_assert_actor(
  p_account_id BIGINT,
  p_required_role TEXT
)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.accounts
    WHERE account_id = p_account_id
      AND account_type = p_required_role
      AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'Active % account required', p_required_role
      USING ERRCODE = '42501';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_inventory_stock_request(
  p_requested_by BIGINT,
  p_item_id BIGINT,
  p_requested_quantity INTEGER,
  p_reason TEXT,
  p_remarks TEXT DEFAULT NULL
)
RETURNS public.inventory_stock_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_facility_id BIGINT;
  v_request public.inventory_stock_requests%ROWTYPE;
  v_item_name TEXT;
BEGIN
  PERFORM public.inventory_assert_actor(p_requested_by, 'midwife');

  v_facility_id := public.inventory_midwife_facility_id(p_requested_by);
  IF v_facility_id IS NULL THEN
    RAISE EXCEPTION 'Midwife has no valid BHC inventory assignment'
      USING ERRCODE = '23503';
  END IF;

  IF p_requested_quantity IS NULL OR p_requested_quantity <= 0 THEN
    RAISE EXCEPTION 'Requested quantity must be greater than zero'
      USING ERRCODE = '22023';
  END IF;

  IF p_reason IS NULL OR btrim(p_reason) = '' THEN
    RAISE EXCEPTION 'Request reason is required'
      USING ERRCODE = '22023';
  END IF;

  SELECT name INTO v_item_name
  FROM public.inventory_items
  WHERE item_id = p_item_id;

  IF v_item_name IS NULL THEN
    RAISE EXCEPTION 'Inventory item not found'
      USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO public.inventory_stock_requests (
    facility_id,
    item_id,
    requested_quantity,
    reason,
    remarks,
    status,
    requested_by
  ) VALUES (
    v_facility_id,
    p_item_id,
    p_requested_quantity,
    btrim(p_reason),
    nullif(btrim(coalesce(p_remarks, '')), ''),
    'pending',
    p_requested_by
  )
  RETURNING * INTO v_request;

  INSERT INTO public.notifications (account_id, title, message, type)
  SELECT
    account_id,
    'New stock request',
    format('%s requested %s units of %s.',
      (SELECT name FROM public.health_facilities WHERE facility_id = v_facility_id),
      p_requested_quantity,
      v_item_name),
    'general'
  FROM public.accounts
  WHERE account_type = 'admin' AND status = 'active';

  INSERT INTO public.audit_trail (
    account_id,
    action,
    table_name,
    description,
    new_data
  ) VALUES (
    p_requested_by,
    'submit_inventory_stock_request',
    'inventory_stock_requests',
    format('Submitted stock request #%s for %s units of "%s"',
      v_request.request_id, p_requested_quantity, v_item_name),
    to_jsonb(v_request)
  );

  RETURN v_request;
END;
$$;

CREATE OR REPLACE FUNCTION public.approve_inventory_stock_request(
  p_request_id BIGINT,
  p_admin_id BIGINT,
  p_admin_remarks TEXT DEFAULT NULL
)
RETURNS public.inventory_stock_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request public.inventory_stock_requests%ROWTYPE;
BEGIN
  PERFORM public.inventory_assert_actor(p_admin_id, 'admin');

  SELECT * INTO v_request
  FROM public.inventory_stock_requests
  WHERE request_id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Stock request not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_request.status <> 'pending' THEN
    RAISE EXCEPTION 'Only pending requests can be approved'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.inventory_stock_requests
  SET status = 'approved',
      reviewed_by = p_admin_id,
      reviewed_at = now(),
      admin_remarks = nullif(btrim(coalesce(p_admin_remarks, '')), '')
  WHERE request_id = p_request_id
  RETURNING * INTO v_request;

  INSERT INTO public.notifications (account_id, title, message, type)
  VALUES (
    v_request.requested_by,
    'Stock request approved',
    format('Your stock request #%s was approved by RHU Main.', p_request_id),
    'general'
  );

  RETURN v_request;
END;
$$;

CREATE OR REPLACE FUNCTION public.reject_inventory_stock_request(
  p_request_id BIGINT,
  p_admin_id BIGINT,
  p_admin_remarks TEXT DEFAULT NULL
)
RETURNS public.inventory_stock_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request public.inventory_stock_requests%ROWTYPE;
BEGIN
  PERFORM public.inventory_assert_actor(p_admin_id, 'admin');

  SELECT * INTO v_request
  FROM public.inventory_stock_requests
  WHERE request_id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Stock request not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_request.status NOT IN ('pending', 'approved') THEN
    RAISE EXCEPTION 'This request can no longer be rejected'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.inventory_stock_requests
  SET status = 'rejected',
      reviewed_by = p_admin_id,
      reviewed_at = now(),
      admin_remarks = nullif(btrim(coalesce(p_admin_remarks, '')), '')
  WHERE request_id = p_request_id
  RETURNING * INTO v_request;

  INSERT INTO public.notifications (account_id, title, message, type)
  VALUES (
    v_request.requested_by,
    'Stock request update',
    format('Your stock request #%s was not approved.%s',
      p_request_id,
      CASE
        WHEN v_request.admin_remarks IS NULL THEN ''
        ELSE ' ' || v_request.admin_remarks
      END),
    'general'
  );

  RETURN v_request;
END;
$$;

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
    IF p_quantity <> v_request.requested_quantity THEN
      RAISE EXCEPTION 'A linked request must be issued in its full requested quantity (%)',
        v_request.requested_quantity
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

CREATE OR REPLACE FUNCTION public.receive_inventory_transfer(
  p_transfer_id BIGINT,
  p_received_by BIGINT
)
RETURNS public.inventory_transfers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_transfer public.inventory_transfers%ROWTYPE;
  v_source public.inventory_batches%ROWTYPE;
  v_destination_batch_id BIGINT;
  v_midwife_facility_id BIGINT;
  v_item_name TEXT;
  v_facility_name TEXT;
BEGIN
  PERFORM public.inventory_assert_actor(p_received_by, 'midwife');
  v_midwife_facility_id := public.inventory_midwife_facility_id(p_received_by);

  SELECT * INTO v_transfer
  FROM public.inventory_transfers
  WHERE transfer_id = p_transfer_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Inventory transfer not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_midwife_facility_id IS NULL
     OR v_transfer.destination_facility_id <> v_midwife_facility_id THEN
    RAISE EXCEPTION 'This transfer belongs to another BHC'
      USING ERRCODE = '42501';
  END IF;

  -- Safe retry for a slow network or accidental double tap.
  IF v_transfer.status = 'received' THEN
    RETURN v_transfer;
  END IF;
  IF v_transfer.status <> 'pending_receipt' THEN
    RAISE EXCEPTION 'Transfer cannot be received in its current status'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_source
  FROM public.inventory_batches
  WHERE batch_id = v_transfer.source_batch_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transfer source batch no longer exists'
      USING ERRCODE = 'P0002';
  END IF;
  IF v_source.expiration_date < CURRENT_DATE THEN
    RAISE EXCEPTION 'The issued batch expired before receipt; contact RHU Main for resolution'
      USING ERRCODE = '22023';
  END IF;

  -- Serialize receipts for the same item/batch/facility so concurrent taps or
  -- multiple devices cannot create duplicate destination batches.
  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      v_source.item_id::text || ':' ||
      v_transfer.destination_facility_id::text || ':' ||
      v_source.batch_number,
      0
    )
  );

  SELECT batch_id INTO v_destination_batch_id
  FROM public.inventory_batches
  WHERE item_id = v_source.item_id
    AND facility_id = v_transfer.destination_facility_id
    AND batch_number = v_source.batch_number
    AND status = 'active'
  ORDER BY batch_id
  LIMIT 1
  FOR UPDATE;

  IF v_destination_batch_id IS NULL THEN
    INSERT INTO public.inventory_batches (
      item_id,
      facility_id,
      batch_number,
      quantity_received,
      quantity_remaining,
      received_date,
      expiration_date,
      manufacturer,
      status
    ) VALUES (
      v_source.item_id,
      v_transfer.destination_facility_id,
      v_source.batch_number,
      v_transfer.quantity_issued,
      v_transfer.quantity_issued,
      CURRENT_DATE,
      v_source.expiration_date,
      v_source.manufacturer,
      'active'
    )
    RETURNING batch_id INTO v_destination_batch_id;
  ELSE
    UPDATE public.inventory_batches
    SET quantity_received = quantity_received + v_transfer.quantity_issued,
        quantity_remaining = quantity_remaining + v_transfer.quantity_issued
    WHERE batch_id = v_destination_batch_id;
  END IF;

  INSERT INTO public.inventory_transactions (
    batch_id,
    facility_id,
    transaction_type,
    quantity,
    reference_type,
    reference_id,
    performed_by
  ) VALUES (
    v_destination_batch_id,
    v_transfer.destination_facility_id,
    'transfer',
    v_transfer.quantity_issued,
    'Received from RHU Main',
    v_transfer.transfer_id,
    p_received_by
  );

  UPDATE public.inventory_transfers
  SET status = 'received',
      received_by = p_received_by,
      received_at = now(),
      destination_batch_id = v_destination_batch_id
  WHERE transfer_id = p_transfer_id
  RETURNING * INTO v_transfer;

  IF v_transfer.request_id IS NOT NULL THEN
    UPDATE public.inventory_stock_requests
    SET status = 'received'
    WHERE request_id = v_transfer.request_id;
  END IF;

  SELECT i.name, hf.name
    INTO v_item_name, v_facility_name
  FROM public.inventory_items i
  CROSS JOIN public.health_facilities hf
  WHERE i.item_id = v_source.item_id
    AND hf.facility_id = v_transfer.destination_facility_id;

  INSERT INTO public.notifications (account_id, title, message, type)
  SELECT
    account_id,
    'BHC received issued stocks',
    format('%s confirmed receipt of %s units of %s.',
      v_facility_name, v_transfer.quantity_issued, v_item_name),
    'general'
  FROM public.accounts
  WHERE account_type = 'admin' AND status = 'active';

  INSERT INTO public.audit_trail (
    account_id,
    action,
    table_name,
    description,
    new_data
  ) VALUES (
    p_received_by,
    'receive_inventory_transfer',
    'inventory_transfers',
    format('%s received transfer #%s (%s units of "%s")',
      v_facility_name, p_transfer_id, v_transfer.quantity_issued, v_item_name),
    to_jsonb(v_transfer)
  );

  RETURN v_transfer;
END;
$$;

-- This project currently uses its own accounts/password login over the anon
-- Supabase client rather than Supabase Auth. Keep these two tables compatible
-- with that existing model and expose writes only through the RPCs above.
ALTER TABLE public.inventory_stock_requests DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_transfers DISABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.inventory_stock_requests FROM anon, authenticated;
REVOKE ALL ON public.inventory_transfers FROM anon, authenticated;
GRANT SELECT ON public.inventory_stock_requests TO anon, authenticated;
GRANT SELECT ON public.inventory_transfers TO anon, authenticated;

REVOKE ALL ON FUNCTION public.inventory_midwife_facility_id(BIGINT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.inventory_assert_actor(BIGINT, TEXT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.submit_inventory_stock_request(
  BIGINT, BIGINT, INTEGER, TEXT, TEXT
) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.approve_inventory_stock_request(
  BIGINT, BIGINT, TEXT
) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reject_inventory_stock_request(
  BIGINT, BIGINT, TEXT
) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.issue_inventory_transfer(
  BIGINT, BIGINT, INTEGER, BIGINT, BIGINT, TEXT
) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.receive_inventory_transfer(
  BIGINT, BIGINT
) TO anon, authenticated;

COMMIT;
