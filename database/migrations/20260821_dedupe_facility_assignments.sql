-- ==============================================================================
-- MIGRATION: 20260821_dedupe_facility_assignments.sql
--
-- Cleans up the duplicate rows left behind by a self-perpetuating loop in
-- SupabaseService.getMidwifeContext().
--
-- WHAT WENT WRONG
--   The mobile app read a midwife's posting with:
--
--     .from('facility_assignments').eq('account_id', id).eq('is_active', true)
--     .maybeSingle()
--
--   maybeSingle() raises a 406 the moment an account has more than one active
--   row. The catch swallowed it, leaving the posting null, and the very next
--   block then GUESSED a centre from a substring of the e-mail address and
--   INSERTED another facility_assignments row. So every screen that resolved the
--   context added a row, and the next resolution was guaranteed to fail the same
--   way. Four parallel calls on one screen load meant four new rows at a time.
--
--   Worse than the row count: the guess defaulted to facility 1, so a midwife
--   actually posted elsewhere had doses deducted from the wrong centre's stock.
--   On this database, account 41 is posted to Sta. Barbara BHC (midwives.
--   assigned_bhc_id = 5) but had accumulated eight active rows pointing at
--   Tiaong BHC.
--
-- THE CODE FIX
--   getMidwifeContext now reads midwives.assigned_bhc_id first — the column the
--   admin portal writes when it reassigns a midwife, and the one the rest of the
--   app already trusts — falls back to the most recent facility_assignments row
--   with order/limit instead of maybeSingle(), and never inserts a guess.
--
-- THIS SCRIPT
--   Reconciles the rows already in the table. It changes no clinical record and
--   no stock; it only marks superseded assignment rows inactive.
--
-- Safe to run more than once.
-- ==============================================================================


-- ---------------------------------------------------------------------------
-- 1. What is about to change (review this before running section 2)
-- ---------------------------------------------------------------------------
SELECT
  a.account_id,
  a.email_address,
  a.account_type,
  m.assigned_bhc_id                      AS authoritative_posting,
  count(*)                               AS active_assignment_rows,
  array_agg(DISTINCT fa.facility_id)     AS facilities_on_file
FROM public.facility_assignments fa
JOIN public.accounts a  ON a.account_id = fa.account_id
LEFT JOIN public.midwives m ON m.account_id = fa.account_id
WHERE COALESCE(fa.is_active, true)
GROUP BY a.account_id, a.email_address, a.account_type, m.assigned_bhc_id
HAVING count(*) > 1
ORDER BY count(*) DESC;


-- ---------------------------------------------------------------------------
-- 2a. Collapse exact duplicates: same account, same facility, more than one
--     active row. Keeps the newest and retires the rest.
--
--     This cannot change anyone's posting — every row being retired names the
--     same facility as the one being kept.
-- ---------------------------------------------------------------------------
WITH ranked AS (
  SELECT
    facility_assignment_id,
    row_number() OVER (
      PARTITION BY account_id, facility_id
      ORDER BY assigned_at DESC NULLS LAST, facility_assignment_id DESC
    ) AS rn
  FROM public.facility_assignments
  WHERE COALESCE(is_active, true)
)
UPDATE public.facility_assignments fa
   SET is_active = false,
       ended_at  = COALESCE(fa.ended_at, now())
  FROM ranked
 WHERE ranked.facility_assignment_id = fa.facility_assignment_id
   AND ranked.rn > 1;


-- ---------------------------------------------------------------------------
-- 2b. Retire midwife rows that contradict the midwife's actual posting.
--
--     midwives.assigned_bhc_id is what the admin portal writes on the Midwife
--     Assignment page and what the mobile app now reads first, so it decides.
--     Only rows naming a DIFFERENT facility are retired, and only when the
--     midwife has a posting on file at all.
-- ---------------------------------------------------------------------------
UPDATE public.facility_assignments fa
   SET is_active = false,
       ended_at  = COALESCE(fa.ended_at, now())
  FROM public.midwives m
 WHERE m.account_id = fa.account_id
   AND m.assigned_bhc_id IS NOT NULL
   AND COALESCE(fa.is_active, true)
   AND fa.facility_id <> m.assigned_bhc_id;


-- ---------------------------------------------------------------------------
-- 2c. Make sure every midwife still has one active row naming the right centre.
--     2b may have retired the only row a midwife had.
-- ---------------------------------------------------------------------------
INSERT INTO public.facility_assignments (account_id, facility_id, is_active)
SELECT m.account_id, m.assigned_bhc_id, true
  FROM public.midwives m
 WHERE m.assigned_bhc_id IS NOT NULL
   AND NOT EXISTS (
     SELECT 1 FROM public.facility_assignments fa
      WHERE fa.account_id = m.account_id
        AND fa.facility_id = m.assigned_bhc_id
        AND COALESCE(fa.is_active, true)
   );


-- ---------------------------------------------------------------------------
-- 3. Confirm: this should return no rows.
-- ---------------------------------------------------------------------------
SELECT
  fa.account_id,
  a.email_address,
  count(*) AS still_duplicated
FROM public.facility_assignments fa
JOIN public.accounts a ON a.account_id = fa.account_id
WHERE COALESCE(fa.is_active, true)
GROUP BY fa.account_id, a.email_address
HAVING count(*) > 1;


-- ---------------------------------------------------------------------------
-- 4. OPTIONAL hardening — read the caveat first.
--
-- One active assignment per account is the real invariant: a mother attends one
-- centre, a midwife is posted to one, a portal account runs one office. This
-- index makes the runaway impossible at the database level rather than relying
-- on every caller to behave.
--
-- CAVEAT: if you ever add a flow that transfers a mother between centres by
-- inserting the new row before retiring the old one, that flow will start
-- failing with a unique violation and will need reordering. Nothing in the
-- codebase does that today. Uncomment only once you have run section 3 and seen
-- it come back empty.
--
-- CREATE UNIQUE INDEX IF NOT EXISTS uq_facility_assignment_one_active_per_account
--   ON public.facility_assignments (account_id)
--   WHERE is_active;
-- ---------------------------------------------------------------------------
