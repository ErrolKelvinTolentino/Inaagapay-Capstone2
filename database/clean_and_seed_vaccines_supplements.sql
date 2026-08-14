-- ====================================================================
-- InaAgapay — Clean Inventory & Seed Vaccines + Prenatal Supplements
-- Clean up all inventory tables and re-populate only Vaccines and
-- Maternal/Prenatal Checkup Supplements connected to health facilities.
-- Run this in the Supabase SQL Editor.
-- ====================================================================

BEGIN;

-- 0. Ensure required schema columns exist
ALTER TABLE public.inventory_items ADD COLUMN IF NOT EXISTS generic_name VARCHAR(255);
ALTER TABLE public.inventory_items ADD COLUMN IF NOT EXISTS is_archived BOOLEAN NOT NULL DEFAULT FALSE;

-- 1. Wipe existing inventory movement ledger, requests, transfers, batches, and items
TRUNCATE TABLE public.inventory_transactions CASCADE;
TRUNCATE TABLE public.inventory_transfers CASCADE;
TRUNCATE TABLE public.inventory_stock_requests CASCADE;
TRUNCATE TABLE public.inventory_batches CASCADE;
DELETE FROM public.inventory_items;

-- 2. Insert ONLY Vaccines and Prenatal / Checkup Supplements into inventory_items
INSERT INTO public.inventory_items (name, generic_name, item_type, unit_of_measure, minimum_stock_threshold, is_archived)
VALUES
  -- DOH Child & Maternal Vaccines
  ('BCG Vaccine', 'Bacillus Calmette-Guérin (Tuberculosis)', 'vaccine', 'vials', 20, false),
  ('Hepatitis B Vaccine', 'Hepatitis B (Pediatric Birth Dose)', 'vaccine', 'vials', 25, false),
  ('Pentavalent Vaccine', 'DPT-HepB-Hib Combination', 'vaccine', 'vials', 30, false),
  ('OPV Polio Vaccine', 'Oral Polio Vaccine (bOPV)', 'vaccine', 'vials', 30, false),
  ('IPV Polio Vaccine', 'Inactivated Polio Vaccine', 'vaccine', 'vials', 20, false),
  ('PCV-13 Vaccine', 'Pneumococcal Conjugate 13-Valent', 'vaccine', 'vials', 25, false),
  ('MR Vaccine', 'Measles-Rubella Vaccine', 'vaccine', 'vials', 20, false),
  ('MMR Vaccine', 'Measles-Mumps-Rubella Vaccine', 'vaccine', 'vials', 20, false),
  ('Tetanus Diphtheria (Td) Vaccine', 'Tetanus-Diphtheria Toxoid (Maternal)', 'vaccine', 'vials', 30, false),

  -- Prenatal & Maternal Checkup Supplements
  ('Ferrous Sulfate + Folic Acid', 'Iron 60mg + Folic Acid 400mcg', 'supplement', 'tablets', 200, false),
  ('Calcium Carbonate', 'Elemental Calcium 500mg (Prenatal)', 'supplement', 'tablets', 150, false),
  ('Vitamin A 200,000 IU', 'Retinol Palmitate High-Dose', 'supplement', 'capsules', 100, false),
  ('Micronutrient Powder (MNP)', 'Multiple Micronutrient Sachets', 'supplement', 'sachets', 150, false),
  ('Ascorbic Acid (Vitamin C)', 'Vitamin C 500mg Tablet', 'supplement', 'tablets', 100, false);

-- 3. Seed Central Warehouse Batches for all items (facility_id IS NULL)
INSERT INTO public.inventory_batches (item_id, facility_id, batch_number, quantity_received, quantity_remaining, received_date, expiration_date, manufacturer, status)
SELECT 
  item_id, 
  NULL, 
  'BATCH-CENTRAL-' || item_id || '-01', 
  500, 
  500, 
  CURRENT_DATE - INTERVAL '15 days', 
  CURRENT_DATE + INTERVAL '365 days', 
  'DOH Central Supply Depot', 
  'active'
FROM public.inventory_items;

-- 4. Seed Active BHC Stock Batches for each BHC facility
-- Connects inventory to all active Barangay Health Centers in public.health_facilities
INSERT INTO public.inventory_batches (item_id, facility_id, batch_number, quantity_received, quantity_remaining, received_date, expiration_date, manufacturer, status)
SELECT 
  i.item_id, 
  hf.facility_id, 
  'BATCH-BHC' || hf.facility_id || '-' || i.item_id, 
  100, 
  100, 
  CURRENT_DATE - INTERVAL '10 days', 
  CURRENT_DATE + INTERVAL '300 days', 
  'DOH Regional Distribution Hub', 
  'active'
FROM public.inventory_items i
CROSS JOIN public.health_facilities hf
WHERE hf.facility_type = 'BHC';

-- Fallback: If health_facilities table has no BHC records, insert default batches for BHC IDs 1..5
INSERT INTO public.inventory_batches (item_id, facility_id, batch_number, quantity_received, quantity_remaining, received_date, expiration_date, manufacturer, status)
SELECT 
  i.item_id, 
  f.bhc_id, 
  'BATCH-BHC' || f.bhc_id || '-' || i.item_id, 
  100, 
  100, 
  CURRENT_DATE - INTERVAL '10 days', 
  CURRENT_DATE + INTERVAL '300 days', 
  'DOH Regional Distribution Hub', 
  'active'
