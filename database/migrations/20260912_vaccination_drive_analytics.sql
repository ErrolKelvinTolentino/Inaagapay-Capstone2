-- ==============================================================================
-- MIGRATION: 20260912_vaccination_drive_analytics.sql
--
-- Makes a past vaccination drive answerable: who was invited, who came, how
-- many doses that took, and what the turnout was.
--
-- WHY
-- ---
-- 20260817_drive_invitations.sql remembers who was invited to a drive. Nothing
-- remembers who turned up. The dose lands in `immunization_records` (child) or
-- `maternal_td_records` (mother) carrying a facility, a vaccine and a date, and
-- the drive it was given at is nowhere in the row.
--
-- So the two halves of every question an RHU asks about a drive -- "we invited
-- 42 mothers, how many came?" -- live in tables that cannot be joined. The only
-- bridge available today is the coincidence that a dose given at a drive shares
-- the drive's facility and date, which is true but is an inference, not a
-- record, and it breaks the moment two drives are held at one centre on one
-- day.
--
-- WHAT THIS ADDS
--
--   1. immunization_records.immunization_schedule_id
--      maternal_td_records.immunization_schedule_id
--      Nullable. Set when a dose is given as part of a drive; null for an
--      ordinary walk-in visit, which is the honest reading and not a defect.
--
--   2. A backfill for history, using the facility + vaccine + date inference
--      described above -- but ONLY where exactly one drive can claim the dose.
--      An ambiguous dose is left null rather than guessed at.
--
--   3. Two read-only views the admin portal reports from:
--        vaccination_drive_analytics    -- one row per drive, with the counts
--        vaccination_drive_participants -- one row per person at a drive
--
-- WHY THE VIEWS STILL MATCH ON FACILITY + DATE
--
-- The new column is authoritative when set, and the views prefer it. But every
-- dose recorded before this migration has it null, and so does every dose the
-- Flutter app records until it is taught to stamp it. Dropping to zero for all
-- historical drives would make the feature useless on the data that exists, so
-- an unstamped dose still falls back to the inference -- and the views say
-- which drives are ambiguous rather than quietly double-counting.
--
-- WHY THE VACCINE IS MATCHED BY NAME, NOT BY vaccine_id
--
-- `vaccines` holds one row per DOSE -- Pentavalent 1, 2 and 3 are three rows.
-- A drive is scheduled against the series (see the note in
-- lib/services/vaccination_drive_service.dart: "the first dose stands for the
-- series"), while each child's record carries the dose they actually received.
-- Matching on vaccine_id would therefore find only the children who happened to
-- be due dose 1 and report every catch-up child as a no-show.
--
-- WHY PARTICIPANTS ARE NUMBERED, NOT NAMED
--
-- Same rule 20260830_dose_traceability.sql set for the dose ledger: this view
-- is read by RHU and municipal officers with no treatment relationship to the
-- patient, and it exports to CSV. The BHC chart number (NAK-000 / INA-000)
-- identifies the row for follow-up; anyone who needs the name looks the number
-- up in Patient Records, where that access is governed.
--
-- ORDERING-SAFE: additive only. Every column is nullable, both views are new
-- names, and no function is replaced -- so nothing an earlier migration
-- installed is rewound by running this, and the portal keeps working if this
-- has not been run yet.
-- ==============================================================================

-- ---------------------------------------------------------------------------
-- 0. Preconditions
-- ---------------------------------------------------------------------------
DO $preflight$
BEGIN
  IF to_regclass('public.immunization_schedule') IS NULL THEN
    RAISE EXCEPTION
      'public.immunization_schedule is missing. Run the base schema first.';
  END IF;

  IF to_regclass('public.drive_invitations') IS NULL THEN
    RAISE EXCEPTION
      'public.drive_invitations is missing. Run database/migrations/20260817_drive_invitations.sql first.';
  END IF;

  IF to_regclass('public.maternal_td_records') IS NULL THEN
    RAISE EXCEPTION
      'public.maternal_td_records is missing. Run database/migrations/20260819_maternal_td_records_and_sync.sql first.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name   = 'immunization_records'
       AND column_name  = 'facility_id'
  ) THEN
    RAISE EXCEPTION
      'immunization_records.facility_id is missing. Run database/migrations/20260819_fix_open_vial_deduction_and_linkage.sql first.';
  END IF;
