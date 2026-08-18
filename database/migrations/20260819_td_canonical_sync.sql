-- ==============================================================================
-- MIGRATION: 20260819_td_canonical_sync.sql
-- Single source of truth for Maternal Td doses.
--
-- PROBLEM THIS FIXES
--   The prenatal checkup screen writes prenatal_checkups.td_vaccine_dose as
--   'TD 1'..'TD 5' (spaced, upper-case), while maternal_td_records.dose_number
--   is constrained to 'Td1'..'Td5'. Consequences:
--     1. The one-time backfill in 20260819_maternal_td_records_and_sync.sql
--        filtered on `IN ('Td1',...,'Td5')` and therefore matched NO rows.
--     2. Nothing syncs a prenatal-checkup Td forward into maternal_td_records,
--        so the two screens disagreed about which doses a mother has had.
--
--   Fix: a canonical normalizer, a corrective backfill that uses it, and a
--   forward-sync trigger so every Td recorded through a prenatal checkup also
--   lands in maternal_td_records.
-- ==============================================================================

-- 1. Canonical dose normalizer: 'TD 2', 'Td2', 'td-2', '2', 'Dose 2' -> 'Td2'
CREATE OR REPLACE FUNCTION public.normalize_td_dose(p_raw TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_digits TEXT;
  v_num INTEGER;
BEGIN
  IF p_raw IS NULL THEN RETURN NULL; END IF;

  v_digits := NULLIF(regexp_replace(p_raw, '\D', '', 'g'), '');
  IF v_digits IS NULL THEN RETURN NULL; END IF;

  v_num := v_digits::INTEGER;
  IF v_num < 1 OR v_num > 5 THEN RETURN NULL; END IF;

  RETURN 'Td' || v_num;
END $$;

-- 2. Shared helper: DOH protection window + next due date for a dose
CREATE OR REPLACE FUNCTION public.td_dose_schedule(
  p_dose TEXT,
  p_date DATE,
  OUT o_protection_until DATE,
  OUT o_next_due DATE
)
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  CASE p_dose
    WHEN 'Td1' THEN o_protection_until := NULL;                        o_next_due := p_date + INTERVAL '28 days';
    WHEN 'Td2' THEN o_protection_until := p_date + INTERVAL '3 years'; o_next_due := p_date + INTERVAL '180 days';
    WHEN 'Td3' THEN o_protection_until := p_date + INTERVAL '5 years'; o_next_due := p_date + INTERVAL '365 days';
    WHEN 'Td4' THEN o_protection_until := p_date + INTERVAL '10 years';o_next_due := p_date + INTERVAL '365 days';
    WHEN 'Td5' THEN o_protection_until := p_date + INTERVAL '50 years';o_next_due := NULL;
    ELSE o_protection_until := NULL; o_next_due := NULL;
  END CASE;
END $$;

-- 3. Corrective backfill: catches the 'TD 1'-style rows the original migration missed.
--    DO NOTHING on conflict so authoritative maternal_td_records rows (which carry
--    inventory linkage) are never clobbered by a thinner legacy row.
DO $$
DECLARE
  v_rec RECORD;
  v_prot DATE;
  v_next DATE;
  v_dose TEXT;
  v_admin BIGINT;
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'prenatal_checkups') THEN
    FOR v_rec IN
      SELECT
        ce.mother_id,
        pc.td_vaccine_dose,
        COALESCE(ce.encounter_datetime::DATE, ce.created_at::DATE, CURRENT_DATE) AS v_date,
        ce.facility_id,
        ce.recorded_by
      FROM public.prenatal_checkups pc
      JOIN public.clinical_encounters ce ON ce.encounter_id = pc.encounter_id
      WHERE public.normalize_td_dose(pc.td_vaccine_dose) IS NOT NULL
      ORDER BY ce.created_at ASC
    LOOP
      v_dose := public.normalize_td_dose(v_rec.td_vaccine_dose);
      SELECT o_protection_until, o_next_due INTO v_prot, v_next
      FROM public.td_dose_schedule(v_dose, v_rec.v_date);

      -- Only reference a real midwife row, otherwise leave NULL (avoids FK violation)
      SELECT midwife_id INTO v_admin FROM public.midwives WHERE midwife_id = v_rec.recorded_by;

      INSERT INTO public.maternal_td_records (
        mother_id, dose_number, vaccination_date, facility_id, source,
        administered_by, inventory_deducted, protection_until, next_due_date, remarks
      ) VALUES (
        v_rec.mother_id, v_dose, v_rec.v_date, v_rec.facility_id, 'bhc',
        v_admin, true, v_prot, v_next, 'Recorded during prenatal checkup'
      )
      ON CONFLICT (mother_id, dose_number) DO NOTHING;
    END LOOP;
  END IF;
