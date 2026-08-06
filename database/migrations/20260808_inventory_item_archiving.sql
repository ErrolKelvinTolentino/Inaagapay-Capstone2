-- Migration: 20260808_inventory_item_archiving.sql
-- Description: Adds is_archived boolean column to public.inventory_items table and creates an index for efficient filtering.

-- 1. Add is_archived column if it doesn't already exist
ALTER TABLE public.inventory_items 
ADD COLUMN IF NOT EXISTS is_archived BOOLEAN NOT NULL DEFAULT FALSE;

-- 2. Create index for fast status lookups
CREATE INDEX IF NOT EXISTS idx_inventory_items_is_archived ON public.inventory_items(is_archived);

-- 3. Comment on column
COMMENT ON COLUMN public.inventory_items.is_archived IS 'Indicates whether an inventory item has been archived by an admin.';
