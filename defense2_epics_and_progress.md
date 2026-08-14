# InaAgapay — Product Definition, Epics, User Stories & Progress

> **Status:** Post–Capstone Defense 1 revision map. Supersedes `epics_and_user_stories.md`.
> **Last updated:** 2026-08-15
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
| E1 | Identity, Access & Account Lifecycle | 8 | **80%** | Complete for defense; QR removed, `password_history` unused |
| E2 | Mother & Pregnancy Registry | 12 | **100%** | Done — blood type now transcribed from lab documents |
| E3 | Prenatal Encounter & Clinical Decision Support | 15 | **88%** | Cited BP module + trend card built; nine legacy rule blocks remain |
| E4 | Diagnostic Document Intelligence | 12 | **92%** | "Explain My Report" reframing done |
| E5 | Automated Prenatal Scheduling & Reminders | 8 | **85%** | Engine extracted and tested; SMS live; pg_cron outstanding |
| E6 | Child Health — Immunization & Growth | 15 | **92%** | Growth verified against WHO; immunization complete |
| E7 | Mother Experience, Self-Care & Baby Book | 12 | **88%** | Baby Book shipped; vitals page repaired; jargon audit open |
| E8 | Inventory Distribution (RHU → BHC) | 8 | **90%** | Release-edit path left to verify |
| E9 | Admin Web — Monitoring, Reporting & Governance | 7 | **80%** | **Largest remaining gap by weight** |
| E10 | Research & Documentation Artifacts | 3 | **100%** | ERD, sampling and limitations complete |
| **E11** | **Midwife Analytics & Decision Support** *(new)* | 6 | **80%** | Dashboard analytics, priority band, GDM surfacing |
| **E12** | **Gestational Diabetes Screening** *(new)* | 5 | **85%** | Pending migration run + protocol confirmation |
| | **Weighted overall** | 111 | **~89%** | ~90% against the original 100-point scope |

Legend: ✅ done · 🟡 partial · 🔴 partial with a known defect · ❌ not started · ⛔ removed

**Test suite: 224 passing, 0 failing.**

> **Health warning on these figures.** E5, E7 and E11 partly rest on four query
> fixes that have not been confirmed on a device. If the Schedules tab is still
> empty when opened, E5 is not 85%. See §6.

---

## 3. Epics & User Stories

### E1 — Identity, Access & Account Lifecycle — 80%

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

### E3 — Prenatal Encounter & Clinical Decision Support — 88%

#### E3-01 Prenatal checkup capture — ✅
#### E3-02 Gestational weight gain vs IOM 2009 — ✅
Includes twin ranges, rate-of-gain by week, and a documented fallback for
underweight-twin where no official IOM data exists.

#### E3-03 Risk flagging — 🟡
- [x] **`lib/services/blood_pressure_reference.dart`** — one cited,
      configurable rule set. 21 tests
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
- [ ] ⚠️ **Confirm the thresholds** with the clinical adviser and record the
      guideline edition in `kBloodPressureSourceNote`
- [ ] 🔴 **Nine legacy BP rule blocks remain**, five inside
      `add_prenatal_checkup_screen.dart`. One uses the non-pregnancy AHA
      staging (130/80 = Stage 1) while the card directly beneath it uses the
      pregnancy thresholds, so **145/95 currently displays "HTN Stage 2" and
      "Hypertension in Pregnancy" side by side**. One compares with `>`, so
      exactly 140/90 classifies differently there than in every risk engine.
      This is what keeps E3 below 100%
- [ ] Fetal heart rate: engines use 120–160; the reference to encode is
      110–160. One of them is wrong and neither is cited

#### E3-04 Care insights show who approved — ✅
#### E3-05 Simplified checkup form — ✅

---

### E4 — Diagnostic Document Intelligence — 92%

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

### E5 — Automated Prenatal Scheduling & Reminders — 85%

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

#### E5-03 Reminders — ✅
- [x] **SMS live** — sender `AGAPAY`, same path as temporary passwords
- [x] Push infra, in-app notifications, realtime
- [ ] pg_cron jobs not yet enabled in Supabase

