> **⚠️ SUPERSEDED — historical record only.**
> This document describes the pre–Capstone Defense 1 scope. Its six epics are now largely complete, and it does not cover the defense revisions (patient numbers, contact-number login, inventory distribution, Baby Book, self-logged vitals, automated scheduling).
> **Current product map: [defense2_epics_and_progress.md](defense2_epics_and_progress.md)**

---

# Epic: EPIC-01 Core Maternal Health & Prenatal Workflows
*Goal:* Refine the maternal registration and prenatal checkup workflows to enforce proper business processes and data constraints.
*Context:* The current flow allows exiting before completing a mandatory first checkup and lacks critical data constraints like pre-pregnancy weight and LMP validations. This epic ensures data integrity and workflow enforcement, foundational for accurate risk assessment and AI interpretation.

## Stories

### EPIC-01-001 Implement Pre-Pregnancy Weight and Address Customization
*As a* midwife
*I want* to input the mother's pre-pregnancy weight and fully customize her address if she doesn't live at the BHC
*So that* baseline BMI can be accurately calculated for weight gain tracking and her correct location is recorded.

*Acceptance Criteria:*
- [ ] Add Mother form includes a "Pre-Pregnancy Weight" field restricted to 30-200 kg.
- [ ] Baseline BMI is calculated using pre-pregnancy weight instead of current weight.
- [ ] Address customization is clearly toggleable and captures Barangay, City, and Province.

*Technical Notes:*
- Modify `lib/screens/midwife/midwife_add_mother_screen.dart` Step 3 and Step 1.
- Update `SupabaseService.addMotherFullByMidwifeWithAutoPassword` to accept the new weight field.
- Ensure the database `mothers` table schema supports or can store `pre_pregnancy_weight`.

*Dependencies:* None

### EPIC-01-002 Enforce LMP Constraints and Optional Email
*As a* midwife
*I want* the system to validate LMP dates strictly and allow registering mothers without an email address
*So that* I cannot enter impossible gestation dates and can still register mothers who lack digital literacy.

*Acceptance Criteria:*
- [ ] LMP cannot be in the future or > 43 weeks in the past.
- [ ] LMP < 4 weeks ago shows a warning to confirm via serum hCG.
- [ ] Email field is optional; system gracefully handles auth creation without it (e.g., auto-generated email for internal Supabase auth).

*Technical Notes:*
- Update `_validateStepInline` in `midwife_add_mother_screen.dart`.
- Requires coordination with the backend authentication strategy in `SupabaseService`.

*Dependencies:* None

### EPIC-01-003 Enforce Mandatory Prenatal Checkup Progression
*As a* midwife
*I want* to be forced to complete the initial prenatal checkup immediately after adding a mother
*So that* the business process is followed and no mother record is left incomplete.

*Acceptance Criteria:*
- [ ] After successful mother registration, the app navigates to `AddPrenatalCheckupScreen`.
- [ ] The device back button/swipe gesture is disabled on the initial `AddPrenatalCheckupScreen` unless explicitly cancelled via a warning dialog.

*Technical Notes:*
- Implement `PopScope` (or `WillPopScope`) in `add_prenatal_checkup_screen.dart` when a specific flag (e.g., `isInitialRegistration`) is passed.

*Dependencies:* EPIC-01-001, EPIC-01-002

### EPIC-01-004 Streamline Prenatal Checkup Data Entry
*As a* midwife
*I want* unnecessary fields (like fetal position and medications) removed from the routine checkup and a cleaner AI summary
*So that* my data entry is faster and the generated summary is easy to read.

*Acceptance Criteria:*
- [ ] Fetal Position dropdown is removed from the prenatal checkup form.
- [ ] Medication Plan and Prescription sections are removed.
- [ ] The AI summary generates a bulleted list of findings and symptoms instead of a dense paragraph.

*Technical Notes:*
- Remove `_MedicationPlanEntry` and related logic in `add_prenatal_checkup_screen.dart`.
- Update `_buildRuleBasedAssessmentText` and the Groq prompt to output bulleted lists.

