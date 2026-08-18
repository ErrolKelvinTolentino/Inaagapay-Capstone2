# InaAgapay — Product Definition, Epics, User Stories & Progress

> **Status:** Post–Capstone Defense 1 revision map. Supersedes `epics_and_user_stories.md`.
> **Last updated:** 2026-08-17 (revision 3)
> **Scope decisions:** QR account linking **removed** (E1-05). PhilHealth /
> 4Ps / civil status fields **descoped** (E2-05). Both recorded below.

---

## 1. What InaAgapay Is

**Purpose:**

> InaAgapay is a maternal and child health record system for Philippine barangay health centers that replaces paper prenatal and immunization records with a shared digital record, adds rule-based risk flagging and plain-language AI explanations so mothers understand their own health data, and gives the RHU/admin visibility and supply control over the health centers under it.

### The problem it solves

| Failure of the paper system | Consequence today | InaAgapay's answer |
|---|---|---|
| Records live on paper in one BHC | Lost, unreadable, not portable, no aggregate view | One record per mother, readable by her assigned midwife and the RHU |
| Clinical data is captured but never interpreted | BP 150/95 is recorded; risk is not escalated | Cited rule engines flag risk at the point of entry |
| Mothers never see or understand their own data | Low adherence, missed visits, low health literacy | Mother app with her own records in mother-friendly language, plus reminders |

### Three actors, three surfaces

- **Admin / RHU staff — web** (`admin-web/`) — oversees all BHCs, accounts, reports, audit trail, and owns the vaccine/supplement stockroom.
- **Midwife — mobile** (`lib/screens/midwife/`) — the primary data creator. Registers mothers, performs prenatal checkups, uploads ultrasound/lab results, records immunizations and growth, receives supplies, schedules vaccination drives.
- **Mother — mobile** (`lib/screens/mother/`) — consumes her own record, self-logs weight, journals, asks the chatbot, receives reminders.

### Positioning guardrail — one principle, applied four times

The system **screens, records and refers. It does not diagnose.** This is not a
disclaimer bolted on; it is the same architecture in four separate features,
which is the strongest single answer this project has:

| Feature | Who decides | What the app does |
|---|---|---|
| **Blood type** | The laboratory | Transcribes from a report attached in the same action. Never typed from memory |
| **Blood pressure** | The referring physician | Applies a cited threshold, names the rule on screen, states the pattern |
| **Gestational diabetes** | The physician | Identifies who is due, records values, compares to guideline, refers |
| **Ultrasound** | The sonologist | Restates their findings in plain language. Adds nothing of its own |

Every AI output is attributable to a human approver
(`clinical_encounters.is_midwife_approved`, `ai_responses.approved_by`), and
every clinical rule lives in one overridable object with its source named in
the file.

---

## 2. Epic Map & Progress Summary

| # | Epic | Wt | Progress | Status |
|---|---|---|---|---|
| E1 | Identity, Access & Account Lifecycle | 8 | **95%** | QR removed cleanly; only `password_history` left unused |
| E2 | Mother & Pregnancy Registry | 12 | **100%** | Blood type transcribed from documents; GPAL's L restored |
| E3 | Prenatal Encounter & Clinical Decision Support | 15 | **99%** | BP and FHR both on one cited rule set; only adviser sign-off left |
| E4 | Diagnostic Document Intelligence | 12 | **93%** | "Explain My Report" done; OCR truncation and rate-limit failures fixed |
| E5 | Scheduling, Reminders & Vaccination Drives | 8 | **99%** | Day-before SMS reminders live; dose intervals enforced |
| E6 | Child Health — Immunization & Growth | 15 | **93%** | Growth verified against WHO; child drives added |
| E7 | Mother Experience, Self-Care & Baby Book | 12 | **85%** | Baby Book shipped; jargon audit measurably not done |
| E8 | Inventory Distribution (RHU → BHC) | 8 | **88%** | Gates drives by live stock; second Supabase client unresolved |
| E9 | Admin Web — Monitoring, Reporting & Governance | 7 | **78%** | **Largest remaining gap by weight.** No role checks exist at all |
| E10 | Research & Documentation Artifacts | 3 | **92%** | ERD and sampling complete; limitations section owes thirteen entries |
| **E11** | **Midwife Analytics & Decision Support** *(new)* | 6 | **85%** | Dashboard analytics, priority band, GDM surfacing — device-verified |
| **E12** | **Gestational Diabetes Screening** *(new)* | 5 | **88%** | OGTT extraction and classification verified; migration + protocol outstanding |
| | **Weighted overall** | 111 | **~92%** | Against the same 111-point scope |

Legend: ✅ done · 🟡 partial · 🔴 partial with a known defect · ❌ not started · ⛔ removed

**Test suite: 280 passing, 0 failing.** `flutter analyze lib/ test/` reports zero errors.

