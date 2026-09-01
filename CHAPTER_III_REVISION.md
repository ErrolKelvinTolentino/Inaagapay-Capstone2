# CHAPTER III — Revision Pack
## Project Technical Description → Ethical Considerations

**Prepared against the codebase as of commit `88eca72` (vaccination drive analytics).**

This pack has two parts:

- **Part A — Alignment Audit.** Every place the current draft no longer matches the system, and why it matters to a panel.
- **Part B — Revised Text.** Paste-ready replacement prose, in the same academic register as your existing chapter.

---

# PART A — ALIGNMENT AUDIT

## A.1 Findings that a panelist can verify against your system

| # | Draft says | System actually does | Risk if unrevised |
|---|---|---|---|
| 1 | Vision model is `meta-llama/llama-4-scout-17b-16e-instruct`; dashboard summaries use `llama-3.3-70b-versatile` | Vision is `qwen/qwen3.6-27b`. The entire Llama 3.x line was **withdrawn by Groq** and is documented in `groq_service.dart` as no longer served | **Highest risk item.** An IT panelist who checks will find you named two models your system cannot call. |
| 2 | Fallbacks are only "other Groq models" | Three-layer fallback: Groq → **NVIDIA NIM** (same open weights, OpenAI-compatible protocol) → **Google Gemini** for vision. Fallback is cross-*provider*, not just cross-model | You are underselling a real reliability engineering decision that directly evidences ISO 25010 **Reliability** and **Flexibility**. |
| 3 | "Brevo API services are integrated to support email-based notifications" | No Brevo integration exists. Email is written to an `email_queue` table for server-side dispatch; no sender provider is wired in the repository | Unverifiable claim. Either finish the integration or describe the queue honestly. |
| 4 | Mobile libraries include "QR code generation" | QR was **deliberately removed**. `admin-web/pages/inventory.html` documents the removal: the caption claimed the code could be scanned, but neither the portal nor the app has a scanner. The printable dispatch slip remains | Claiming a removed feature is the kind of thing a demo exposes immediately. |
| 5 | Roles are variously "mothers, midwives, and the RHU Head Nurse" / "mothers, barangay health workers, midwives, and BHC administrators" / "administrators" | Exactly four account types exist: `mother`, `midwife`, `admin` (RHU administrator), `mho` (Municipal Health Office). There is **no** barangay-health-worker role and no "Head Nurse" role | Three different role vocabularies in one chapter. Panels notice this fast. |
| 6 | "RHU–BHC inventory coordination" | A full **three-tier supply chain**: MHO → RHU → BHC, with upward stock requests (`submit_inventory_stock_request`), guarded transfers (`issue_inventory_transfer`, `inventory_assert_may_transfer`), batch tracking, **dose-level dispensing from opened vials**, and an audit ledger that reconciles sealed units against doses | You built a logistics subsystem and described a fraction of it. This is a whole contribution going unclaimed. |
| 7 | "Rule-based monitoring" described generically, with no sources | A fully sourced deterministic clinical layer: IOM 2009 (weight gain), WHO 2011 + Abbassi-Ghanavati 2009 (CBC), INTERGROWTH-21st + WHO fetal growth charts (ultrasound), WHO child growth standards (z-scores bundled locally), plus single-source-of-truth references for blood pressure, fetal heart rate, immunization timing, prenatal scheduling, and maternal Td | **This is your strongest defense of the non-diagnostic claim** and it is currently invisible. The rules are citable; cite them. |
| 8 | Security described as "Supabase Authentication and role-based access control" | **Neither is accurate.** There is no `signInWithPassword` call in the repository — authentication is application-level, bcrypt against an `accounts` table over the anon client. Authorization is enforced by ~35 **`SECURITY DEFINER` stored procedures** with direct table writes revoked from client roles. Row Level Security is enabled but inoperative: its `has_role()` predicate keys on `auth.uid()`, which is always null without a Supabase Auth session. Real controls also include bcrypt hashing, `flutter_secure_storage`, an append-only `audit_trail`, and a hardened **Content-Security-Policy** setting `Permissions-Policy: camera=(), microphone=(), geolocation=()` | ISO 25010 **Security** is one of your nine characteristics. You have strong evidence for it — but not the evidence the draft names. Claiming Supabase Auth and RLS invites a question you cannot answer; see the correction note under *Security and Data Protection Design*. |
| 9 | No mention of bilingual output | `LanguageService` provides English/Filipino throughout, and the AI system prompt **mandates** dual-language output in colloquial Tagalog, explicitly forbidding z-scores and medical jargon in mother-facing text | Direct evidence for **Interaction Capability**, unclaimed. |
| 10 | "OCR-supported extraction" | There is no OCR engine (no Tesseract). Extraction is performed by a **vision-language model** | Technically imprecise. An IT panelist will ask which OCR library you used, and you don't have one. |
| 11 | Non-diagnostic disclaimer appears three times, near-verbatim | — | Reads as padding. State it once, authoritatively, then cross-reference. |
| 12 | Ethics section says "no actual patient records" and cites RA 10173 | True, but silent on the fact that document images and clinical text are **transmitted to third-party processors abroad** (Groq, NVIDIA, Google, Semaphore) | This is a genuine RA 10173 disclosure obligation and the most likely ethics question you will be asked. Address it before you are asked. |
| 13 | Mixed tense: methodology is future ("will"), technical description is present ("utilizes"), with no signal | — | Reads as inconsistent editing rather than a deliberate convention. |
| 14 | UAT participants listed as "mothers, midwives, and Barangay Health Center administrators" | Your 30 respondents contain no administrators (5 midwives, 20 mothers, 2 OB-GYNs, 3 IT experts) | Internal contradiction inside the same chapter. |
| 15 | Table 3.5 says tested on "Android 13/14"; Testing Environment says minimum "Android 8.0 or higher" | Both are defensible but the draft never distinguishes them | Reads as a contradiction unless you label one *minimum supported* and the other *verified*. |