END
$preflight$;


BEGIN;

-- ---------------------------------------------------------------------------
-- 1. The link from a dose to the drive it was given at
-- ---------------------------------------------------------------------------
--
-- ON DELETE SET NULL, not CASCADE. Deleting a drive from the calendar must
-- never delete the clinical record of a dose that was actually administered;
-- the dose stays, it simply stops being attributed to a drive.

ALTER TABLE public.immunization_records
  ADD COLUMN IF NOT EXISTS immunization_schedule_id BIGINT
    REFERENCES public.immunization_schedule (immunization_schedule_id)
    ON DELETE SET NULL;

ALTER TABLE public.maternal_td_records
  ADD COLUMN IF NOT EXISTS immunization_schedule_id BIGINT
    REFERENCES public.immunization_schedule (immunization_schedule_id)
    ON DELETE SET NULL;

COMMENT ON COLUMN public.immunization_records.immunization_schedule_id IS
  'The vaccination drive this dose was given at, when it was given at one. '
  'NULL for an ordinary visit -- absence of a drive, not missing data.';

COMMENT ON COLUMN public.maternal_td_records.immunization_schedule_id IS
  'The vaccination drive this Td dose was given at, when it was given at one. '
  'NULL for an ordinary prenatal visit.';

-- The views group by this column; the drive detail panel filters on it.
CREATE INDEX IF NOT EXISTS idx_immunization_records_drive
  ON public.immunization_records (immunization_schedule_id)
  WHERE immunization_schedule_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_maternal_td_records_drive
  ON public.maternal_td_records (immunization_schedule_id)
  WHERE immunization_schedule_id IS NOT NULL;

-- The fallback match in the views, and the backfill below.
CREATE INDEX IF NOT EXISTS idx_immunization_records_facility_date
  ON public.immunization_records (facility_id, vaccination_date);

CREATE INDEX IF NOT EXISTS idx_maternal_td_records_facility_date
  ON public.maternal_td_records (facility_id, vaccination_date);


-- ---------------------------------------------------------------------------
-- 2. Backfill history
-- ---------------------------------------------------------------------------
--
-- A dose is attributed to a drive only when exactly ONE drive at that facility,
-- on that date, for that vaccine could have given it. Two drives that collide
-- on all three leave every dose unattributed: a guess here would show up as a
-- turnout figure, which is precisely the kind of number that must not be
-- invented.

WITH claimant AS (
  SELECT ir.immunization_record_id,
         MIN(s.immunization_schedule_id) AS drive_id,
         COUNT(*)                        AS candidates
    FROM public.immunization_records ir
    JOIN public.vaccines rv ON rv.vaccine_id = ir.vaccine_id
    JOIN public.immunization_schedule s
      ON s.facility_id    = ir.facility_id
     AND s.schedule_date  = ir.vaccination_date
    JOIN public.vaccines dv
      ON dv.vaccine_id         = s.vaccine_id
     AND dv.vaccine_name       = rv.vaccine_name
     AND dv.target_recipients  = 'child'
   WHERE ir.immunization_schedule_id IS NULL
     AND ir.facility_id IS NOT NULL
   GROUP BY ir.immunization_record_id
)
UPDATE public.immunization_records ir
   SET immunization_schedule_id = c.drive_id
  FROM claimant c
 WHERE c.immunization_record_id = ir.immunization_record_id
   AND c.candidates = 1;

-- Td is the only vaccine given to mothers in this catalogue, so a maternal
-- drive on a date at a facility is identified by facility and date alone.
WITH claimant AS (
  SELECT td.td_record_id,
         MIN(s.immunization_schedule_id) AS drive_id,
         COUNT(*)                        AS candidates
    FROM public.maternal_td_records td
    JOIN public.immunization_schedule s
      ON s.facility_id   = td.facility_id
     AND s.schedule_date = td.vaccination_date
    JOIN public.vaccines dv
      ON dv.vaccine_id        = s.vaccine_id
     AND dv.target_recipients = 'mother'
   WHERE td.immunization_schedule_id IS NULL
     AND td.facility_id IS NOT NULL
   GROUP BY td.td_record_id
)
UPDATE public.maternal_td_records td
   SET immunization_schedule_id = c.drive_id
  FROM claimant c
 WHERE c.td_record_id = td.td_record_id
   AND c.candidates = 1;

COMMIT;


