# InaAgapay — Product Definition, Epics, User Stories & Progress

> **Status:** Post–Capstone Defense 1 revision map. Supersedes `epics_and_user_stories.md`.
> **Last updated:** 2026-08-04
> **Scope decision:** QR-based account linking is **descoped for now** (see E1-05).

---

## 1. What InaAgapay Is

**Purpose:**

> InaAgapay is a maternal and child health record system for Philippine barangay health centers that replaces paper prenatal and immunization records with a shared digital record, adds rule-based risk flagging and plain-language AI explanations so mothers understand their own health data, and gives the RHU/admin visibility and supply control over the health centers under it.

### The problem it solves

| Failure of the paper system | Consequence today | InaAgapay's answer |
|---|---|---|
| Records live on paper in one BHC | Lost, unreadable, not portable, no aggregate view | One record per mother, readable by her assigned midwife and the RHU |
| Clinical data is captured but never interpreted | BP 150/95 is recorded; risk is not escalated | `smart_risk_engine.dart` + `weight_gain_engine.dart` flag risk at point of entry |
| Mothers never see or understand their own data | Low adherence, missed visits, low health literacy | Mother app with her own records in mother-friendly language, plus reminders |

### Three actors, three surfaces

- **Admin / RHU staff — web** (`admin-web/`) — oversees all BHCs, accounts, reports, audit trail, and owns the vaccine/supplement stockroom.
- **Midwife — mobile** (`lib/screens/midwife/`) — the primary data creator. Registers mothers, performs prenatal checkups, uploads ultrasound/lab results, records immunizations and growth, receives supplies.
- **Mother — mobile** (`lib/screens/mother/`) — consumes her own record, self-logs vitals, journals, asks the chatbot, receives reminders.

### Positioning guardrail

The AI is **interpretative, not diagnostic**. It explains an existing radiologist/lab report and existing measurements in simpler language. It does not produce a diagnosis and does not replace the midwife's judgment. Every AI output is attributable to a human approver (`clinical_encounters.is_midwife_approved`, `ai_responses.approved_by`).

---

## 2. Epic Map & Progress Summary

| # | Epic | Progress | Status |
|---|---|---|---|
| E1 | Identity, Access & Account Lifecycle | **80%** | Revisions largely applied; QR linking descoped |
| E2 | Mother & Pregnancy Registry | **90%** | Patient number done; blood type research outstanding |
| E3 | Prenatal Encounter & Clinical Decision Support | **80%** | Attribution done; BP/FHR clinical research outstanding |
| E4 | Diagnostic Document Intelligence (Ultrasound / Lab / OCR) | **80%** | AI-purpose reframing outstanding |
| E5 | Automated Prenatal Scheduling & Reminders | **45%** | Auto-schedule algorithm not built |
| E6 | Child Health — Immunization & Growth | **80%** | Data + UI complete, 0–5y chart polish left |
| E7 | Mother Experience, Self-Care & Baby Book | **55%** | Baby Book module not started |
| E8 | Inventory Distribution (RHU → BHC) | **90%** | De-mocked; release-edit path left to verify |
| E9 | Admin Web — Monitoring, Reporting & Governance | **80%** | Working; polish + role hardening left |
| E10 | Research & Documentation Artifacts | **25%** | ERD redo + sampling revision not done |
| | **Weighted overall** | **~73%** | |

Legend: ✅ done · 🟡 partial · 🔴 partial with a known defect · ❌ not started · ⏸️ parked

---

## 3. Epics & User Stories

### E1 — Identity, Access & Account Lifecycle — 80%

*Goal:* Let a mother with only a cellphone number get an account and keep it, without forcing an email she may not have.

#### E1-01 Log in with contact number or email — ✅
> **As a** mother with no email, **I want** to log in with my cellphone number **so that** I can access my record.

- [x] Login detects identifier type (email vs PH mobile) — `lib/screens/auth/login.dart:33-48`
- [x] Invalid identifier produces a clear message — `login.dart:82`

#### E1-02 Auto-generated temporary password — ✅
> **As a** midwife registering a mother on her behalf, **I want** the system to generate a temporary password **so that** she can log in without me inventing one.

- [x] `is_temporary_password` column — `database/migrations/add_temporary_password_columns.sql`
- [x] Forced change screen on first login — `lib/screens/mother/change_temporary_password.dart`, gated at `lib/main.dart:145-151`
- [x] `created_by` distinguishes self-registered from midwife-created accounts