## A.2 Structural recommendations

1. **Adopt an explicit tense convention** and state it once. Recommended: *present tense* for the artifact (Project Technical Description onward, because the system exists), *future tense* for procedures not yet performed (Testing Environment, Data Gathering, Ethical Considerations). Part B applies this consistently.

2. **Add two subsections that are missing**, both of which the panel will otherwise ask for:
   - *Rule-Based Clinical Monitoring* — placed **before** AI-Assisted Functionalities, so the reader learns that clinical judgment is deterministic and sourced before they learn that an LLM is involved. This ordering does most of the ethical work for you.
   - *Security and Data Protection Design* — consolidating RLS, hashing, session storage, CSP, and the audit trail.

3. **Add Table 3.6 (web and backend environment)** and **Table 3.7 (clinical rule sources)**. The second table is the single highest-value addition in this revision: it converts "we used rules" into "here is the published standard behind each rule."

4. **Retire the term "OCR"** or, if your adviser prefers the familiar word, define it once: *"AI-assisted document extraction (functionally equivalent to OCR, implemented through a vision-language model rather than a character-recognition engine)."*

5. **Fix the role vocabulary globally.** Search the full manuscript for *"Head Nurse"*, *"barangay health worker"*, and *"BHC administrator"* and reconcile all of them to the four implemented roles.

---

# PART B — REVISED TEXT

> **Note on convention.** The following sections describe the developed artifact and are therefore written in the present tense. Sections describing procedures not yet performed — testing, evaluation, and data gathering — remain in the future tense, consistent with the earlier parts of this chapter.

---

## Project Technical Description

InaAgapay is an AI-assisted maternal and child health information system developed to support the recording, monitoring, and communication of maternal and child health information within barangay-level healthcare settings. The system consists of an Android mobile application and a web-based administrative portal operating over a shared cloud backend, and is designed to work alongside the existing workflows of the Barangay Health Centers under Baliwag City Rural Health Unit III rather than to replace them.

The system serves four user roles, which correspond directly to the account types enforced by the database. **Mothers** access their own maternal and child health records, schedules, reminders, and health information through the mobile application. **Midwives** document prenatal checkups, laboratory and ultrasound results, child growth measurements, and immunizations, and manage the health center's stock of vaccines and supplements. **Rural Health Unit administrators** oversee accounts, facilities, midwife assignments, reporting, and the supply of stock to the health centers under their jurisdiction. **Municipal Health Office administrators** operate at the tier above the Rural Health Units and act on the stock requests those units submit. Every role is bound to a facility, and every clinical record is visible only to the roles and facilities entitled to see it.

