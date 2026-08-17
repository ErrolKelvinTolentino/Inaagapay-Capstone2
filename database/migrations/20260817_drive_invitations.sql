-- InaAgapay: record who was invited to a vaccination drive
--
-- WHY
-- ---
-- Scheduling a drive already works out who is due, messages them, and then
-- forgets. The drive row lands in `immunization_schedule`; one notification
-- row lands per mother; the list itself is discarded.
--
-- That costs two things.
--
-- 1. NO REMINDER IS POSSIBLE. A drive on the 19th should be reminded on the
--    18th, and on the 18th nothing knows who was invited. The only ways to
--    recover the list are to re-derive eligibility in SQL — which would mean a
--    second copy of the tetanus and childhood-dose rules, in a language where
--    they cannot be tested — or to parse the text of notification messages.
--    Both are worse than remembering.
--
-- 2. NO AUDIT TRAIL. If a mother says she was never told, there is today no
--    evidence either way. The app records that a drive happened, not that she
--    was invited to it.
--
-- Storing the list makes the reminder job hold NO clinical logic at all:
-- eligibility is decided once, by the rules in
-- `lib/services/vaccination_drive_service.dart`, at the moment of scheduling.
-- Reminding is then only a delivery concern — re-send to a stored list.
--
-- WHY THE CONTACT DETAILS ARE COPIED IN
-- -------------------------------------
-- Phone and email are snapshotted rather than joined at reminder time. The
-- record should say where the invitation was actually sent. If a mother
-- changes her number between the 16th and the 18th, the reminder should go to
-- the new one — so the job reads the live number — but the invitation must
-- still show where the original went. One column answers "where did we send
-- it", the other answers "where do we send now"; a join can only answer the
-- second.
--
-- NOT ENABLING RLS
-- ----------------
-- Deliberate, and consistent with the other operational tables here. This app
-- authenticates with account IDs against the anon key rather than through
-- Supabase auth, so a row-level policy keyed on auth.uid() would reject every
-- write the app makes. This belongs in the limitations section alongside the
-- inventory tables, not in a policy that would have to be written to allow
-- everything anyway.

BEGIN;

CREATE TABLE IF NOT EXISTS public.drive_invitations (
    invitation_id BIGSERIAL PRIMARY KEY,

    immunization_schedule_id BIGINT NOT NULL
        REFERENCES public.immunization_schedule (immunization_schedule_id)
        ON DELETE CASCADE,

    mother_id BIGINT NOT NULL
        REFERENCES public.mothers (mother_id)
        ON DELETE CASCADE,

    -- The mother is always the one messaged; hers is the number on file. On a
    -- child drive the child is who the appointment is for, and the message has
    -- to name them — a mother with three children cannot act on "please come
    -- in". Null on a maternal drive.
    child_id BIGINT
        REFERENCES public.children (child_id)
        ON DELETE CASCADE,
    child_name TEXT,

    -- Where the invitation was sent, as it stood that day. See the note above.
    phone_number TEXT,
    email_address TEXT,

    invited_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Set by the daily reminder job. Its presence is what stops a second run
    -- on the same day sending a second text: cheaper and more honest than
    -- matching on the wording of a notification, and it doubles as the record
    -- of when she was reminded.
    reminded_at TIMESTAMPTZ
);

-- One invitation per person per drive. A maternal drive has one row per
-- mother; a child drive has one per child, so a mother with two children due
-- is invited twice and reminded twice — she has two appointments to keep.
-- COALESCE because NULL never equals NULL in a unique index, which would
-- otherwise let a maternal drive record the same mother repeatedly.
CREATE UNIQUE INDEX IF NOT EXISTS idx_drive_invitations_unique
    ON public.drive_invitations (
        immunization_schedule_id, mother_id, COALESCE(child_id, -1)
    );

-- The reminder job's query: the drives happening tomorrow, and for each the
-- invitations not yet reminded.
CREATE INDEX IF NOT EXISTS idx_drive_invitations_pending
    ON public.drive_invitations (immunization_schedule_id)
    WHERE reminded_at IS NULL;

COMMIT;

-- ============================================================
-- ROLLBACK — run only if this migration must be undone.
-- Dropping this table destroys the record of who was invited to which drive.
-- ============================================================
-- DROP INDEX IF EXISTS idx_drive_invitations_pending;
-- DROP INDEX IF EXISTS idx_drive_invitations_unique;
-- DROP TABLE IF EXISTS public.drive_invitations;
