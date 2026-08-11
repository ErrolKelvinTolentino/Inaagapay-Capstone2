-- Migration: 20260809_fix_transfer_request_id_constraint.sql
-- Description: Drops unique constraint on public.inventory_transfers(request_id) to allow multiple transfers or re-issuing for stock requests without duplicate key errors.

-- 1. Drop unique constraint on request_id if it exists
ALTER TABLE public.inventory_transfers 
DROP CONSTRAINT IF EXISTS inventory_transfers_request_id_key;

-- 2. Drop unique index if exists
DROP INDEX IF EXISTS public.inventory_transfers_request_id_key;

-- 3. Create non-unique index for fast request_id lookup
CREATE INDEX IF NOT EXISTS idx_inventory_transfers_request_id 
ON public.inventory_transfers(request_id);
