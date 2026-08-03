-- =====================================================
-- DATABASE: Maternal & Child Health Information System
-- PostgreSQL (Supabase) Version
-- =====================================================
-- url: 'https://buvseyqcdacctlupznya.supabase.co',
-- anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ1dnNleXFjZGFjY3RsdXB6bnlhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI2MzE2NTUsImV4cCI6MjA4ODIwNzY1NX0.VPh8ZZFqdeFyb8YuMxllbJJa-nWl4VXNq74o6-Itjjw',
-- =========================
-- ACCOUNTS & SECURITY
-- =========================
CREATE TABLE accounts (
    account_id BIGSERIAL PRIMARY KEY,
    email_address VARCHAR(255) UNIQUE,
    password_hash VARCHAR(255),
    account_type VARCHAR(20) NOT NULL CHECK (account_type IN ('admin', 'midwife', 'mother')),
    first_name VARCHAR(100),
    middle_name VARCHAR(100),
    last_name VARCHAR(100),
    extension_name VARCHAR(100),
    phone_number VARCHAR(20),
    verification_code VARCHAR(100),
    verification_expires TIMESTAMP,
    is_verified BOOLEAN DEFAULT FALSE,
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'suspended')),
    reset_code VARCHAR(6),
    reset_expires TIMESTAMP,
    last_login_token VARCHAR(128),
    last_login_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE password_history (
    pass_history_id BIGSERIAL PRIMARY KEY,
    account_id BIGINT NOT NULL REFERENCES accounts(account_id) ON DELETE CASCADE,
    password VARCHAR(255) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    replaced_at TIMESTAMP
);
CREATE TABLE audit_trail (
    audit_id BIGSERIAL PRIMARY KEY,
    account_id BIGINT REFERENCES accounts(account_id) ON DELETE
    SET NULL,
        action VARCHAR(100) NOT NULL,
        table_name VARCHAR(100),
        old_data JSONB,
        new_data JSONB,
        description TEXT,
        action_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        ip_address VARCHAR(45)
);
-- =========================
-- BARANGAY & STAFF
-- =========================
CREATE TABLE bhc (
    bhc_id BIGSERIAL PRIMARY KEY,
    bhc_name VARCHAR(255) NOT NULL
);
CREATE TABLE midwives (
    midwife_id BIGSERIAL PRIMARY KEY,
    account_id BIGINT NOT NULL UNIQUE REFERENCES accounts(account_id) ON DELETE CASCADE,
    assigned_bhc_id BIGINT NOT NULL REFERENCES bhc(bhc_id) ON DELETE RESTRICT
);
-- =========================
-- MOTHERS & MEDICAL PROFILE
-- =========================
CREATE TABLE mothers (
    mother_id BIGSERIAL PRIMARY KEY,
    account_id BIGINT NOT NULL UNIQUE REFERENCES accounts(account_id),
    assigned_bhc_id BIGINT REFERENCES bhc(bhc_id) ON DELETE CASCADE,
    birthdate DATE,
    house_number VARCHAR(50),
    street VARCHAR(100),
    barangay VARCHAR(100),
    city_municipality VARCHAR(100),
    province VARCHAR(100),
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
    height DECIMAL(5, 2),
    weight DECIMAL(5, 2),
    blood_type VARCHAR(100)
);
CREATE TABLE emergency_contacts (
    emergency_contact_id BIGSERIAL PRIMARY KEY,
    mother_id BIGINT NOT NULL REFERENCES mothers(mother_id) ON DELETE CASCADE,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    middle_name VARCHAR(100),
    extension_name VARCHAR(20),
    phone_number VARCHAR(20),
    affiliation VARCHAR(100),
    email_address VARCHAR(255),
    house_number VARCHAR(50),
    street VARCHAR(100),
    barangay VARCHAR(100),
    city_municipality VARCHAR(100),
    province VARCHAR(100),
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE medical_conditions (
    med_condition_id BIGSERIAL PRIMARY KEY,
    mother_id BIGINT NOT NULL REFERENCES mothers(mother_id) ON DELETE CASCADE,
    condition_name VARCHAR(255) NOT NULL,
    diagnosis_date DATE,
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'resolved')),
    remarks TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE allergies (
    allergy_id BIGSERIAL PRIMARY KEY,
    mother_id BIGINT NOT NULL REFERENCES mothers(mother_id) ON DELETE CASCADE,
    allergen VARCHAR(255) NOT NULL,
    diagnosis_date DATE,
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'resolved')),
    treatment TEXT,
    remarks TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