Functionally, the system is organized into six areas. *Maternal health management* covers mother registration, pregnancy episodes, prenatal checkups, maternal vitals, laboratory results, ultrasound records, maternal weight-gain evaluation, maternal tetanus-diphtheria immunization, and delivery outcomes. *Child health management* covers birth details, growth measurements, immunization records, and the child's health booklet. *Monitoring and scheduling* covers the prenatal visit schedule, gestational diabetes screening windows, immunization due dates, vaccination drives, and the reminders generated from them. *Communication* covers in-application notifications, push notifications, SMS reminders, and a maternal health chatbot. *Inventory and logistics* covers stock levels, batches, expiries, dose-level dispensing, and stock requests and transfers across the three facility tiers. *Administration and accountability* covers account management, facility management, reporting, and an audit trail of changes to clinical and inventory data.

Two design commitments govern the whole system and are described in detail in the subsections that follow. First, **every clinical judgment the system makes is deterministic and sourced**: thresholds, ranges, schedules, and growth classifications are computed by rule modules that cite published standards, not by a language model. Second, **artificial intelligence is confined to explanation, extraction, and accessibility**: it restates what the rules or the attending professional have already determined, in language a mother can understand, and in either English or Filipino. The system does not diagnose, does not prescribe, and does not replace professional clinical judgment. Every AI-extracted value passes through midwife review and correction before it is stored as part of a health record. Final clinical assessment remains at all times the responsibility of licensed healthcare professionals.

---

## Technical Requirements

**Table 3.5**
*System and Permission Requirements of the InaAgapay Mobile Application*

| Specification | Description |
|---|---|
| Operating System | Android. The minimum supported version is Android 8.0 (API 26); development and verification are conducted on Android 13 and 14. |
| Distribution | Android Package (APK) installation through a controlled distribution link during the pilot implementation. |
| Camera | Required for capturing ultrasound reports, laboratory results, immunization cards, and maternal registration forms for AI-assisted extraction, and for profile photographs. |
| Media and File Access | Required for selecting and retrieving previously captured health documents and images from the device gallery. |
| Internet Access | Required for authentication, database synchronization, file storage, push notification delivery, SMS dispatch, address lookup, and AI-assisted processing. |
| Local Storage | Required for authentication sessions held in encrypted secure storage, application preferences, temporary image files, and generated PDF reports. |
| Audio Output | Required for text-to-speech playback of health summaries, reminders, and guidance. |
| Audio Recording | Required for voice dictation of health notes, which is transcribed by speech-to-text. |
| Push Notifications | Required for prenatal checkup reminders, immunization and vaccination drive reminders, and health-related alerts. |

**Table 3.6**
*Web Portal and Backend Environment Requirements*

| Component | Requirement |
|---|---|
| Client Device | Desktop or laptop computer running Windows 10 or higher, Intel Core i5 or equivalent processor, 8 GB RAM. |
| Browser | Google Chrome (current stable release); the portal targets standard ECMAScript and requires no browser extension. |
| Connectivity | Stable broadband or mobile internet connection. |
| Hosting | Static hosting with enforced HTTPS and security response headers. |
| Backend | Managed PostgreSQL with Row Level Security, authentication, object storage, real-time subscriptions, scheduled jobs, and serverless functions. |
| Server-Side Scheduling | A daily scheduled job executing in Philippine Standard Time (UTC+8) for reminder generation and dispatch. |

The requirements in Tables 3.5 and 3.6 reflect the fact that the mobile application performs image capture, audio capture and playback, local report generation, and continuous synchronization, while the web portal is a thin administrative client whose processing occurs in the backend.

---

## Development Tools and Technologies

The InaAgapay system is developed using programming languages, frameworks, and cloud services selected for their suitability to barangay-level healthcare environments, where budget, hardware, and technical support are limited. These technologies are organized across four components: the mobile application, the web-based administration platform, the cloud backend, and version control. The artificial intelligence services utilized by the system are discussed separately under AI-Assisted Functionalities.

The mobile application is developed using Flutter as the primary cross-platform development framework, with Dart as the programming language. The application communicates with the backend to support database access, file storage, and real-time synchronization of healthcare records, and utilizes Firebase Cloud Messaging for the delivery of push notifications such as prenatal checkup reminders, immunization reminders, and healthcare-related alerts. Additional components integrated into the application support camera access for capturing healthcare documents, gallery access for selecting previously saved images, chart visualization for growth and weight monitoring, calendar-based scheduling, audio recording for voice dictation, audio playback and speech synthesis for spoken healthcare guidance, encrypted storage of user sessions on the device, and the generation of printable healthcare summaries and reports. These technologies support the mobile application functionalities intended for mothers and midwives.