#### E5-04 Vaccination drives — ✅ NEW
A midwife schedules a drive (vaccine + date) which appears on the Schedules
calendar and invites eligible mothers by SMS, email and in-app notice.
- [x] No schema change — `immunization_schedule` was already facility + vaccine + date
- [x] Eligibility: pregnant mothers below **TD2**, the dose that protects the
      newborn against neonatal tetanus
- [x] **Saving and sending are separate acts.** Creating a drive messages
      nobody; the recipient list is shown with names and dose status, and
      sending sits behind a confirmation stating the count
- [x] An unreadable dose counts as zero — an unreadable record is not evidence
      of protection
- [x] Unreachable mothers surfaced, not silently dropped
- [x] SMS kept under one 160-character billing segment
- [ ] Children's drives — next iteration

#### E5-05 Scheduling limitations statement — ✅
Documented: proposed dates ignore holidays, closures, non-working days and
clinic capacity; the midwife resolves those.

---

### E6 — Child Health: Immunization & Growth — 92%

#### E6-01 Full 0–12 month immunization schedule — ✅
#### E6-02 Growth monitoring with WHO Z-scores — ✅
#### E6-03 Child registration & birth details — ✅
- [ ] Verify the growth axis scales to 60 months with SD bands across the range

---

### E7 — Mother Experience, Self-Care & Baby Book — 88%

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

### E8 — Inventory Distribution (RHU → BHC) — 90%

E8-01 through E8-06 ✅ — catalog, batches, expiry, issue-to-BHC, notification,
midwife receipt confirmation, stock requests, and a who/when audit trail.

- [ ] Editing a release after issue — verify an edit path exists and re-notifies
- [ ] Auth hardening: the migration documents that account IDs are not
      production-grade credentials and RLS is off. Belongs in limitations
- [ ] `inventory_repository.dart` points at a different Supabase project than
      the app and hardcodes its URL and anon key

---

### E9 — Admin Web: Monitoring, Reporting & Governance — 80%

E9-01 through E9-05 ✅ — executive dashboard, reports and export, account and
assignment management (including activate/deactivate/suspend), audit trail and
backup, patient records browser.

**This is now the largest remaining gap by weight.**
- [ ] Surface patient number in `patient-records.html`
- [ ] Role-based access hardening

---

### E10 — Research & Documentation Artifacts — 100%

ERD redesign, population sampling revision and the consolidated limitations
section are complete.

**Add to limitations:** QR linking removed; PhilHealth/4Ps/civil status
descoped; `password_history` retained but not enforced; mothers cannot
self-log BP.

---

### E11 — Midwife Analytics & Decision Support — 80% *(new scope)*

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

### E12 — Gestational Diabetes Screening — 85% *(new scope)*

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
1. **Run the GDM migration** in Supabase
2. **Confirm three sets of clinical thresholds** with the adviser (GDM
   protocol, BP cut-points, visit intervals) and record each citation

### Tier 1 — verify on a device (§6)
3. The four query fixes

### Tier 2 — real build work
4. **E9 admin web polish + role hardening** — largest gap by weight
5. **Consolidate the nine BP rule blocks** onto `BloodPressureReference` —
   removes a visible contradiction; a refactor in a 5,000-line file
6. Mother-facing jargon audit (E7-02)

### Tier 3 — polish
7. Enable pg_cron
8. Children's vaccination drives
9. GDM postpartum follow-up

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
| BP conditions / genetics / medications | E3-03 | 🟡 module built, legacy blocks remain |
| Fetal heart rate & tones | E3-03 | 🟡 uncited, 120–160 vs 110–160 |
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

## 6. Unverified on Device

Four query bugs were found by reading the schema and fixed. None has been
confirmed running, and three epic percentages depend on them.

| Check | Expect | Was |
|---|---|---|
| Schedules tab | Checkups appear on their scheduled dates | Selected `prenatal_checkup_id`, which does not exist |
| Dashboard → Recent Visits | Populated | Same bad column |
| Mother vitals page | BP shows; weight chart includes midwife measurements | Four non-existent columns |
| Vaccination drive | Drive saves and appears on the calendar | Insert tries `bhc_id`, falls back to `facility_id` — the schema file and the live queries disagree |

Fifteen minutes of device testing converts these from *believed fixed* to
*fixed*, and it is the highest-value item on this document.
