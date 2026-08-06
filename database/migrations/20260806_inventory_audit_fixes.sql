-- =====================================================================
-- Inventory audit & traceability fixes
--
-- Safe to run more than once. Every statement is idempotent.
--
-- This migration is ORDERING-SAFE with the admin portal: the portal detects
-- whether these objects exist and falls back to its previous behaviour if they
-- do not. You may therefore deploy the site before or after running this file.
--
-- WHAT IT ADDS
--
-- 1. inventory_stock_requests.approved_quantity
--    A part-approval previously overwrote requested_quantity, destroying the
--    record of what the midwife originally asked for. Worse, the portal tried
--    to write that update directly from the browser, but anon only holds SELECT
--    on this table (see 20260803_inventory_distribution_workflow.sql), so the
--    write silently did nothing. The approved figure now has its own column and
--    is set through a SECURITY DEFINER RPC, matching how every other write to
--    this table already works.
--
-- 2. inventory_disposals + record_inventory_disposal()
--    The disposal certificate was rendered from function-call defaults (officer
--    "RHU Health Officer", today's date, quantity_received rather than the
--    quantity actually destroyed), so reprinting an old certificate produced a
--    document with the wrong officer, quantity and date. Disposal facts are now
--    persisted when the disposal happens.
--
--    The RPC also makes disposal atomic. The portal previously zeroed the batch,
--    then inserted the ledger row, then inserted the record as three separate
--    calls; a failure part-way left stock destroyed with no ledger entry.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 0. Preflight — fail early with a clear message rather than a cryptic
--    "relation does not exist" halfway through.
--    Everything runs inside one transaction, so a failure here leaves the
--    database completely unchanged.
-- ---------------------------------------------------------------------
DO $preflight$
BEGIN
  IF to_regclass('public.inventory_stock_requests') IS NULL THEN
    RAISE EXCEPTION
      'Prerequisite missing: table public.inventory_stock_requests does not exist. Run database/migrations/20260803_inventory_distribution_workflow.sql first, then re-run this file.';
  END IF;

  IF to_regclass('public.inventory_batches') IS NULL THEN
    RAISE EXCEPTION
      'Prerequisite missing: table public.inventory_batches does not exist.';
  END IF;

  IF to_regclass('public.inventory_transactions') IS NULL THEN
    RAISE EXCEPTION
      'Prerequisite missing: table public.inventory_transactions does not exist.';
  END IF;

  IF to_regclass('public.notifications') IS NULL THEN
    RAISE EXCEPTION
      'Prerequisite missing: table public.notifications does not exist.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'inventory_assert_actor'
  ) THEN
    RAISE EXCEPTION
      'Prerequisite missing: function public.inventory_assert_actor() does not exist. Run database/migrations/20260803_inventory_distribution_workflow.sql first, then re-run this file.';
  END IF;
END
$preflight$;

-- ---------------------------------------------------------------------
-- 1. Approved quantity
-- ---------------------------------------------------------------------
ALTER TABLE public.inventory_stock_requests
  ADD COLUMN IF NOT EXISTS approved_quantity integer;

COMMENT ON COLUMN public.inventory_stock_requests.approved_quantity IS
  'Quantity the admin approved. NULL means the full requested_quantity was approved.';

ALTER TABLE public.inventory_stock_requests
  DROP CONSTRAINT IF EXISTS chk_stock_request_approved_qty;
ALTER TABLE public.inventory_stock_requests
  ADD CONSTRAINT chk_stock_request_approved_qty
  CHECK (approved_quantity IS NULL OR approved_quantity > 0);