The web-based administration platform is developed using HTML5, CSS3, and JavaScript, which run directly in a standard web browser without requiring the installation of additional software. Chart.js is utilized for dashboard visualization and healthcare-related monitoring summaries, jsPDF is utilized for generating exportable healthcare-related reports, and Font Awesome and Google Fonts are utilized to support interface presentation and usability. The platform supports administrative sign-in, account and facility management, midwife assignment, patient record review, monitoring dashboards, inventory and stock distribution, audit trail review, database backup, and healthcare-related reporting, and is intended for Rural Health Unit and Municipal Health Office administrators. It is deployed as a static website with enforced HTTPS and security response headers, which requires no dedicated application server and minimizes hosting cost.

The backend infrastructure is built using Supabase, which serves as the centralized backend platform for database management, cloud storage, and real-time synchronization. PostgreSQL is utilized as the relational database for storing maternal and child healthcare records, prenatal monitoring data, immunization records, child growth information, inventory transactions, healthcare-related notifications, and system audit logs. The structure of the database is maintained through a versioned set of database change scripts kept in the project repository, so that every modification to the database is documented, reproducible, and traceable to the change that introduced it. Cloud storage is utilized for uploaded healthcare-related images and documents, while operations that cannot safely be performed on the user's device, such as the generation and dispatch of scheduled reminders, are carried out by server-side functions executed on a daily schedule following Philippine Standard Time.

Account security is implemented at the application level using a dedicated account record for each user. Passwords are stored as one-way cryptographic hashes rather than as readable text, and a password history is retained to prevent the reuse of previous credentials. Operations that create or modify healthcare and inventory records are carried out through controlled database procedures that verify the user's role and assigned facility before any change is recorded, so that access rules are enforced by the server rather than by the application installed on the user's device.

The system architecture utilizes lightweight and cloud-based technologies to support cost-efficient deployment and maintenance within barangay-level healthcare environments. Flutter enables mobile development from a single codebase, reducing development complexity and maintenance cost while maintaining consistent application performance across Android devices. The use of Supabase as a Backend-as-a-Service platform minimizes the need for dedicated server infrastructure and backend maintenance while still supporting centralized database management, cloud storage, and real-time synchronization. The web-based administration platform likewise utilizes lightweight web technologies including HTML5, CSS3, and JavaScript to support broad browser compatibility and reduced hosting overhead. This design approach aligns with studies indicating that mobile health (mHealth) systems and lightweight digital healthcare platforms can improve healthcare accessibility, communication, and healthcare monitoring efficiency within low-resource and community healthcare settings (Ameyaw et al., 2024; Mbunge, 2024).

GitHub is utilized as the repository platform for version control, source code management, collaborative development, and project tracking throughout the system development lifecycle.

---

## Rule-Based Clinical Monitoring

*(New subsection. Place this before "AI-Assisted Functionalities.")*

All clinical determinations in InaAgapay are produced by deterministic rule modules. Each module implements published maternal and child health standards, exposes a single point of judgment for the value it governs, and is covered by unit tests. No clinical threshold is evaluated by a language model, and no clinical threshold is duplicated across the application: the mother's record, the midwife's recording screen, and the risk summary all read the same module, so they cannot disagree with one another.

**Table 3.7**
*Clinical Rule Modules and Their Reference Standards*

| Monitored Parameter | Basis of the Rule |
|---|---|
| Blood pressure in pregnancy | Pregnancy-specific hypertension thresholds (140/90 and 160/110 mmHg), applied inclusively at the cut-point. |
| Fetal heart rate | Contemporary baseline range of 110–160 bpm. |
| Gestational weight gain | Institute of Medicine (2009) recommendations by pre-pregnancy body mass index category, with an adaptive mode for records lacking a pre-pregnancy weight. |
| Complete blood count in pregnancy | WHO (2011) haemoglobin thresholds for anaemia, with trimester-specific reference intervals from Abbassi-Ghanavati, Greer, and Cunningham (2009). |
| Fetal biometry from ultrasound | INTERGROWTH-21st fetal growth standards (Papageorghiou et al., 2014) and WHO fetal growth charts (Kiserud et al., 2017). |
| Gestational diabetes screening | Screening window at 24–28 weeks of gestation, with risk-based earlier screening. |
| Prenatal visit scheduling | Standard antenatal visit intervals by gestational age, capped at the expected date of delivery. |
| Child growth | WHO Child Growth Standards, evaluated as weight-for-age, height-for-age, and BMI-for-age z-scores against reference tables held locally within the application. |
| Childhood immunization timing | National immunization schedule, evaluated per dose against the child's date of birth. |
| Maternal tetanus-diphtheria immunization | Doses Td1 through Td5, normalized to a single canonical dose key across all recording paths. |

