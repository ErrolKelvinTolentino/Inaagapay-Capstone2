-- Extend the existing audit trail without backfilling or modifying history.
-- Clinical encounters and account/password changes are already audited.
-- Drives use immunization_schedule; scheduled_by is an account_id, whereas
-- maternal_td_records.administered_by is a midwife_id.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

ALTER TABLE public.immunization_schedule
  ADD COLUMN IF NOT EXISTS scheduled_by BIGINT
    REFERENCES public.accounts(account_id) ON DELETE SET NULL;
COMMENT ON COLUMN public.immunization_schedule.scheduled_by IS
  'Account that scheduled the vaccination drive; NULL for older or unattributed schedules.';

CREATE OR REPLACE FUNCTION public.audit_module_for(p_table TEXT, p_action TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $fn$
  SELECT CASE
    WHEN COALESCE(p_table, '') LIKE 'inventory%' THEN 'Inventory'
    WHEN p_action ILIKE '%inventory%' OR p_action ILIKE '%stock%'
      OR p_action ILIKE '%batch%' OR p_action ILIKE '%transfer%'
      OR p_action ILIKE '%vial%' OR p_action ILIKE '%dispos%' THEN 'Inventory'
    WHEN p_action ILIKE '%password%' OR p_action ILIKE '%login%'
      OR p_action ILIKE '%logout%' OR p_action ILIKE '%session%'
      OR p_action ILIKE '%verif%' THEN 'Security'
    WHEN p_table = 'immunization_schedule' THEN 'Vaccination Drives'
    WHEN COALESCE(p_table, '') IN ('accounts', 'password_history')
      OR p_action ILIKE '%account%' THEN 'Accounts'
    WHEN COALESCE(p_table, '') IN ('health_facilities', 'facility_assignments', 'midwives')
      OR p_action ILIKE '%facility%' OR p_action ILIKE '%midwife%' THEN 'Facilities'
    WHEN COALESCE(p_table, '') IN ('ai_responses', 'ai_edit_history', 'ai_prompt_logs')
      OR lower(left(COALESCE(p_action, ''), 3)) = 'ai_' THEN 'AI'
    WHEN p_action ILIKE '%backup%' OR p_action ILIKE '%restore%' THEN 'System'
    WHEN COALESCE(p_table, '') IN ('mothers', 'children', 'pregnancies', 'prenatal_checkups',
      'clinical_encounters', 'immunization_records', 'lab_tests', 'ultrasounds',
      'deliveries', 'child_growth_records', 'maternal_vitals', 'given_medications',
      'maternal_td_records') THEN 'Clinical'
    ELSE 'Activity'
  END;
$fn$;

CREATE OR REPLACE FUNCTION public.audit_vaccination_activity()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $fn$
DECLARE
  v_old JSONB;
  v_new JSONB;
  v_row JSONB;
  v_id TEXT;
  v_actor BIGINT;
  v_who JSONB;
  v_audit BIGINT;
  v_action TEXT;
  v_label TEXT;
  v_entity TEXT;
  v_fields TEXT;
  v_related JSONB;
  v_rows JSONB;
  v_verb TEXT := CASE TG_OP WHEN 'INSERT' THEN 'recorded'
                  WHEN 'DELETE' THEN 'deleted' ELSE 'updated' END;
BEGIN
  IF TG_OP <> 'INSERT' THEN v_old := to_jsonb(OLD); END IF;
  IF TG_OP <> 'DELETE' THEN v_new := to_jsonb(NEW); END IF;
  v_row := COALESCE(v_new, v_old);

  -- Inventory bookkeeping after a Td dose is not another clinical edit.
  IF TG_OP = 'UPDATE' AND
      v_old - ARRAY['inventory_deducted', 'updated_at']
        = v_new - ARRAY['inventory_deducted', 'updated_at'] THEN
    RETURN NULL;
  END IF;
  IF TG_OP = 'UPDATE' THEN
    SELECT string_agg(replace(key, '_', ' '), ', ' ORDER BY key)
      INTO v_fields FROM jsonb_each(v_new)
      WHERE v_old->key IS DISTINCT FROM value
        AND key NOT IN ('inventory_deducted', 'updated_at');
  END IF;

  IF TG_TABLE_NAME = 'maternal_td_records' THEN
    v_id := v_row->>'td_record_id';
    v_action := CASE TG_OP WHEN 'INSERT' THEN 'create_maternal_td'
                   WHEN 'DELETE' THEN 'delete_maternal_td' ELSE 'update_maternal_td' END;
    v_label := 'Td vaccination';
    v_entity := format('Td vaccination (%s) — record #%s', v_row->>'dose_number', v_id);
    SELECT m.account_id INTO v_actor FROM public.midwives m
      WHERE m.midwife_id = public.audit_bigint(v_row->>'administered_by');
    v_related := jsonb_build_object('td_record_id', v_id,
      'mother_id', v_row->>'mother_id', 'facility_id', v_row->>'facility_id',
      'immunization_schedule_id', v_row->>'immunization_schedule_id');
    v_rows := public.audit_kv('Dose', v_row->>'dose_number')
      || public.audit_kv('Record source', v_row->>'source');
  ELSIF TG_TABLE_NAME = 'immunization_schedule' THEN
    v_id := v_row->>'immunization_schedule_id';
    v_action := CASE TG_OP WHEN 'INSERT' THEN 'schedule_vaccination_drive'
                   WHEN 'DELETE' THEN 'delete_vaccination_drive' ELSE 'update_vaccination_drive' END;
    v_label := 'Vaccination drive';
    v_entity := 'Vaccination drive #' || v_id;
    v_actor := public.audit_bigint(v_row->>'scheduled_by');
    v_related := jsonb_build_object('immunization_schedule_id', v_id,
      'facility_id', COALESCE(v_row->>'facility_id', v_row->>'bhc_id'),
      'vaccine_id', v_row->>'vaccine_id');
    v_rows := public.audit_kv('Scheduled date', v_row->>'schedule_date')
      || public.audit_kv('Facility number', COALESCE(v_row->>'facility_id', v_row->>'bhc_id'))
      || public.audit_kv('Vaccine number', v_row->>'vaccine_id');
  ELSE
    RAISE EXCEPTION 'Unexpected vaccination audit table: %', TG_TABLE_NAME;
  END IF;

  v_who := public.audit_account_actor(v_actor);
  v_audit := public.audit_write(
    NULL, v_action, TG_TABLE_NAME, v_id, v_entity,
    format('%s %s — record #%s', v_label, v_verb, v_id),
    format('%s was %s. Record #%s.%s', v_label, v_verb, v_id,
      CASE WHEN v_fields IS NOT NULL THEN ' Fields changed: ' || v_fields || '.' ELSE '' END),
    public.audit_section('Record', public.audit_kv('Record number', '#' || v_id)
      || v_rows || public.audit_kv('Fields changed', v_fields)),
    v_related, v_old, v_new, NULL, lower(TG_OP)
  );
  -- audit_write resolves ambiguous numeric ids as midwife ids first. These
  -- have already been resolved to account ids; snapshot the exact account.
  IF v_audit IS NOT NULL AND v_who->>'account_id' IS NOT NULL THEN
    UPDATE public.audit_trail SET
      account_id = (v_who->>'account_id')::bigint,
      actor_name = v_who->>'name', actor_role = v_who->>'role',
      actor_facility_id = nullif(v_who->>'facility_id', '')::bigint,
      actor_facility_name = v_who->>'facility_name'
    WHERE audit_id = v_audit;
  END IF;
  RETURN NULL;
END;
$fn$;
REVOKE ALL ON FUNCTION public.audit_vaccination_activity() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_audit_maternal_td ON public.maternal_td_records;
CREATE TRIGGER trg_audit_maternal_td
  AFTER INSERT OR UPDATE OR DELETE ON public.maternal_td_records
  FOR EACH ROW EXECUTE FUNCTION public.audit_vaccination_activity();
DROP TRIGGER IF EXISTS trg_audit_vaccination_drive ON public.immunization_schedule;
CREATE TRIGGER trg_audit_vaccination_drive
  AFTER INSERT OR UPDATE OR DELETE ON public.immunization_schedule
  FOR EACH ROW EXECUTE FUNCTION public.audit_vaccination_activity();

-- The checkup form also permits risk-level/factor overrides while the AI
-- remarks remain approved. Those edits do not produce ai_edit_history rows.
CREATE OR REPLACE FUNCTION public.audit_prenatal_ai_review()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $fn$
DECLARE
  v_ai public.ai_responses%ROWTYPE;
  v_who JSONB;
  v_audit BIGINT;
BEGIN
  IF NEW.ai_response_id IS NULL OR COALESCE(NEW.assessed_by_ai, true) THEN
    RETURN NULL;
  END IF;
  SELECT * INTO v_ai FROM public.ai_responses
    WHERE ai_response_id = NEW.ai_response_id;
  -- Text edits already have their own explicit application audit. A skipped
  -- AI response or a manually authored assessment is not an AI review event.
  IF NOT FOUND OR v_ai.reference_table IS DISTINCT FROM 'prenatal_checkups'
      OR NOT COALESCE(v_ai.generated_by_ai, false)
      OR COALESCE(v_ai.status, '') NOT IN ('approved', 'generated') THEN
    RETURN NULL;
  END IF;
  v_who := public.audit_account_actor(v_ai.approved_by);
  v_audit := public.audit_write(
    NULL, 'ai_prenatal_insight_edited', TG_TABLE_NAME, NEW.pregnancy_risk_id::text,
    'Prenatal risk review #' || NEW.pregnancy_risk_id,
    'Prenatal checkup AI risk insights edited',
    'The midwife overrode the prenatal AI risk insights before saving the assessment. Clinical values are held in the patient record.',
    public.audit_section('Review', public.audit_kv('Assessment number', '#' || NEW.pregnancy_risk_id)
      || public.audit_kv('AI response number', '#' || NEW.ai_response_id)),
    jsonb_build_object('pregnancy_risk_id', NEW.pregnancy_risk_id,
      'ai_response_id', NEW.ai_response_id, 'pregnancy_id', NEW.pregnancy_id,
      'encounter_id', v_ai.reference_id),
    NULL, to_jsonb(NEW), NULL, lower(TG_OP)
  );
  IF v_audit IS NOT NULL AND v_who->>'account_id' IS NOT NULL THEN
    UPDATE public.audit_trail SET account_id = (v_who->>'account_id')::bigint,
      actor_name = v_who->>'name', actor_role = v_who->>'role',
      actor_facility_id = nullif(v_who->>'facility_id', '')::bigint,
      actor_facility_name = v_who->>'facility_name'
    WHERE audit_id = v_audit;
  END IF;
  RETURN NULL;
END;
$fn$;
REVOKE ALL ON FUNCTION public.audit_prenatal_ai_review() FROM PUBLIC;
DROP TRIGGER IF EXISTS trg_audit_prenatal_ai_review ON public.pregnancy_risk_assessments;
CREATE TRIGGER trg_audit_prenatal_ai_review
  AFTER INSERT ON public.pregnancy_risk_assessments
  FOR EACH ROW EXECUTE FUNCTION public.audit_prenatal_ai_review();
COMMIT;