-- ---------------------------------------------------------------------------
-- 3. One row per drive, with its counts
-- ---------------------------------------------------------------------------
--
-- Deliberately NOT scoped to a facility. The portal filters by facility itself
-- through PortalScope, exactly as it does for every other table it reads; a
-- view that pre-filtered would need to know who is asking, which it cannot.

CREATE OR REPLACE VIEW public.vaccination_drive_analytics AS
WITH drive AS (
  SELECT
    s.immunization_schedule_id                    AS drive_id,
    s.facility_id,
    s.schedule_date,
    s.notes,
    s.created_at,
    v.vaccine_id,
    v.vaccine_name,
    v.dose_number                                 AS scheduled_dose_number,
    v.target_recipients,
    -- When two drive rows collide on facility + date + vaccine, only the
    -- earliest may claim doses that carry no explicit drive id. Without this
    -- the same ten children would be counted as attending both rows, and every
    -- municipal total would be double.
    s.immunization_schedule_id = MIN(s.immunization_schedule_id) OVER (
      PARTITION BY s.facility_id, s.schedule_date, v.vaccine_name
    )                                             AS is_canonical,
    COUNT(*) OVER (
      PARTITION BY s.facility_id, s.schedule_date, v.vaccine_name
    )                                             AS colliding_rows
  FROM public.immunization_schedule s
  JOIN public.vaccines v ON v.vaccine_id = s.vaccine_id
),

-- Every dose attributable to a drive, as {drive, subject}. The subject key is
-- text because a child drive counts children and a maternal drive counts
-- mothers, and the two id spaces overlap.
dose AS (
  SELECT
    d.drive_id,
    'c' || ir.child_id::TEXT AS subject_key
  FROM public.immunization_records ir
  JOIN public.vaccines rv ON rv.vaccine_id = ir.vaccine_id
  JOIN drive d
    ON d.target_recipients = 'child'
   AND (
         ir.immunization_schedule_id = d.drive_id
         OR (
              ir.immunization_schedule_id IS NULL
          AND d.is_canonical
          AND ir.facility_id      = d.facility_id
          AND ir.vaccination_date = d.schedule_date
          AND rv.vaccine_name     = d.vaccine_name
         )
       )
  WHERE COALESCE(ir.status, 'administered') = 'administered'

  UNION ALL

  SELECT
    d.drive_id,
    'm' || td.mother_id::TEXT AS subject_key
  FROM public.maternal_td_records td
  JOIN drive d
    ON d.target_recipients = 'mother'
   AND (
         td.immunization_schedule_id = d.drive_id
         OR (
              td.immunization_schedule_id IS NULL
          AND d.is_canonical
          AND td.facility_id      = d.facility_id
          AND td.vaccination_date = d.schedule_date
         )
       )
),

invited AS (
  SELECT
    i.immunization_schedule_id AS drive_id,
    CASE WHEN i.child_id IS NOT NULL
         THEN 'c' || i.child_id::TEXT
         ELSE 'm' || i.mother_id::TEXT
    END                        AS subject_key,
    i.reminded_at,
    -- An invitation with neither a number nor an address was recorded but never
    -- delivered. Counting it in the denominator of a turnout rate blames the
    -- drive for a contact-details problem, so it is reported separately.
    (COALESCE(NULLIF(BTRIM(i.phone_number), ''),
              NULLIF(BTRIM(i.email_address), '')) IS NOT NULL) AS reachable
  FROM public.drive_invitations i
),

invited_agg AS (
  SELECT
    drive_id,
    COUNT(*)                                        AS invited_count,
    COUNT(*) FILTER (WHERE reachable)               AS invited_reachable,
    COUNT(*) FILTER (WHERE NOT reachable)           AS invited_unreachable,
    COUNT(*) FILTER (WHERE reminded_at IS NOT NULL) AS reminded_count
  FROM invited
  GROUP BY drive_id
),

attend_agg AS (
  SELECT
    d.drive_id,
    COUNT(*)                            AS doses_administered,
    COUNT(DISTINCT d.subject_key)       AS attended_count,
    COUNT(DISTINCT d.subject_key) FILTER (WHERE i.subject_key IS NOT NULL)
                                        AS invited_attended,
    COUNT(DISTINCT d.subject_key) FILTER (WHERE i.subject_key IS NULL)
                                        AS walk_in_count
  FROM dose d
  LEFT JOIN invited i
    ON i.drive_id = d.drive_id AND i.subject_key = d.subject_key
  GROUP BY d.drive_id
)