Two properties of this layer are worth stating explicitly, because they bear directly on the **Safety** and **Reliability** characteristics evaluated in this study.

First, the rules are **auditable**. Each module carries its citation in source, so an obstetrician-gynecologist reviewing the system can trace any classification the system displays back to the published standard that produced it. This is what makes the expert review described under *Population and Sample of the Study* a meaningful exercise rather than a general impression.

Second, the rules are **single-source**. Consolidating each judgment into one module was itself a corrective measure: prior to consolidation, several parameters were evaluated in multiple places using inconsistent thresholds, which produced contradictory classifications on the same screen. Centralization removed that class of defect and is the reason the system can guarantee that what the midwife saw when she recorded a value is what the mother later sees on her own record.

---

## AI-Assisted Functionalities

Artificial intelligence in InaAgapay operates strictly downstream of the rule layer described above. It performs three functions — **extraction**, **explanation**, and **accessibility** — and performs no clinical evaluation of its own.

**Extraction.** A vision-language model reads photographed maternal registration forms, immunization cards, laboratory reports, and ultrasound reports, and proposes structured field values. These values are **proposals, not records**. They are presented to the midwife in a review screen where every field can be corrected before anything is written to the database, and the extraction output is retained separately from the record it produced so that the origin of a value remains traceable. This midwife-review gate is the control that permits an imperfect extractor to be used safely in a clinical record system.

**Explanation.** A text model restates findings that have already been determined — by a rule module, or by the attending professional — in plain, non-clinical language. The system prompt governing mother-facing output requires that every explanation be produced in both English and conversational Filipino, in the register of a trusted older sister rather than a clinician, and explicitly forbids z-scores, medical jargon, and dietary, lifestyle, or treatment suggestions. The model is not given the authority to introduce a finding; it is given a finding and asked to make it understandable.

**Accessibility.** Speech-to-text transcribes dictated health notes for midwives working with their hands occupied. Text-to-speech vocalizes summaries, reminders, and guidance for mothers with limited reading fluency, using a cloud speech model where available and falling back to on-device synthesis otherwise.

**Table 3.8**
*Artificial Intelligence Models and Their Roles*

| Function | Primary Model | Fallback Chain |
|---|---|---|
| Document and image extraction | `qwen/qwen3.6-27b` (Groq) | Google Gemini (`gemini-2.0-flash`, then `gemini-1.5-flash`, then `gemini-2.0-flash-lite`) |
| Text explanation and summarization | `openai/gpt-oss-120b` (Groq) | `openai/gpt-oss-20b` (Groq), then `qwen/qwen3.6-27b` (Groq); each of the first two additionally falls back to the same open weights hosted on NVIDIA NIM |
| Speech-to-text | `whisper-large-v3-turbo` (Groq) | `whisper-large-v3` (Groq) |
| Text-to-speech | `canopylabs/orpheus-v1-english` (Groq) | On-device platform speech synthesis |

The fallback design is deliberate and is a response to an observed failure. The models are open-weight and are reached through inference providers, which means the set of models a provider serves can change without notice — and did, when an entire model family the system depended on was withdrawn and every AI-generated explanation silently degraded to its rule-based fallback while extraction continued to work. The chain in Table 3.8 is therefore constructed on two principles: the final text fallback is drawn from a **different model family** than the first two, so that a fault confined to one family cannot exhaust the chain; and the chain crosses **provider boundaries**, so that a provider outage or rate limit does not disable the feature. Because the fallback hosts serve the same open weights, the prompts and safety constraints behave identically regardless of which host answers.

Underneath all of this sits the guarantee stated in the *Project Technical Description*: if every AI service in Table 3.8 were unreachable, the system would continue to record health information, evaluate it against the rules in Table 3.7, generate schedules and reminders, and manage inventory. The artificial intelligence layer improves comprehension and reduces encoding effort. It is not load-bearing for care.

