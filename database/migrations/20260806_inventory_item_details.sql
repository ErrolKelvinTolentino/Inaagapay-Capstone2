-- InaAgapay complete inventory item details
--
-- Adds first-class catalog metadata used by the Add/Edit Inventory Item form.
-- A single free-text strength_description safely supports combination products
-- such as "60 mg iron + 400 mcg folic acid".

BEGIN;

ALTER TABLE public.inventory_items
  ADD COLUMN IF NOT EXISTS generic_name VARCHAR(160),
  ADD COLUMN IF NOT EXISTS item_code VARCHAR(50),
  ADD COLUMN IF NOT EXISTS strength_description VARCHAR(160),
  ADD COLUMN IF NOT EXISTS dosage_form VARCHAR(80);

-- Normalize accidental empty strings before applying format checks. Legacy
-- rows remain nullable and can be completed through Edit Item Details.
UPDATE public.inventory_items
SET generic_name = nullif(btrim(generic_name), ''),
    item_code = nullif(upper(btrim(item_code)), ''),
    strength_description = nullif(btrim(strength_description), ''),
    dosage_form = nullif(btrim(dosage_form), '');

DO $migration$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.inventory_items'::regclass
      AND conname = 'inventory_items_item_code_format_check'
  ) THEN
    ALTER TABLE public.inventory_items
      ADD CONSTRAINT inventory_items_item_code_format_check
      CHECK (
        item_code IS NULL OR (
          item_code = upper(btrim(item_code))
          AND item_code ~ '^[A-Z0-9][A-Z0-9._/-]{1,49}$'
        )
      ) NOT VALID;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.inventory_items'::regclass
      AND conname = 'inventory_items_strength_description_format_check'
  ) THEN
    ALTER TABLE public.inventory_items
      ADD CONSTRAINT inventory_items_strength_description_format_check
      CHECK (
        strength_description IS NULL OR (
          strength_description = btrim(strength_description)
          AND char_length(strength_description) BETWEEN 1 AND 160
        )
      ) NOT VALID;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.inventory_items'::regclass
      AND conname = 'inventory_items_dosage_form_format_check'
  ) THEN
    ALTER TABLE public.inventory_items
      ADD CONSTRAINT inventory_items_dosage_form_format_check
      CHECK (
        dosage_form IS NULL OR (
          dosage_form = btrim(dosage_form)
          AND char_length(dosage_form) BETWEEN 1 AND 80
        )
      ) NOT VALID;
  END IF;
END
$migration$;

ALTER TABLE public.inventory_items
  VALIDATE CONSTRAINT inventory_items_item_code_format_check;
ALTER TABLE public.inventory_items
  VALIDATE CONSTRAINT inventory_items_strength_description_format_check;
ALTER TABLE public.inventory_items
  VALIDATE CONSTRAINT inventory_items_dosage_form_format_check;

CREATE UNIQUE INDEX IF NOT EXISTS inventory_items_item_code_ci_uidx
  ON public.inventory_items (lower(item_code))
  WHERE item_code IS NOT NULL;

COMMENT ON COLUMN public.inventory_items.generic_name
  IS 'Active or non-brand name displayed separately from the familiar catalog name.';
COMMENT ON COLUMN public.inventory_items.item_code
  IS 'Human-facing inventory catalog code, normalized to uppercase and case-insensitively unique.';
COMMENT ON COLUMN public.inventory_items.strength_description
  IS 'Free-text medicine strength or supply specification, including combination strengths.';
COMMENT ON COLUMN public.inventory_items.dosage_form
  IS 'Medicine dosage form or practical supply form, such as Tablet, Vial, Implant, Kit, or Medical device.';

-- Ask PostgREST to expose the added fields immediately after this migration.
NOTIFY pgrst, 'reload schema';

COMMIT;