#### E1-03 Add an email later — ✅
> **As a** mother who registered with only a number, **I want** to add my email later **so that** I can use email recovery.

- [x] Editable email with live uniqueness check — `lib/screens/mother/complete_profile.dart:137-150`

#### E1-04 Password recovery & OTP — ✅
- [x] `forgot_password.dart`, `forgot_password_verification.dart`, `reset_password_screen.dart`, `verify_otp_screen.dart`

#### E1-05 QR account linking — ⏸️ PARKED (descoped)
> **As a** mother who registered online first, **I want** the midwife to scan my QR **so that** my records link instead of duplicating.

- [x] QR generation widget exists — `lib/widgets/mother_qr_code.dart`, shown from `mother_profile_page.dart:6629`
- [ ] Midwife-side scanner + link/merge transaction — **not built, intentionally deferred**

**Panel answer:** duplicate prevention is handled by phone/email uniqueness checks at registration. QR linking is documented as future work.

**Remaining:** decide whether to keep or hide the QR widget in the demo build; document the duplicate-prevention strategy for the defense.

---

### E2 — Mother & Pregnancy Registry — 85%

*Goal:* One complete, uniquely identifiable maternal record created at BHC intake.

#### E2-01 Multi-step Add Mother — ✅
- [x] Full wizard — `lib/screens/midwife/midwife_add_mother_screen.dart` (6,291 lines)
- [x] PH address cascade — `lib/services/ph_address_service.dart`
- [x] OCR pre-fill from prenatal card — `GroqService.extractMotherRegistrationData`

#### E2-02 Pre-pregnancy weight drives baseline BMI — ✅
> **As a** midwife, **I want** to record pre-pregnancy weight **so that** weight gain is measured from the correct baseline.

- [x] Captured at registration and used as the weight-gain baseline, not current weight
- [x] Baseline BMI category feeds `lib/services/weight_gain_engine.dart`

#### E2-03 Unique Patient Number — ✅
> **As a** midwife, **I want** each mother to have a patient number unique within my BHC **so that** I can match her to the physical chart.

- [x] `facility_assignments.patient_number` + partial unique index + auto-increment trigger `set_patient_number()` — `database/active-draftschema.sql:68-93`
- [x] Read from the database via `SupabaseService.getPatientNumbersByAccountId` (batched, one query per list) and `getPatientNumberForMother`
- [x] Displayed on the midwife mothers list and on the mother profile header badge (`profile_header_card.dart`)
- [x] Searchable by patient number in the mothers list
- [x] Missing numbers render as `—` rather than falling back to `mother_id`

**Defect found and fixed during this pass.** The `INA-001` IDs previously shown were generated from the *list loop index* (`midwife_mothers_screen.dart:275`/`:393`, `midwife_dashboard.dart:345`), not from the database. They were never persisted and changed whenever the list was re-sorted, filtered, or paginated — the same mother could show two different IDs on two screens. Worth mentioning at defense as an example of validating displayed data against its source of truth.

#### E2-04 Blood type — 🟡
- [x] Captured as a manual field across registration, profile, and checkup
- [ ] Blood Type API feasibility research (panel item) not done

**Recommendation:** no API can *determine* blood type — it requires a serologic test, and no such service exists. Reframe for the defense: blood type is sourced from the mother's lab result / prenatal card, optionally OCR-extracted from the lab report, and **requires midwife confirmation before storing**. Present "automatic blood type determination" as a rejected approach with the clinical reason. A rejected approach with a stated reason is a stronger defense answer than an inconclusive feasibility study.

---

### E3 — Prenatal Encounter & Clinical Decision Support — 75%

*Goal:* Turn a checkup into structured data plus an interpreted, attributable assessment.

#### E3-01 Prenatal checkup capture — ✅
- [x] `lib/screens/midwife/add_prenatal_checkup_screen.dart` (4,969 lines)
- [x] Schema covers BP, fetal heart beat, fetal heart tone, fundal height, edema, TD dose, next schedule — `prenatal_checkups`

#### E3-02 Gestational weight gain vs IOM 2009 — ✅
> **As a** midwife, **I want** weight gain evaluated against IOM guidelines for her BMI category **so that** I can advise her if she is gaining too little or too much.

- [x] `lib/services/weight_gain_engine.dart` — IOM 2009 ranges by BMI category, **including twin-pregnancy ranges**, rate-of-gain by gestational week, and a documented fallback for underweight-twin (no official IOM data exists)
- [x] Persisted to `weight_gain_evaluations`