---

## API Integrations

**Table 3.9**
*External Services and Their Purpose*

| Service | Purpose | Data Transmitted |
|---|---|---|
| Groq Cloud | Extraction, explanation, transcription, and speech synthesis | Document images, de-identified clinical values, dictated audio |
| NVIDIA NIM | Cross-provider fallback for text models | As above, text only |
| Google Gemini | Cross-provider fallback for document extraction | Document images |
| Firebase Cloud Messaging | Push notification delivery | Device registration token and notification text |
| Semaphore SMS | Checkup reminders, vaccination drive invitations, account verification codes | Mobile number and message body |
| PSGC API | Standardization of Philippine region, province, municipality, and barangay names during registration | Address query terms only |
| Supabase | Authentication, database, object storage, real-time synchronization, scheduled functions | All system data |

Two safeguards apply to every entry in Table 3.9. All credentials are supplied through environment configuration and are never committed to the repository or embedded in client code. And where a service is unavailable, the dependent feature degrades to a defined fallback rather than failing the surrounding workflow — the fallback chains for AI services are given in Table 3.8; SMS and email dispatch are queued for retry; and address selection accepts manual entry when the standards lookup cannot be reached.

> **Action required before submission.** The current draft states that Brevo is integrated for email notifications. No such integration exists in the codebase — outbound email is written to an `email_queue` table for server-side dispatch, and no sending provider is wired. Either complete the integration and name the provider you actually use, or replace the claim with a description of the queue. Do not leave the Brevo sentence in the manuscript.

---

## Security and Data Protection Design

*(New subsection. Place after "API Integrations.")*

Security in InaAgapay is enforced at four layers, so that no single client-side control is the only thing standing between a user and a record they are not entitled to see.

**Database.** Authorization is enforced inside the database rather than in the client. Operations that create or modify healthcare and inventory records are exposed only as **`SECURITY DEFINER` stored procedures**, and direct write access to the underlying tables is revoked from client roles. Each procedure validates the acting account's role and facility assignment before performing any change — for example, a stock transfer is refused unless the acting account holds a role permitted to issue one and the destination facility sits below the source in the facility hierarchy. A client therefore cannot write to a record it is not entitled to modify, and cannot bypass the check by addressing the table directly, because it holds no write privilege on the table at all.

**Authentication and credentials.** Authentication is implemented at the application level against a dedicated `accounts` table. Passwords are stored as bcrypt hashes, never in plaintext. Password history is retained to prevent reuse, and temporary credentials issued during account creation must be changed at first sign-in. Authentication sessions on the mobile application are held in platform-encrypted secure storage rather than in ordinary preferences.

> **Correction to an earlier draft of this pack, and a defect to resolve.** An earlier version of this section stated that authorization is enforced through PostgreSQL Row Level Security policies. That is not accurate for this system and should not be claimed. Row Level Security is enabled on the clinical tables and policies exist, but every policy resolves through a `has_role()` function keyed on `auth.uid()`. Because the system uses application-level authentication rather than Supabase Auth, no Supabase Auth session is ever established, `auth.uid()` is always null, and those policies consequently match no rows — a condition already documented in `inventory_repository.dart`, where it caused midwives to be refused access to their own health center's stock. The operative control is the `SECURITY DEFINER` procedure pattern described above. Two options are defensible for the manuscript: describe the procedure pattern only, as written here; or, if time permits before final submission, replace the `auth.uid()` predicate with one that reads the acting account from a session variable set by the application, which would make the RLS layer operative and allow both controls to be claimed. Do not claim Row Level Security as an enforced control while the predicate remains inoperative.

**Transport and browser surface.** The web portal is served exclusively over HTTPS with HTTP Strict Transport Security. A Content-Security-Policy enumerates every permitted script, style, font, image, and connection origin and forbids all others; framing is denied outright; and a Permissions-Policy disables camera, microphone, and geolocation access for the portal, which has no legitimate use for any of them. The portal is additionally marked `noindex, nofollow`, as it is not intended for public discovery.

**Accountability.** An append-only `audit_trail` records changes to clinical records, account state, and inventory movements, together with the actor and the facility in whose context the action occurred. The audit summary is generated server-side so that it cannot be authored by the client, and it is written to reconcile against the underlying transaction — including the case of a dose drawn from an already-opened vial, where whole-unit and dose-level quantities differ. Sensitive values are redacted in the audit view, and this redaction is covered by an automated test.