-- =========================
-- PREGNANCY & CARE
-- =========================
CREATE TABLE pregnancies (
    pregnancy_id BIGSERIAL PRIMARY KEY,
    mother_id BIGINT NOT NULL REFERENCES mothers(mother_id) ON DELETE CASCADE,
    pregnancy_risk_level VARCHAR(10) CHECK (
        pregnancy_risk_level IN ('low', 'medium', 'high')
    ),
    last_menstrual_period DATE,
    expected_date_of_delivery DATE,
    pre_pregnancy_weight DECIMAL(5, 2),
    fetal_count INT DEFAULT 1,
    status VARCHAR(10) NOT NULL CHECK (status IN ('ongoing', 'ended')),
    gestational_age_at_end DECIMAL(4, 1),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ended_at TIMESTAMP
);
CREATE TABLE pregnancy_outcomes (
    outcome_id BIGSERIAL PRIMARY KEY,
    pregnancy_id BIGINT NOT NULL REFERENCES pregnancies(pregnancy_id) ON DELETE CASCADE,
    fetus_number INT DEFAULT 1,
    outcome VARCHAR(20) CHECK (
        outcome IN (
            'live_birth',
            'stillbirth',
            'miscarriage',
            'abortion',
            'ectopic',
            'fetal_loss',
            'vanishing_twin'
        )
    ),
    outcome_date DATE,
    is_outcome_date_estimated BOOLEAN DEFAULT FALSE,
    gestational_age_at_end DECIMAL(4, 1),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


CREATE TABLE prenatal_checkups (
    prenatal_checkup_id BIGSERIAL PRIMARY KEY,
    pregnancy_id BIGINT NOT NULL REFERENCES pregnancies(pregnancy_id) ON DELETE CASCADE,
    midwife_id BIGINT NOT NULL REFERENCES midwives(midwife_id) ON DELETE RESTRICT,
    age_of_gestation DECIMAL(4, 1),
    checkup_weight DECIMAL(5, 2),
    blood_pressure_systolic INT,
    blood_pressure_diastolic INT,
    fetal_position VARCHAR(100),
    fetal_heart_beat INT,
    fetal_heart_tone VARCHAR(100),
    td_vaccine_dose VARCHAR(50),
    edema VARCHAR(10) DEFAULT 'none' CHECK (edema IN ('none', 'mild', 'moderate', 'severe')),
    remarks TEXT,
    checkup_datetime TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    next_schedule DATE
);

CREATE TABLE ultrasounds (
    ultrasound_id BIGSERIAL PRIMARY KEY,
    pregnancy_id BIGINT NOT NULL REFERENCES pregnancies(pregnancy_id) ON DELETE CASCADE,
    ultrasound_date DATE NOT NULL,
    ultrasound_location VARCHAR(255),
    ultrasound_image TEXT,
    remarks TEXT,
    health_worker_name VARCHAR(255),
    health_worker_institution VARCHAR(255),
    health_worker_profession VARCHAR(100),
    -- Trimester-aware 3-tier monitoring classification (AI-assisted)
    -- Values: within_expected_range | requires_closer_monitoring | follow_up_recommended
    -- Reference: INTERGROWTH-21st (Papageorghiou et al., Lancet 2014)
    --            WHO Fetal Growth Charts (Kiserud et al., PLOS Medicine 2017)
    monitoring_classification VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE lab_tests (
    lab_test_id BIGSERIAL PRIMARY KEY,
    pregnancy_id BIGINT NOT NULL REFERENCES pregnancies(pregnancy_id) ON DELETE CASCADE,
    lab_test_type VARCHAR(255),
    lab_test_date DATE,
    lab_test_location VARCHAR(255),
    lab_test_image TEXT,
    remarks TEXT,
    health_worker_name VARCHAR(255),
    health_worker_institution VARCHAR(255),
    health_worker_profession VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE deliveries (
    delivery_id BIGSERIAL PRIMARY KEY,
    pregnancy_id BIGINT NOT NULL REFERENCES pregnancies(pregnancy_id) ON DELETE CASCADE,
    fetus_number INT DEFAULT 1,
    delivery_date DATE,
    is_delivery_date_estimated BOOLEAN DEFAULT FALSE,
    place_of_delivery VARCHAR(255),
    delivery_method VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
-- =========================
-- CHILD & IMMUNIZATION
-- =========================
CREATE TABLE children (
    child_id BIGSERIAL PRIMARY KEY,
    mother_id BIGINT NOT NULL REFERENCES mothers(mother_id) ON DELETE CASCADE,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    middle_name VARCHAR(100),
    extension_name VARCHAR(20),
    sex VARCHAR(10) CHECK (sex IN ('male', 'female')),
    added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE birth_details (
    birth_details_id BIGSERIAL PRIMARY KEY,
    child_id BIGINT NOT NULL UNIQUE REFERENCES children(child_id) ON DELETE CASCADE,
    birthdate DATE,
    birth_weight DECIMAL(5, 2),
    birth VARCHAR(255),
    birthplace_city_municipality VARCHAR(255),
    birthplace_province VARCHAR(255),
    birth_length DECIMAL(5, 2),
    head_circumference DECIMAL(5, 2),
    birth_complications TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE child_details (
    child_details_id BIGSERIAL PRIMARY KEY,
    child_id BIGINT NOT NULL REFERENCES children(child_id) ON DELETE CASCADE,
    child_height DECIMAL(5, 2),
    child_weight DECIMAL(5, 2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE vaccines (
    vaccine_id BIGSERIAL PRIMARY KEY,
    vaccine_name VARCHAR(255) NOT NULL,
    dose_number INT NOT NULL,
    recommended_age_months DECIMAL(4, 1) NOT NULL,
    target_recipients VARCHAR(10) NOT NULL CHECK (target_recipients IN ('child', 'mother')),
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (vaccine_name, dose_number)
);
CREATE TABLE immunization_schedule (
    immunization_schedule_id BIGSERIAL PRIMARY KEY,
    bhc_id BIGINT NOT NULL REFERENCES bhc(bhc_id) ON DELETE CASCADE,
    vaccine_id BIGINT NOT NULL REFERENCES vaccines(vaccine_id) ON DELETE CASCADE,
    schedule_date DATE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (bhc_id, vaccine_id, schedule_date)
);
CREATE TABLE immunization_record (
    immunization_record_id BIGSERIAL PRIMARY KEY,
    child_id BIGINT NOT NULL REFERENCES children(child_id) ON DELETE CASCADE,
    vaccine_id BIGINT NOT NULL REFERENCES vaccines(vaccine_id) ON DELETE CASCADE,
    vaccination_date DATE NOT NULL,
    remarks TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (child_id, vaccine_id)
);
-- =========================
-- ADDITIONAL TABLES
-- =========================
CREATE TABLE checkup_schedule (
    schedule_id BIGSERIAL PRIMARY KEY,
    mother_id BIGINT NOT NULL REFERENCES mothers(mother_id) ON DELETE CASCADE,
    scheduled_date DATE NOT NULL,
    status VARCHAR(20) DEFAULT 'scheduled' CHECK (
        status IN ('scheduled', 'completed', 'missed', 'cancelled')
    ),
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE mother_medications (
    mother_medication_id BIGSERIAL PRIMARY KEY,
    mother_id BIGINT NOT NULL REFERENCES mothers(mother_id) ON DELETE CASCADE,
    mother_medication_name VARCHAR(255) NOT NULL,
    frequency VARCHAR(100),
    quantity INT,
    start_date DATE,
    end_date DATE,
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'completed', 'stopped')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE given_medications (
    given_medication_id BIGSERIAL PRIMARY KEY,
    mother_id BIGINT NOT NULL REFERENCES mothers(mother_id) ON DELETE CASCADE,
    given_medication_name VARCHAR(255) NOT NULL,
    quantity INT NOT NULL,
    date_given DATE NOT NULL
);
CREATE TABLE journal_entries (
    entry_id BIGSERIAL PRIMARY KEY,
    mother_id BIGINT NOT NULL REFERENCES mothers(mother_id) ON DELETE CASCADE,
    title VARCHAR(255),
    content TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
-- =====================================================
-- AI RESPONSES TABLE
-- Stores all AI-generated insights from different modules
-- =====================================================
CREATE TABLE ai_responses (
    ai_response_id BIGSERIAL PRIMARY KEY,
    -- Unique identifier for each AI-generated response
    response_type VARCHAR(50) NOT NULL,
    -- Type of AI output.
    -- Examples: risk_assessment, checkup_summary, lab_insight,
    -- ultrasound_analysis, growth_analysis, recommendation
    reference_table VARCHAR(50),
    -- Name of the table that the AI analysis is based on.
    -- Examples: ultrasounds, prenatal_checkups, lab_tests,
    -- child_details, pregnancies
    reference_id BIGINT,
    -- ID of the specific record from the reference_table
    -- that the AI analyzed
    ai_model VARCHAR(100),
    -- Name or version of the AI model used
    -- Example: Gemini 1.5, GPT-4, Custom AI model
    confidence_score DECIMAL(5, 2),
    -- Optional confidence score from AI
    -- Example: 0.92 = 92% confidence
    response TEXT NOT NULL,
    -- The full AI-generated explanation, insight,
    -- or recommendation
    response_category VARCHAR(50),
    -- Classification of AI output
    -- Examples: analysis, insight, recommendation, alert
    status VARCHAR(20) DEFAULT 'generated',
    -- Current review status of the AI response
    -- Examples: generated, edited, approved
    generated_by_ai BOOLEAN DEFAULT TRUE,
    -- Indicates if the response was generated by AI
    -- or manually created by a healthcare worker
    approved_by BIGINT REFERENCES accounts(account_id),
    -- Account ID of the midwife or admin who approved the AI output
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    -- Timestamp when the AI response was generated
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP -- Timestamp when the AI response was last updated
);
-- =====================================================
-- AI EDIT HISTORY
-- Tracks edits made to AI responses for transparency
-- =====================================================
CREATE TABLE ai_edit_history (
    ai_edit_history_id BIGSERIAL PRIMARY KEY,
    -- Unique identifier for each edit record
    ai_response_id BIGINT NOT NULL REFERENCES ai_responses(ai_response_id) ON DELETE CASCADE,
    -- The AI response that was edited
    old_content TEXT,
    -- Original AI-generated content before editing
    new_content TEXT,
    -- Updated content after editing
    edited_by BIGINT REFERENCES accounts(account_id),
    -- Account ID of the user who edited the response
    edit_reason TEXT,
    -- Optional explanation of why the AI output was edited
    -- Example: AI misinterpreted fetal heart rate
    edited_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP -- Timestamp when the edit occurred
);
-- =====================================================
-- PREGNANCY RISK ASSESSMENTS
-- Stores overall pregnancy risk classification
-- =====================================================
CREATE TABLE pregnancy_risk_assessments (
    pregnancy_risk_id BIGSERIAL PRIMARY KEY,
    -- Unique identifier for each pregnancy risk evaluation
    pregnancy_id BIGINT NOT NULL REFERENCES pregnancies(pregnancy_id) ON DELETE CASCADE,
    -- The pregnancy being evaluated
    ai_response_id BIGINT REFERENCES ai_responses(ai_response_id),
    -- Links the risk assessment to the AI response
    -- that generated the evaluation
    risk_level VARCHAR(10),
    -- Overall pregnancy risk level
    -- Examples: low, medium, high
    assessed_by_ai BOOLEAN DEFAULT TRUE,
    -- Indicates if the risk was generated by AI
    -- or manually evaluated by a midwife
    reviewed_by BIGINT REFERENCES accounts(account_id),
    -- Midwife or healthcare worker who reviewed
    -- or confirmed the AI-generated risk
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    -- Timestamp when the risk assessment was created
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP -- Timestamp when the risk assessment was last updated
);
-- =====================================================
-- PREGNANCY RISK FACTORS
-- Stores individual risk factors contributing to pregnancy risk
-- =====================================================
CREATE TABLE pregnancy_risk_factors (
    risk_factor_id BIGSERIAL PRIMARY KEY,
    -- Unique identifier for each risk factor
    pregnancy_risk_id BIGINT NOT NULL REFERENCES pregnancy_risk_assessments(pregnancy_risk_id) ON DELETE CASCADE,
    -- The pregnancy risk assessment this factor belongs to
    factor VARCHAR(255) NOT NULL,
    -- Description of the detected risk factor
    -- Example: High Blood Pressure, Low Fetal Heart Rate
    risk_influence VARCHAR(10),
    -- Level of influence this factor contributes to the overall risk
    -- Examples: low, medium, high
    source_table VARCHAR(50),
    -- Table where the factor originated
    -- Examples: prenatal_checkups, ultrasounds, lab_tests
    source_id BIGINT,
    -- Specific record ID in the source_table
    -- Example: prenatal_checkup_id or ultrasound_id
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP -- Timestamp when the risk factor was recorded
);
-- =====================================================
-- AI PROMPT LOGS
-- Stores prompts sent to the AI model for transparency
-- and reproducibility of AI-generated insights
-- =====================================================
CREATE TABLE ai_prompt_logs (
    prompt_log_id BIGSERIAL PRIMARY KEY,
    -- Unique identifier for each prompt record
    ai_response_id BIGINT REFERENCES ai_responses(ai_response_id),
    -- AI response generated from this prompt
    prompt TEXT,
    -- The full prompt sent to the AI model
    model_used VARCHAR(100),
    -- AI model used to generate the response
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP -- Timestamp when the AI prompt was executed
);
CREATE TABLE files (
    file_id BIGSERIAL PRIMARY KEY,
    -- Unique identifier for each uploaded file
    bucket_name VARCHAR(100) NOT NULL,
    -- Supabase storage bucket name
    -- Example: ultrasounds, lab-tests, child-growth, profile-photos
    file_path TEXT NOT NULL,
    -- Path inside the bucket
    -- Example: ultrasounds/12/scan_171991234.png
    file_name VARCHAR(255),
    -- Original uploaded file name
    file_category VARCHAR(50),
    -- Logical file category
    -- Examples: ultrasound_image, lab_result_image, growth_chart, profile_photo
    mime_type VARCHAR(100),
    -- File MIME type
    -- Example: image/png, image/jpeg, application/pdf
    file_size BIGINT,
    -- File size in bytes
    uploaded_by BIGINT REFERENCES accounts(account_id) ON DELETE
    SET NULL,
        -- Account that uploaded the file
        reference_type VARCHAR(50),
        -- Logical reference type
        -- Examples: ultrasound, lab_test, child, account
        reference_id BIGINT,
        -- ID of the referenced record
        processing_type VARCHAR(50),
        -- Defines what processing should be applied to this file
        -- Examples:
        -- mother_registration
        -- child_registration
        -- lab_test
        -- ultrasound_analysis
        -- profile_photo
        ai_processed BOOLEAN DEFAULT FALSE,
        -- Indicates whether the file has been analyzed by AI
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE ocr_results (
    ocr_result_id BIGSERIAL PRIMARY KEY,
    -- Unique OCR result record
    file_id BIGINT NOT NULL REFERENCES files(file_id) ON DELETE CASCADE,
    -- File that was processed with OCR
    extracted_text TEXT,
    -- Raw OCR text extracted from the image
    structured_data JSONB,
    -- Structured OCR data
    -- Example JSON:
    -- {
    --   "glucose": 135,
    --   "hemoglobin": 11.2
    -- }
    processed_by_ai BOOLEAN DEFAULT TRUE,
    -- Indicates whether OCR was performed by AI (Gemini)
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE symptom_types (
    symptom_type_id BIGSERIAL PRIMARY KEY,
    -- Standardized pregnancy symptom
    symptom_name VARCHAR(100) UNIQUE NOT NULL,
    -- Clinical classification
    risk_category VARCHAR(10) NOT NULL CHECK (risk_category IN ('normal', 'warning', 'danger')),
    -- Optional medical explanation
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE pregnancy_symptoms (
    symptom_id BIGSERIAL PRIMARY KEY,
    -- Pregnancy where symptom occurred
    pregnancy_id BIGINT NOT NULL REFERENCES pregnancies(pregnancy_id) ON DELETE CASCADE,
    -- Prenatal visit where symptom was observed
    prenatal_checkup_id BIGINT REFERENCES prenatal_checkups(prenatal_checkup_id) ON DELETE
    SET NULL,
        -- Link to standardized symptom
        symptom_type_id BIGINT NOT NULL REFERENCES symptom_types(symptom_type_id) ON DELETE RESTRICT,
        -- Optional clinical notes
        notes TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =========================
-- NOTIFICATIONS
-- =========================
CREATE TABLE notifications (
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

CREATE TABLE device_tokens (
    device_token_id BIGSERIAL PRIMARY KEY,
    account_id BIGINT NOT NULL REFERENCES accounts(account_id) ON DELETE CASCADE,
    fcm_token TEXT NOT NULL,
    platform VARCHAR(10) DEFAULT 'android' CHECK (platform IN ('android', 'ios')),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX idx_device_tokens_unique ON device_tokens(account_id, fcm_token);

-- =========================
-- CREATE INDEXES FOR PERFORMANCE
-- =========================
CREATE INDEX idx_accounts_email ON accounts(email_address);
CREATE INDEX idx_accounts_type ON accounts(account_type);
CREATE INDEX idx_mothers_account ON mothers(account_id);
CREATE INDEX idx_mothers_bhc ON mothers(assigned_bhc_id);
CREATE INDEX idx_pregnancies_mother ON pregnancies(mother_id);
CREATE INDEX idx_pregnancies_status ON pregnancies(status);
CREATE INDEX idx_pregnancy_outcomes_pregnancy ON pregnancy_outcomes(pregnancy_id);
CREATE INDEX idx_deliveries_pregnancy ON deliveries(pregnancy_id);
CREATE INDEX idx_children_mother ON children(mother_id);
CREATE INDEX idx_prenatal_pregnancy ON prenatal_checkups(pregnancy_id);
CREATE INDEX idx_immunization_child ON immunization_record(child_id);
CREATE INDEX idx_checkup_schedule_mother ON checkup_schedule(mother_id);
CREATE INDEX idx_checkup_schedule_date ON checkup_schedule(scheduled_date);
CREATE INDEX idx_files_reference ON files(reference_type, reference_id);
CREATE INDEX idx_ocr_file ON ocr_results(file_id);
CREATE INDEX idx_ai_reference ON ai_responses(reference_table, reference_id);
CREATE INDEX idx_symptoms_pregnancy ON pregnancy_symptoms(pregnancy_id);
CREATE INDEX idx_symptoms_checkup ON pregnancy_symptoms(prenatal_checkup_id);
CREATE INDEX idx_notifications_account ON notifications(account_id);
CREATE INDEX idx_notifications_unread ON notifications(account_id, is_read) WHERE is_read = FALSE;
CREATE INDEX idx_device_tokens_account ON device_tokens(account_id);
-- =========================
-- UPDATED_AT TRIGGERS
-- =========================
CREATE OR REPLACE FUNCTION update_updated_at_column() RETURNS TRIGGER AS $$ BEGIN NEW.updated_at = CURRENT_TIMESTAMP;
RETURN NEW;
END;
$$ language 'plpgsql';
DROP TRIGGER IF EXISTS update_accounts_updated_at ON accounts;
CREATE TRIGGER update_accounts_updated_at BEFORE
UPDATE ON accounts FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
DROP TRIGGER IF EXISTS update_emergency_contacts_updated_at ON emergency_contacts;
CREATE TRIGGER update_emergency_contacts_updated_at BEFORE
UPDATE ON emergency_contacts FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
DROP TRIGGER IF EXISTS update_allergies_updated_at ON allergies;
CREATE TRIGGER update_allergies_updated_at BEFORE
UPDATE ON allergies FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
DROP TRIGGER IF EXISTS update_child_details_updated_at ON child_details;
CREATE TRIGGER update_child_details_updated_at BEFORE
UPDATE ON child_details FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
DROP TRIGGER IF EXISTS update_checkup_schedule_updated_at ON checkup_schedule;
CREATE TRIGGER update_checkup_schedule_updated_at BEFORE
UPDATE ON checkup_schedule FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
DROP TRIGGER IF EXISTS update_journal_entries_updated_at ON journal_entries;
CREATE TRIGGER update_journal_entries_updated_at BEFORE
UPDATE ON journal_entries FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
DROP TRIGGER IF EXISTS update_ai_responses_updated_at ON ai_responses;
CREATE TRIGGER update_ai_responses_updated_at BEFORE
UPDATE ON ai_responses FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
DROP TRIGGER IF EXISTS update_pregnancy_risk_assessments_updated_at ON pregnancy_risk_assessments;
CREATE TRIGGER update_pregnancy_risk_assessments_updated_at BEFORE
UPDATE ON pregnancy_risk_assessments FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
DROP TRIGGER IF EXISTS update_device_tokens_updated_at ON device_tokens;
CREATE TRIGGER update_device_tokens_updated_at BEFORE
UPDATE ON device_tokens FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
-- =========================
-- NOTIFICATION TRIGGERS
-- =========================

-- Trigger: When a checkup is scheduled, notify the mother
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

-- Trigger: When a child immunization is recorded, check for next due vaccine and notify
CREATE OR REPLACE FUNCTION notify_next_vaccine_due() RETURNS TRIGGER AS $$
DECLARE
  v_mother_id BIGINT;
  v_account_id BIGINT;
  v_child_name TEXT;
  v_birthdate DATE;
  v_age_weeks INT;
  v_next_vaccine RECORD;
BEGIN
  -- Get child info (birthdate is in birth_details, not children)
  SELECT c.mother_id, c.first_name || ' ' || c.last_name, bd.birthdate
    INTO v_mother_id, v_child_name, v_birthdate
    FROM children c
    LEFT JOIN birth_details bd ON bd.child_id = c.child_id
    WHERE c.child_id = NEW.child_id;
  IF v_mother_id IS NULL THEN RETURN NEW; END IF;

  -- Get mother's account
  SELECT account_id INTO v_account_id
    FROM mothers WHERE mother_id = v_mother_id;
  IF v_account_id IS NULL OR v_birthdate IS NULL THEN RETURN NEW; END IF;

  -- Calculate child age in weeks
  v_age_weeks := (CURRENT_DATE - v_birthdate) / 7;

  -- Find next unvaccinated vaccine that is age-appropriate
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

-- Trigger: When a prenatal checkup is saved with next_schedule, auto-create checkup_schedule row
CREATE OR REPLACE FUNCTION auto_schedule_next_checkup() RETURNS TRIGGER AS $$
DECLARE
  v_mother_id BIGINT;
BEGIN
  IF NEW.next_schedule IS NULL THEN RETURN NEW; END IF;

  SELECT mother_id INTO v_mother_id
    FROM pregnancies WHERE pregnancy_id = NEW.pregnancy_id;
  IF v_mother_id IS NULL THEN RETURN NEW; END IF;

  -- Insert schedule (which will fire notify_checkup_scheduled trigger)
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

-- Trigger: Call Edge Function to send push notification
-- Uses pg_net extension (available on Supabase free tier)
CREATE OR REPLACE FUNCTION send_push_on_notification() RETURNS TRIGGER AS $$
DECLARE
  v_supabase_url TEXT := 'https://buvseyqcdacctlupznya.supabase.co';
  v_anon_key TEXT := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ1dnNleXFjZGFjY3RsdXB6bnlhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI2MzE2NTUsImV4cCI6MjA4ODIwNzY1NX0.VPh8ZZFqdeFyb8YuMxllbJJa-nWl4VXNq74o6-Itjjw';
BEGIN
  PERFORM net.http_post(
    url := v_supabase_url || '/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_anon_key
    ),
    body := jsonb_build_object(
      'notification_id', NEW.notification_id,
      'account_id', NEW.account_id,
      'title', NEW.title,
      'message', NEW.message,
      'type', NEW.type
    )
  );
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Don't fail the insert if push fails
  RAISE WARNING 'Push notification failed: %', SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_send_push_notification ON notifications;
CREATE TRIGGER trg_send_push_notification
  AFTER INSERT ON notifications
  FOR EACH ROW
  EXECUTE FUNCTION send_push_on_notification();

-- =========================
-- PG_CRON DAILY REMINDER JOBS
-- Requires the pg_cron extension (enabled by default on Supabase).
-- Run: CREATE EXTENSION IF NOT EXISTS pg_cron; in the SQL editor first.
-- =========================

-- Function: Send reminders for checkups scheduled in the next 3 days
CREATE OR REPLACE FUNCTION send_upcoming_checkup_reminders() RETURNS void AS $$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN
    SELECT cs.schedule_id,
           cs.mother_id,
           cs.scheduled_date,
           m.account_id,
           a.first_name
      FROM checkup_schedule cs
      JOIN mothers m ON m.mother_id = cs.mother_id
      JOIN accounts a ON a.account_id = m.account_id
     WHERE cs.status = 'scheduled'
       AND cs.scheduled_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '3 days'
       -- Avoid duplicate reminders: check no reminder exists for this schedule in the last 24 hours
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
      rec.account_id,
      'Checkup Reminder',
      'Hi ' || rec.first_name || ', your prenatal checkup is on ' ||
        TO_CHAR(rec.scheduled_date, 'Mon DD, YYYY') || '. Please prepare and arrive on time.',
      'checkup_reminder'
    );
  END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Function: Send reminders for overdue/upcoming vaccines based on child age
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
       -- Child has reached the recommended age (within 2-week grace window)
       AND ((CURRENT_DATE - bd.birthdate) / 30.0) >= (v.recommended_age_months - 0.5)
       -- Vaccine not yet given
       AND NOT EXISTS (
         SELECT 1 FROM immunization_record ir
          WHERE ir.child_id = c.child_id AND ir.vaccine_id = v.vaccine_id
       )
       -- No reminder sent for this vaccine in the last 7 days
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

-- Function: Mark missed checkups (scheduled date has passed without completion)
CREATE OR REPLACE FUNCTION mark_missed_checkups() RETURNS void AS $$
BEGIN
  UPDATE checkup_schedule
     SET status = 'missed'
   WHERE status = 'scheduled'
     AND scheduled_date < CURRENT_DATE;
END;
$$ LANGUAGE plpgsql;

-- Schedule the cron jobs (runs daily at 8:00 AM Philippine Time = 00:00 UTC)
-- NOTE: Run these in the Supabase SQL editor after enabling pg_cron.
-- SELECT cron.schedule('daily-checkup-reminders',  '0 0 * * *', 'SELECT send_upcoming_checkup_reminders()');
-- SELECT cron.schedule('daily-vaccine-reminders',   '0 0 * * *', 'SELECT send_vaccine_due_reminders()');
-- SELECT cron.schedule('daily-mark-missed-checkups','5 0 * * *', 'SELECT mark_missed_checkups()');

-- =========================
-- RLS FIX
-- The app uses the anon key with custom authentication (not Supabase Auth).
-- Disable RLS on tables that the midwife inserts into so the anon key
-- is not blocked by row-level security policies.
-- Run these statements in the Supabase SQL editor if you see
-- "new row violates row-level security policy" errors.
-- =========================
ALTER TABLE emergency_contacts DISABLE ROW LEVEL SECURITY;
ALTER TABLE medical_conditions DISABLE ROW LEVEL SECURITY;
ALTER TABLE allergies DISABLE ROW LEVEL SECURITY;
ALTER TABLE mothers DISABLE ROW LEVEL SECURITY;
ALTER TABLE pregnancies DISABLE ROW LEVEL SECURITY;
ALTER TABLE pregnancy_outcomes DISABLE ROW LEVEL SECURITY;
ALTER TABLE deliveries DISABLE ROW LEVEL SECURITY;
ALTER TABLE prenatal_checkups DISABLE ROW LEVEL SECURITY;
ALTER TABLE mother_medications DISABLE ROW LEVEL SECURITY;
ALTER TABLE given_medications DISABLE ROW LEVEL SECURITY;
ALTER TABLE ultrasounds DISABLE ROW LEVEL SECURITY;
ALTER TABLE lab_tests DISABLE ROW LEVEL SECURITY;
ALTER TABLE files DISABLE ROW LEVEL SECURITY;
ALTER TABLE pregnancy_symptoms DISABLE ROW LEVEL SECURITY;
ALTER TABLE symptom_types DISABLE ROW LEVEL SECURITY;
ALTER TABLE ai_responses DISABLE ROW LEVEL SECURITY;
ALTER TABLE ai_edit_history DISABLE ROW LEVEL SECURITY;
ALTER TABLE pregnancy_risk_assessments DISABLE ROW LEVEL SECURITY;
ALTER TABLE pregnancy_risk_factors DISABLE ROW LEVEL SECURITY;
ALTER TABLE notifications DISABLE ROW LEVEL SECURITY;
ALTER TABLE device_tokens DISABLE ROW LEVEL SECURITY;
ALTER TABLE checkup_schedule DISABLE ROW LEVEL SECURITY;

-- =========================
-- WEIGHT GAIN EVALUATIONS
-- Stores per-checkup maternal weight gain analysis results
-- =========================
CREATE TABLE weight_gain_evaluations (
    evaluation_id BIGSERIAL PRIMARY KEY,
    pregnancy_id BIGINT NOT NULL REFERENCES pregnancies(pregnancy_id) ON DELETE CASCADE,
    prenatal_checkup_id BIGINT REFERENCES prenatal_checkups(prenatal_checkup_id) ON DELETE CASCADE,
    mode VARCHAR(10) NOT NULL CHECK (mode IN ('FULL', 'TREND')),
    bmi_category VARCHAR(20),
    baseline_weight DECIMAL(5, 2),
    baseline_week DECIMAL(4, 1),
    current_weight DECIMAL(5, 2),
    current_week DECIMAL(4, 1),
    expected_gain DECIMAL(5, 2),
    actual_gain DECIMAL(5, 2),
    weekly_gain DECIMAL(5, 3),
    status VARCHAR(20) NOT NULL CHECK (status IN ('NORMAL', 'LOW', 'HIGH', 'INSUFFICIENT DATA')),
    confidence VARCHAR(10) NOT NULL CHECK (confidence IN ('HIGH', 'MEDIUM', 'LOW')),
    message TEXT,
    flags TEXT[],
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_wge_pregnancy ON weight_gain_evaluations(pregnancy_id);
CREATE INDEX idx_wge_checkup ON weight_gain_evaluations(prenatal_checkup_id);
ALTER TABLE weight_gain_evaluations DISABLE ROW LEVEL SECURITY;

-- TO DO: 
-- 1. Separate outcomes from pregnancies table, 
-- 2. Modify pregnancy table to remove outcome-related columns
-- 3. Modify pregnancy table to track fetal count
-- 4. Fetal count must be changeable to adapt cases such as vanishing twin or fetal loss. Reasons are needed for changing.
-- 5. Deliveries and outcomes must adapt to multiple fetuses

-- =====================================================
-- MIGRATION SCRIPT (ALTER STATEMENTS)
-- Use these to update an already running database instead of dropping and recreating
-- =====================================================
/*
-- 1. Create pregnancy_outcomes table to separate outcomes
CREATE TABLE pregnancy_outcomes (
    outcome_id BIGSERIAL PRIMARY KEY,
    pregnancy_id BIGINT NOT NULL REFERENCES pregnancies(pregnancy_id) ON DELETE CASCADE,
    fetus_number INT DEFAULT 1,
    outcome VARCHAR(20) CHECK (
        outcome IN (
            'live_birth',
            'stillbirth',
            'miscarriage',
            'abortion',
            'ectopic',
            'fetal_loss',
            'vanishing_twin'
        )
    ),
    outcome_date DATE,
    is_outcome_date_estimated BOOLEAN DEFAULT FALSE,
    gestational_age_at_end DECIMAL(4, 1),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- (Optional) Copy existing outcome data securely before dropping
-- INSERT INTO pregnancy_outcomes (pregnancy_id, outcome, outcome_date, is_outcome_date_estimated, gestational_age_at_end) 
-- SELECT pregnancy_id, outcome, outcome_date, is_outcome_date_estimated, gestational_age_at_end FROM pregnancies WHERE outcome IS NOT NULL;

-- 2. Modify pregnancies table to track fetal count and remove old columns
ALTER TABLE pregnancies ADD COLUMN fetal_count INT DEFAULT 1;

ALTER TABLE pregnancies
    DROP COLUMN outcome,
    DROP COLUMN outcome_date,
    DROP COLUMN is_outcome_date_estimated;

-- 3. Modify deliveries table to adapt to multiple fetuses
ALTER TABLE deliveries DROP CONSTRAINT IF EXISTS deliveries_pregnancy_id_key;
ALTER TABLE deliveries ADD COLUMN fetus_number INT DEFAULT 1;

-- 4. Create indexes and disable RLS for the new tables
CREATE INDEX idx_pregnancy_outcomes_pregnancy ON pregnancy_outcomes(pregnancy_id);
ALTER TABLE pregnancy_outcomes DISABLE ROW LEVEL SECURITY;

-- 5. Add pre_pregnancy_weight to pregnancies table (per-pregnancy baseline)
ALTER TABLE pregnancies ADD COLUMN IF NOT EXISTS pre_pregnancy_weight DECIMAL(5, 2);

-- 6. Create weight_gain_evaluations table
CREATE TABLE IF NOT EXISTS weight_gain_evaluations (
    evaluation_id BIGSERIAL PRIMARY KEY,
    pregnancy_id BIGINT NOT NULL REFERENCES pregnancies(pregnancy_id) ON DELETE CASCADE,
    prenatal_checkup_id BIGINT REFERENCES prenatal_checkups(prenatal_checkup_id) ON DELETE CASCADE,
    mode VARCHAR(10) NOT NULL CHECK (mode IN ('FULL', 'TREND')),
    bmi_category VARCHAR(20),
    baseline_weight DECIMAL(5, 2),
    baseline_week DECIMAL(4, 1),
    current_weight DECIMAL(5, 2),
    current_week DECIMAL(4, 1),
    expected_gain DECIMAL(5, 2),
    actual_gain DECIMAL(5, 2),
    weekly_gain DECIMAL(5, 3),
    status VARCHAR(20) NOT NULL CHECK (status IN ('NORMAL', 'LOW', 'HIGH', 'INSUFFICIENT DATA')),
    confidence VARCHAR(10) NOT NULL CHECK (confidence IN ('HIGH', 'MEDIUM', 'LOW')),
    message TEXT,
    flags TEXT[],
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_wge_pregnancy ON weight_gain_evaluations(pregnancy_id);
CREATE INDEX IF NOT EXISTS idx_wge_checkup ON weight_gain_evaluations(prenatal_checkup_id);
ALTER TABLE weight_gain_evaluations DISABLE ROW LEVEL SECURITY;
*/

-- =====================================================
-- ROLLBACK SCRIPT (UNDO ALTER STATEMENTS)
-- Use these to revert the database to its previous state
-- =====================================================
/*
-- 1. Restore deliveries table constraints and remove new column
ALTER TABLE deliveries DROP COLUMN IF EXISTS fetus_number;
ALTER TABLE deliveries ADD CONSTRAINT deliveries_pregnancy_id_key UNIQUE (pregnancy_id);

-- 2. Restore old columns to pregnancies table and remove new column
ALTER TABLE pregnancies
    ADD COLUMN outcome VARCHAR(20) CHECK (
        outcome IN (
            'live_birth',
            'stillbirth',
            'miscarriage',
            'abortion',
            'ectopic'
        )
    ),
    ADD COLUMN outcome_date DATE,
    ADD COLUMN is_outcome_date_estimated BOOLEAN DEFAULT FALSE;

ALTER TABLE pregnancies DROP COLUMN IF EXISTS fetal_count;

-- 3. Drop the new pregnancy_outcomes table (this automatically drops its index and RLS rule)
DROP TABLE IF EXISTS pregnancy_outcomes CASCADE;
*/

-- ============================================================
-- DAY-BEFORE CHECKUP SMS REMINDER (pg_cron)
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
-- InaAgapay inventory distribution workflow
--
-- Adds structured BHC stock requests and RHU -> BHC transfers. Stock is
-- deducted from RHU when issued, but is not credited to the BHC until a
-- midwife confirms receipt through receive_inventory_transfer().
--
-- CAPSTONE/DEMO AUTH NOTE: the existing applications use a custom accounts
-- login over the public anon client instead of Supabase Auth. These RPCs match
-- that existing model by validating the supplied active account and role, but
-- the account id is not a production-grade authorization credential. Before a
-- real deployment, migrate accounts to Supabase Auth, enable RLS, derive the
-- actor from auth.uid(), and remove anon access to sensitive account data.

BEGIN;

-- The inventory page already renders "transfer" movements, but the original
-- database check constraint did not allow the value.
ALTER TABLE public.inventory_transactions
  DROP CONSTRAINT IF EXISTS inventory_transactions_transaction_type_check;

ALTER TABLE public.inventory_transactions
  ADD CONSTRAINT inventory_transactions_transaction_type_check
  CHECK (
    transaction_type IN (
      'receipt',
      'dispense',
      'adjustment',
      'expiry_disposal',
      'transfer'
    )
  );

CREATE TABLE IF NOT EXISTS public.inventory_stock_requests (
  request_id BIGSERIAL PRIMARY KEY,
  facility_id BIGINT NOT NULL
    REFERENCES public.health_facilities(facility_id) ON DELETE RESTRICT,
  item_id BIGINT NOT NULL
    REFERENCES public.inventory_items(item_id) ON DELETE RESTRICT,
  requested_quantity INTEGER NOT NULL CHECK (requested_quantity > 0),
  reason TEXT NOT NULL CHECK (btrim(reason) <> ''),
  remarks TEXT,
  status VARCHAR(20) NOT NULL DEFAULT 'pending'
    CHECK (
      status IN (
        'pending',
        'approved',
        'rejected',
        'issued',
        'received',
        'completed',
        'cancelled'
      )
    ),
  requested_by BIGINT NOT NULL
    REFERENCES public.accounts(account_id) ON DELETE RESTRICT,
  reviewed_by BIGINT
    REFERENCES public.accounts(account_id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ,
  admin_remarks TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.inventory_transfers (
  transfer_id BIGSERIAL PRIMARY KEY,
  request_id BIGINT UNIQUE
    REFERENCES public.inventory_stock_requests(request_id) ON DELETE SET NULL,
  source_batch_id BIGINT NOT NULL
    REFERENCES public.inventory_batches(batch_id) ON DELETE RESTRICT,
  destination_facility_id BIGINT NOT NULL
    REFERENCES public.health_facilities(facility_id) ON DELETE RESTRICT,
  quantity_issued INTEGER NOT NULL CHECK (quantity_issued > 0),
  status VARCHAR(24) NOT NULL DEFAULT 'pending_receipt'
    CHECK (status IN ('pending_receipt', 'received', 'cancelled')),
  remarks TEXT,
  issued_by BIGINT NOT NULL
    REFERENCES public.accounts(account_id) ON DELETE RESTRICT,
  issued_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  received_by BIGINT
    REFERENCES public.accounts(account_id) ON DELETE SET NULL,
  received_at TIMESTAMPTZ,
  destination_batch_id BIGINT
    REFERENCES public.inventory_batches(batch_id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_inventory_stock_requests_facility_status
  ON public.inventory_stock_requests(facility_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_inventory_stock_requests_item
  ON public.inventory_stock_requests(item_id);
CREATE INDEX IF NOT EXISTS idx_inventory_stock_requests_requested_by
  ON public.inventory_stock_requests(requested_by, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_inventory_transfers_destination_status
  ON public.inventory_transfers(destination_facility_id, status, issued_at DESC);
CREATE INDEX IF NOT EXISTS idx_inventory_transfers_source_batch
  ON public.inventory_transfers(source_batch_id);

CREATE OR REPLACE FUNCTION public.inventory_touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_inventory_stock_requests_updated_at
  ON public.inventory_stock_requests;
CREATE TRIGGER trg_inventory_stock_requests_updated_at
BEFORE UPDATE ON public.inventory_stock_requests
FOR EACH ROW EXECUTE FUNCTION public.inventory_touch_updated_at();

DROP TRIGGER IF EXISTS trg_inventory_transfers_updated_at
  ON public.inventory_transfers;
CREATE TRIGGER trg_inventory_transfers_updated_at
BEFORE UPDATE ON public.inventory_transfers
FOR EACH ROW EXECUTE FUNCTION public.inventory_touch_updated_at();

-- Midwife assignments and inventory batches use the same canonical
-- health_facilities identifier.
CREATE OR REPLACE FUNCTION public.inventory_midwife_facility_id(
  p_account_id BIGINT
)
RETURNS BIGINT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_facility_id BIGINT;
BEGIN
  SELECT hf.facility_id
    INTO v_facility_id
  FROM public.accounts a
  JOIN public.midwives m ON m.account_id = a.account_id
  JOIN public.health_facilities hf ON hf.facility_id = m.assigned_bhc_id
  WHERE a.account_id = p_account_id
    AND a.account_type = 'midwife'
    AND a.status = 'active'
    AND hf.facility_type = 'BHC'
  ORDER BY hf.facility_id
  LIMIT 1;

  RETURN v_facility_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.inventory_assert_actor(
  p_account_id BIGINT,
  p_required_role TEXT
)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.accounts
    WHERE account_id = p_account_id
      AND account_type = p_required_role
      AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'Active % account required', p_required_role
      USING ERRCODE = '42501';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_inventory_stock_request(
  p_requested_by BIGINT,
  p_item_id BIGINT,
  p_requested_quantity INTEGER,
  p_reason TEXT,
  p_remarks TEXT DEFAULT NULL
)
RETURNS public.inventory_stock_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_facility_id BIGINT;
  v_request public.inventory_stock_requests%ROWTYPE;
  v_item_name TEXT;
BEGIN
  PERFORM public.inventory_assert_actor(p_requested_by, 'midwife');

  v_facility_id := public.inventory_midwife_facility_id(p_requested_by);
  IF v_facility_id IS NULL THEN
    RAISE EXCEPTION 'Midwife has no valid BHC inventory assignment'
      USING ERRCODE = '23503';
  END IF;

  IF p_requested_quantity IS NULL OR p_requested_quantity <= 0 THEN
    RAISE EXCEPTION 'Requested quantity must be greater than zero'
      USING ERRCODE = '22023';
  END IF;

  IF p_reason IS NULL OR btrim(p_reason) = '' THEN
    RAISE EXCEPTION 'Request reason is required'
      USING ERRCODE = '22023';
  END IF;

  SELECT name INTO v_item_name
  FROM public.inventory_items
  WHERE item_id = p_item_id;

  IF v_item_name IS NULL THEN
    RAISE EXCEPTION 'Inventory item not found'
      USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO public.inventory_stock_requests (
    facility_id,
    item_id,
    requested_quantity,
    reason,
    remarks,
    status,
    requested_by
  ) VALUES (
    v_facility_id,
    p_item_id,
    p_requested_quantity,
    btrim(p_reason),
    nullif(btrim(coalesce(p_remarks, '')), ''),
    'pending',
    p_requested_by
  )
  RETURNING * INTO v_request;

  INSERT INTO public.notifications (account_id, title, message, type)
  SELECT
    account_id,
    'New stock request',
    format('%s requested %s units of %s.',
      (SELECT name FROM public.health_facilities WHERE facility_id = v_facility_id),
      p_requested_quantity,
      v_item_name),
    'general'
  FROM public.accounts
  WHERE account_type = 'admin' AND status = 'active';

  INSERT INTO public.audit_trail (
    account_id,
    action,
    table_name,
    description,
    new_data
  ) VALUES (
    p_requested_by,
    'submit_inventory_stock_request',
    'inventory_stock_requests',
    format('Submitted stock request #%s for %s units of "%s"',
      v_request.request_id, p_requested_quantity, v_item_name),
    to_jsonb(v_request)
  );

  RETURN v_request;
END;
$$;

CREATE OR REPLACE FUNCTION public.approve_inventory_stock_request(
  p_request_id BIGINT,
  p_admin_id BIGINT,
  p_admin_remarks TEXT DEFAULT NULL
)
RETURNS public.inventory_stock_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request public.inventory_stock_requests%ROWTYPE;
BEGIN
  PERFORM public.inventory_assert_actor(p_admin_id, 'admin');

  SELECT * INTO v_request
  FROM public.inventory_stock_requests
  WHERE request_id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Stock request not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_request.status <> 'pending' THEN
    RAISE EXCEPTION 'Only pending requests can be approved'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.inventory_stock_requests
  SET status = 'approved',
      reviewed_by = p_admin_id,
      reviewed_at = now(),
      admin_remarks = nullif(btrim(coalesce(p_admin_remarks, '')), '')
  WHERE request_id = p_request_id
  RETURNING * INTO v_request;

  INSERT INTO public.notifications (account_id, title, message, type)
  VALUES (
    v_request.requested_by,
    'Stock request approved',
    format('Your stock request #%s was approved by RHU Main.', p_request_id),
    'general'
  );

  RETURN v_request;
END;
$$;

CREATE OR REPLACE FUNCTION public.reject_inventory_stock_request(
  p_request_id BIGINT,
  p_admin_id BIGINT,
  p_admin_remarks TEXT DEFAULT NULL
)
RETURNS public.inventory_stock_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request public.inventory_stock_requests%ROWTYPE;
BEGIN
  PERFORM public.inventory_assert_actor(p_admin_id, 'admin');

  SELECT * INTO v_request
  FROM public.inventory_stock_requests
  WHERE request_id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Stock request not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_request.status NOT IN ('pending', 'approved') THEN
    RAISE EXCEPTION 'This request can no longer be rejected'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.inventory_stock_requests
  SET status = 'rejected',
      reviewed_by = p_admin_id,
      reviewed_at = now(),
      admin_remarks = nullif(btrim(coalesce(p_admin_remarks, '')), '')
  WHERE request_id = p_request_id
  RETURNING * INTO v_request;

  INSERT INTO public.notifications (account_id, title, message, type)
  VALUES (
    v_request.requested_by,
    'Stock request update',
    format('Your stock request #%s was not approved.%s',
      p_request_id,
      CASE
        WHEN v_request.admin_remarks IS NULL THEN ''
        ELSE ' ' || v_request.admin_remarks
      END),
    'general'
  );

  RETURN v_request;
END;
$$;

CREATE OR REPLACE FUNCTION public.issue_inventory_transfer(
  p_source_batch_id BIGINT,
  p_destination_facility_id BIGINT,
  p_quantity INTEGER,
  p_issued_by BIGINT,
  p_request_id BIGINT DEFAULT NULL,
  p_remarks TEXT DEFAULT NULL
)
RETURNS public.inventory_transfers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_source public.inventory_batches%ROWTYPE;
  v_request public.inventory_stock_requests%ROWTYPE;
  v_transfer public.inventory_transfers%ROWTYPE;
  v_item_name TEXT;
  v_facility_name TEXT;
BEGIN
  PERFORM public.inventory_assert_actor(p_issued_by, 'admin');

  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'Issue quantity must be greater than zero'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_source
  FROM public.inventory_batches
  WHERE batch_id = p_source_batch_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Source batch not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_source.facility_id IS NOT NULL THEN
    RAISE EXCEPTION 'Stock can only be issued from the central warehouse'
      USING ERRCODE = '22023';
  END IF;
  IF v_source.status <> 'active' OR v_source.expiration_date < CURRENT_DATE THEN
    RAISE EXCEPTION 'Source batch is not active and usable'
      USING ERRCODE = '22023';
  END IF;
  IF v_source.quantity_remaining < p_quantity THEN
    RAISE EXCEPTION 'Insufficient central stock: only % available',
      v_source.quantity_remaining USING ERRCODE = '22023';
  END IF;

  SELECT name INTO v_facility_name
  FROM public.health_facilities
  WHERE facility_id = p_destination_facility_id
    AND facility_type = 'BHC';
  IF v_facility_name IS NULL THEN
    RAISE EXCEPTION 'Destination BHC not found' USING ERRCODE = '23503';
  END IF;

  IF p_request_id IS NOT NULL THEN
    SELECT * INTO v_request
    FROM public.inventory_stock_requests
    WHERE request_id = p_request_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Linked stock request not found' USING ERRCODE = 'P0002';
    END IF;
    IF v_request.status <> 'approved' THEN
      RAISE EXCEPTION 'Only approved requests can be issued'
        USING ERRCODE = '22023';
    END IF;
    IF v_request.facility_id <> p_destination_facility_id
       OR v_request.item_id <> v_source.item_id THEN
      RAISE EXCEPTION 'Batch item or destination does not match the stock request'
        USING ERRCODE = '22023';
    END IF;
    IF p_quantity <> v_request.requested_quantity THEN
      RAISE EXCEPTION 'A linked request must be issued in its full requested quantity (%)',
        v_request.requested_quantity
        USING ERRCODE = '22023';
    END IF;
  END IF;

  INSERT INTO public.inventory_transfers (
    request_id,
    source_batch_id,
    destination_facility_id,
    quantity_issued,
    status,
    remarks,
    issued_by
  ) VALUES (
    p_request_id,
    p_source_batch_id,
    p_destination_facility_id,
    p_quantity,
    'pending_receipt',
    nullif(btrim(coalesce(p_remarks, '')), ''),
    p_issued_by
  )
  RETURNING * INTO v_transfer;

  UPDATE public.inventory_batches
  SET quantity_remaining = quantity_remaining - p_quantity
  WHERE batch_id = p_source_batch_id;

  SELECT name INTO v_item_name
  FROM public.inventory_items
  WHERE item_id = v_source.item_id;

  INSERT INTO public.inventory_transactions (
    batch_id,
    facility_id,
    transaction_type,
    quantity,
    reference_type,
    reference_id,
    performed_by
  ) VALUES (
    p_source_batch_id,
    NULL,
    'transfer',
    -p_quantity,
    'Issued to ' || v_facility_name || ' — pending receipt',
    v_transfer.transfer_id,
    p_issued_by
  );

  IF p_request_id IS NOT NULL THEN
    UPDATE public.inventory_stock_requests
    SET status = 'issued'
    WHERE request_id = p_request_id;
  END IF;

  INSERT INTO public.notifications (account_id, title, message, type)
  SELECT
    m.account_id,
    'Incoming stocks from RHU Main',
    format('%s units of %s are waiting for your receipt confirmation.',
      p_quantity, v_item_name),
    'general'
  FROM public.midwives m
  JOIN public.health_facilities hf ON hf.facility_id = m.assigned_bhc_id
  JOIN public.accounts a ON a.account_id = m.account_id
  WHERE hf.facility_id = p_destination_facility_id
    AND a.status = 'active';

  INSERT INTO public.audit_trail (
    account_id,
    action,
    table_name,
    description,
    new_data
  ) VALUES (
    p_issued_by,
    'issue_inventory_transfer',
    'inventory_transfers',
    format('Issued %s units of "%s" to %s; pending receipt',
      p_quantity, v_item_name, v_facility_name),
    to_jsonb(v_transfer)
  );

  RETURN v_transfer;
END;
$$;

CREATE OR REPLACE FUNCTION public.receive_inventory_transfer(
  p_transfer_id BIGINT,
  p_received_by BIGINT
)
RETURNS public.inventory_transfers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_transfer public.inventory_transfers%ROWTYPE;
  v_source public.inventory_batches%ROWTYPE;
  v_destination_batch_id BIGINT;
  v_midwife_facility_id BIGINT;
  v_item_name TEXT;
  v_facility_name TEXT;
BEGIN
  PERFORM public.inventory_assert_actor(p_received_by, 'midwife');
  v_midwife_facility_id := public.inventory_midwife_facility_id(p_received_by);

  SELECT * INTO v_transfer
  FROM public.inventory_transfers
  WHERE transfer_id = p_transfer_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Inventory transfer not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_midwife_facility_id IS NULL
     OR v_transfer.destination_facility_id <> v_midwife_facility_id THEN
    RAISE EXCEPTION 'This transfer belongs to another BHC'
      USING ERRCODE = '42501';
  END IF;

  -- Safe retry for a slow network or accidental double tap.
  IF v_transfer.status = 'received' THEN
    RETURN v_transfer;
  END IF;
  IF v_transfer.status <> 'pending_receipt' THEN
    RAISE EXCEPTION 'Transfer cannot be received in its current status'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_source
  FROM public.inventory_batches
  WHERE batch_id = v_transfer.source_batch_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transfer source batch no longer exists'
      USING ERRCODE = 'P0002';
  END IF;
  IF v_source.expiration_date < CURRENT_DATE THEN
    RAISE EXCEPTION 'The issued batch expired before receipt; contact RHU Main for resolution'
      USING ERRCODE = '22023';
  END IF;

  -- Serialize receipts for the same item/batch/facility so concurrent taps or
  -- multiple devices cannot create duplicate destination batches.
  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      v_source.item_id::text || ':' ||
      v_transfer.destination_facility_id::text || ':' ||
      v_source.batch_number,
      0
    )
  );

  SELECT batch_id INTO v_destination_batch_id
  FROM public.inventory_batches
  WHERE item_id = v_source.item_id
    AND facility_id = v_transfer.destination_facility_id
    AND batch_number = v_source.batch_number
    AND status = 'active'
  ORDER BY batch_id
  LIMIT 1
  FOR UPDATE;

  IF v_destination_batch_id IS NULL THEN
    INSERT INTO public.inventory_batches (
      item_id,
      facility_id,
      batch_number,
      quantity_received,
      quantity_remaining,
      received_date,
      expiration_date,
      manufacturer,
      status
    ) VALUES (
      v_source.item_id,
      v_transfer.destination_facility_id,
      v_source.batch_number,
      v_transfer.quantity_issued,
      v_transfer.quantity_issued,
      CURRENT_DATE,
      v_source.expiration_date,
      v_source.manufacturer,
      'active'
    )
    RETURNING batch_id INTO v_destination_batch_id;
  ELSE
    UPDATE public.inventory_batches
    SET quantity_received = quantity_received + v_transfer.quantity_issued,
        quantity_remaining = quantity_remaining + v_transfer.quantity_issued
    WHERE batch_id = v_destination_batch_id;
  END IF;

  INSERT INTO public.inventory_transactions (
    batch_id,
    facility_id,
    transaction_type,
    quantity,
    reference_type,
    reference_id,
    performed_by
  ) VALUES (
    v_destination_batch_id,
    v_transfer.destination_facility_id,
    'transfer',
    v_transfer.quantity_issued,
    'Received from RHU Main',
    v_transfer.transfer_id,
    p_received_by
  );

  UPDATE public.inventory_transfers
  SET status = 'received',
      received_by = p_received_by,
      received_at = now(),
      destination_batch_id = v_destination_batch_id
  WHERE transfer_id = p_transfer_id
  RETURNING * INTO v_transfer;

  IF v_transfer.request_id IS NOT NULL THEN
    UPDATE public.inventory_stock_requests
    SET status = 'received'
    WHERE request_id = v_transfer.request_id;
  END IF;

  SELECT i.name, hf.name
    INTO v_item_name, v_facility_name
  FROM public.inventory_items i
  CROSS JOIN public.health_facilities hf
  WHERE i.item_id = v_source.item_id
    AND hf.facility_id = v_transfer.destination_facility_id;

  INSERT INTO public.notifications (account_id, title, message, type)
  SELECT
    account_id,
    'BHC received issued stocks',
    format('%s confirmed receipt of %s units of %s.',
      v_facility_name, v_transfer.quantity_issued, v_item_name),
    'general'
  FROM public.accounts
  WHERE account_type = 'admin' AND status = 'active';

  INSERT INTO public.audit_trail (
    account_id,
    action,
    table_name,
    description,
    new_data
  ) VALUES (
    p_received_by,
    'receive_inventory_transfer',
    'inventory_transfers',
    format('%s received transfer #%s (%s units of "%s")',
      v_facility_name, p_transfer_id, v_transfer.quantity_issued, v_item_name),
    to_jsonb(v_transfer)
  );

  RETURN v_transfer;
END;
$$;

-- This project currently uses its own accounts/password login over the anon
-- Supabase client rather than Supabase Auth. Keep these two tables compatible
-- with that existing model and expose writes only through the RPCs above.
ALTER TABLE public.inventory_stock_requests DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_transfers DISABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.inventory_stock_requests FROM anon, authenticated;
REVOKE ALL ON public.inventory_transfers FROM anon, authenticated;
GRANT SELECT ON public.inventory_stock_requests TO anon, authenticated;
GRANT SELECT ON public.inventory_transfers TO anon, authenticated;

REVOKE ALL ON FUNCTION public.inventory_midwife_facility_id(BIGINT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.inventory_assert_actor(BIGINT, TEXT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.submit_inventory_stock_request(
  BIGINT, BIGINT, INTEGER, TEXT, TEXT
) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.approve_inventory_stock_request(
  BIGINT, BIGINT, TEXT
) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reject_inventory_stock_request(
  BIGINT, BIGINT, TEXT
) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.issue_inventory_transfer(
  BIGINT, BIGINT, INTEGER, BIGINT, BIGINT, TEXT
) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.receive_inventory_transfer(
  BIGINT, BIGINT
) TO anon, authenticated;

COMMIT;