-- Approve with an explicit quantity.
--
-- Deliberately a NEW function name rather than a changed signature on
-- approve_inventory_stock_request(). Adding a defaulted 4th parameter to the
-- existing function would make the 3-argument call ambiguous and break the
-- currently deployed portal. Both functions now coexist; the old one keeps
-- working unchanged.
CREATE OR REPLACE FUNCTION public.approve_inventory_stock_request_with_quantity(
  p_request_id BIGINT,
  p_admin_id BIGINT,
  p_approved_quantity INTEGER,
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

  IF p_approved_quantity IS NULL OR p_approved_quantity <= 0 THEN
    RAISE EXCEPTION 'Approved quantity must be greater than zero'
      USING ERRCODE = '22023';
  END IF;

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
  IF p_approved_quantity > v_request.requested_quantity THEN
    RAISE EXCEPTION 'Approved quantity (%) cannot exceed the requested quantity (%)',
      p_approved_quantity, v_request.requested_quantity
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.inventory_stock_requests
  SET status = 'approved',
      approved_quantity = p_approved_quantity,
      reviewed_by = p_admin_id,
      reviewed_at = now(),
      admin_remarks = nullif(btrim(coalesce(p_admin_remarks, '')), '')
  WHERE request_id = p_request_id
  RETURNING * INTO v_request;

  INSERT INTO public.notifications (account_id, title, message, type)
  VALUES (
    v_request.requested_by,
    'Stock request approved',
    CASE
      WHEN p_approved_quantity < v_request.requested_quantity THEN
        format('Your stock request #%s was partially approved by RHU Main: %s of %s units.',
               p_request_id, p_approved_quantity, v_request.requested_quantity)
      ELSE
        format('Your stock request #%s was approved by RHU Main.', p_request_id)
    END,
    'general'
  );

  RETURN v_request;
END;
$$;

-- ---------------------------------------------------------------------
-- 2. Disposal records
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.inventory_disposals (
    disposal_id       BIGSERIAL PRIMARY KEY,
    batch_id          BIGINT NOT NULL
                      REFERENCES public.inventory_batches(batch_id) ON DELETE RESTRICT,
    facility_id       BIGINT,
    quantity_disposed INTEGER NOT NULL CHECK (quantity_disposed > 0),
    disposal_method   TEXT NOT NULL,
    officer_name      TEXT NOT NULL,
    notes             TEXT,
    disposed_by       BIGINT REFERENCES public.accounts(account_id) ON DELETE SET NULL,
    disposed_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Plain column, not GENERATED: to_char() over timestamptz is STABLE, not
    -- IMMUTABLE, so Postgres rejects it in a generated column. Set by the RPC.
    certificate_no    TEXT
);

CREATE INDEX IF NOT EXISTS idx_inventory_disposals_batch
  ON public.inventory_disposals(batch_id, disposed_at DESC);

COMMENT ON TABLE public.inventory_disposals IS
  'Immutable record of each pharmaceutical disposal. Source of truth for the DOH disposal certificate.';

-- Atomic disposal: zero the batch, write the ledger row and record the
-- disposal in a single transaction.
CREATE OR REPLACE FUNCTION public.record_inventory_disposal(
  p_batch_id BIGINT,
  p_admin_id BIGINT,
  p_method TEXT,
  p_officer TEXT,
  p_notes TEXT DEFAULT NULL
)
RETURNS public.inventory_disposals
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_batch    public.inventory_batches%ROWTYPE;
  v_disposal public.inventory_disposals%ROWTYPE;
  v_qty      INTEGER;
BEGIN
  PERFORM public.inventory_assert_actor(p_admin_id, 'admin');

  IF nullif(btrim(coalesce(p_officer, '')), '') IS NULL THEN
    RAISE EXCEPTION 'An authorised officer name is required'
      USING ERRCODE = '22023';
  END IF;
  IF nullif(btrim(coalesce(p_method, '')), '') IS NULL THEN
    RAISE EXCEPTION 'A disposal method is required'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_batch
  FROM public.inventory_batches
  WHERE batch_id = p_batch_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Batch not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_batch.status = 'discarded' THEN
    RAISE EXCEPTION 'This batch has already been disposed'
      USING ERRCODE = '22023';
  END IF;

  v_qty := coalesce(v_batch.quantity_remaining, 0);
  IF v_qty <= 0 THEN
    RAISE EXCEPTION 'Batch has no remaining stock to dispose'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.inventory_batches
  SET quantity_remaining = 0,
      status = 'discarded'
  WHERE batch_id = p_batch_id;

  INSERT INTO public.inventory_transactions (
    batch_id, facility_id, transaction_type, quantity, reference_type, performed_by
  )
  VALUES (
    p_batch_id,
    v_batch.facility_id,
    'expiry_disposal',
    -v_qty,
    format('Disposal via %s (Officer: %s)', p_method, p_officer),
    p_admin_id
  );

  INSERT INTO public.inventory_disposals (
    batch_id, facility_id, quantity_disposed, disposal_method,
    officer_name, notes, disposed_by
  )
  VALUES (
    p_batch_id,
    v_batch.facility_id,
    v_qty,
    p_method,
    p_officer,
    nullif(btrim(coalesce(p_notes, '')), ''),
    p_admin_id
  )
  RETURNING * INTO v_disposal;

  UPDATE public.inventory_disposals
  SET certificate_no = 'DISP-' || to_char(v_disposal.disposed_at, 'YYYY')
                       || '-' || v_disposal.disposal_id::text
  WHERE disposal_id = v_disposal.disposal_id
  RETURNING * INTO v_disposal;

  RETURN v_disposal;
END;
$$;

-- ---------------------------------------------------------------------
-- 3. Grants — mirrors 20260803_inventory_distribution_workflow.sql
--    This project authenticates over the anon client rather than Supabase
--    Auth, so writes are exposed only through SECURITY DEFINER RPCs.
-- ---------------------------------------------------------------------
ALTER TABLE public.inventory_disposals DISABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.inventory_disposals FROM anon, authenticated;
GRANT SELECT ON public.inventory_disposals TO anon, authenticated;

GRANT EXECUTE ON FUNCTION public.approve_inventory_stock_request_with_quantity(
  BIGINT, BIGINT, INTEGER, TEXT
) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_inventory_disposal(
  BIGINT, BIGINT, TEXT, TEXT, TEXT
) TO anon, authenticated;

COMMIT;

-- ---------------------------------------------------------------------
-- Reload PostgREST's schema cache so the new column and functions are
-- visible to the REST API immediately rather than after its next refresh.
-- ---------------------------------------------------------------------
NOTIFY pgrst, 'reload schema';