> **Why the headline barely moved, and why that is the point.** Revision 2 read
> ~92%. Revision 3 reads ~92%. In between, the busiest clinical screen in the
> app stopped showing two contradictory severity labels for the same reading,
> a whole category of reminder started existing, and 37 tests were added.
>
> The number did not move because **revision 2's number was wrong**. E3 was
> scored 90% while carrying a defect that displayed "HTN Stage 2" and
> "Hypertension in Pregnancy" side by side; E5 was scored 92% while the table
> its reminders read from did not exist in the database. Both are now true
> rather than merely claimed. A progress figure that survives being checked is
> worth more than one that goes up.
>
> **The pattern worth defending.** Four separate features were found running
> silently degraded, each one looking exactly like normal operation — see §8.
> That is the same failure mode as revision 2's defect list, and having found
> it four more times is itself a finding about the system.

---

## 3. Epics & User Stories

### E1 — Identity, Access & Account Lifecycle — 95%

#### E1-01 Log in with contact number or email — ✅
- [x] Login detects identifier type — `lib/screens/auth/login.dart:33-48`

#### E1-02 Auto-generated temporary password — ✅
- [x] `is_temporary_password` column; forced change screen gated at `main.dart:145-151`
- [x] Delivered by SMS — **working**, sender name `AGAPAY`

#### E1-03 Add an email later — ✅
#### E1-04 Password recovery & OTP — ✅

#### E1-05 QR account linking — ⛔ REMOVED (2026-08-15)
Previously parked with a QR generator shipped and no scanner. The generator has
now been deleted entirely: `mother_qr_code.dart`, the header icon on the mother
profile, and the `qr_flutter` dependency. The encoded `inaagapay://mother/{id}`
deep link had no handler either.

**Panel answer:** duplicate accounts are prevented at registration by phone and
email uniqueness — `SupabaseService.isPhoneNumberAvailable`, `isEmailAvailable`
and `getExistingMotherAccount`. QR would have been convenience on top of that
mechanism, not the mechanism itself.

**Remaining:** `password_history` exists in the schema, has RLS enabled, and is
referenced by no code and no trigger — password reuse is not prevented. One
line in the limitations section, not code.

---

### E2 — Mother & Pregnancy Registry — 100%

#### E2-01 Multi-step Add Mother — ✅
#### E2-02 Pre-pregnancy weight drives baseline BMI — ✅
#### E2-03 Unique Patient Number — ✅
Index-derived `INA-001` IDs replaced with the persisted database value. Worth
mentioning at defense as an example of validating displayed data against its
source of truth.

#### E2-04 Blood type — ✅
- [x] Extracted from lab report images as a discrete OCR field
- [x] Strict parser — `lib/models/blood_type.dart`, 40 tests. Accepts
      "O Positive", "AB Rh(D) Positive", "Blood Type: B Neg"; rejects "A"
      alone, "Unknown", and prose like "A positive result for HBsAg"
- [x] Conflicts with an existing record are **flagged, never overwritten**
- [x] Read-only on the mother profile — one write path, always backed by a document
- [x] Closed a live defect: the old dropdown offered "Unknown", which the
      `mothers.blood_type` CHECK constraint rejects

**Panel answer:** no API can determine blood type — it requires a serologic
test. It is transcribed from the mother's lab result and confirmed by the
midwife. Automatic determination is a *rejected* approach with a clinical
reason, which is a stronger answer than an inconclusive feasibility study.

#### E2-05 PhilHealth / 4Ps / civil status — ⛔ DESCOPED (2026-08-15)
`philhealth_number`, `philhealth_status`, `is_four_ps` and `civil_status` exist
in the schema and are captured nowhere. Decision: out of scope for BHC intake in
this version; they are RHU-level data. **Note this in limitations** — a panelist
reading the ERD will see the columns.

---

### E3 — Prenatal Encounter & Clinical Decision Support — 99%

#### E3-01 Prenatal checkup capture — ✅
#### E3-02 Gestational weight gain vs IOM 2009 — ✅
Includes twin ranges, rate-of-gain by week, and a documented fallback for
underweight-twin where no official IOM data exists.

#### E3-03 Risk flagging — ✅ DONE (revision 3)
- [x] **`lib/services/blood_pressure_reference.dart`** — one cited,
      configurable rule set. 28 tests
- [x] **Two-occasion criterion implemented.** Gestational hypertension is
      defined on two occasions, not one reading; the app previously alarmed on
      a single raised value, which over-calls and trains people to ignore it
- [x] Severe range (≥160/110) outranks the pattern — same-day referral, not
      "wait and repeat"
- [x] Raised readings before week 20 noted as pointing to pre-existing rather
      than pregnancy-related hypertension
- [x] Low readings in weeks 16–28 explained as the normal mid-pregnancy fall
      rather than flagged — a purely numeric rule fires on healthy mothers
- [x] BP trend chart on the mother profile, plotted against gestational age
      with the thresholds drawn as labelled reference lines