*Dependencies:* None

### EPIC-01-005 Evaluate Gestational Weight Gain Against IOM Guidelines
*As a* midwife
*I want* the system to evaluate the mother's weight gain during prenatal checkups against the IOM (Institute of Medicine) 2009 guidelines
*So that* I can properly advise her if she is gaining too little or too much weight based on her pre-pregnancy BMI.

*Acceptance Criteria:*
- [ ] The system calculates the mother's baseline BMI from her pre-pregnancy weight.
- [ ] During prenatal checkups, the current weight is compared against the pre-pregnancy weight.
- [ ] The total weight gain is evaluated against the recommended IOM (2009) ranges for her baseline BMI category (e.g., 11.5-16 kg for normal weight).
- [ ] The AI interpretative summary or UI includes a clear note on whether the weight gain is on track, below, or above the recommended guidelines.

*Technical Notes:*
- Update `lib/services/smart_risk_engine.dart` or `GroqService` to include the IOM 2009 logic.
- Requires data from `EPIC-01-001`.

*Dependencies:* EPIC-01-001

---

# Epic: EPIC-02 Child Health Module: Extended Immunization (0-12 Months)
*Goal:* Extend the immunization tracking module to cover the full 0-12 months schedule as mandated by the DOH.
*Context:* The current system hardcodes vaccines up to 14 weeks. The thesis requires full coverage for the first year of life to support accurate local health tracking and reminders.

## Stories

### EPIC-02-001 Expand Vaccine Schedule Data Model
*As a* system
*I want* to define the complete set of vaccines for 0-12 months
*So that* the app can track all necessary immunizations (e.g., Measles at 9 mos, MMR at 12 mos).

*Acceptance Criteria:*
- [ ] Vaccine schedule data structure includes 6 months, 9 months, and 12 months milestones.
- [ ] Specific vaccines (Measles, MMR, Vitamin A, etc.) are accurately mapped to their target weeks/months.

*Technical Notes:*
- Update `lib/models/vaccine_schedule.dart` to include timelines up to 52 weeks (12 months).
- Ensure existing DB schema `child_vaccines` table can support these new entries.

*Dependencies:* None

### EPIC-02-002 Update Immunization UI
*As a* midwife and mother
*I want* the immunization screen to display the full 12-month schedule
*So that* I can view, update, and track long-term vaccine compliance.

*Acceptance Criteria:*
- [ ] The UI renders timeline sections up to 12 months.
- [ ] Midwives can mark 9-month and 12-month vaccines as complete.

*Technical Notes:*
- Update `child_immunization_screen.dart` (or equivalent) to scroll/display the extended schedule.

*Dependencies:* EPIC-02-001

---

# Epic: EPIC-03 Child Health Module: Extended Growth Monitoring (0-5 Years)
*Goal:* Expand child growth tracking to cover 0-5 years based on WHO standards.
*Context:* The thesis emphasizes early childhood development (under five). The current system stops at 13 weeks. Expanding this requires importing standard WHO LMS values for up to 60 months and updating the charting UI.

## Stories

### EPIC-03-001 Integrate WHO 0-5 Years LMS Data
*As a* system
*I want* to load WHO growth standards (L, M, S parameters) for children up to 60 months
*So that* I can calculate precise Z-scores for height-for-age and weight-for-age up to age 5.

*Acceptance Criteria:*
- [ ] LMS reference data structure is expanded to hold month-by-month values up to 60 months for both boys and girls.
- [ ] Z-score calculation logic correctly handles data points beyond 13 weeks (interpolating days/months appropriately).

*Technical Notes:*
- Update `lib/services/growth_reference_data.dart` using the WHO PDFs available in the repository.
- A script may be needed to extract/format the CSV/PDF data into Dart maps/lists.

*Dependencies:* None

### EPIC-03-002 Update Growth Monitoring Charts
*As a* midwife and mother
*I want* the growth charts to scale up to 5 years (60 months)
*So that* I can visually track the child's development trajectory over early childhood.