#### E3-03 Risk flagging — 🟡
- [x] `smart_risk_engine.dart` + `risk_engine.dart` produce a risk status; `clinical_encounters.risk_status` is low/moderate/high/critical
- [ ] BP clinical depth from the panel — gestational hypertension vs pre-eclampsia thresholds, genetic/family-history factors, medication appropriateness by BP status — **research not yet embedded**
- [ ] Fetal heart rate / fetal heart tone rules are thin (`smart_risk_engine.dart` reads `fetal_heart_beat` but has minimal rule coverage)

**Remaining:** encode ACOG/DOH BP thresholds and the normal FHR range (110–160 bpm) with cited sources; add the Doppler non-integration statement to study limitations.

#### E3-04 Care insights show who approved — ✅
> **As a** mother, **I want** to see which midwife approved this assessment **so that** I know a real person stands behind it.

- [x] Schema — `clinical_encounters.is_midwife_approved`, `clinical_encounters.recorded_by`, `ai_responses.approved_by`
- [x] `is_midwife_approved` now selected in every encounter query (`records_screen.dart`, `mother_profile_service.dart`, `midwife_dashboard.dart`)
- [x] Attribution banner rendered inside the AI insight card, directly above the disclaimer — `record_detail_screen.dart:_buildApprovalAttribution`
- [x] Approved → green "Assessed and approved by [Midwife name]"; unapproved → amber "Pending midwife review"; bilingual via the existing `_t()` pattern
- [x] Wired on the mother's records screen, the mother profile record views, and the midwife dashboard

Self-logged vitals intentionally show no attribution — nothing there was midwife-reviewed, and claiming otherwise would be worse than showing nothing.

#### E3-05 Simplified checkup form — ✅
- [x] Medication plan / prescription sections removed; AI summary emits bulleted findings

---

### E4 — Diagnostic Document Intelligence — 80%

*Goal:* Take a photo of an ultrasound or lab report and turn it into structured, explainable data.

#### E4-01 Ultrasound capture & OCR extraction — ✅
- [x] `ultrasound_analyzer_screen.dart` (5,728 lines) + `add_ultrasound_page.dart`
- [x] `GroqService.analyzeUltrasoundImages`, `extractUltrasoundSummaryOCR`, `generateUltrasoundGrowthInsight`
- [x] Extracts patient name, location, attending professional → `ultrasounds.health_worker_name / _institution / _profession`
- [x] Fetal count extraction (commit `e7623c1`), validations (`8d20b4f`)

#### E4-02 Lab test capture & interpretation — ✅
- [x] `add_lab_test_page.dart`, `lab_test_analyzer_screen.dart`, `lab_cbc_interpretation_engine.dart`

#### E4-03 File management — ✅
- [x] `files` table stores `file_size`, `mime_type`, `bucket_name`, `uploaded_by` — `active-draftschema.sql:663-678`
- [x] File size written on upload — `supabase_service.dart:2061`, `ultrasound_analyzer_screen.dart:2034`
- [ ] Confirm PDF is accepted alongside JPG/PNG in the client-side picker filter (the `mime_type` column already supports it)

#### E4-04 Reframe AI ultrasound interpretation — ❌ (research item)
> Panel question: if the radiologist already interpreted it, what does the AI add?

**Recommended direction:** stop calling it "interpretation." Reposition the module as **"Explain My Report"** — a mother-facing translation layer that:
1. restates the radiologist's existing findings in Filipino / simple English,
2. maps numeric values (EFW, AFI, BPD) onto gestational-age norms so the mother can see whether her baby is on track,
3. never contradicts or re-derives the radiologist's impression.

`UltrasoundInterpretationEngine` already produces a `monitoring_classification` — restrict the AI to *explaining* that, not generating it.

**Remaining:** rename module labels in the UI, add a persistent disclaimer, adjust the Groq prompt to forbid new findings.

---

### E5 — Automated Prenatal Scheduling & Reminders — 45%

*Goal:* The system proposes the next visit date instead of the midwife computing it.

#### E5-01 Manual scheduling & calendar — ✅
- [x] `midwife_schedules_screen.dart`, `midwife_calendar.dart`, `schedules` + `checkup_schedule` tables
- [x] `prenatal_checkups.next_schedule` is captured

#### E5-02 Automated visit interval computation — ❌ Not started
> **As a** midwife, **I want** the next visit date auto-proposed from gestational age **so that** intervals follow clinical guidelines.