- [x] A test asserts no output label ever contains "hypertension",
      "preeclampsia", "stage 1/2" or "crisis"
- [x] ✅ **The ten legacy BP rule blocks are gone.** Revision 2 recorded nine
      (there were ten — one more sat in `risk_engine.dart`, outside the
      screens that were searched). One used the non-pregnancy AHA staging, so
      **145/95 displayed "HTN Stage 2" and "Hypertension in Pregnancy" eight
      lines apart in the same section**; another compared with `>`, putting
      exactly 140/90 a stage below where every risk engine put it. All ten now
      call `BloodPressureReference`. `smart_risk_engine.dart` — dead code
      carrying an uncited `sys >= 135` "borderline" threshold appearing in no
      guideline in this project — was deleted rather than migrated
- [x] ✅ **The two-occasion criterion now runs at the point of entry.** The
      checkup screen already loaded the last six visits with their pressures
      and never used them. A second raised reading is now named as such while
      the midwife is still typing, instead of only on the trend card
- [x] ✅ **Gestational age is stated in completed weeks.** A stored visit came
      back as `weeks + days/7` and was rounded for display, so 10w6d read as
      "week 11" while the screen that recorded it said "week 10" — the same
      afternoon appearing as two different weeks
- [x] ✅ **The trend chart plots one point per visit, not per week.** Two
      checkups on the same day resolved to the same gestational age and landed
      on the same x, so the second hid behind the first — on the one card whose
      purpose is showing whether a raised reading repeated
- [x] ✅ **A regression guard.** The suite fails if either screen or
      `risk_engine.dart` reintroduces a staging label or stops reading the
      shared rule set

#### E3-03b Fetal heart rate — ✅ DONE (revision 3)
- [x] **`lib/services/fetal_heart_rate_reference.dart`** — same shape as the
      BP module, cited to the NICHD baseline range. 16 tests
- [x] **Seven sites held two ranges.** Six said 120–160, one said 110–160.
      The minority was the correct one: **in six of seven places a normal
      baseline of 110–119 bpm was reported as a finding** on the mother's own
      record. The app was over-calling on healthy babies
- [x] The seventh site was a colour callback under the input field
      (`v >= 110 && v <= 160`) with the range typed into its label. The first
      guard missed it because it keyed on variable names; it now checks for
      any comparison against a literal bound, and for the range spelled out as
      text
- [x] The field hint says something different in each state rather than
      changing colour alone — a red line reading "Normal range" is close to
      self-contradictory, and colour is not available to every reader
- [x] Two context notes the old code had nowhere to put: a low rate may be the
      mother's own pulse, and nothing heard before week 12 is a Doppler
      limitation rather than a missing measurement

**Remaining for E3 — not code:**
- [ ] ⚠️ **Confirm the BP thresholds** with the clinical adviser and record the
      guideline edition in `kBloodPressureSourceNote`
- [ ] ⚠️ **Confirm the FHR baseline** and record it in
      `kFetalHeartRateSourceNote`. If the RHU follows 120–160, that is
      `FhrThresholds(baselineMin: 120)` and no other file changes

#### E3-04 Care insights show who approved — ✅
#### E3-05 Simplified checkup form — ✅

---

### E4 — Diagnostic Document Intelligence — 93%

#### E4-01 Ultrasound capture & OCR extraction — ✅
#### E4-02 Lab test capture & interpretation — ✅
#### E4-03 File management — ✅
- [ ] Confirm PDF is accepted alongside JPG/PNG in the client-side picker

#### E4-04 Reframe AI ultrasound interpretation — ✅ DONE
> Panel question: if the radiologist already interpreted it, what does the AI add?

The module is now **"Explain My Report."** The prompt opens *"You are a
TRANSLATOR, not an interpreter"* and states that a qualified sonologist has
already examined the scan and their work is finished. A hard constraint block
forbids stating any finding absent from the report, revising or contradicting
the impression, or deriving a conclusion from the measurements. Where
information is missing it must say the scan did not record it.

All UI language changed from "interpretation" to "explanation" in English and
Filipino; zero occurrences of "AI-assisted interpretation" remain in `lib/`.

**Panel answer:** the radiologist interprets; InaAgapay translates. Its
contribution is comprehension, not diagnosis — and a mother who understands her
own report attends her next visit.

---

### E5 — Scheduling, Reminders & Vaccination Drives — 99%

#### E5-01 Manual scheduling & calendar — ✅

#### E5-02 Automated visit interval computation — ✅ DONE
The interval logic **already existed** inside `add_prenatal_checkup_screen.dart`
and was clinically correct; the earlier note that "no interval logic exists
anywhere" checked `supabase_service.dart` and the schedules screen, not the
checkup screen. It has been extracted to
**`lib/services/prenatal_schedule_engine.dart`** — same dates, now cited,
configurable, unit tested (17 tests), and reusable by GDM screening timing.