*Acceptance Criteria:*
- [ ] Growth chart X-axis scales to accommodate up to 60 months.
- [ ] Standard WHO curve lines (e.g., median, +/- 2SD, +/- 3SD) are rendered up to 60 months.
- [ ] Plotted points correctly map to the extended timeline.

*Technical Notes:*
- Modify the chart widget (likely using `fl_chart`) in the child dashboard or growth details screen.

*Dependencies:* EPIC-03-001

---

# Epic: EPIC-04 AI-Assisted Interpretative Functionalities
*Goal:* Implement non-diagnostic, AI-generated explanations for maternal and child health records.
*Context:* The thesis strictly positions the AI as an interpretative assistant (not a diagnostic tool) to improve maternal health literacy. This involves natural language summaries of checkups, growth metrics, and OCR extraction from external documents.

## Stories

### EPIC-04-001 OCR Extraction for Diagnostic Records
*As a* midwife
*I want* the system to extract the Patient Name, Clinic Location, and Attending Professional from Ultrasound and Lab Test images
*So that* I don't have to manually type administrative details from these reports.

*Acceptance Criteria:*
- [ ] AI prompt specifically requests extraction of Patient Name, Location, and Professional.
- [ ] The extracted fields populate editable text fields in the UI before final submission.

*Technical Notes:*
- Update `GroqService.extractUltrasoundData` and `extractLabTestData`.
- Update `lib/models/ocr_result.dart`.
- Update `ultrasound_analyzer_screen.dart` and `lab_test_analyzer_screen.dart`.

*Dependencies:* None

### EPIC-04-002 AI Interpretation of Child Growth
*As a* mother
*I want* the system to explain my child's growth chart in simple terms
*So that* I understand if their weight and height are on track without needing a medical degree.

*Acceptance Criteria:*
- [ ] `GroqService` takes child age, gender, current weight/height, and Z-scores.
- [ ] Returns a short, localized (English/Filipino) paragraph explaining the growth status (e.g., "Normal weight, keep it up!").

*Technical Notes:*
- Create `generateGrowthInterpretation` in `GroqService`.
- Display the result on the child's growth details screen.

*Dependencies:* EPIC-03-001

---

# Epic: EPIC-05 Administrative Web Dashboard Enhancements
*Goal:* Align the web dashboard with the thesis requirements for community-level monitoring and reporting.
*Context:* The web dashboard exists in HTML/JS. It needs to support exporting data for LGU reporting and accommodating the new data fields introduced in the mobile app.

## Stories

### EPIC-05-001 Implement CSV Report Generation
*As a* BHC Administrator
*I want* to export maternal and child health data as CSV files
*So that* I can submit physical or spreadsheet reports to the Local Government Unit (LGU).

*Acceptance Criteria:*
- [ ] A "Generate Report" button exists on the web dashboard.
- [ ] Users can select a date range and report type (Maternal or Child).
- [ ] The system downloads a properly formatted CSV file.

*Technical Notes:*
- Implement using JavaScript Blob and Supabase JS client in `admin-web/pages/dashboard.html` or a new `reports.html`.

*Dependencies:* None

---

# Epic: EPIC-06 Automated Reminder & Notification System
*Goal:* Implement push or in-app notifications for upcoming health milestones.
*Context:* Timeliness of vaccination and prenatal follow-ups is a major focus in the thesis. A notification system is required to alert mothers.

## Stories

### EPIC-06-001 In-App Notification Engine
*As a* mother
*I want* to receive notifications for upcoming prenatal checkups and child immunizations
*So that* I do not miss critical healthcare appointments.

*Acceptance Criteria:*
- [ ] A `notifications` table exists in Supabase.
- [ ] When a checkup is scheduled or a vaccine is due soon, a record is inserted into the notifications table.
- [ ] Mothers have a Notification bell/screen in the app to view these alerts.

*Technical Notes:*
- Define `notifications` schema (id, user_id, title, message, is_read, created_at).
- Implement a Flutter stream to listen to `notifications` table changes in real-time.

*Dependencies:* None
