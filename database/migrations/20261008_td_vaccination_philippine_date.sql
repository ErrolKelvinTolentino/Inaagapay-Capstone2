-- The app sends the Philippine calendar date, while Supabase sessions use UTC.
-- From midnight to 07:59 Philippine time, CURRENT_DATE is still yesterday in
-- UTC and rejects today's Td administration as a future vaccination.
-- Patch only that comparison on the installed RPC, preserving its stock,
-- interval, audit, permissions and timestamp behavior. Do not change the
-- function/session timezone: timestamp-without-time-zone logs rely on UTC.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $migration$
DECLARE
  v_function regprocedure := 'public.administer_maternal_td_dose(bigint,text,date,bigint,bigint,text,text,text,text)'::regprocedure;
  v_definition text;
  v_old_guard constant text := 'p_vaccination_date > CURRENT_DATE';
  v_new_guard constant text := 'p_vaccination_date > (CURRENT_TIMESTAMP AT TIME ZONE ''Asia/Manila'')::date';
BEGIN
  v_definition := pg_get_functiondef(v_function);
  IF position(v_new_guard IN v_definition) > 0 THEN
    RETURN;
  END IF;
  IF position(v_old_guard IN v_definition) = 0 THEN
    RAISE EXCEPTION 'Unexpected Td date validation; review the installed function before applying this migration';
  END IF;
  EXECUTE replace(v_definition, v_old_guard, v_new_guard);
END;
$migration$;

COMMIT;
