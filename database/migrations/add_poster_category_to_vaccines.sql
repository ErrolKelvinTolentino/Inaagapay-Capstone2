-- Migration: Add poster_category column to vaccines table
ALTER TABLE vaccines ADD COLUMN poster_category INT;

-- Seed default categories based on vaccine rules:
-- 1: M.M.R. / Measles
-- 2: BCG, Penta, Polio, PCV, Rotavirus, HepB, Vitamin A (childhood vaccines)
-- 3: Buntis Tetanus (maternal vaccines)

-- 1. Category 1: MMR / Measles
UPDATE vaccines 
SET poster_category = 1 
WHERE vaccine_name ILIKE '%mmr%' 
   OR vaccine_name ILIKE '%measles%' 
   OR vaccine_name ILIKE '%tigdas%' 
   OR vaccine_name ILIKE '%beke%';

-- 2. Category 3: Buntis Tetanus
UPDATE vaccines 
SET poster_category = 3 
WHERE target_recipients = 'mother' 
   OR vaccine_name ILIKE '%tetanus%' 
   OR vaccine_name ILIKE '%toxoid%' 
   OR vaccine_name ILIKE '%td%';

-- 3. Category 2: BCG, Penta, OPV (other childhood vaccines)
UPDATE vaccines 
SET poster_category = 2 
WHERE poster_category IS NULL;