---

## Testing Environment

*(Retained in future tense — this describes procedure not yet performed.)*

Testing will be conducted across mobile, web, and integrated backend environments.

**Mobile testing** will use both an emulator and a physical device. The Android Studio Emulator will be used during development to evaluate interface behavior and version compatibility. A physical Android smartphone running Android 13, with an octa-core processor, 8 GB of RAM, and 128 GB of internal storage, will serve as the primary verification device, because camera capture, microphone capture, notification delivery, local file access, and real-time synchronization behave differently outside an emulator. The minimum device profile the application is intended to support is Android 8.0 or higher with at least 4 GB of RAM, 200 MB of free storage, a working camera and microphone, audio output, and mobile data or Wi-Fi connectivity.

**Web testing** will be conducted on a desktop or laptop running Windows 10 or higher with an Intel Core i5 or equivalent processor, 8 GB of RAM, and Google Chrome, covering dashboard monitoring, account and facility management, patient records, inventory, reporting, and audit trail review.

**Integration testing** will verify that the mobile application, web portal, PostgreSQL backend, object storage, real-time subscriptions, scheduled reminder functions, notification services, SMS dispatch, address standardization, and AI services operate together as one system. It will specifically verify the behaviors that only appear at the seams: that a record created on one client appears on the other; that a scheduled reminder fires on the correct Philippine calendar date; that stock dispensed on the mobile application is reflected in the portal's ledger and audit trail; and that each AI fallback chain in Table 3.8 actually engages when its primary is unavailable, rather than failing the surrounding workflow.

**Rule verification** will be conducted separately from feature testing. Each module in Table 3.7 will be exercised at and around its published thresholds through boundary-value testing, so that classification is confirmed to be correct at the cut-point itself and not merely on either side of it. The obstetrician-gynecologist respondents will review the rule thresholds, the wording of system-generated recommendations, and the boundary between rule-based output, AI-generated explanation, and professional clinical judgment before the formal system evaluation begins.

A **test case matrix** will be prepared covering the mother-side mobile functions, the midwife-side documentation and monitoring functions, the administrative portal functions, database synchronization, notification and messaging services, inventory and transfer operations, and AI-assisted features. Each entry will record the test case number, module, preconditions, test steps, expected output, actual output, result, remarks, and any correction applied. A test case will be recorded as passed when the function behaves according to the approved requirement, data are correctly stored or retrieved, the intended task completes, and no critical error occurs. It will be recorded as failed when the function does not operate, produces incorrect output, raises a system error, fails to persist or retrieve records, or prevents task completion. Failed cases will be corrected and retested before evaluation.

Simulated maternal and child health data will be used throughout. No actual patient record will be entered into the system at any stage of development, testing, demonstration, or evaluation.

Following internal testing, **User Acceptance Testing** will be conducted with the mothers and midwives among the study respondents, who will perform role-appropriate workflow tasks. Usability concerns, errors, and recommendations arising from this activity will be documented and applied as refinements before the formal evaluation using the ISO/IEC 25010:2023-based questionnaire.

The mobile application will be distributed for the pilot through a controlled installation link, which allows the researchers to deliver builds directly to the intended participants during development and evaluation without public marketplace release. Publication through the Google Play Store is identified as a future direction, as it would provide centralized version management and independent verification of application authenticity.

---

## Design and Diagrams

*(Structural guidance — retain your existing figures, revised as noted.)*

Your figure set is sound and should be kept. Three revisions align it with the sections above:

1. **Figure 5 (System Architecture).** The current caption describes an "AI-assisted interpretation engine" processing database records. This inverts the actual architecture and contradicts your non-diagnostic claim. Redraw the application layer to show two distinct paths: clinical values flowing through the **rule modules** to produce classifications, and those classifications flowing to the **AI layer** for explanation only. Show the extraction path terminating in a **midwife review** step before it reaches the database. A panelist who sees this diagram should be able to state your safety argument without your having to make it.

2. **Figure 4 (Use Case).** Extend to four actors. The Municipal Health Office actor and the stock request and transfer use cases are currently absent.