Intervals: 4-weekly to 28 weeks, 2-weekly to 36, weekly thereafter, 3-day
post-term, shortened for high risk. A term cap prevents proposing a visit past
week 42.

- [ ] ⚠️ Confirm with the adviser whether the RHU follows this conventional
      model or WHO 2016's 8-contact model — a different model, not different
      numbers. "Every two days in the final weeks" from the Defense 1 notes is
      post-term surveillance and is deliberately not encoded as routine

#### E5-03 Reminders — ✅ DONE (revision 3)
- [x] **SMS live** — sender `AGAPAY`, same path as temporary passwords
- [x] In-app notifications, realtime

**Day-before reminders — new in revision 3.** A mother is now reminded the day
before her prenatal checkup *and* the day before a drive she was invited to,
by SMS.

- [x] **`supabase/functions/send-reminders`** — one daily job covering both,
      because they are the same job over different rows. Deployed and verified
      returning correct counts against live data
- [x] **It holds no clinical logic.** Who is due for a drive was decided when
      the drive was scheduled, by the tested rules in
      `vaccination_drive_service.dart`, and stored. Reminding re-sends to a
      stored list. Whether a checkup exists was decided by
      `PrenatalScheduleEngine`. Nothing in the reminder path decides who needs
      care — which is why none of those rules had to be rewritten in SQL
- [x] **`drive_invitations`** (`20260817_drive_invitations.sql`) — records who
      was invited to which drive, including mothers who could not be reached.
      Before this the list was computed, messaged and discarded, so *"nobody
      told me"* had no evidence either way
- [x] **`checkup_schedule` and its trigger** (`20260817_checkup_schedule.sql`)
      — see §8. The table did not exist in this project's database at all
- [x] **Dates are computed in Asia/Manila.** The job runs at 22:00 UTC to land
      at 6 AM Manila, and at that instant the UTC date is still the previous
      day — so a naive `CURRENT_DATE + 1` targets *today* in Manila. Every
      reminder would have gone out a day early, every day, with nothing in the
      output to show it
- [x] **A dry-run mode.** `preview_daily_reminders()` and a `dry_run` flag
      report who *would* be texted without sending or spending. The feature can
      be demonstrated rather than described
- [x] Deduped by `reminded_at`, so a second run the same day sends nothing
- [x] Messages stay under one 160-character billing segment
- [x] `send_day_before_checkup_sms()` retired — it sent no SMS despite its
      name, and leaving it schedulable invited someone to switch it on and
      believe texts were going out

#### E5-04 Vaccination drives — ✅ NEW
A midwife schedules a drive (vaccine + date) which appears on the Schedules
calendar and invites everyone due by SMS, email and in-app notice.

**Maternal drives**
- [x] No schema change — `immunization_schedule` was already facility + vaccine + date
- [x] Eligibility is the **whole five-dose series**, not TD2. TD2 protects the
      newborn in this pregnancy; TD3–TD5 extend protection toward lifetime, and
      a drive is when they get given
- [x] Doses counted **across every pregnancy** — tetanus protection accumulates
      over a lifetime, so counting per pregnancy showed mothers who had TD2
      years ago as never vaccinated
- [x] Minimum intervals enforced (4 weeks, 6 months, 1 year, 1 year). A dose
      given too soon does not extend protection, so inviting early wastes a
      vial and leaves her believing she is covered
- [x] Eligibility follows the **drive date**, not today

**Child drives**
- [x] Recipients are children old enough for a dose they have not had; the
      **mother** is messaged, since hers is the contact on file, and the
      message names the child to bring
- [x] Timeliness judged by `ImmunizationSchedule`, the same rules the child
      profile uses, so a child cannot read as "due" here and "not due" there
- [x] ✅ **Minimum interval between doses now enforced** (revision 3). The
      query already fetched `vaccination_date` and then collapsed the rows into
      a set of ids, discarding the one value that made the rule computable. The
      judgement is `ImmunizationSchedule`'s — the same rules the child's own
      profile applies — so she cannot read as due here and "wait four weeks"
      there. `VaccinationDriveService.dueDoseFor` is a pure function with 11
      tests, including that the interval is measured to the **drive date**
      rather than to today
- [x] The age ceiling is respected in the same pass: a dose past its upper
      limit is skipped rather than offered. Only Rotavirus carries one in the
      DOH childhood schedule

**Stock and safety**
- [x] Live stock shown per vaccine; out-of-stock options greyed and unselectable
- [x] Counts only active, unexpired batches — expired stock is not stock
- [x] "Stock not tracked" distinguished from "out of stock"
- [x] One action, one confirmation naming the count; the drive is written
      before anything sends, so nobody is invited to a drive that failed to save
- [x] An unreadable dose counts as zero — an unreadable record is not evidence
      of protection
- [x] Unreachable mothers surfaced, not silently dropped
- [x] SMS kept under one 160-character billing segment
- [x] Results counted in **mothers**, not messages