SELECT
  d.drive_id,
  d.schedule_date,
  d.notes,
  d.created_at,

  -- Where
  d.facility_id,
  hf.name                                   AS facility_name,
  hf.barangay,
  hf.facility_type,
  hf.parent_facility_id                     AS rhu_facility_id,
  rhu.name                                  AS rhu_name,

  -- What
  d.vaccine_id,
  d.vaccine_name,
  d.scheduled_dose_number,
  d.target_recipients,
  CASE WHEN d.target_recipients = 'mother' THEN 'Mothers' ELSE 'Children' END
                                            AS audience,

  -- When, relative to today
  CASE
    WHEN d.schedule_date > CURRENT_DATE THEN 'upcoming'
    WHEN d.schedule_date = CURRENT_DATE THEN 'today'
    ELSE 'completed'
  END                                       AS drive_status,

  -- Who was asked
  COALESCE(ia.invited_count, 0)             AS invited_count,
  COALESCE(ia.invited_reachable, 0)         AS invited_reachable,
  COALESCE(ia.invited_unreachable, 0)       AS invited_unreachable,
  COALESCE(ia.reminded_count, 0)            AS reminded_count,

  -- Who came
  COALESCE(aa.attended_count, 0)            AS attended_count,
  COALESCE(aa.invited_attended, 0)          AS invited_attended,
  COALESCE(aa.walk_in_count, 0)             AS walk_in_count,
  COALESCE(aa.doses_administered, 0)        AS doses_administered,

  -- NULL for a drive that has not happened yet. Nobody has failed to attend a
  -- drive that is still to come, and subtracting an empty attendance from the
  -- invitation list would report the entire barangay as no-shows the moment the
  -- drive was scheduled.
  CASE
    WHEN d.schedule_date > CURRENT_DATE THEN NULL
    ELSE GREATEST(COALESCE(ia.invited_count, 0) - COALESCE(aa.invited_attended, 0), 0)
  END                                       AS no_show_count,

  -- Turnout, as a percentage of those invited. NULL -- not zero -- in two
  -- cases: a drive still to come has no turnout yet, and a drive with no
  -- recorded invitation list has nothing to measure turnout against. 0% would
  -- read as a drive nobody attended, which is a different fact entirely.
  CASE
    WHEN d.schedule_date > CURRENT_DATE       THEN NULL
    WHEN COALESCE(ia.invited_count, 0) = 0    THEN NULL
    ELSE ROUND(100.0 * COALESCE(aa.invited_attended, 0) / ia.invited_count, 1)
  END                                       AS turnout_rate,

  -- The same figure against those the invitation could actually reach.
  CASE
    WHEN d.schedule_date > CURRENT_DATE       THEN NULL
    WHEN COALESCE(ia.invited_reachable, 0) = 0 THEN NULL
    ELSE ROUND(100.0 * COALESCE(aa.invited_attended, 0) / ia.invited_reachable, 1)
  END                                       AS reachable_turnout_rate,

  -- Honesty flags, so the portal can mark a figure rather than present a
  -- collision as fact.
  d.is_canonical,
  d.colliding_rows

FROM drive d
LEFT JOIN public.health_facilities hf  ON hf.facility_id  = d.facility_id
LEFT JOIN public.health_facilities rhu ON rhu.facility_id = hf.parent_facility_id
LEFT JOIN invited_agg ia ON ia.drive_id = d.drive_id
LEFT JOIN attend_agg  aa ON aa.drive_id = d.drive_id;

COMMENT ON VIEW public.vaccination_drive_analytics IS
  'One row per vaccination drive (immunization_schedule) with its barangay, '
  'vaccine, invitation list size and attendance already resolved. A dose is '
  'attributed by immunization_schedule_id when set, otherwise by facility + '
  'date + vaccine NAME (not id -- a drive is scheduled against a series, a '
  'record carries the dose actually given). Where two drive rows collide on '
  'all three, only the earliest claims unstamped doses and colliding_rows > 1 '
  'says so.';