3. **Figure 3 (Level 1 DFD).** Add the inventory and logistics process. The current diagram shows account management, maternal health, child health, AI analysis, and reporting, and omits an entire implemented subsystem.

Each figure should be followed by a short narrative paragraph, as in your current draft — that pattern is correct and reads well.

---

## Ethical Considerations

The researchers will observe established ethical standards throughout the conduct of this study.

**Institutional permission and informed consent.** Written permission will be secured from Baliwag City Rural Health Unit III and the participating Barangay Health Centers before any data-gathering activity begins. Informed consent will be obtained from every respondent — mothers, midwives, obstetrician-gynecologists, and information technology experts — prior to observation, interview, system use, and questionnaire administration. Respondents will be informed of the objectives of the study, the nature of the evaluation, the intended academic use of their responses, and their right to decline or withdraw at any point without penalty or consequence. Audio recording will occur only with explicit consent, and only for the purpose of documenting requirements. No respondent will be subjected to coercion or undue influence.

**No use of actual patient records.** The study will not collect, process, or store real patient health information. All maternal and child health data used during development, testing, demonstration, and evaluation will be simulated data constructed to match the structure of standard maternal and child health record formats. This is the primary protection in this study: the clinical data the system handles during the research period does not belong to any identifiable person.

**Data privacy and confidentiality.** In compliance with the Data Privacy Act of 2012 (Republic Act No. 10173), all information gathered from respondents will be treated as confidential. Evaluation responses will be anonymized at the point of encoding, and no personally identifiable information will appear in any report, publication, or presentation arising from the study. Research data and documents will be stored securely and accessed only by members of the research team. Upon completion of the study and fulfillment of academic requirements, digital records will be retained for one year for documentation and verification purposes, after which they will be permanently deleted.

**Third-party processing and cross-border transmission.** The researchers acknowledge that the system's AI-assisted, messaging, and notification functions transmit data to external service providers, some of which process data outside the Philippines. Specifically, document images and clinical text are transmitted to inference providers for extraction and explanation; mobile numbers and message text are transmitted to an SMS gateway; and device tokens and notification text are transmitted to a push notification service. Three measures address this. First, because only simulated data are used during the study, no actual patient information leaves the country during the research period. Second, service credentials are held in environment configuration, never committed to the repository, and never embedded in distributed client code. Third, this dependency is documented here so that any future deployment involving real patient data is understood to require a data-sharing assessment and the consent of the data subjects before it proceeds. The researchers recognize that a system of this kind cannot be deployed with live patient records on the strength of academic consent alone.

**Non-diagnostic boundary and professional oversight.** The system does not diagnose, does not prescribe, and does not render final clinical judgment. Clinical determinations are produced by deterministic rule modules implementing published standards, as set out in Table 3.7; artificial intelligence is confined to explanation, extraction, and accessibility, as set out in Table 3.8. Every value extracted from a document by an AI model is presented for midwife review and correction before it is stored. Every explanation shown to a mother restates a finding that a rule or a professional has already established. Responsibility for assessment, interpretation, and care remains at all times with the licensed healthcare professionals attending to the mother and child. This boundary was reviewed by the obstetrician-gynecologist respondents before the formal evaluation, and the wording of system-generated recommendations was revised where it risked being read as clinical advice.

**Risk of AI error.** The researchers acknowledge that generative models can produce fluent output that is incorrect. Three controls limit the consequences. Extraction output cannot enter a health record without midwife review. Explanation output is constrained by prompt to restate an already-determined finding and is forbidden from offering medical, dietary, or lifestyle recommendations. And no clinical threshold is evaluated by a model, so a model failure degrades the readability of an explanation without altering the underlying classification. Where AI services are unavailable, the system falls back to rule-based output rather than to silence.

**Transparency and accountability.** The system maintains an audit trail of changes to clinical records, account state, and inventory movements, recording the responsible actor and facility. AI-generated outputs are retained alongside their revision history, so that the origin of a stored value — whether extracted, corrected, or entered directly — remains traceable. These mechanisms exist so that the use of automation in the system remains reviewable by the professionals accountable for the care it supports.

**Benefit and non-maleficence.** The study is intended to support, not replace, the work of barangay health centers. The system is designed to reduce documentation burden, improve the continuity of maternal and child records, and make health information more understandable to mothers, including through Filipino-language output and speech synthesis for those with limited reading fluency. No respondent will receive or forgo any healthcare service as a consequence of participating in this study.