#### E5-05 Scheduling limitations statement — ✅
Documented: proposed dates ignore holidays, closures, non-working days and
clinic capacity; the midwife resolves those.

---

### E6 — Child Health: Immunization & Growth — 93%

#### E6-01 Full 0–12 month immunization schedule — ✅
#### E6-02 Growth monitoring with WHO Z-scores — ✅
#### E6-03 Child registration & birth details — ✅
- [ ] Verify the growth axis scales to 60 months with SD bands across the range

---

### E7 — Mother Experience, Self-Care & Baby Book — 85%

#### E7-01 Self-logged vitals — ✅ (with a repair)
The page's checkup query requested four columns that do not exist on
`prenatal_checkups`. PostgREST rejected it, the catch swallowed it, and the
page rendered as though the mother had no checkups — **no blood pressure, and a
weight-gain analysis built only from self-reported weights.** The
"self-reported data never overwrites clinical data" behaviour was real but had
nothing to act on. Fixed; BP now displays as a plain reading with no clinical
label, because interpretation belongs on the midwife's side.

**Note:** mothers cannot log their own BP — `maternal_vitals` has no BP
columns. The user story should read "logs her own weight."

#### E7-02 Mother-friendly language & illustrations — 🟡
- [ ] No systematic jargon audit — "fundal height", "AOG", "edema", "Z-score"
      still appear on mother-facing screens

#### E7-03 Journal — ✅
#### E7-04 Chatbot — ✅

#### E7-05 Baby Book module — ✅ DONE
~3,760 lines across `child_baby_book_page.dart`, a 596-line repository, five
widgets, four migrations, **157 DOH ECCD postnatal milestones seeded**, and
four dedicated test files.

#### E7-06 Mother dashboard & records — ✅

---

### E8 — Inventory Distribution (RHU → BHC) — 88%

E8-01 through E8-06 ✅ — catalog, batches, expiry, issue-to-BHC, notification,
midwife receipt confirmation, stock requests, and a who/when audit trail.

- [ ] Editing a release after issue — verify an edit path exists and re-notifies
- [ ] Auth hardening: the migration documents that account IDs are not
      production-grade credentials and RLS is off. Belongs in limitations
- [ ] `inventory_repository.dart` points at a different Supabase project than
      the app and hardcodes its URL and anon key

---

### E9 — Admin Web: Monitoring, Reporting & Governance — 78%

E9-01 through E9-05 ✅ — executive dashboard, reports and export, account and
assignment management (including activate/deactivate/suspend), audit trail and
backup, patient records browser.

**This is now the largest remaining gap by weight.**
- [ ] Surface patient number in `patient-records.html`
- [ ] Role-based access hardening

---

### E10 — Research & Documentation Artifacts — 92%

ERD redesign and the population sampling revision are complete. The
**limitations section is now materially out of date** — it owes thirteen
entries, four of them carried over from revision 2. This is the cheapest
remaining work on the board: it is writing, not code.

**Carried from revision 2**
1. QR account linking removed (E1-05)
2. PhilHealth / 4Ps / civil status descoped (E2-05)
3. `password_history` retained in schema but not enforced
4. Mothers cannot self-log blood pressure — `maternal_vitals` has no BP columns

**New in revision 3**
5. **Blood pressure thresholds** follow ACOG PB 222, pending confirmation
   against the DOH/POGS edition the RHU uses
6. **Fetal heart rate baseline** follows NICHD 110–160, pending the same
   confirmation
7. **No alerting when an external model provider retires a model.** Groq
   removed the Llama 3.x line; every AI text feature fell back silently and
   nobody noticed until a specific screen was tested
8. **`email_queue` has no consumer.** Emails are written to the queue table and
   nothing reads it, so no email this system has "sent" has ever been
   delivered. SMS is the working channel
9. **Push notifications are not delivered.** The trigger is absent from this
   database, the `send-push` Edge Function does not exist, and the version in
   `supabase_setup.sql` points at a different Supabase project than the app
   uses. In-app notifications and realtime are unaffected
10. **The BP trend chart spaces visits by sequence, not elapsed time.** A
    four-week gap and a same-day repeat are drawn the same distance apart. The
    trade was deliberate: plotting by gestational week collapsed same-week
    visits onto one point, hiding exactly the repeat the card exists to show
11. **`drive_invitations` has RLS disabled**, consistent with the other
    operational tables. This app authenticates with account IDs against the
    anon key rather than Supabase auth, so a policy keyed on `auth.uid()`
    would reject every write the app makes
12. **A second Supabase client.** `inventory_repository.dart` constructs its
    own client with a hardcoded URL and anon key. It currently matches `.env`,
    but `.env` is gitignored — any build where it fails to load puts the app on
    one project and inventory on another
13. **Reminder SMS is billed per message.** A day-before reminder to every
    mother with a checkup is a recurring daily cost against Semaphore credits