FROM public.inventory_items i
CROSS JOIN (VALUES (1), (2), (3), (4), (5)) AS f(bhc_id)
WHERE NOT EXISTS (SELECT 1 FROM public.health_facilities WHERE facility_type = 'BHC');

-- 5. Record Initial Receipt Transactions in Movement Ledger
INSERT INTO public.inventory_transactions (batch_id, facility_id, transaction_type, quantity, reference_type, performed_by, logged_at)
SELECT 
  batch_id, 
  facility_id, 
  'receipt', 
  quantity_received, 
  'Initial DOH Vaccine & Prenatal Supplement Allocation', 
  1, 
  CURRENT_TIMESTAMP - INTERVAL '10 days'
FROM public.inventory_batches;

-- 6. Link Clinical Vaccines table to Physical Inventory Items
ALTER TABLE public.vaccines 
ADD COLUMN IF NOT EXISTS inventory_item_id BIGINT REFERENCES public.inventory_items(item_id) ON DELETE SET NULL;

ALTER TABLE public.immunization_records 
ADD COLUMN IF NOT EXISTS administration_place VARCHAR(30) DEFAULT 'local_facility' CHECK (administration_place IN ('local_facility', 'external_facility')),
ADD COLUMN IF NOT EXISTS facility_id BIGINT REFERENCES public.health_facilities(facility_id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS inventory_batch_id BIGINT REFERENCES public.inventory_batches(batch_id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS inventory_deducted BOOLEAN DEFAULT false;

-- Map clinical vaccine entries to physical inventory items
UPDATE public.vaccines v
SET inventory_item_id = i.item_id
FROM public.inventory_items i
WHERE (v.vaccine_name ILIKE '%bcg%' AND i.name ILIKE '%bcg%')
   OR (v.vaccine_name ILIKE '%penta%' AND i.name ILIKE '%penta%')
   OR (v.vaccine_name ILIKE '%pcv%' AND i.name ILIKE '%pcv%')
   OR (v.vaccine_name ILIKE '%opv%' AND i.name ILIKE '%opv%')
   OR (v.vaccine_name ILIKE '%ipv%' AND i.name ILIKE '%ipv%')
   OR (v.vaccine_name ILIKE '%measles%' AND (i.name ILIKE '%mr%' OR i.name ILIKE '%measles%'))
   OR (v.vaccine_name ILIKE '%mmr%' AND (i.name ILIKE '%mr%' OR i.name ILIKE '%mmr%'))
   OR (v.vaccine_name ILIKE '%hep%' AND i.name ILIKE '%hep%')
   OR (v.vaccine_name ILIKE '%tetanus%' AND i.name ILIKE '%tetanus%')
   OR (v.vaccine_name ILIKE '%td%' AND i.name ILIKE '%td%');

-- 7. Stored Procedure for Automatic FEFO Stock Deduction (Flutter RPC)
CREATE OR REPLACE FUNCTION public.deduct_immunization_stock(
  p_immunization_record_id BIGINT
) RETURNS jsonb AS $$
DECLARE
  v_rec RECORD;
  v_inv_item_id BIGINT;
  v_selected_batch RECORD;
BEGIN
  SELECT ir.*, v.inventory_item_id, m.assigned_bhc_id
  INTO v_rec
  FROM immunization_records ir
  JOIN vaccines v ON v.vaccine_id = ir.vaccine_id
  LEFT JOIN midwives m ON m.midwife_id = ir.administered_by
  WHERE ir.immunization_record_id = p_immunization_record_id;

  IF v_rec IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Record not found');
  END IF;

  IF v_rec.administration_place = 'external_facility' OR v_rec.inventory_deducted = true THEN
    RETURN jsonb_build_object('success', true, 'message', 'No stock deduction required');
  END IF;

  v_rec.facility_id := COALESCE(v_rec.facility_id, v_rec.assigned_bhc_id, 1);
  v_inv_item_id := v_rec.inventory_item_id;

  IF v_inv_item_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Vaccine item not mapped in catalog');
  END IF;

  SELECT * INTO v_selected_batch
  FROM inventory_batches
  WHERE item_id = v_inv_item_id
    AND (facility_id = v_rec.facility_id OR (facility_id IS NULL AND v_rec.facility_id IS NULL))
    AND status = 'active'
    AND quantity_remaining > 0
    AND expiration_date >= CURRENT_DATE
  ORDER BY expiration_date ASC
  LIMIT 1;

  IF v_selected_batch IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Out of stock at facility');
  END IF;

  UPDATE inventory_batches
  SET quantity_remaining = quantity_remaining - 1
  WHERE batch_id = v_selected_batch.batch_id;

  INSERT INTO inventory_transactions (
    batch_id, facility_id, transaction_type, quantity, reference_type, logged_at
  ) VALUES (
    v_selected_batch.batch_id,
    v_rec.facility_id,
    'dispense',
    -1,
    'Auto-dispensed for Child Immunization Record #' || p_immunization_record_id,
    NOW()
  );

  UPDATE immunization_records
  SET inventory_batch_id = v_selected_batch.batch_id,
      facility_id = v_rec.facility_id,
      inventory_deducted = true
  WHERE immunization_record_id = p_immunization_record_id;

  RETURN jsonb_build_object('success', true, 'batch_number', v_selected_batch.batch_number);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT;