- [ ] No interval logic exists anywhere in `supabase_service.dart` or `midwife_schedules_screen.dart`

**Clinical note — correct this before building.** The schedule in the defense notes ("1st–3rd month monthly, 6th–8th every two weeks, 9th month weekly, final weeks every two days") does not match standard guidance. WHO 2016 recommends 8 antenatal contacts; the DOH/ACOG-conventional schedule is:

| Gestational age | Interval |
|---|---|
| Up to 28 weeks | every 4 weeks |
| 28–36 weeks | every 2 weeks |
| 36 weeks to delivery | every week |

"Every two days" is post-term or high-risk surveillance, **not** routine care — do not encode it as a default.

**Remaining:** a `PrenatalScheduleEngine` taking AOG + risk status and returning a proposed date the midwife can override.

#### E5-03 Reminders — 🟡
- [x] Push infra — `push_notification_service.dart`, `device_tokens`, FCM, `send-push` edge function
- [x] In-app notifications — `notifications` table, `notifications_screen.dart`, realtime enabled (`20260803_inventory_notifications_realtime.sql`)
- [x] SMS service + `midwife_sms_reminders_screen.dart`
- [ ] pg_cron jobs not yet enabled in Supabase (see `TODO.md`)
- [ ] SMS blocked on provider sender-name approval (see `TODO.md`)

#### E5-04 Scheduling limitations statement — ❌
- [ ] Document that auto-schedules ignore local holidays, health-center closures, non-working days, and other conflicts

---

### E6 — Child Health: Immunization & Growth — 80%

#### E6-01 Full 0–12 month immunization schedule — ✅
- [x] BCG, OPV 0–3, Penta 1–3, PCV 1–3, Rota 1–2, IPV, Vitamin A (6 & 12 mo), MCV 1–2, MMR — `lib/models/vaccine_schedule.dart`
- [x] `add_immunization_page.dart`, `child_immunization_list_page.dart`, `mother_child_vaccine.dart`
- [x] Immunization card OCR — `GroqService.extractImmunizationCardData` + `immunization_ocr_review_page.dart`
- [x] Poster view — `immunization_poster_screen.dart` (2,821 lines) + `poster_columns` table

#### E6-02 Growth monitoring with WHO Z-scores — 🟡 mostly done
- [x] WHO LMS reference data for weight and height, boys and girls — `growth_reference_data.dart`
- [x] Box-Cox LMS Z-score computation — `growth_calculator.dart`
- [x] Charts — `growth_line_chart.dart`, `child_growth_list_page.dart`, `mother_child_growth.dart`
- [x] Source data in `child growth standards/` (BMI / Height / Weight for Age)
- [ ] Verify the axis genuinely scales to 60 months and SD bands render across the full range

#### E6-03 Child registration & birth details — ✅
- [x] `add_child_choice.dart` → `add_child_select_mother.dart` → `add_child_step3_child.dart` → `add_child_step4_birth.dart`

---

### E7 — Mother Experience, Self-Care & Baby Book — 55%

#### E7-01 Self-logged vitals — ✅
> **As a** mother, **I want** to log my own BP and weight between visits **so that** my midwife sees trends, not just visit-day snapshots.

- [x] `lib/screens/mother/mother_vitals_page.dart` (1,382 lines) → `maternal_vitals` with `source: 'mother_self'`
- [x] Deduplicates against official checkups, **preferring the midwife's record** — `mother_vitals_page.dart:183`. Worth calling out at defense: self-reported data never overwrites clinical data.

#### E7-02 Mother-friendly language & illustrations — 🟡
- [x] 59 image assets; bilingual `_t('English','Filipino')` helper pattern; `language_service.dart`
- [ ] No systematic jargon audit — "fundal height", "AOG", "edema", "Z-score" still appear on mother-facing screens

**Remaining:** a glossary pass giving every mother-facing clinical term a plain-language label plus an optional "what does this mean?" tap.

#### E7-03 Journal — ✅
- [x] `mother_journal_screen.dart`, `add_journal_page.dart`, `journal_details_page.dart`, `journal_entries`

#### E7-04 Chatbot — ✅
- [x] `mother_chatbot_page.dart` (3,043 lines), `chatbot_service.dart`, `chatbot_sessions` / `chatbot_messages`
- [x] Groq TTS + audio transcription available — `speakWithGroqTts`, `transcribeAudio`

#### E7-05 Baby Book module — ❌ Not started
> **As a** mother, after childbirth **I want** a keepsake record of my baby's firsts, milestones, and photos **so that** the app stays useful past delivery.