---

### E11 — Midwife Analytics & Decision Support — 85% *(new scope)*

*Goal:* turn recorded data into something a midwife acts on today.

- [x] One `AnalyticsMetric` type and one card shell — twelve metrics, one
      layout. Four visuals only: donut, bars, ranked bars, coverage meter
- [x] **Severity colours reserved for severity.** Ordered categories use a
      brand ramp; green/amber/red mean good/watch/alert; grey means *not
      measured* and never green
- [x] **Counts over percentages** below n=10 — one person moves a small-centre
      percentage by double digits
- [x] Services measured against *eligible denominators*, not tallies. Replaced
      three tiles counting every Ferrous/Calcium/TD dose ever recorded — totals
      that only rose and could never show a gap
- [x] Descriptive → diagnostic → prescriptive on every card, with the
      diagnostic layer being deterministic rules over recorded rows, never
      generated prose
- [x] "Needs attention" priority band: checkups due, high-risk pregnancies
      named with their factor, children behind on doses, GDM screening, low stock
- [x] Risk drivers card reads `pregnancy_risk_factors` — the causes the
      database already stored and nothing had ever displayed. Groups wordings
      that describe the same finding, since three screens write maternal age
      three different ways and one embeds the mother's own age
- [ ] Not verified on a device
- [ ] Inventory cards fall back to clearly-labelled sample data

---

### E12 — Gestational Diabetes Screening — 88% *(new scope)*

*Goal:* identify who needs screening, record the result, alert the midwife —
without diagnosing.

**Framing that matters:** GDM is caused by placental hormones creating insulin
resistance, **not by cravings**, and it is usually **asymptomatic**. That is why
the feature is built around screening rather than symptom detection, and why
symptoms belong only as a prompt to test.

- [x] `lib/services/gestational_diabetes_screening.dart` — 25 tests
- [x] Risk stratification from data already held: maternal age, pre-pregnancy
      BMI, previous baby ≥4000g, recorded diabetes. Nothing new asked of the midwife
- [x] Both protocols supported — one-step 75g (default) and two-step 100g
- [x] **An incomplete test is not a negative one** — too few samples returns
      "incomplete" and asks for a repeat
- [x] mmol/L guarded twice: the prompt returns null for mmol/L reports, and the
      field rejects anything outside 20–600. A 5.1 entered as mg/dL would sail
      under every threshold and look reassuring
- [x] Glucose capture in the lab form with live reading and referral action
- [x] Dashboard: screening coverage card + four priority rows
- [x] Nothing writes a diagnosis. A test asserts no output names a condition
- [ ] 🔴 **Run `database/migrations/20260812_gdm_glucose_values.sql`** — until
      then glucose values cannot save and the card shows a "waiting on the
      columns" state by design
- [ ] ⚠️ Confirm the protocol with the adviser — this is the research asked for
- [ ] Family history of diabetes is a recognised risk factor the app cannot record
- [ ] Postpartum 6–12 week OGTT follow-up — future work

---

## 4. Priority Ordering Before Defense 2

### Tier 0 — blocking, and not code
1. **Run two migrations** in Supabase:
   - `20260812_gdm_glucose_values.sql` — without it glucose cannot save
   - `20260815_ai_responses_index.sql` — the mother profile times out without
     it. Six of the tables the profile reads have no index on `pregnancy_id`,
     and the scans lengthen with every record saved
2. **Confirm five sets of clinical thresholds** with the adviser, and record
   each citation in the file that holds it:
   - GDM protocol — one-step 75g or two-step 100g
   - Blood pressure cut-points — `kBloodPressureSourceNote`
   - Fetal heart rate baseline — `kFetalHeartRateSourceNote`
   - Antenatal visit intervals — conventional or WHO 8-contact
   - TD minimum intervals between doses
3. **Rotate the `service_role` key** before this project holds real patient
   data. It bypasses every rule in the database, and rotating it also
   regenerates the anon key — so `.env`, `admin-web/js/supabase-client.js`,
   `inventory_repository.dart` and `job_settings` all need updating together

### Tier 1 — writing, not code
4. **Update the limitations section** — thirteen entries listed under E10.
   Three weighted points for an afternoon of writing, and the cheapest work
   remaining

### Tier 2 — real build work
5. **E9 admin web polish + role hardening** — largest gap by weight. There are
   no role checks at all in `common-security.js` or `auth.js`
6. Mother-facing jargon audit (E7-02) — 44 hits in `mother_child_growth.dart`
   alone
7. Email delivery — `email_queue` has no consumer (§8)
8. Push notification delivery — no `send-push` function exists (§8)

### Tier 3 — polish
9. GDM postpartum follow-up
10. Inventory analytics cards still fall back to labelled sample data (E11)