-- ---------------------------------------------------------------------------
-- 4. One row per person at a drive
-- ---------------------------------------------------------------------------
--
-- Invited-and-came, invited-and-did-not, and came-without-an-invitation, in one
-- list. The third case is not an error: a mother who hears about the drive from
-- a neighbour and brings her child is a success, and a roster that hid her
-- would report fewer doses than the inventory ledger shows.

CREATE OR REPLACE VIEW public.vaccination_drive_participants AS
WITH drive AS (
  SELECT
    s.immunization_schedule_id AS drive_id,
    s.facility_id,
    s.schedule_date,
    v.vaccine_name,
    v.target_recipients,
    s.immunization_schedule_id = MIN(s.immunization_schedule_id) OVER (
      PARTITION BY s.facility_id, s.schedule_date, v.vaccine_name
    ) AS is_canonical
  FROM public.immunization_schedule s
  JOIN public.vaccines v ON v.vaccine_id = s.vaccine_id
),

dose AS (
  SELECT
    d.drive_id,
    'child'::TEXT       AS subject_kind,
    ir.child_id         AS subject_id,
    ir.vaccination_date,
    rv.dose_number
  FROM public.immunization_records ir
  JOIN public.vaccines rv ON rv.vaccine_id = ir.vaccine_id
  JOIN drive d
    ON d.target_recipients = 'child'
   AND (
         ir.immunization_schedule_id = d.drive_id
         OR (
              ir.immunization_schedule_id IS NULL
          AND d.is_canonical
          AND ir.facility_id      = d.facility_id
          AND ir.vaccination_date = d.schedule_date
          AND rv.vaccine_name     = d.vaccine_name
         )
       )
  WHERE COALESCE(ir.status, 'administered') = 'administered'

  UNION ALL

  SELECT
    d.drive_id,
    'mother'::TEXT      AS subject_kind,
    td.mother_id        AS subject_id,
    td.vaccination_date,
    -- dose_number is stored as 'Td1'..'Td5' on the maternal table.
    NULLIF(REGEXP_REPLACE(COALESCE(td.dose_number, ''), '[^0-9]', '', 'g'), '')::INT
  FROM public.maternal_td_records td
  JOIN drive d
    ON d.target_recipients = 'mother'
   AND (
         td.immunization_schedule_id = d.drive_id
         OR (
              td.immunization_schedule_id IS NULL
          AND d.is_canonical
          AND td.facility_id      = d.facility_id
          AND td.vaccination_date = d.schedule_date
         )
       )
),

dose_agg AS (
  SELECT drive_id, subject_kind, subject_id,
         COUNT(*)              AS doses_received,
         MIN(vaccination_date) AS attended_on,
         MAX(dose_number)      AS dose_number
  FROM dose
  GROUP BY drive_id, subject_kind, subject_id
),

invited AS (
  SELECT
    i.immunization_schedule_id AS drive_id,
    CASE WHEN i.child_id IS NOT NULL THEN 'child' ELSE 'mother' END AS subject_kind,
    COALESCE(i.child_id, i.mother_id) AS subject_id,
    i.invited_at,
    i.reminded_at,
    (COALESCE(NULLIF(BTRIM(i.phone_number), ''),
              NULLIF(BTRIM(i.email_address), '')) IS NOT NULL) AS reachable
  FROM public.drive_invitations i
),

roster AS (
  SELECT
    COALESCE(iv.drive_id, da.drive_id)         AS drive_id,
    COALESCE(iv.subject_kind, da.subject_kind) AS subject_kind,
    COALESCE(iv.subject_id, da.subject_id)     AS subject_id,
    (iv.drive_id IS NOT NULL)                  AS was_invited,
    COALESCE(iv.reachable, true)               AS reachable,
    iv.invited_at,
    iv.reminded_at,
    (da.drive_id IS NOT NULL)                  AS attended,
    COALESCE(da.doses_received, 0)             AS doses_received,
    da.attended_on,
    da.dose_number
  FROM invited iv
  FULL OUTER JOIN dose_agg da
    ON da.drive_id     = iv.drive_id
   AND da.subject_kind = iv.subject_kind
   AND da.subject_id   = iv.subject_id
)