END $$;

-- 4. Normalize the legacy column itself so future reads are consistent everywhere.
UPDATE public.prenatal_checkups
SET td_vaccine_dose = public.normalize_td_dose(td_vaccine_dose)
WHERE public.normalize_td_dose(td_vaccine_dose) IS NOT NULL
  AND td_vaccine_dose <> public.normalize_td_dose(td_vaccine_dose);

-- 5. Forward sync: any Td recorded via a prenatal checkup lands in maternal_td_records.
CREATE OR REPLACE FUNCTION public.sync_prenatal_td_to_maternal_records()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_dose TEXT;
  v_mother BIGINT;
  v_date DATE;
  v_facility BIGINT;
  v_recorded_by BIGINT;
  v_admin BIGINT;
  v_prot DATE;
  v_next DATE;
BEGIN
  v_dose := public.normalize_td_dose(NEW.td_vaccine_dose);
  IF v_dose IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT ce.mother_id,
         COALESCE(ce.encounter_datetime::DATE, ce.created_at::DATE, CURRENT_DATE),
         ce.facility_id,
         ce.recorded_by
    INTO v_mother, v_date, v_facility, v_recorded_by
  FROM public.clinical_encounters ce
  WHERE ce.encounter_id = NEW.encounter_id;

  IF v_mother IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT o_protection_until, o_next_due INTO v_prot, v_next
  FROM public.td_dose_schedule(v_dose, v_date);

  -- Only reference a real midwife row, otherwise leave NULL (avoids FK violation)
  SELECT midwife_id INTO v_admin FROM public.midwives WHERE midwife_id = v_recorded_by;

  INSERT INTO public.maternal_td_records (
    mother_id, dose_number, vaccination_date, facility_id, source,
    administered_by, inventory_deducted, protection_until, next_due_date, remarks
  ) VALUES (
    v_mother, v_dose, v_date, v_facility, 'bhc',
    v_admin, true, v_prot, v_next, 'Recorded during prenatal checkup'
  )
  ON CONFLICT (mother_id, dose_number) DO NOTHING;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_sync_prenatal_td ON public.prenatal_checkups;
CREATE TRIGGER trg_sync_prenatal_td
AFTER INSERT OR UPDATE OF td_vaccine_dose ON public.prenatal_checkups
FOR EACH ROW
EXECUTE FUNCTION public.sync_prenatal_td_to_maternal_records();

-- 6. Keep the legacy column canonical on write, so both formats can never diverge again.
ALTER TABLE public.prenatal_checkups DROP CONSTRAINT IF EXISTS chk_prenatal_td_dose_canonical;
ALTER TABLE public.prenatal_checkups ADD CONSTRAINT chk_prenatal_td_dose_canonical
  CHECK (
    td_vaccine_dose IS NULL
    OR td_vaccine_dose IN ('-', '', 'none')
    OR td_vaccine_dose IN ('Td1', 'Td2', 'Td3', 'Td4', 'Td5')
  ) NOT VALID;