- [x] Adjacent pieces already exist — `child_milestones` + `milestone_templates` tables, `baby_growth_model.dart`, journal infrastructure
- [ ] No Baby Book screen, no post-birth transition flow

**Remaining (smallest viable version):** once `deliveries` / `birth_details` is recorded, unlock a Baby Book tab reusing the journal + milestone tables — photo, date, milestone, note. Medium priority, and largely assembly of existing parts.

#### E7-06 Mother dashboard & records — ✅
- [x] `mother_dashboard.dart` (3,291 lines), `records_screen.dart`, `mother_pregnancy_detail_page.dart`, countdown / baby-size / tips widgets

---

### E8 — Inventory Distribution (RHU → BHC) — 85%

*Goal:* The admin holds the stock; BHCs request or receive it; nothing is credited until a midwife confirms receipt.

#### E8-01 Admin stock catalog, batches & expiry — ✅
- [x] `admin-web/pages/inventory.html` — catalog, batches, transactions, low-stock/expiry KPIs, CSV export, analytics charts
- [x] `inventory_items`, `inventory_batches`, `inventory_transactions`

#### E8-02 Admin issues supplies to a chosen BHC — ✅
> **As an** admin, **I want** to pick a BHC, pick vaccines/supplements with quantities, and send them **so that** health centers are stocked according to need.

- [x] `issue_inventory_transfer` RPC — called from `inventory.html:2555`
- [x] `inventory_transfers` table; `transfer` added to the transaction-type check constraint
- [x] Stock deducted from RHU at issue, **not** credited to the BHC until receipt — `20260803_inventory_distribution_workflow.sql`

#### E8-03 Midwives are notified of a release — ✅
- [x] RPCs write to `notifications`; realtime publication enabled
- [x] Flutter subscribes live — `inventory_repository.dart:subscribeToInventoryNotifications`

#### E8-04 Midwife confirms receipt — ✅
> **As a** midwife, **I want** to mark supplies as received **so that** our BHC stock reflects what actually arrived.

- [x] `receive_inventory_transfer()` RPC — `inventory_repository.dart:342`, wired at `midwife_inventory_mock_page.dart:2523`

#### E8-05 BHC requests stock — ✅
- [x] `inventory_stock_requests` with pending / approved / rejected / issued / received / completed / cancelled
- [x] Midwife submits via `submitStockRequest`; admin approves or rejects via `approve_inventory_stock_request` / `reject_inventory_stock_request`

#### E8-06 Who/when audit trail on every movement — ✅
- [x] `requested_by`, `reviewed_by`, `reviewed_at`, `issued_at`, plus `audit_trail` inserts on the web side

