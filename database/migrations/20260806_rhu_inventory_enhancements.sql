-- Migration: RHU Inventory & Generic Name Enhancements
-- Description: Adds generic_name column to public.inventory_items and updates seed data

BEGIN;

-- 1. Add generic_name column to inventory_items table
ALTER TABLE public.inventory_items 
  ADD COLUMN IF NOT EXISTS generic_name VARCHAR(255);

-- 2. Populate generic_name for standard items if null
UPDATE public.inventory_items SET generic_name = 'BCG Vaccine' WHERE LOWER(name) LIKE '%bcg%' AND generic_name IS NULL;
UPDATE public.inventory_items SET generic_name = 'Hepatitis B Vaccine (Recombinant)' WHERE LOWER(name) LIKE '%hep%' AND generic_name IS NULL;
UPDATE public.inventory_items SET generic_name = 'Diphtheria, Tetanus, Pertussis, HepB, Hib Vaccine' WHERE LOWER(name) LIKE '%penta%' AND generic_name IS NULL;
UPDATE public.inventory_items SET generic_name = 'Oral Polio Vaccine' WHERE LOWER(name) LIKE '%opv%' AND generic_name IS NULL;
UPDATE public.inventory_items SET generic_name = 'Inactivated Polio Vaccine' WHERE LOWER(name) LIKE '%ipv%' AND generic_name IS NULL;
UPDATE public.inventory_items SET generic_name = 'Measles, Mumps, Rubella Vaccine' WHERE LOWER(name) LIKE '%mmr%' AND generic_name IS NULL;
UPDATE public.inventory_items SET generic_name = 'Tetanus Diphtheria Toxoid' WHERE LOWER(name) LIKE '%td%' AND generic_name IS NULL;
UPDATE public.inventory_items SET generic_name = 'Ferrous Sulfate + Folic Acid' WHERE LOWER(name) LIKE '%iron%' OR LOWER(name) LIKE '%ferrous%' AND generic_name IS NULL;
UPDATE public.inventory_items SET generic_name = 'Vitamin A (Retinol Capsule)' WHERE LOWER(name) LIKE '%vit%' AND generic_name IS NULL;
UPDATE public.inventory_items SET generic_name = 'Medroxyprogesterone Acetate (DMPA Injection)' WHERE LOWER(name) LIKE '%dmpa%' OR LOWER(name) LIKE '%depo%' AND generic_name IS NULL;
UPDATE public.inventory_items SET generic_name = 'Ethinylestradiol + Levonorgestrel (Pills)' WHERE LOWER(name) LIKE '%pill%' OR LOWER(name) LIKE '%coc%' AND generic_name IS NULL;
UPDATE public.inventory_items SET generic_name = 'Paracetamol 500mg' WHERE LOWER(name) LIKE '%paracetamol%' OR LOWER(name) LIKE '%biogesic%' AND generic_name IS NULL;
UPDATE public.inventory_items SET generic_name = 'Amoxicillin 500mg Capsule' WHERE LOWER(name) LIKE '%amoxicillin%' AND generic_name IS NULL;

-- Fallback for any remaining null generic names to default to item name
UPDATE public.inventory_items SET generic_name = name WHERE generic_name IS NULL OR generic_name = '';

COMMIT;
