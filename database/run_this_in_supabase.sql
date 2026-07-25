-- ================================================================
-- InaAgapay — Run this ONCE in the Supabase SQL Editor
-- This script is safe to re-run (uses IF NOT EXISTS / OR REPLACE)
-- ================================================================

-- ============================================================
-- SECTION 1: NEW TABLES
-- ============================================================

CREATE TABLE IF NOT EXISTS notifications (
    notification_id BIGSERIAL PRIMARY KEY,
    account_id BIGINT NOT NULL REFERENCES accounts(account_id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    type VARCHAR(50) DEFAULT 'general' CHECK (
        type IN ('checkup_reminder', 'vaccine_reminder', 'general')
    ),
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS device_tokens (
    device_token_id BIGSERIAL PRIMARY KEY,
    account_id BIGINT NOT NULL REFERENCES accounts(account_id) ON DELETE CASCADE,
    fcm_token TEXT NOT NULL,
    platform VARCHAR(10) DEFAULT 'android' CHECK (platform IN ('android', 'ios')),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS email_queue (
    queue_id BIGSERIAL PRIMARY KEY,
    recipient VARCHAR(255) NOT NULL,
    subject VARCHAR(255) NOT NULL,
    html_content TEXT NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Fix created_by check constraint on accounts if present
ALTER TABLE accounts DROP CONSTRAINT IF EXISTS accounts_created_by_check;

-- ============================================================
-- SECTION 2: INDEXES
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_notifications_account ON notifications(account_id);
CREATE INDEX IF NOT EXISTS idx_notifications_unread ON notifications(account_id, is_read) WHERE is_read = FALSE;
CREATE UNIQUE INDEX IF NOT EXISTS idx_device_tokens_unique ON device_tokens(account_id, fcm_token);
CREATE INDEX IF NOT EXISTS idx_device_tokens_account ON device_tokens(account_id);

-- ============================================================
-- SECTION 3: RLS (disable for anon key access)
-- ============================================================

ALTER TABLE notifications DISABLE ROW LEVEL SECURITY;
ALTER TABLE email_queue DISABLE ROW LEVEL SECURITY;
ALTER TABLE device_tokens DISABLE ROW LEVEL SECURITY;
ALTER TABLE checkup_schedule DISABLE ROW LEVEL SECURITY;

-- ============================================================
-- SECTION 4: UPDATED_AT TRIGGER FOR DEVICE TOKENS
-- ============================================================

DROP TRIGGER IF EXISTS update_device_tokens_updated_at ON device_tokens;
CREATE TRIGGER update_device_tokens_updated_at BEFORE
UPDATE ON device_tokens FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- SECTION 5: NOTIFICATION TRIGGERS
-- ============================================================

-- 5a. When a checkup is scheduled, notify the mother
CREATE OR REPLACE FUNCTION notify_checkup_scheduled() RETURNS TRIGGER AS $$
DECLARE
  v_account_id BIGINT;
  v_scheduled TEXT;
BEGIN
  SELECT account_id INTO v_account_id
    FROM mothers WHERE mother_id = NEW.mother_id;
  IF v_account_id IS NULL THEN RETURN NEW; END IF;

  v_scheduled := TO_CHAR(NEW.scheduled_date, 'Mon DD, YYYY');

  INSERT INTO notifications (account_id, title, message, type)
  VALUES (
    v_account_id,
    'Upcoming Prenatal Checkup',
    'You have a prenatal checkup scheduled on ' || v_scheduled || '. Please prepare and arrive on time.',
    'checkup_reminder'
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_notify_checkup_scheduled ON checkup_schedule;
CREATE TRIGGER trg_notify_checkup_scheduled
  AFTER INSERT ON checkup_schedule
  FOR EACH ROW
  EXECUTE FUNCTION notify_checkup_scheduled();

-- 5b. When a child immunization is recorded, check for next due vaccine
-- NOTE: birthdate is in birth_details table, not children table
CREATE OR REPLACE FUNCTION notify_next_vaccine_due() RETURNS TRIGGER AS $$
DECLARE
  v_mother_id BIGINT;
  v_account_id BIGINT;
  v_child_name TEXT;
  v_birthdate DATE;
  v_age_weeks INT;
  v_next_vaccine RECORD;
BEGIN
  SELECT c.mother_id, c.first_name || ' ' || c.last_name, bd.birthdate
    INTO v_mother_id, v_child_name, v_birthdate
    FROM children c
    LEFT JOIN birth_details bd ON bd.child_id = c.child_id
    WHERE c.child_id = NEW.child_id;

  IF v_mother_id IS NULL THEN RETURN NEW; END IF;

  SELECT account_id INTO v_account_id
    FROM mothers WHERE mother_id = v_mother_id;
  IF v_account_id IS NULL OR v_birthdate IS NULL THEN RETURN NEW; END IF;

  v_age_weeks := (CURRENT_DATE - v_birthdate) / 7;

  SELECT v.vaccine_name, v.recommended_age_months INTO v_next_vaccine
    FROM vaccines v
    WHERE v.target_recipients = 'child'
      AND v.recommended_age_months <= (v_age_weeks / 4.0) + 2
      AND NOT EXISTS (
        SELECT 1 FROM immunization_record ir
        WHERE ir.child_id = NEW.child_id AND ir.vaccine_id = v.vaccine_id
      )
    ORDER BY v.recommended_age_months ASC
    LIMIT 1;

  IF v_next_vaccine IS NOT NULL THEN
    INSERT INTO notifications (account_id, title, message, type)
    VALUES (
      v_account_id,
      'Vaccine Reminder for ' || v_child_name,
      v_next_vaccine.vaccine_name || ' is due (recommended at ' || v_next_vaccine.recommended_age_months || ' months). Please visit your BHC.',
      'vaccine_reminder'
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_notify_next_vaccine ON immunization_record;
CREATE TRIGGER trg_notify_next_vaccine
  AFTER INSERT ON immunization_record
  FOR EACH ROW
  EXECUTE FUNCTION notify_next_vaccine_due();

-- 5c. When a prenatal checkup is saved with next_schedule, auto-create schedule
CREATE OR REPLACE FUNCTION auto_schedule_next_checkup() RETURNS TRIGGER AS $$
DECLARE
  v_mother_id BIGINT;
BEGIN
  IF NEW.next_schedule IS NULL THEN RETURN NEW; END IF;

  SELECT mother_id INTO v_mother_id
    FROM pregnancies WHERE pregnancy_id = NEW.pregnancy_id;
  IF v_mother_id IS NULL THEN RETURN NEW; END IF;

  INSERT INTO checkup_schedule (mother_id, scheduled_date, notes)
  VALUES (v_mother_id, NEW.next_schedule, 'Auto-scheduled from prenatal checkup')
  ON CONFLICT DO NOTHING;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_auto_schedule_checkup ON prenatal_checkups;
CREATE TRIGGER trg_auto_schedule_checkup
  AFTER INSERT ON prenatal_checkups
  FOR EACH ROW
  EXECUTE FUNCTION auto_schedule_next_checkup();

-- ============================================================
-- SECTION 6: DAILY REMINDER FUNCTIONS (for pg_cron)
-- ============================================================

-- 6a. Checkup reminders (3 days ahead, deduped per 24h)
CREATE OR REPLACE FUNCTION send_upcoming_checkup_reminders() RETURNS void AS $$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN
    SELECT cs.schedule_id, cs.mother_id, cs.scheduled_date, m.account_id, a.first_name
      FROM checkup_schedule cs
      JOIN mothers m ON m.mother_id = cs.mother_id
      JOIN accounts a ON a.account_id = m.account_id
     WHERE cs.status = 'scheduled'
       AND cs.scheduled_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '3 days'
       AND NOT EXISTS (
         SELECT 1 FROM notifications n
          WHERE n.account_id = m.account_id
            AND n.type = 'checkup_reminder'
            AND n.title = 'Checkup Reminder'
            AND n.created_at > NOW() - INTERVAL '24 hours'
            AND n.message LIKE '%' || TO_CHAR(cs.scheduled_date, 'Mon DD, YYYY') || '%'
       )
  LOOP
    INSERT INTO notifications (account_id, title, message, type)
    VALUES (
      rec.account_id, 'Checkup Reminder',
      'Hi ' || rec.first_name || ', your prenatal checkup is on ' ||
        TO_CHAR(rec.scheduled_date, 'Mon DD, YYYY') || '. Please prepare and arrive on time.',
      'checkup_reminder'
    );
  END LOOP;
END;
$$ LANGUAGE plpgsql;

-- 6b. Vaccine reminders (age-based, deduped per 7 days)
-- NOTE: birthdate is in birth_details table, not children table
CREATE OR REPLACE FUNCTION send_vaccine_due_reminders() RETURNS void AS $$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN
    SELECT DISTINCT ON (c.child_id, v.vaccine_id)
           c.child_id,
           c.first_name || ' ' || c.last_name AS child_name,
           c.mother_id,
           m.account_id,
           v.vaccine_id,
           v.vaccine_name,
           v.recommended_age_months,
           bd.birthdate,
           ((CURRENT_DATE - bd.birthdate) / 30.0) AS age_months
      FROM children c
      JOIN birth_details bd ON bd.child_id = c.child_id
      JOIN mothers m ON m.mother_id = c.mother_id
      JOIN vaccines v ON v.target_recipients = 'child'
     WHERE bd.birthdate IS NOT NULL
       AND ((CURRENT_DATE - bd.birthdate) / 30.0) >= (v.recommended_age_months - 0.5)
       AND NOT EXISTS (
         SELECT 1 FROM immunization_record ir
          WHERE ir.child_id = c.child_id AND ir.vaccine_id = v.vaccine_id
       )
       AND NOT EXISTS (
         SELECT 1 FROM notifications n
          WHERE n.account_id = m.account_id
            AND n.type = 'vaccine_reminder'
            AND n.created_at > NOW() - INTERVAL '7 days'
            AND n.message LIKE '%' || v.vaccine_name || '%'
            AND n.message LIKE '%' || c.first_name || '%'
       )
     ORDER BY c.child_id, v.vaccine_id, v.recommended_age_months ASC
  LOOP
    INSERT INTO notifications (account_id, title, message, type)
    VALUES (
      rec.account_id,
      'Vaccine Due: ' || rec.child_name,
      rec.vaccine_name || ' is due for ' || rec.child_name ||
        ' (recommended at ' || rec.recommended_age_months || ' months, child is now ' ||
        ROUND(rec.age_months::numeric, 1) || ' months). Please visit your BHC.',
      'vaccine_reminder'
    );
  END LOOP;
END;
$$ LANGUAGE plpgsql;

-- 6c. Mark missed checkups
CREATE OR REPLACE FUNCTION mark_missed_checkups() RETURNS void AS $$
BEGIN
  UPDATE checkup_schedule SET status = 'missed'
   WHERE status = 'scheduled' AND scheduled_date < CURRENT_DATE;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- SECTION 7: SEED MISSING VACCINES
-- ============================================================

INSERT INTO vaccines (vaccine_name, dose_number, recommended_age_months, target_recipients, notes) VALUES
  ('PCV', 1, 1.5, 'child', 'Pneumococcal Conjugate Vaccine - 1st dose'),
  ('PCV', 2, 2.5, 'child', 'Pneumococcal Conjugate Vaccine - 2nd dose'),
  ('PCV', 3, 3.5, 'child', 'Pneumococcal Conjugate Vaccine - 3rd dose'),
  ('Rotavirus', 1, 1.5, 'child', 'Rotavirus Vaccine - 1st dose'),
  ('Rotavirus', 2, 2.5, 'child', 'Rotavirus Vaccine - 2nd dose'),
  ('IPV', 1, 3.5, 'child', 'Inactivated Polio Vaccine'),
  ('Vitamin A', 1, 6.0, 'child', 'Vitamin A Supplementation - 1st dose'),
  ('Vitamin A', 2, 12.0, 'child', 'Vitamin A Supplementation - 2nd dose'),
  ('Measles', 2, 12.0, 'child', 'Measles-Containing Vaccine - 2nd dose'),
  ('MMR', 1, 12.0, 'child', 'Measles, Mumps, Rubella Vaccine')
ON CONFLICT (vaccine_name, dose_number) DO NOTHING;

-- ============================================================
-- SECTION 8: TEST NOTIFICATION (for your account)
-- ============================================================

INSERT INTO notifications (account_id, title, message, type)
VALUES (96, 'Welcome to InaAgapay!',
  'Your notification system is now active. You will receive reminders for checkups and vaccines here.',
  'general');

-- ============================================================
-- SECTION 9: PG_CRON (run separately if pg_cron is enabled)
-- Uncomment and run these lines individually:
-- ============================================================

-- CREATE EXTENSION IF NOT EXISTS pg_cron;
-- SELECT cron.schedule('daily-checkup-reminders',  '0 0 * * *', 'SELECT send_upcoming_checkup_reminders()');
-- SELECT cron.schedule('daily-vaccine-reminders',   '0 0 * * *', 'SELECT send_vaccine_due_reminders()');
-- SELECT cron.schedule('daily-mark-missed-checkups','5 0 * * *', 'SELECT mark_missed_checkups()');

-- ============================================================
-- SECTION 10: PG_NET (needed for push notification trigger)
-- Uncomment and run if you want push notifications:
-- ============================================================

-- CREATE EXTENSION IF NOT EXISTS pg_net;

-- ============================================================
-- SECTION 11: DAY-BEFORE CHECKUP SMS REMINDER (pg_cron)
-- Inserts a notification 1 day before a scheduled checkup.
-- Future: can also call an SMS Edge Function (Semaphore).
-- ============================================================

CREATE OR REPLACE FUNCTION send_day_before_checkup_sms() RETURNS void AS $$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN
    SELECT cs.schedule_id, cs.mother_id, cs.scheduled_date,
           m.account_id, a.first_name, a.phone_number
      FROM checkup_schedule cs
      JOIN mothers m ON m.mother_id = cs.mother_id
      JOIN accounts a ON a.account_id = m.account_id
     WHERE cs.status = 'scheduled'
       AND cs.scheduled_date = CURRENT_DATE + INTERVAL '1 day'
       AND NOT EXISTS (
         SELECT 1 FROM notifications n
          WHERE n.account_id = m.account_id
            AND n.type = 'checkup_reminder'
            AND n.title = 'Checkup Tomorrow'
            AND n.created_at > NOW() - INTERVAL '24 hours'
       )
  LOOP
    INSERT INTO notifications (account_id, title, message, type)
    VALUES (
      rec.account_id,
      'Checkup Tomorrow',
      'Hi ' || rec.first_name || ', just a reminder that you have a prenatal checkup scheduled tomorrow, ' ||
        TO_CHAR(rec.scheduled_date, 'Mon DD, YYYY') || '. Please prepare and arrive on time. Take care, mama!',
      'checkup_reminder'
    );
  END LOOP;
END;
$$ LANGUAGE plpgsql;

-- SELECT cron.schedule('day-before-checkup-sms', '0 22 * * *', 'SELECT send_day_before_checkup_sms()');
-- Runs at 6 AM PHT (22:00 UTC previous day)

-- ============================================================
-- ADD STOCK TRACKING PER BHC
-- ============================================================
ALTER TABLE public.inventory_batches ADD COLUMN IF NOT EXISTS facility_id bigint REFERENCES public.health_facilities(facility_id) ON DELETE SET NULL;
ALTER TABLE public.inventory_transactions ADD COLUMN IF NOT EXISTS facility_id bigint REFERENCES public.health_facilities(facility_id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_inventory_batches_facility ON public.inventory_batches(facility_id);
CREATE INDEX IF NOT EXISTS idx_inventory_transactions_facility ON public.inventory_transactions(facility_id);

-- ============================================================
-- DONE! You should see "Success" with no errors.
-- ============================================================
