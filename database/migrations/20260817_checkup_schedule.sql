-- InaAgapay: the prenatal side of scheduling — table and triggers
--
-- WHY
-- ---
-- `checkup_schedule` and the two triggers that feed it are defined in
-- `database/supabase_setup.sql`, and that file was never run against this
-- project. The table does not exist here.
--
-- Which means:
--
--   * `PrenatalScheduleEngine` proposes the next visit and it is written to
--     `prenatal_checkups.next_schedule`, and nothing ever picks it up.
--   * `midwife_sms_reminders_screen.dart` queries `checkup_schedule` on open.
--     Against a table that does not exist PostgREST returns an error, the
--     catch swallows it, and the screen renders as though no checkup were
--     scheduled for anyone. It has looked like "no data yet" rather than like
--     a fault — the same shape as the defects in section 7 of the progress
--     document.
--   * The day-before reminder has nothing to read.
--
-- This extracts only those pieces from `supabase_setup.sql`. Running that
-- whole file now would replay a schema this database has since diverged from;
-- running these four objects is the smallest change that makes the chain work.
--
-- THE CHAIN, ONCE THIS IS APPLIED
-- -------------------------------
--   midwife saves a checkup with a proposed next visit
--     -> trg_auto_schedule_checkup copies it into checkup_schedule
--        -> trg_notify_checkup_scheduled tells her it is booked
--           -> the daily job reminds her the day before
--
-- Every step is a row in a table that can be inspected, which is the point.

BEGIN;

-- ------------------------------------------------------------------
-- The table
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.checkup_schedule (
    schedule_id    BIGSERIAL PRIMARY KEY,
    mother_id      BIGINT NOT NULL
                     REFERENCES public.mothers (mother_id) ON DELETE CASCADE,
    scheduled_date DATE NOT NULL,
    status         VARCHAR(20) DEFAULT 'scheduled' CHECK (
                       status IN ('scheduled', 'completed', 'missed', 'cancelled')
                   ),
    notes          TEXT,
    created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- One booking per mother per day.
--
-- Not in the original definition, and its absence had teeth: the auto-schedule
-- trigger below ends with ON CONFLICT DO NOTHING, which silently does nothing
-- at all when there is no constraint for it to conflict against. Two checkups
-- proposing the same next date would have produced two rows, and the day-
-- before job would have texted her twice about one appointment.
CREATE UNIQUE INDEX IF NOT EXISTS idx_checkup_schedule_one_per_day
    ON public.checkup_schedule (mother_id, scheduled_date);

-- The reminder job's query: everything still booked for a given date.
CREATE INDEX IF NOT EXISTS idx_checkup_schedule_upcoming
    ON public.checkup_schedule (scheduled_date)
    WHERE status = 'scheduled';

-- ------------------------------------------------------------------
-- A saved checkup books the next one
-- ------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.auto_schedule_next_checkup()
RETURNS TRIGGER AS $$
DECLARE
    v_mother_id BIGINT;
BEGIN
    IF NEW.next_schedule IS NULL THEN RETURN NEW; END IF;

    SELECT mother_id INTO v_mother_id
      FROM public.pregnancies
     WHERE pregnancy_id = NEW.pregnancy_id;

    IF v_mother_id IS NULL THEN RETURN NEW; END IF;

    INSERT INTO public.checkup_schedule (mother_id, scheduled_date, notes)
    VALUES (v_mother_id, NEW.next_schedule, 'Auto-scheduled from prenatal checkup')
    ON CONFLICT (mother_id, scheduled_date) DO NOTHING;

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    -- Booking the next visit must never cost the midwife the checkup she just
    -- recorded. The clinical record is the thing that matters; the reminder is
    -- a convenience on top of it.
    RAISE WARNING 'auto_schedule_next_checkup failed: %', SQLERRM;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_auto_schedule_checkup ON public.prenatal_checkups;
CREATE TRIGGER trg_auto_schedule_checkup
    AFTER INSERT ON public.prenatal_checkups
    FOR EACH ROW
    EXECUTE FUNCTION public.auto_schedule_next_checkup();

-- ------------------------------------------------------------------
-- DELIBERATELY NOT CREATED: notify_checkup_scheduled
--
-- `supabase_setup.sql` also defines a trigger that posts "Upcoming Prenatal
-- Checkup" whenever a row lands in checkup_schedule. Creating it here was a
-- mistake, caught by reading the notifications table after a save:
--
--   13:34:14  Upcoming Prenatal Checkup  — scheduled on Aug 19, 2026
--   13:34:16  Prenatal Checkup Recorded  — next schedule is on Aug 19, 2026
--
-- Two notices, two seconds apart, telling one mother the same thing. The app
-- already sends the second itself, from add_prenatal_checkup_screen.dart, in
-- its own voice and with more context.
--
-- And nothing in the app ever inserts into checkup_schedule — the trigger
-- above is its only writer. So the notice could never fire in any situation
-- other than immediately after a checkup save, which is precisely the moment
-- the app has already told her. There is no case it covers.
--
-- If manual scheduling is ever added — a midwife booking a visit without
-- recording a checkup — this becomes worth having, because then there would
-- be an insert the app does not announce. Restore it from supabase_setup.sql
-- at that point, not before.
-- ------------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_notify_checkup_scheduled ON public.checkup_schedule;
DROP FUNCTION IF EXISTS public.notify_checkup_scheduled();

COMMIT;

-- Confirm:
--   SELECT to_regclass('public.checkup_schedule');
--   SELECT tgname FROM pg_trigger WHERE tgname = 'trg_auto_schedule_checkup';
--
-- Then save a prenatal checkup in the app and check the row appeared:
--   SELECT * FROM public.checkup_schedule ORDER BY created_at DESC LIMIT 5;
--
-- And that she was told once, not twice:
--   SELECT title, created_at FROM public.notifications
--    ORDER BY created_at DESC LIMIT 3;
--
-- ============================================================
-- ROLLBACK
-- ============================================================
-- DROP TRIGGER IF EXISTS trg_auto_schedule_checkup ON public.prenatal_checkups;
-- DROP FUNCTION IF EXISTS public.auto_schedule_next_checkup();
-- DROP TABLE IF EXISTS public.checkup_schedule;
