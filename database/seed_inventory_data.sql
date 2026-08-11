-- =====================================================
-- InaAgapay — Real DOH Medical Inventory Seed Script
-- Populates DOH vaccines, supplements, contraceptives, medical supplies,
-- active batches, midwife stock requests, transfers, and transactions.
-- =====================================================

-- 0. Ensure generic_name column exists
ALTER TABLE public.inventory_items ADD COLUMN IF NOT EXISTS generic_name VARCHAR(255);

-- 1. Insert DOH Inventory Item Catalog
INSERT INTO public.inventory_items (name, generic_name, item_type, unit_of_measure, minimum_stock_threshold)
VALUES
  ('BCG Vaccine', 'Bacillus Calmette-Guérin', 'vaccine', 'vials', 20),
  ('Pentavalent Vaccine', 'DPT-HepB-Hib Combo', 'vaccine', 'vials', 30),
  ('PCV-13 Vaccine', 'Pneumococcal Conjugate 13', 'vaccine', 'vials', 25),
  ('OPV Polio Vaccine', 'Oral Polio Vaccine', 'vaccine', 'vials', 30),
  ('MR Vaccine', 'Measles-Rubella Vaccine', 'vaccine', 'vials', 20),
  ('Depo-Provera', 'DMPA Injection 150mg/mL', 'contraceptive', 'vials', 40),
  ('Trust Contraceptive Pills', 'Ethinylestradiol + Levonorgestrel', 'contraceptive', 'blisters', 50),
  ('Implanon NXT', 'Etonogestrel Subdermal Implant 68mg', 'contraceptive', 'kits', 15),
  ('Ferrous Sulfate + Folic Acid', 'Iron 60mg + Folic 400mcg', 'supplement', 'tablets', 200),
  ('Vitamin A 200,000 IU', 'Retinol Palmitate (Child)', 'supplement', 'capsules', 100),
  ('Micronutrient Powder (MNP)', 'Multiple Micronutrient Powder', 'supplement', 'sachets', 150),
  ('Paracetamol 500mg', 'Paracetamol 500mg Tablet', 'medical_device', 'tablets', 300),
  ('Amoxicillin 500mg', 'Amoxicillin Trihydrate Capsule', 'medical_device', 'capsules', 200),
  ('Oral Rehydration Salts', 'ORS Hydration Powder', 'supplement', 'sachets', 150),
  ('Auto-Disable Syringes 0.5mL', 'Vaccine AD Syringes', 'medical_device', 'pieces', 500)
ON CONFLICT (name) DO UPDATE SET
  generic_name = EXCLUDED.generic_name,
  item_type = EXCLUDED.item_type,
  unit_of_measure = EXCLUDED.unit_of_measure,
  minimum_stock_threshold = EXCLUDED.minimum_stock_threshold;

-- 2. Insert Stock Batches for Central Warehouse and BHCs
-- Central Warehouse Batches (facility_id IS NULL)
INSERT INTO public.inventory_batches (item_id, facility_id, batch_number, quantity_received, quantity_remaining, received_date, expiration_date, manufacturer, status)
SELECT 
  item_id, 
  NULL, 
  'BATCH-CENTRAL-' || item_id || '-01', 
  500, 
  380, 
  CURRENT_DATE - INTERVAL '30 days', 
  CURRENT_DATE + INTERVAL '365 days', 
  'DOH Central Supply Warehouse', 
  'active'
FROM public.inventory_items;

-- Insert a second expiring batch for alert demonstration
INSERT INTO public.inventory_batches (item_id, facility_id, batch_number, quantity_received, quantity_remaining, received_date, expiration_date, manufacturer, status)
SELECT 
  item_id, 
  NULL, 
  'BATCH-CENTRAL-EXP-' || item_id, 
  100, 
  45, 
  CURRENT_DATE - INTERVAL '180 days', 
  CURRENT_DATE + INTERVAL '12 days', 
  'Biologicals Inc. Philippines', 
  'active'