SELECT
  r.drive_id,
  d.facility_id,
  d.schedule_date,
  d.vaccine_name,
  r.subject_kind,
  r.subject_id,

  -- Chart number only, never a name. See the header note.
  CASE
    WHEN r.subject_kind = 'child'  AND ch.child_number IS NOT NULL
      THEN 'NAK-' || LPAD(ch.child_number::TEXT, 3, '0')
    WHEN r.subject_kind = 'mother' AND fa.patient_number IS NOT NULL
      THEN 'INA-' || LPAD(fa.patient_number::TEXT, 3, '0')
    WHEN r.subject_kind = 'child'  THEN 'Child #'   || r.subject_id
    ELSE 'Patient #' || r.subject_id
  END                                              AS chart_number,

  COALESCE(ch.assigned_bhc_id, mo.assigned_bhc_id) AS subject_bhc_id,

  r.was_invited,
  r.reachable,
  r.invited_at,
  r.reminded_at,
  r.attended,
  r.doses_received,
  r.attended_on,
  r.dose_number,

  CASE
    WHEN r.attended AND NOT r.was_invited THEN 'walk_in'
    WHEN r.attended                       THEN 'attended'
    WHEN NOT r.reachable                  THEN 'unreachable'
    WHEN d.schedule_date > CURRENT_DATE   THEN 'expected'
    ELSE 'no_show'
  END                                              AS outcome

FROM roster r
JOIN drive d ON d.drive_id = r.drive_id
LEFT JOIN public.children ch
       ON r.subject_kind = 'child' AND ch.child_id = r.subject_id
LEFT JOIN public.mothers mo
       ON r.subject_kind = 'mother' AND mo.mother_id = r.subject_id
-- LATERAL with LIMIT 1 for the same reason the dose ledger uses one:
-- facility_assignments has carried duplicate active rows before now, and a
-- plain join on it would emit a participant twice.
LEFT JOIN LATERAL (
  SELECT f.patient_number
    FROM public.facility_assignments f
   WHERE f.account_id  = mo.account_id
     AND f.facility_id = d.facility_id
     AND f.is_active   = true
     AND f.patient_number IS NOT NULL
   ORDER BY f.assigned_at DESC NULLS LAST, f.facility_assignment_id DESC
   LIMIT 1
) fa ON true;

COMMENT ON VIEW public.vaccination_drive_participants IS
  'The roster of one vaccination drive: everyone invited, whether they came, '
  'and everyone who came without an invitation. Identified by BHC chart number '
  'only (NAK-000 / INA-000), matching the rule 20260830_dose_traceability.sql '
  'set for the dose ledger.';


-- ---------------------------------------------------------------------------
-- 5. Grants
-- ---------------------------------------------------------------------------
-- The portal authenticates with account ids against the anon key rather than
-- through Supabase auth, so anon is the role that reads these. Consistent with
-- inventory_dose_ledger and audit_trail_detailed.

GRANT SELECT ON public.vaccination_drive_analytics    TO anon, authenticated, service_role;
GRANT SELECT ON public.vaccination_drive_participants TO anon, authenticated, service_role;


-- ---------------------------------------------------------------------------
-- 6. Verify
-- ---------------------------------------------------------------------------
-- SELECT drive_id, schedule_date, facility_name, barangay, vaccine_name,
--        audience, invited_count, attended_count, no_show_count, turnout_rate,
--        doses_administered, drive_status, colliding_rows
--   FROM public.vaccination_drive_analytics
--  ORDER BY schedule_date DESC;
--
-- Any drive reading colliding_rows > 1 is two calendar entries for one real
-- drive. Only the earliest counts attendance; delete the duplicate.
--
-- SELECT * FROM public.vaccination_drive_participants
--  WHERE drive_id = 1 ORDER BY outcome, chart_number;


-- ============================================================
-- ROLLBACK -- run only if this migration must be undone.
-- Dropping the columns discards which drive each dose was given at; the doses
-- themselves are untouched.
-- ============================================================
-- DROP VIEW IF EXISTS public.vaccination_drive_participants;
-- DROP VIEW IF EXISTS public.vaccination_drive_analytics;
-- DROP INDEX IF EXISTS public.idx_maternal_td_records_facility_date;
-- DROP INDEX IF EXISTS public.idx_immunization_records_facility_date;
-- DROP INDEX IF EXISTS public.idx_maternal_td_records_drive;
-- DROP INDEX IF EXISTS public.idx_immunization_records_drive;
-- ALTER TABLE public.maternal_td_records  DROP COLUMN IF EXISTS immunization_schedule_id;
-- ALTER TABLE public.immunization_records DROP COLUMN IF EXISTS immunization_schedule_id;