**Remaining (the 15%):**
- [x] Renamed `MidwifeInventoryMockPage` → `MidwifeInventoryPage` (`midwife_inventory_page.dart`), route updated in `main.dart`, `_showMockMessage` stubs replaced with a real logout and a Settings link
- [ ] Editing a release after issue (the panel's "she can add or lessen, and midwives get informed on every update") — verify an edit path exists and re-notifies.
- [ ] Auth hardening: the migration itself documents that account IDs are not production-grade credentials and RLS is off (`20260803_inventory_distribution_workflow.sql:7-12`). Move this into the study's limitations section proactively.

---

### E9 — Admin Web: Monitoring, Reporting & Governance — 80%

#### E9-01 Executive dashboard — ✅
- [x] Mothers / midwives / children / pregnancies / BHC KPIs, risk chart, per-BHC chart, monthly trends, inventory chart, recent audit feed — `dashboard.html`

#### E9-02 Reports & export — ✅
- [x] `reports.html` — BHC and date-range filters, immunization rate, high-risk badge, stock alerts, PDF export; CSV exports on inventory tabs

#### E9-03 Account & assignment management — ✅
- [x] `accounts.html`, `account-create.html`, `midwife-assignment.html`, `change-password.html`, `common-security.js`

#### E9-04 Audit trail & backup — ✅
- [x] `audit-trail.html`, `backup.html`, `audit_trail` / `audit_logs` tables

#### E9-05 Patient records browser — ✅
- [x] `patient-records.html`

**Remaining:** surface patient number in `patient-records.html`; role-based access hardening.

---

### E10 — Research & Documentation Artifacts — 25%

Not code, but High Priority on the panel's list — and currently the weakest area.

#### E10-01 Redesign the ERD — ❌
The live schema has roughly 60 tables (`active-draftschema.sql`). A single flat ERD will be unreadable at defense.

**Recommended approach:** one conceptual ERD (10–12 core entities) plus four subject-area ERDs:
1. Identity & Facility
2. Maternal & Pregnancy
3. Child Health
4. Inventory & Notifications

Generate from the actual schema so the diagram cannot drift from the code.

#### E10-02 Revise population sampling — ❌
- [ ] State target population, sampling frame, and sampling technique
- [ ] Show the **computed sample size with its formula** (Slovin / Cochran, with confidence level and margin of error visible)
- [ ] Clearly separate *target respondents* from *computed sample size* — this was the panel's specific complaint

#### E10-03 Study limitations section — ❌
Consolidate every "we do not do X" statement the panel asked for:

- [ ] No Doppler device integration — fetal heart rate is manually entered from the midwife's own Doppler reading
- [ ] Automated schedules ignore holidays, closures, non-working days, and conflicts
- [ ] AI is interpretative, never diagnostic; all outputs require midwife approval
- [ ] Blood type is transcribed from a lab result, never inferred
- [ ] Custom account auth without RLS is a capstone-scope decision, not production-ready
- [ ] QR account linking deferred

---

## 4. Priority Ordering Before Defense 2

### Tier 1 — ✅ DONE (2026-08-04)
1. ~~**Real patient number in the app UI** (E2-03)~~ — done; fabricated index-derived IDs replaced with the persisted database value
2. ~~**"Approved by [midwife]" on insights and records** (E3-04)~~ — done; attribution banner on the AI insight card
3. ~~**De-mock the inventory page** (E8)~~ — done; renamed, rerouted, stubs removed

Two out-of-scope defects were found during this pass and are tracked separately: the `/profile` and `/help` routes are navigated to but never registered (they throw), and six top-level screen files under `lib/screens/` are unreferenced duplicates — one of which still contains hardcoded `INA-001` IDs.

### Tier 2 — real build work
4. `PrenatalScheduleEngine` with corrected clinical intervals (E5-02)
5. Baby Book MVP on top of existing milestone + journal tables (E7-05)
6. BP / FHR clinical rules with citations in the risk engine (E3-03)

### Tier 3 — documentation, but panel-critical
7. ERD redesign (E10-01)
8. Population sampling revision (E10-02)
9. Consolidated limitations section (E10-03)
10. Reframe ultrasound AI as "Explain My Report" (E4-04) — mostly wording + prompt change

### Tier 4 — polish
11. Mother-facing jargon audit (E7-02)
12. Enable pg_cron; resolve SMS sender name (E5-03)

---

## 5. Mapping: Defense 1 Revisions → Epics

| Panel revision | Epic / Story | Status |
|---|---|---|
| Revise population sampling | E10-02 | ❌ |
| Redesign ERD | E10-01 | ❌ |
| Temp password on contact-only registration | E1-02 | ✅ |
| Log in with contact number | E1-01 | ✅ |
| Editable email added later | E1-03 | ✅ |
| QR account linking | E1-05 | ⏸️ descoped |
| Store uploaded file size | E4-03 | ✅ |
| Accept JPG / PNG / PDF | E4-03 | 🟡 verify picker |
| Unique Patient Number | E2-03 | ✅ |
| Midwife attribution (facilitated / created / approved) | E3-04 | ✅ |
| More illustrations / simpler terms | E7-02 | 🟡 |
| Baby Book module | E7-05 | ❌ |
| Mother self-logs vitals | E7-01 | ✅ |
| Pre-pregnancy weight logic | E2-02 | ✅ |
| Weight gain from pre-preg + current + AOG | E3-02 | ✅ |
| Blood Type API research | E2-04 | 🟡 recommend rejecting |
| BP conditions / genetics / medications | E3-03 | ❌ research |
| Fetal heart rate & tones | E3-03 | 🟡 |
| Doppler limitation statement | E10-03 | ❌ |
| Inventory availability (available / low / out) | E8-01 | ✅ |
| Automated prenatal scheduling | E5-02 | ❌ |
| Scheduling limitations statement | E5-04 | ❌ |
| Care insights show approver | E3-04 | ✅ |
| Ultrasound AI value reevaluation | E4-04 | ❌ |
| **New:** admin releases stock to a chosen BHC | E8-02 | ✅ |
| **New:** midwives notified of release | E8-03 | ✅ |
| **New:** midwife "received" confirmation | E8-04 | ✅ |
| **New:** who sent / who received / when | E8-06 | ✅ |
