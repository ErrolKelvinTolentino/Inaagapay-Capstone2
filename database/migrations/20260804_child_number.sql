-- InaAgapay: persisted child number (NAK-000)
--
-- Mirrors the mother patient-number design (facility_assignments.patient_number
-- rendered as INA-000): a small, human-readable number that is unique WITHIN a
-- barangay health center, so a midwife can match a record to a physical chart.
--
-- Why the number lives on children instead of a join table: unlike mothers, a
-- child has no facility assignment row of its own. It is registered at whichever
-- BHC the midwife works in, so the BHC is recorded directly on the child.
--
-- Guardian-only children (registered by a father or other guardian rather than a
-- registered mother) get a number too — assigned_bhc_id comes from the
-- registering midwife's BHC, which the app already resolves.
--
-- NOTE ON THE COLUMN TYPE: assigned_bhc_id is a plain BIGINT with no foreign
-- key, deliberately. This project currently has two facility tables in play --
-- `bhc` (bhc_id), used by the admin web and most of the app, and
-- `health_facilities` (facility_id), used by the inventory module with a `bhc`
-- fallback. `mothers.assigned_bhc_id` is stored the same unconstrained way.
-- Adding an FK here would either fail or silently pick the wrong parent until
-- those two tables are reconciled. Naming the column assigned_bhc_id keeps it
-- consistent with `mothers`.

BEGIN;

ALTER TABLE public.children
  ADD COLUMN IF NOT EXISTS assigned_bhc_id BIGINT;

ALTER TABLE public.children
  ADD COLUMN IF NOT EXISTS child_number INTEGER;

-- Unique per BHC, and only for rows that actually have both values.
-- Partial index mirrors unique_patient_number_per_facility.
CREATE UNIQUE INDEX IF NOT EXISTS unique_child_number_per_bhc
  ON public.children (assigned_bhc_id, child_number)
  WHERE assigned_bhc_id IS NOT NULL AND child_number IS NOT NULL;

CREATE OR REPLACE FUNCTION public.set_child_number()
RETURNS TRIGGER AS $$
BEGIN
  -- Only assign when the caller supplied a BHC and did not already provide a
  -- number (keeps backfills and data migrations idempotent).
  IF NEW.assigned_bhc_id IS NOT NULL AND NEW.child_number IS NULL THEN
    SELECT COALESCE(MAX(child_number), 0) + 1
      INTO NEW.child_number
      FROM public.children
     WHERE assigned_bhc_id = NEW.assigned_bhc_id
       AND child_number IS NOT NULL;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_children_child_number ON public.children;

CREATE TRIGGER trg_children_child_number
  BEFORE INSERT ON public.children
  FOR EACH ROW
  EXECUTE FUNCTION public.set_child_number();

-- Backfill existing rows.
--
-- Children linked to a registered mother inherit that mother's BHC. Guardian-
-- only children have no derivable BHC, so they stay NULL and the app renders no
-- badge rather than inventing a number.
UPDATE public.children c
   SET assigned_bhc_id = m.assigned_bhc_id
  FROM public.mothers m
 WHERE c.mother_id = m.mother_id
   AND c.assigned_bhc_id IS NULL
   AND m.assigned_bhc_id IS NOT NULL;

-- Number the backfilled rows per BHC, oldest child first so the sequence
-- reflects registration order.
WITH numbered AS (
  SELECT child_id,
         ROW_NUMBER() OVER (
           PARTITION BY assigned_bhc_id
           ORDER BY added_at NULLS LAST, child_id
         ) AS seq
    FROM public.children
   WHERE assigned_bhc_id IS NOT NULL
     AND child_number IS NULL
)
UPDATE public.children c
   SET child_number = n.seq
  FROM numbered n
 WHERE c.child_id = n.child_id;

COMMIT;