### Done since revision 2
- ~~Consolidate the BP rule blocks~~ — all ten, plus fetal heart rate (E3)
- ~~Enable pg_cron~~ — one daily job, armed and dry-run verified (E5)
- ~~Children's vaccination drives~~ — including the minimum dose interval (E5)
- ~~Verify child drives on a device~~ (§6)

---

## 5. Mapping: Defense 1 Revisions → Epics

| Panel revision | Epic / Story | Status |
|---|---|---|
| Revise population sampling | E10-02 | ✅ |
| Redesign ERD | E10-01 | ✅ |
| Temp password on contact-only registration | E1-02 | ✅ |
| Log in with contact number | E1-01 | ✅ |
| Editable email added later | E1-03 | ✅ |
| QR account linking | E1-05 | ⛔ removed |
| Store uploaded file size | E4-03 | ✅ |
| Accept JPG / PNG / PDF | E4-03 | 🟡 verify picker |
| Unique Patient Number | E2-03 | ✅ |
| Midwife attribution | E3-04 | ✅ |
| More illustrations / simpler terms | E7-02 | 🟡 |
| Baby Book module | E7-05 | ✅ |
| Mother self-logs vitals | E7-01 | ✅ |
| Pre-pregnancy weight logic | E2-02 | ✅ |
| Weight gain from pre-preg + current + AOG | E3-02 | ✅ |
| Blood Type API research | E2-04 | ✅ rejected with reason |
| BP conditions / genetics / medications | E3-03 | ✅ all ten rule blocks on one cited module |
| Fetal heart rate & tones | E3-03b | ✅ cited 110–160; the *rate* is judged, the tone is recorded only |
| Doppler limitation statement | E10-03 | ✅ |
| Inventory availability | E8-01 | ✅ |
| Automated prenatal scheduling | E5-02 | ✅ |
| Scheduling limitations statement | E5-05 | ✅ |
| Care insights show approver | E3-04 | ✅ |
| Ultrasound AI value reevaluation | E4-04 | ✅ |
| Admin releases stock to a chosen BHC | E8-02 | ✅ |
| Midwives notified of release | E8-03 | ✅ |
| Midwife "received" confirmation | E8-04 | ✅ |
| Who sent / who received / when | E8-06 | ✅ |
| **New:** gestational diabetes (adviser request) | E12 | ✅ pending migration |

---

## 6. Verification Status

### Confirmed on a device
- Recent Visits populates; Schedules tab lists checkups on their dates
- Mother profile loads; obstetric score shows the L; no QR anywhere
- Weight-gain chart reflects the latest checkup weight
- Blood pressure trend renders with thresholds and detects the two-occasion pattern
- Blood type extracted from a lab report, with the strict parser correctly
  *refusing* an ABO group printed without its Rh factor
- OGTT extraction and classification — 92 fasting alone triggers referral, and
  96/185 names both samples
- Vaccination drive schedules and the SMS arrives from `AGAPAY`

### Confirmed on a device — revision 3
- Blood pressure guidance card at every threshold: 118/76 within range, 140/90
  and 145/95 at threshold with "repeat at next visit", 165/115 severe with
  "refer today", 85/55 below range, and 80/120 refused as unreadable rather
  than reported as low
- The before-week-20 note appears for a mother at 10 weeks; the mid-pregnancy
  fall note correctly does *not* appear on a low reading outside weeks 16–28
- Two consecutive raised readings produce "2 consecutive readings at or above
  140/90 (week 10 and week 10) — refer for assessment", and a subsequent
  normal reading reports the episode rather than erasing it
- Summary step shows `AT THRESHOLD` beside `ABOVE EXPECTED`, same voice
- Fetal heart rate: 115 bpm within range, 104 bpm outside with the maternal
  pulse note
- The prenatal chain end to end: a checkup proposing 19 Aug wrote its
  `checkup_schedule` row automatically
- `send-reminders` returning `manila_today: 2026-08-17`,
  `reminding_for: 2026-08-19`, `checkups.due: 1` against live data

### Not yet seen running
- The 6 AM cron firing for real. Armed, dry-run verified, and due to send its
  first live SMS on 18 Aug 2026
- Drive invitations recorded against a drive scheduled through the app — the
  table exists and the write path is tested, but no drive has been scheduled
  since it was added
- The Edge Function has never been type-checked locally; Deno is not installed
  on the development machine. It deploys and runs clean, which is weaker
  evidence than a type-check but not nothing

---

## 7. Defects Found and Fixed

Worth keeping: most were silent, and several are good defense material about
validating displayed data against its source. Twenty-one across two revisions,
none of which announced itself — every one was found by comparing what the
screen said against what the data actually held.

### Revision 3

