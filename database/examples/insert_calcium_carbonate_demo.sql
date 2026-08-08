-- Complete InaAgapay inventory-item example
-- Run database/migrations/20260806_inventory_item_details.sql first.
-- Quantity, batch/lot, manufacturer, received date, and expiration are added
-- afterward through the Admin Portal's Record Stock Received workflow.

INSERT INTO public.inventory_items (
  item_code,
  name,
  generic_name,
  strength_description,
  dosage_form,
  item_type,
  unit_of_measure,
  minimum_stock_threshold
)
VALUES (
  'SUP-CAL-500-TAB',
  'Calcium Carbonate 500 mg Tablet',
  'Calcium Carbonate',
  '500 mg',
  'Tablet',
  'supplement',
  'tablets',
  100
)
ON CONFLICT (name) DO UPDATE SET
  item_code = EXCLUDED.item_code,
  generic_name = EXCLUDED.generic_name,
  strength_description = EXCLUDED.strength_description,
  dosage_form = EXCLUDED.dosage_form,
  item_type = EXCLUDED.item_type,
  unit_of_measure = EXCLUDED.unit_of_measure,
  minimum_stock_threshold = EXCLUDED.minimum_stock_threshold
RETURNING
  item_id,
  item_code,
  name,
  generic_name,
  strength_description,
  dosage_form,
  item_type,
  unit_of_measure,
  minimum_stock_threshold;