FROM public.inventory_items
WHERE item_type = 'vaccine' LIMIT 3;

-- 3. Insert BHC Specific Stock Batches
-- Calumpang BHC (Facility ID 1 or BHC 1)
INSERT INTO public.inventory_batches (item_id, facility_id, batch_number, quantity_received, quantity_remaining, received_date, expiration_date, manufacturer, status)
SELECT 
  item_id, 
  1, 
  'BATCH-BHC1-' || item_id, 
  150, 
  95, 
  CURRENT_DATE - INTERVAL '20 days', 
  CURRENT_DATE + INTERVAL '300 days', 
  'DOH Regional Depot', 
  'active'
FROM public.inventory_items;

-- Tarcan BHC (Facility ID 2)
INSERT INTO public.inventory_batches (item_id, facility_id, batch_number, quantity_received, quantity_remaining, received_date, expiration_date, manufacturer, status)
SELECT 
  item_id, 
  2, 
  'BATCH-BHC2-' || item_id, 
  120, 
  40, 
  CURRENT_DATE - INTERVAL '25 days', 
  CURRENT_DATE + INTERVAL '280 days', 
  'DOH Regional Depot', 
  'active'
FROM public.inventory_items;

-- 4. Insert Initial Transaction Records
INSERT INTO public.inventory_transactions (batch_id, facility_id, transaction_type, quantity, reference_type, performed_by, logged_at)
SELECT 
  batch_id, 
  facility_id, 
  'receipt', 
  quantity_received, 
  'Initial DOH Stock Allocation Receipt', 
  1, 
  CURRENT_TIMESTAMP - INTERVAL '30 days'
FROM public.inventory_batches;

-- 5. Insert Sample Dispense Transactions
INSERT INTO public.inventory_transactions (batch_id, facility_id, transaction_type, quantity, reference_type, performed_by, logged_at)
SELECT 
  batch_id, 
  facility_id, 
  'dispense', 
  -15, 
  'Routine Immunization & Maternal Care Dispensing', 
  1, 
  CURRENT_TIMESTAMP - INTERVAL '5 days'
FROM public.inventory_batches
WHERE status = 'active';

-- 6. Insert Sample Midwife Stock Requests
INSERT INTO public.inventory_stock_requests (facility_id, item_id, requested_quantity, reason, remarks, status, requested_by, created_at)
SELECT 
  1, 
  item_id, 
  50, 
  'Monthly BHC replenishment for maternal & child immunization drive', 
  'High patient volume expected next week', 
  'pending', 
  1, 
  CURRENT_TIMESTAMP - INTERVAL '2 days'
FROM public.inventory_items
WHERE item_type IN ('vaccine', 'supplement') LIMIT 3;

INSERT INTO public.inventory_stock_requests (facility_id, item_id, requested_quantity, reason, remarks, status, requested_by, created_at)
SELECT 
  2, 
  item_id, 
  30, 
  'Family planning supply reorder for BHC clinic', 
  'Low stock threshold reached at health center', 
  'approved', 
  1, 
  CURRENT_TIMESTAMP - INTERVAL '1 day'
FROM public.inventory_items
WHERE item_type = 'contraceptive' LIMIT 2;

-- 7. Insert Sample Issued Stock Transfers
INSERT INTO public.inventory_transfers (request_id, source_batch_id, destination_facility_id, quantity_issued, remarks, status, issued_by, issued_at)
SELECT 
  r.request_id, 
  b.batch_id, 
  r.facility_id, 
  r.requested_quantity, 
  'Dispatched via RHU Logistics Unit', 
  'pending_receipt', 
  1, 
  CURRENT_TIMESTAMP - INTERVAL '6 hours'
FROM public.inventory_stock_requests r
JOIN public.inventory_batches b ON b.item_id = r.item_id AND b.facility_id IS NULL
WHERE r.status = 'approved' LIMIT 2;
