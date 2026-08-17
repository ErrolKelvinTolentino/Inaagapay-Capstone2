-- InaAgapay: the daily day-before reminder job
--
-- WHY
-- ---
-- Every reminder function in this project was written and then never
-- scheduled. `send_upcoming_checkup_reminders`, `send_vaccine_due_reminders`,
-- `mark_missed_checkups` and `send_day_before_checkup_sms` all exist in
-- `run_this_in_supabase.sql` with their `cron.schedule` lines commented out,
-- so nothing time-driven has ever run. The only messages this app has ever
-- sent are the ones a midwife triggered by saving something.
--
-- This replaces four jobs with one. A single daily call to the
-- `send-reminders` Edge Function covers both things a mother has to turn up
-- for — her prenatal checkup and a drive she was invited to — because they
-- are the same job with different rows.
--
-- WHY NOT KEEP IT IN SQL
-- ----------------------
-- `send_day_before_checkup_sms` is named for something it does not do: it
-- inserts an in-app notification and sends no SMS at all. Its own comment
-- admits it ("Future: can also call an SMS Edge Function"). Making it send
-- would mean putting the SMS provider key in the database and writing a third
-- copy of the message wording in a third language. The Edge Function has the
-- key already, and reuses the wording the app sends.
--
-- THE TIMEZONE TRAP THIS AVOIDS
-- -----------------------------
-- The intended schedule is 22:00 UTC, which is 6 AM the next day in Manila.
-- At that instant the UTC date is still the *previous* day, so a function
-- computing `CURRENT_DATE + 1` in UTC targets today-in-Manila rather than
-- tomorrow-in-Manila. Reminders would have gone out a day early, every day,
-- with nothing in the output to show it. The Edge Function computes every
-- date in Asia/Manila; this file passes no date at all so there is only one
-- place that decides what "tomorrow" means.
--
-- BEFORE RUNNING THIS
-- -------------------
--   1. Deploy the function:  supabase functions deploy send-reminders
--   2. Set its secrets:      SEMAPHORE_API_KEY, SEMAPHORE_SENDER_NAME
--      (SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by Supabase)
--   3. Run 20260817_drive_invitations.sql
--   4. Fill in the two placeholders below, then run this file.
--
-- Rehearse it before trusting it — this spends SMS credits:
--
--   select public.run_daily_reminders();                 -- real send
--   select public.preview_daily_reminders('2026-08-19'); -- counts only, no SMS

BEGIN;

CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- ------------------------------------------------------------------
-- Where the function lives, and the key that may call it.
--
-- Kept in one table rather than pasted into each function body. The push
-- trigger in supabase_setup.sql hardcodes a project URL, and it is the URL of
-- a *different* project than the app now uses — so every push it has ever
-- attempted went to the wrong host, and the exception handler swallowed it.
-- One row, changed once, is the fix for that class of mistake.
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.job_settings (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

-- REPLACE BOTH VALUES BEFORE RUNNING.
--   project_url       https://<your-project-ref>.supabase.co
--   service_role_key  Settings -> API -> service_role (secret)
INSERT INTO public.job_settings (key, value) VALUES
    ('project_url',      'https://REPLACE-ME.supabase.co'),
    ('service_role_key', 'REPLACE-ME')
ON CONFLICT (key) DO NOTHING;

-- ------------------------------------------------------------------
-- The job. Fires the function and returns; pg_net is asynchronous, so the
-- result is read from the function's logs rather than from here.
-- ------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.run_daily_reminders() RETURNS void AS $$
DECLARE
    v_url TEXT;
    v_key TEXT;
BEGIN
    SELECT value INTO v_url FROM public.job_settings WHERE key = 'project_url';
    SELECT value INTO v_key FROM public.job_settings WHERE key = 'service_role_key';

    IF v_url IS NULL OR v_key IS NULL OR v_url LIKE '%REPLACE-ME%' THEN
        RAISE WARNING 'run_daily_reminders: job_settings not filled in; nothing sent';
        RETURN;
    END IF;

    PERFORM net.http_post(
        url     := v_url || '/functions/v1/send-reminders',
        headers := jsonb_build_object(
            'Content-Type',  'application/json',
            'Authorization', 'Bearer ' || v_key
        ),
        body    := '{}'::jsonb
    );
END;
$$ LANGUAGE plpgsql;

-- Same call, but the function only counts who it *would* reach. Safe to run
-- as often as you like; spends nothing.
CREATE OR REPLACE FUNCTION public.preview_daily_reminders(p_for_date DATE DEFAULT NULL)
RETURNS void AS $$
DECLARE
    v_url TEXT;
    v_key TEXT;
BEGIN
    SELECT value INTO v_url FROM public.job_settings WHERE key = 'project_url';
    SELECT value INTO v_key FROM public.job_settings WHERE key = 'service_role_key';

    IF v_url IS NULL OR v_key IS NULL OR v_url LIKE '%REPLACE-ME%' THEN
        RAISE WARNING 'preview_daily_reminders: job_settings not filled in';
        RETURN;
    END IF;

    PERFORM net.http_post(
        url     := v_url || '/functions/v1/send-reminders',
        headers := jsonb_build_object(
            'Content-Type',  'application/json',
            'Authorization', 'Bearer ' || v_key
        ),
        body    := jsonb_strip_nulls(jsonb_build_object(
            'dry_run',  true,
            'for_date', p_for_date
        ))
    );
END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------------------------------
-- The schedule. 22:00 UTC = 6:00 AM Manila the following day, which is when a
-- mother can act on the message — a reminder arriving at midnight is read in
-- the morning anyway, and one arriving at 6 AM is read at 6 AM.
-- ------------------------------------------------------------------
SELECT cron.unschedule('daily-day-before-reminders')
 WHERE EXISTS (
     SELECT 1 FROM cron.job WHERE jobname = 'daily-day-before-reminders'
 );

SELECT cron.schedule(
    'daily-day-before-reminders',
    '0 22 * * *',
    $$SELECT public.run_daily_reminders()$$
);

-- ------------------------------------------------------------------
-- Retire the misleading one. It never sent an SMS despite its name, and
-- leaving it schedulable invites someone to turn it on and believe texts are
-- going out. The Edge Function covers what it did, in Manila time.
-- ------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.send_day_before_checkup_sms();

COMMIT;

-- Confirm it registered:
--   SELECT jobname, schedule, active FROM cron.job;
--
-- ============================================================
-- ROLLBACK
-- ============================================================
-- SELECT cron.unschedule('daily-day-before-reminders');
-- DROP FUNCTION IF EXISTS public.preview_daily_reminders(DATE);
-- DROP FUNCTION IF EXISTS public.run_daily_reminders();
-- DROP TABLE IF EXISTS public.job_settings;