| Defect | What was happening |
|---|---|
| BP staging contradiction | `145/95` rendered "HTN Stage 2" from the non-pregnancy AHA scale eight lines above a card reading "Hypertension in Pregnancy". Ten independent rule blocks, three different scales, no citation |
| `>` versus `>=` | Exactly 140/90 — the textbook cut-point — classified a stage lower in the pill than in every risk engine |
| Severe BP shown as mild | The summary pill collapsed raised and severe into one amber "ELEVATED", so 170/115 and 142/91 looked identical |
| 120/80 called pre-hypertension | The prompt handed the AI the non-pregnancy scale, so a textbook-normal pregnancy reading was written up as a flagged finding — in text the mother reads |
| Fetal heart rate over-flagged | Six of seven sites used 120–160 against a 110–160 baseline, reporting normal babies as findings |
| Severity by substring | Risk chips picked their colour by searching their own label for "hypertension". Rewording a label silently recoloured it |
| Gestational week off by one | Stored visits were rounded, live ones floored, so one afternoon read as "week 11 and week 10" |
| Same-week visits collapsed | Two checkups on one day plotted at the same x; the second hid behind the first, on the card meant to show repeats |
| Child drive intervals | The dose date was fetched and discarded, so a Pentavalent drive could invite a child who had dose 1 last week |
| Reminder job would have run a day early | Scheduled at 22:00 UTC for 6 AM Manila, where `CURRENT_DATE + 1` in UTC is *today* in Manila. Every reminder, every day, with nothing in the output to show it |
| One missing table would silence both reminders | Checkups and drives shared a `try`; the absent `checkup_schedule` would have taken drive reminders down with it |

### Revision 2

| Defect | What was happening |
|---|---|
| Schedules tab & Recent Visits | Selected `prenatal_checkup_id`, a column that does not exist. PostgREST rejected it, `catchError` swallowed it, the lists rendered empty |
| Mother vitals page | Requested four columns that live on the parent encounter. No blood pressure, and weight-gain analysis built only from self-reported weights |
| Mother profile timeout | Eight unguarded queries under one `Future.wait`; any slow table took the whole profile down. Six of the tables it reads have no index on `pregnancy_id` |
| Weight-gain chart | De-duplication dropped the newer of two checkups taken within ~1.4 days, so a new weight never reached the chart |
| GPAL formatter | `formattedGpal` returned `formattedGpa` — the L was computed, stored, and then discarded by two stub getters |
| Blood pressure history | A single normal reading erased an earlier hypertensive episode; the card returned to "no action" |
| TD eligibility | Stopped at TD2 and counted doses per pregnancy rather than per lifetime, so mothers needing TD3–TD5 were never invited and prior doses were invisible |
| Vaccine dropdown | Listed catalogue rows, so one vaccine appeared five times — once per dose |
| Drives on one date | Folded into a single card, making a second drive look like it had deleted the first |
| OCR extraction | The vision model exhausted its token budget narrating before answering, and a later increase breached the tier's rate limit |

---

## 8. Silently Degraded Features Found in Revision 3

Four features were running in a degraded state that looked, from the outside,
exactly like normal operation. None produced an error message, a red screen, or
an empty state that read as broken. This is the same failure mode as the
revision 2 defect list — *a failing call caught into a fallback is
indistinguishable from a legitimate empty result* — and finding it four more
times says something about the system that no individual feature does.

| Feature | What was actually happening | How it looked |
|---|---|---|
| **AI text** — care insights, remarks, chatbot | Groq retired the entire Llama 3.x line. All three models in the fallback chain were gone | Rule-based fallback text appeared, which is correct text. OCR kept working because the vision path had already moved to Qwen, so nothing looked wrong |
| **Email** | `email_service.dart` writes to `email_queue`; nothing in `database/`, `supabase/functions/` or `admin-web/` ever reads that table | Every send reported success. No email has ever been delivered |
| **Push notifications** | The trigger is absent from this database. The `send-push` Edge Function does not exist. The version defined in `supabase_setup.sql` posts to a *different Supabase project* than the app uses, and swallows the failure by design | In-app notifications and realtime worked, so notifications appeared — just never on the lock screen |
| **Checkup reminders had no path at all** | The manual "SMS Reminders" action was removed from the schedules screen in favour of reminders going out on a schedule — and the pg_cron jobs that were meant to replace it were never enabled. `checkup_schedule` and its trigger did not exist in this database either, so `MidwifeSmsRemindersScreen` would have shown nothing had it still been reachable | Nothing visibly failed. The button was gone on purpose and the automatic replacement was assumed to be running |

**Fixed in revision 3:** the model chain (now `openai/gpt-oss-120b` →
`gpt-oss-20b` → `qwen/qwen3.6-27b`, deliberately spanning two model families)
and `checkup_schedule` (`20260817_checkup_schedule.sql`). Email delivery and
push remain open and are recorded in the limitations list.

**What this argues at defense.** The architecture degrades rather than breaks —
every AI surface has a deterministic fallback, and a midwife using the app
during any of these windows still got correct, rule-derived output. That is the
design working. But it degrades *invisibly*, and the honest conclusion is that
graceful degradation without alerting is only half a safety property. The
system needs to say when it is running on its fallback.
