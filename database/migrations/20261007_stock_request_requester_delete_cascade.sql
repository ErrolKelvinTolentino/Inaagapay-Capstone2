-- Deleting an account also deletes stock requests it submitted.
-- Applies to every account, including accounts outside the QA fixtures.
-- Existing requests remain unchanged until their requester is deleted.
-- Transfer request_id links use SET NULL; transfer issuer constraints are
-- separate and can still prevent an account from being deleted.
-- Safe to re-run. Run as postgres in the Supabase SQL Editor.
BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '45s';

ALTER TABLE public.inventory_stock_requests
  DROP CONSTRAINT IF EXISTS inventory_stock_requests_requested_by_fkey;

ALTER TABLE public.inventory_stock_requests
  ADD CONSTRAINT inventory_stock_requests_requested_by_fkey
  FOREIGN KEY (requested_by)
  REFERENCES public.accounts(account_id)
  ON DELETE CASCADE;

COMMENT ON CONSTRAINT inventory_stock_requests_requested_by_fkey
  ON public.inventory_stock_requests IS
  'Deleting a requester account deletes its stock requests; linked transfers retain their stock history with a null request_id.';

COMMIT;

SELECT conname, pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'public.inventory_stock_requests'::regclass
  AND conname = 'inventory_stock_requests_requested_by_fkey';
