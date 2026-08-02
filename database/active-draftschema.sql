-- ============================================================
-- SUPABASE MATERNAL HEALTH SYSTEM - COMPLETE SCHEMA
-- ============================================================
-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
-- ============================================================
-- 1. CORE: FACILITIES & USER MANAGEMENT
-- ============================================================
-- Health Facilities (BHCs, RHUs, Hospitals)
CREATE TABLE public.health_facilities (
    facility_id BIGSERIAL PRIMARY KEY,
    name character varying NOT NULL UNIQUE,
    facility_type character varying NOT NULL DEFAULT 'BHC' CHECK (
        facility_type = ANY (
            ARRAY ['BHC', 'RHU', 'District Hospital', 'Clinic', 'General Hospital']
        )
    ),
    address_street character varying,
    barangay character varying NOT NULL,
    municipality character varying NOT NULL DEFAULT 'Santa Cruz',
    province character varying NOT NULL DEFAULT 'Laguna',
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- Accounts (unified user accounts)
CREATE TABLE public.accounts (
    account_id BIGSERIAL PRIMARY KEY,
    auth_id UUID REFERENCES auth.users(id) ON DELETE
    SET NULL,
        is_verified boolean DEFAULT false,
        status character varying DEFAULT 'active' CHECK (
            status = ANY (ARRAY ['active', 'inactive', 'suspended'])
        ),
        email_address character varying UNIQUE,
        password_hash character varying,
        account_type character varying NOT NULL CHECK (
            account_type = ANY (ARRAY ['admin', 'midwife', 'mother'])
        ),
        first_name character varying,
        middle_name character varying,
        last_name character varying,
        extension_name character varying,
        phone_number character varying UNIQUE,
        verification_code character varying,
        verification_expires timestamp without time zone,
        reset_code character varying,
        reset_expires timestamp without time zone,
        last_login_token character varying,
        last_login_at timestamp without time zone,
        created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
        updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
        is_temporary_password boolean DEFAULT false,
        created_by character varying DEFAULT 'self'
);
-- Password History
CREATE TABLE public.password_history (
    pass_history_id BIGSERIAL PRIMARY KEY,
    account_id bigint NOT NULL REFERENCES public.accounts(account_id) ON DELETE CASCADE,
    password character varying NOT NULL,
    replaced_at timestamp without time zone,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- Facility Assignments
CREATE TABLE public.facility_assignments (
    facility_assignment_id BIGSERIAL PRIMARY KEY,
    account_id bigint NOT NULL REFERENCES public.accounts(account_id) ON DELETE CASCADE,
    facility_id bigint NOT NULL REFERENCES public.health_facilities(facility_id) ON DELETE RESTRICT,
    patient_number integer,
    is_active boolean DEFAULT true,
    assigned_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    ended_at timestamp without time zone
);
-- Partial unique index: patient_number unique per facility (only for mothers)
CREATE UNIQUE INDEX unique_patient_number_per_facility ON facility_assignments (facility_id, patient_number)
WHERE patient_number IS NOT NULL;
-- Patient number auto-assign trigger
CREATE OR REPLACE FUNCTION set_patient_number() RETURNS TRIGGER AS $$ BEGIN IF EXISTS (
        SELECT 1
        FROM accounts
        WHERE account_id = NEW.account_id
            AND account_type = 'mother'
    ) THEN NEW.patient_number := (
        SELECT COALESCE(MAX(patient_number), 0) + 1
        FROM facility_assignments
        WHERE facility_id = NEW.facility_id
            AND patient_number IS NOT NULL
    );
END IF;
RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER trg_facility_assignments_patient_number BEFORE
INSERT ON facility_assignments FOR EACH ROW EXECUTE FUNCTION set_patient_number();
-- ============================================================
-- 2. ROLE-SPECIFIC PROFILES
-- ============================================================
-- Midwives
CREATE TABLE public.midwives (
    midwife_id BIGSERIAL PRIMARY KEY,
    account_id bigint NOT NULL UNIQUE REFERENCES public.accounts(account_id) ON DELETE CASCADE,
    license_number character varying UNIQUE,
    position character varying,
    hire_date date
);
-- Mothers
CREATE TABLE public.mothers (
    mother_id BIGSERIAL PRIMARY KEY,
    account_id bigint NOT NULL UNIQUE REFERENCES public.accounts(account_id) ON DELETE CASCADE,
    birthdate date,
    house_number character varying,
    street character varying,
    barangay character varying,
    city_municipality character varying,
    province character varying,
    height numeric,
    weight numeric,
    blood_type character varying CHECK (
        blood_type = ANY (
            ARRAY ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']
        )
    ),
    status character varying DEFAULT 'active' CHECK (status = ANY (ARRAY ['active', 'inactive'])),
    gravida integer DEFAULT 0,
    para integer DEFAULT 0,
    abortus integer DEFAULT 0,
    living_children integer DEFAULT 0,
    philhealth_number character varying,
    philhealth_status character varying DEFAULT 'Non-Member' CHECK (
        philhealth_status = ANY (ARRAY ['Member', 'Dependent', 'Non-Member'])
    ),
    is_four_ps boolean DEFAULT false,
    civil_status character varying CHECK (
        civil_status = ANY (
            ARRAY ['Single', 'Married', 'Widowed', 'Separated', 'Cohabiting']
        )
    )
);
-- Guardians
CREATE TABLE public.guardians (
    guardian_id BIGSERIAL PRIMARY KEY,
    first_name character varying NOT NULL,
    last_name character varying NOT NULL,
    middle_name character varying,
    extension_name character varying,
    phone_number character varying,
    address text,
    relationship character varying,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- Emergency Contacts
CREATE TABLE public.emergency_contacts (
    emergency_contact_id BIGSERIAL PRIMARY KEY,
    mother_id bigint NOT NULL REFERENCES public.mothers(mother_id) ON DELETE CASCADE,
    first_name character varying,
    last_name character varying,
    middle_name character varying,
    extension_name character varying,
    phone_number character varying,
    affiliation character varying,
    email_address character varying,
    house_number character varying,
    street character varying,
    barangay character varying,
    city_municipality character varying,
    province character varying,
    status character varying DEFAULT 'active' CHECK (status = ANY (ARRAY ['active', 'inactive'])),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- ============================================================
-- 3. MEDICAL HISTORY
-- ============================================================
-- Medical Conditions
CREATE TABLE public.medical_conditions (
    med_condition_id BIGSERIAL PRIMARY KEY,
    mother_id bigint NOT NULL REFERENCES public.mothers(mother_id) ON DELETE CASCADE,
    condition_name character varying NOT NULL,
    diagnosis_date date,
    remarks text,
    status character varying DEFAULT 'active' CHECK (status = ANY (ARRAY ['active', 'resolved'])),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- Allergies
CREATE TABLE public.allergies (
    allergy_id BIGSERIAL PRIMARY KEY,
    mother_id bigint NOT NULL REFERENCES public.mothers(mother_id) ON DELETE CASCADE,
    allergen character varying NOT NULL,
    diagnosis_date date,
    treatment text,
    remarks text,
    status character varying DEFAULT 'active' CHECK (status = ANY (ARRAY ['active', 'resolved'])),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- ============================================================
-- 4. PREGNANCY & CLINICAL ENCOUNTERS
-- ============================================================
-- Pregnancies
CREATE TABLE public.pregnancies (
    pregnancy_id BIGSERIAL PRIMARY KEY,
    mother_id bigint NOT NULL REFERENCES public.mothers(mother_id) ON DELETE CASCADE,
    pre_pregnancy_weight numeric,
    height_cm numeric,
    pre_pregnancy_bmi numeric,
    fetal_count character varying DEFAULT 'Unknown',
    pregnancy_risk_level character varying CHECK (
        pregnancy_risk_level = ANY (ARRAY ['low', 'medium', 'high'])
    ),
    last_menstrual_period date,
    expected_date_of_delivery date,
    status character varying NOT NULL CHECK (status = ANY (ARRAY ['ongoing', 'ended'])),
    gestational_age_at_end numeric,
    ended_at timestamp without time zone,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- Clinical Encounters
CREATE TABLE public.clinical_encounters (
    encounter_id BIGSERIAL PRIMARY KEY,
    pregnancy_id bigint NOT NULL REFERENCES public.pregnancies(pregnancy_id) ON DELETE CASCADE,
    mother_id bigint NOT NULL REFERENCES public.mothers(mother_id) ON DELETE CASCADE,
    recorded_by bigint REFERENCES public.midwives(midwife_id) ON DELETE
    SET NULL,
        facility_id bigint REFERENCES public.health_facilities(facility_id) ON DELETE
    SET NULL,
        encounter_type character varying NOT NULL CHECK (
            encounter_type = ANY (
                ARRAY ['checkup', 'lab_test', 'ultrasound', 'delivery', 'postpartum']
            )
        ),
        encounter_datetime timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
        age_of_gestation_weeks integer,
        age_of_gestation_days integer,
        risk_status character varying DEFAULT 'low' CHECK (
            risk_status = ANY (ARRAY ['low', 'moderate', 'high', 'critical'])
        ),
        midwife_notes text,
        ai_summary text,
        is_midwife_approved boolean DEFAULT false,
        created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- Prenatal Checkups
CREATE TABLE public.prenatal_checkups (
    encounter_id bigint NOT NULL UNIQUE REFERENCES public.clinical_encounters(encounter_id) ON DELETE CASCADE,
    pregnancy_id bigint NOT NULL REFERENCES public.pregnancies(pregnancy_id) ON DELETE CASCADE,
    checkup_weight numeric,
    blood_pressure_systolic integer,
    blood_pressure_diastolic integer,
    fetal_position character varying CHECK (
        fetal_position = ANY (
            ARRAY ['cephalic', 'breech', 'transverse', 'unstable']
        )
    ),
    fetal_heart_beat integer,
    fetal_heart_tone character varying CHECK (
        fetal_heart_tone = ANY (ARRAY ['regular', 'irregular', 'faint', 'absent'])
    ),
    fundal_height_cm numeric,
    td_vaccine_dose character varying,
    edema character varying DEFAULT 'none' CHECK (
        edema = ANY (ARRAY ['none', 'mild', 'moderate', 'severe'])
    ),
    next_schedule date,
    CONSTRAINT chk_blood_pressure CHECK (
        blood_pressure_systolic > 40
        AND blood_pressure_diastolic > 20
    )
);
-- Lab Tests
CREATE TABLE public.lab_tests (
    encounter_id bigint NOT NULL UNIQUE REFERENCES public.clinical_encounters(encounter_id) ON DELETE CASCADE,
    pregnancy_id bigint NOT NULL REFERENCES public.pregnancies(pregnancy_id) ON DELETE CASCADE,
    lab_test_type character varying,
    hemoglobin_g_dl numeric,
    hematocrit_pct numeric,
    wbc_count numeric,
    platelet_count integer,
    urinalysis_protein character varying CHECK (
        urinalysis_protein = ANY (
            ARRAY ['negative', 'trace', '1+', '2+', '3+', '4+']
        )
    ),
    urinalysis_glucose character varying,
    hepatitis_b_status character varying,
    hiv_status character varying,
    syphilis_status character varying,
    lab_test_location character varying,
    lab_test_image text,
    health_worker_name character varying,
    health_worker_institution character varying,
    health_worker_profession character varying,
    file_url text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- Ultrasounds
CREATE TABLE public.ultrasounds (
    encounter_id bigint NOT NULL UNIQUE REFERENCES public.clinical_encounters(encounter_id) ON DELETE CASCADE,
    pregnancy_id bigint NOT NULL REFERENCES public.pregnancies(pregnancy_id) ON DELETE CASCADE,
    ultrasound_date date,
    ultrasound_location character varying,
    ultrasound_image text,
    findings_summary text,
    estimated_fetal_weight_g integer,
    amniotic_fluid_index numeric,
    placental_location character varying,
    gestational_age_ultrasound_weeks integer,
    monitoring_classification character varying,
    health_worker_name character varying,
    health_worker_institution character varying,
    health_worker_profession character varying,
    file_url text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- Deliveries
CREATE TABLE public.deliveries (
    encounter_id bigint NOT NULL UNIQUE REFERENCES public.clinical_encounters(encounter_id) ON DELETE CASCADE,
    pregnancy_id bigint NOT NULL REFERENCES public.pregnancies(pregnancy_id) ON DELETE CASCADE,
    delivery_date date,
    place_of_delivery character varying,
    delivery_method character varying,
    is_delivery_date_estimated boolean DEFAULT false,
    fetus_number integer DEFAULT 1,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- Pregnancy Outcomes
CREATE TABLE public.pregnancy_outcomes (
    outcome_id BIGSERIAL PRIMARY KEY,
    pregnancy_id bigint NOT NULL REFERENCES public.pregnancies(pregnancy_id) ON DELETE CASCADE,
    outcome character varying CHECK (
        outcome = ANY (
            ARRAY ['live_birth', 'stillbirth', 'miscarriage', 'abortion', 'ectopic', 'fetal_loss', 'vanishing_twin']
        )
    ),
    outcome_date date,
    gestational_age_at_end numeric,
    fetus_number integer DEFAULT 1,
    is_outcome_date_estimated boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- ============================================================
-- 5. SYMPTOMS & RISK ASSESSMENT
-- ============================================================
-- Symptom Types
CREATE TABLE public.symptom_types (
    symptom_type_id BIGSERIAL PRIMARY KEY,
    symptom_name character varying NOT NULL UNIQUE,
    risk_category character varying NOT NULL CHECK (
        risk_category = ANY (ARRAY ['normal', 'warning', 'danger'])
    ),
    description text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- Pregnancy Symptoms
CREATE TABLE public.pregnancy_symptoms (
    symptom_id BIGSERIAL PRIMARY KEY,
    pregnancy_id bigint NOT NULL REFERENCES public.pregnancies(pregnancy_id) ON DELETE CASCADE,
    encounter_id bigint REFERENCES public.clinical_encounters(encounter_id) ON DELETE
    SET NULL,
        symptom_type_id bigint NOT NULL REFERENCES public.symptom_types(symptom_type_id) ON DELETE RESTRICT,
        notes text,
        created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- Pregnancy Risk Assessments
CREATE TABLE public.pregnancy_risk_assessments (
    pregnancy_risk_id BIGSERIAL PRIMARY KEY,
    pregnancy_id bigint NOT NULL REFERENCES public.pregnancies(pregnancy_id) ON DELETE CASCADE,
    ai_response_id bigint,
    risk_level character varying,
    reviewed_by bigint REFERENCES public.accounts(account_id) ON DELETE
    SET NULL,
        assessed_by_ai boolean DEFAULT true,
        created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
        updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- Pregnancy Risk Factors
CREATE TABLE public.pregnancy_risk_factors (
    risk_factor_id BIGSERIAL PRIMARY KEY,
    pregnancy_risk_id bigint NOT NULL REFERENCES public.pregnancy_risk_assessments(pregnancy_risk_id) ON DELETE CASCADE,
    factor character varying NOT NULL,
    risk_influence character varying,
    source_table character varying,
    source_id bigint,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- ============================================================
-- 6. CHILDREN & PEDIATRICS
-- ============================================================
-- Children
CREATE TABLE public.children (
    child_id BIGSERIAL PRIMARY KEY,
    guardian_id bigint REFERENCES public.guardians(guardian_id) ON DELETE
    SET NULL,
        mother_id bigint REFERENCES public.mothers(mother_id) ON DELETE
    SET NULL,
        pregnancy_id bigint REFERENCES public.pregnancies(pregnancy_id) ON DELETE
    SET NULL,
        has_guardian_only boolean DEFAULT false,
        first_name character varying,
        last_name character varying,
        middle_name character varying,
        extension_name character varying,
        sex character varying CHECK (sex = ANY (ARRAY ['male', 'female'])),
        added_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- Birth Details
CREATE TABLE public.birth_details (
    birth_details_id BIGSERIAL PRIMARY KEY,
    child_id bigint NOT NULL UNIQUE REFERENCES public.children(child_id) ON DELETE CASCADE,
    birthplace_facility text,
    birthdate date,
    birth_weight numeric,
    birth_length numeric,
    birthplace_city_municipality character varying,
    birthplace_province character varying,
    delivery_type character varying,
    apgar_score integer CHECK (
        apgar_score >= 0
        AND apgar_score <= 10
    ),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- Child Growth Records
CREATE TABLE public.child_growth_records (
    child_details_id BIGSERIAL PRIMARY KEY,
    child_id bigint NOT NULL REFERENCES public.children(child_id) ON DELETE CASCADE,
    measurement_date date NOT NULL,
    child_weight numeric,
    child_height numeric,
    head_circumference_cm numeric,
    weight_for_age_zscore numeric,
    height_for_age_zscore numeric,
    bmi_for_age_zscore numeric,
    recorded_by bigint REFERENCES public.midwives(midwife_id) ON DELETE
    SET NULL,
        notes text,
        created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
        updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- Vaccines Catalog
CREATE TABLE public.vaccines (
    vaccine_id BIGSERIAL PRIMARY KEY,
    vaccine_name character varying NOT NULL,
    dose_number integer NOT NULL,
    recommended_age_months numeric NOT NULL,
    target_recipients character varying NOT NULL CHECK (
        target_recipients = ANY (ARRAY ['child', 'mother'])
    ),
    notes text,
    poster_category integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- Immunization Schedule
CREATE TABLE public.immunization_schedule (
    immunization_schedule_id BIGSERIAL PRIMARY KEY,
    facility_id bigint NOT NULL REFERENCES public.health_facilities(facility_id) ON DELETE CASCADE,
    vaccine_id bigint NOT NULL REFERENCES public.vaccines(vaccine_id) ON DELETE CASCADE,
    schedule_date date NOT NULL,
    notes text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- Immunization Records
CREATE TABLE public.immunization_records (
    immunization_record_id BIGSERIAL PRIMARY KEY,
    child_id bigint NOT NULL REFERENCES public.children(child_id) ON DELETE CASCADE,
    vaccine_id bigint NOT NULL REFERENCES public.vaccines(vaccine_id) ON DELETE RESTRICT,
    vaccination_date date NOT NULL,
    administered_by bigint REFERENCES public.midwives(midwife_id) ON DELETE
    SET NULL,
        dose_number integer NOT NULL DEFAULT 1,
        next_due_date date,
        status character varying DEFAULT 'administered' CHECK (
            status = ANY (ARRAY ['administered', 'missed', 'scheduled'])
        ),
        remarks text,
        created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- ============================================================
-- 7. INVENTORY SYSTEM
-- ============================================================
-- Inventory Items
CREATE TABLE public.inventory_items (
    item_id BIGSERIAL PRIMARY KEY,
    name character varying NOT NULL UNIQUE,
    item_type character varying NOT NULL CHECK (
        item_type = ANY (
            ARRAY ['vaccine', 'supplement', 'medical_device', 'contraceptive']
        )
    ),
    unit_of_measure character varying NOT NULL,
    minimum_stock_threshold integer DEFAULT 50,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- Inventory Batches
CREATE TABLE public.inventory_batches (
    batch_id BIGSERIAL PRIMARY KEY,
    item_id bigint NOT NULL REFERENCES public.inventory_items(item_id) ON DELETE CASCADE,
    facility_id bigint REFERENCES public.health_facilities(facility_id) ON DELETE SET NULL,
    batch_number character varying NOT NULL,
    quantity_received integer NOT NULL,
    quantity_remaining integer NOT NULL,
    received_date date NOT NULL DEFAULT CURRENT_DATE,
    expiration_date date NOT NULL,
    manufacturer character varying,
    status character varying DEFAULT 'active' CHECK (
        status = ANY (ARRAY ['active', 'expired', 'discarded'])
    ),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_batch_quantities CHECK (
        quantity_received >= 0
        AND quantity_remaining >= 0
        AND quantity_remaining <= quantity_received
    ),
    CONSTRAINT chk_batch_expiration CHECK (expiration_date >= received_date)
);
-- Inventory Transactions
CREATE TABLE public.inventory_transactions (
    transaction_id BIGSERIAL PRIMARY KEY,
    batch_id bigint NOT NULL REFERENCES public.inventory_batches(batch_id) ON DELETE CASCADE,
    facility_id bigint REFERENCES public.health_facilities(facility_id) ON DELETE SET NULL,
    transaction_type character varying NOT NULL CHECK (
        transaction_type = ANY (
            ARRAY ['receipt', 'dispense', 'adjustment', 'expiry_disposal']
        )
    ),
    quantity integer NOT NULL,
    reference_type character varying,
    reference_id bigint,
    performed_by bigint REFERENCES public.accounts(account_id) ON DELETE
    SET NULL,
        logged_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- ============================================================
-- 8. SCHEDULING & NOTIFICATIONS
-- ============================================================
-- Schedules
CREATE TABLE public.schedules (
    schedule_id BIGSERIAL PRIMARY KEY,
    mother_id bigint NOT NULL REFERENCES public.mothers(mother_id) ON DELETE CASCADE,
    pregnancy_id bigint REFERENCES public.pregnancies(pregnancy_id) ON DELETE
    SET NULL,
        facility_id bigint REFERENCES public.health_facilities(facility_id) ON DELETE
    SET NULL,
        schedule_date date NOT NULL,
        schedule_time time,
        visit_type character varying NOT NULL CHECK (
            visit_type = ANY (
                ARRAY ['prenatal_checkup', 'postpartum', 'immunization', 'consultation']
            )
        ),
        status character varying DEFAULT 'scheduled' CHECK (
            status = ANY (
                ARRAY ['scheduled', 'completed', 'missed', 'cancelled']
            )
        ),
        is_automated boolean DEFAULT false,
        notes text,
        created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
        updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- Notifications
CREATE TABLE public.notifications (
    notification_id BIGSERIAL PRIMARY KEY,
    account_id bigint NOT NULL REFERENCES public.accounts(account_id) ON DELETE CASCADE,
    title character varying NOT NULL,
    message text NOT NULL,
    type character varying DEFAULT 'general' CHECK (
        type = ANY (
            ARRAY ['checkup_reminder', 'vaccine_reminder', 'general']
        )
    ),
    is_read boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- Email Queue
CREATE TABLE public.email_queue (
    queue_id BIGSERIAL PRIMARY KEY,
    recipient character varying(255) NOT NULL,
    subject character varying(255) NOT NULL,
    html_content text NOT NULL,
    status character varying(20) DEFAULT 'pending',
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- Device Tokens
CREATE TABLE public.device_tokens (
    device_token_id BIGSERIAL PRIMARY KEY,
    account_id bigint NOT NULL REFERENCES public.accounts(account_id) ON DELETE CASCADE,
    fcm_token text NOT NULL,
    platform character varying DEFAULT 'android' CHECK (platform = ANY (ARRAY ['android', 'ios'])),
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- ============================================================
-- 9. AI & ANALYTICS
-- ============================================================
-- AI Responses
CREATE TABLE public.ai_responses (
    ai_response_id BIGSERIAL PRIMARY KEY,
    response_type character varying NOT NULL,
    reference_table character varying,
    reference_id bigint,
    ai_model character varying,
    confidence_score numeric,
    response text NOT NULL,
    response_category character varying,
    approved_by bigint REFERENCES public.accounts(account_id) ON DELETE
    SET NULL,
        status character varying DEFAULT 'generated',
        generated_by_ai boolean DEFAULT true,
        created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
        updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- AI Edit History
CREATE TABLE public.ai_edit_history (
    ai_edit_history_id BIGSERIAL PRIMARY KEY,
    ai_response_id bigint NOT NULL REFERENCES public.ai_responses(ai_response_id) ON DELETE CASCADE,
    old_content text,
    new_content text,
    edited_by bigint REFERENCES public.accounts(account_id) ON DELETE
    SET NULL,
        edit_reason text,
        edited_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- AI Prompt Logs
CREATE TABLE public.ai_prompt_logs (
    prompt_log_id BIGSERIAL PRIMARY KEY,
    ai_response_id bigint REFERENCES public.ai_responses(ai_response_id) ON DELETE
    SET NULL,
        prompt text,
        model_used character varying,
        created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- Weight Gain Evaluations
CREATE TABLE public.weight_gain_evaluations (
    evaluation_id BIGSERIAL PRIMARY KEY,
    pregnancy_id bigint NOT NULL REFERENCES public.pregnancies(pregnancy_id) ON DELETE CASCADE,
    encounter_id bigint REFERENCES public.clinical_encounters(encounter_id) ON DELETE
    SET NULL,
        mode character varying NOT NULL CHECK (mode = ANY (ARRAY ['FULL', 'TREND'])),
        bmi_category character varying,
        baseline_weight numeric,
        baseline_week numeric,
        current_weight numeric,
        current_week numeric,
        expected_gain numeric,
        actual_gain numeric,
        weekly_gain numeric,
        status character varying NOT NULL CHECK (
            status = ANY (
                ARRAY ['NORMAL', 'LOW', 'HIGH', 'INSUFFICIENT DATA']
            )
        ),
        confidence character varying NOT NULL CHECK (
            confidence = ANY (ARRAY ['HIGH', 'MEDIUM', 'LOW'])
        ),
        message text,
        flags TEXT [],
        created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- ============================================================
-- 10. FILES & OCR
-- ============================================================
-- Files
CREATE TABLE public.files (
    file_id BIGSERIAL PRIMARY KEY,
    bucket_name character varying NOT NULL,
    file_path text NOT NULL,
    file_name character varying,
    file_category character varying,
    mime_type character varying,
    file_size bigint,
    uploaded_by bigint REFERENCES public.accounts(account_id) ON DELETE
    SET NULL,
        reference_type character varying,
        reference_id bigint,
        processing_type character varying,
        ai_processed boolean DEFAULT false,
        created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- OCR Results
CREATE TABLE public.ocr_results (
    ocr_result_id BIGSERIAL PRIMARY KEY,
    file_id bigint NOT NULL REFERENCES public.files(file_id) ON DELETE CASCADE,
    extracted_text text,
    structured_data jsonb,
    processed_by_ai boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- ============================================================
-- 11. CHATBOT & JOURNAL
-- ============================================================
-- Chatbot Sessions
CREATE TABLE public.chatbot_sessions (
    session_id BIGSERIAL PRIMARY KEY,
    mother_id bigint NOT NULL REFERENCES public.mothers(mother_id) ON DELETE CASCADE,
    title character varying DEFAULT 'Kausap si Ate Assistant',
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- Chatbot Messages
CREATE TABLE public.chatbot_messages (
    message_id BIGSERIAL PRIMARY KEY,
    session_id bigint NOT NULL REFERENCES public.chatbot_sessions(session_id) ON DELETE CASCADE,
    content text NOT NULL,
    is_user boolean NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- Journal Entries
CREATE TABLE public.journal_entries (
    entry_id BIGSERIAL PRIMARY KEY,
    mother_id bigint NOT NULL REFERENCES public.mothers(mother_id) ON DELETE CASCADE,
    title character varying,
    content text NOT NULL,
    mood character varying,
    entry_date date DEFAULT CURRENT_DATE,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- ============================================================
-- 12. MEDICATIONS
-- ============================================================
-- Mother Medications
CREATE TABLE public.mother_medications (
    mother_medication_id BIGSERIAL PRIMARY KEY,
    mother_id bigint NOT NULL REFERENCES public.mothers(mother_id) ON DELETE CASCADE,
    encounter_id bigint REFERENCES public.clinical_encounters(encounter_id) ON DELETE
    SET NULL,
        mother_medication_name character varying NOT NULL,
        frequency character varying,
        quantity integer,
        start_date date,
        end_date date,
        status character varying DEFAULT 'active' CHECK (
            status = ANY (ARRAY ['active', 'completed', 'stopped'])
        ),
        created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
-- Given Medications
CREATE TABLE public.given_medications (
    given_medication_id BIGSERIAL PRIMARY KEY,
    mother_id bigint NOT NULL REFERENCES public.mothers(mother_id) ON DELETE CASCADE,
    encounter_id bigint REFERENCES public.clinical_encounters(encounter_id) ON DELETE
    SET NULL,
        inventory_batch_id bigint REFERENCES public.inventory_batches(batch_id) ON DELETE RESTRICT,
        given_medication_name character varying NOT NULL,
        quantity integer NOT NULL,
        date_given date NOT NULL
);
-- ============================================================
-- 13. AUDIT TRAIL
-- ============================================================
CREATE TABLE public.audit_trail (
    audit_id BIGSERIAL PRIMARY KEY,
    account_id bigint REFERENCES public.accounts(account_id) ON DELETE
    SET NULL,
        action character varying NOT NULL,
        table_name character varying,
        old_data jsonb,
        new_data jsonb,
        description text,
        ip_address character varying,
        action_timestamp timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
        row_id character varying
);
-- ============================================================
-- 14. POSTER COLUMNS (FIXED)
-- ============================================================
CREATE TABLE public.poster_columns (
    column_id SERIAL PRIMARY KEY,
    facility_id bigint NOT NULL REFERENCES public.health_facilities(facility_id) ON DELETE CASCADE,
    title text NOT NULL,
    subtitle text,
    vaccine_ids INTEGER [] NOT NULL DEFAULT '{}',
    display_order integer NOT NULL DEFAULT 0
);
-- ============================================================
-- 15. MATERNAL VITALS
-- ============================================================
CREATE TABLE public.maternal_vitals (
    vital_id BIGSERIAL PRIMARY KEY,
    pregnancy_id bigint NOT NULL REFERENCES public.pregnancies(pregnancy_id) ON DELETE CASCADE,
    mother_id bigint NOT NULL REFERENCES public.mothers(mother_id) ON DELETE CASCADE,
    age_of_gestation numeric,
    weight_kg numeric NOT NULL,
    height_cm numeric NOT NULL,
    notes text,
    recorded_at timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP
);
-- ============================================================
-- 16. TRIGGERS & AUTOMATION
-- ============================================================
-- OB History Auto-Update Trigger
CREATE OR REPLACE FUNCTION update_mother_ob_history() RETURNS TRIGGER AS $$
DECLARE v_mother_id bigint;
v_gravida integer;
v_para integer;
v_abortus integer;
v_living_children integer;
BEGIN
SELECT mother_id INTO v_mother_id
FROM pregnancies
WHERE pregnancy_id = NEW.pregnancy_id;
SELECT COUNT(*) INTO v_gravida
FROM pregnancies
WHERE mother_id = v_mother_id;
SELECT COUNT(*) INTO v_para
FROM pregnancies p
    JOIN pregnancy_outcomes po ON p.pregnancy_id = po.pregnancy_id
WHERE p.mother_id = v_mother_id
    AND po.outcome IN ('live_birth', 'stillbirth');
SELECT COUNT(*) INTO v_abortus
FROM pregnancies p
    JOIN pregnancy_outcomes po ON p.pregnancy_id = po.pregnancy_id
WHERE p.mother_id = v_mother_id
    AND po.outcome IN (
        'miscarriage',
        'abortion',
        'ectopic',
        'fetal_loss',
        'vanishing_twin'
    );
SELECT COUNT(*) INTO v_living_children
FROM children
WHERE mother_id = v_mother_id;
UPDATE mothers
SET gravida = v_gravida,
    para = v_para,
    abortus = v_abortus,
    living_children = v_living_children
WHERE mother_id = v_mother_id;
RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER trg_update_ob_history
AFTER
INSERT
    OR
UPDATE
    OR DELETE ON pregnancy_outcomes FOR EACH ROW EXECUTE FUNCTION update_mother_ob_history();
-- Living Children Auto-Update
CREATE OR REPLACE FUNCTION update_mother_living_children() RETURNS TRIGGER AS $$ BEGIN IF (TG_OP = 'DELETE') THEN
UPDATE mothers
SET living_children = (
        SELECT COUNT(*)
        FROM children
        WHERE mother_id = OLD.mother_id
    )
WHERE mother_id = OLD.mother_id;
ELSE
UPDATE mothers
SET living_children = (
        SELECT COUNT(*)
        FROM children
        WHERE mother_id = NEW.mother_id
    )
WHERE mother_id = NEW.mother_id;
END IF;
RETURN NULL;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER trg_update_living_children
AFTER
INSERT
    OR DELETE ON children FOR EACH ROW EXECUTE FUNCTION update_mother_living_children();
-- Pre-pregnancy BMI Calculation
CREATE OR REPLACE FUNCTION calculate_pregnancy_bmi() RETURNS TRIGGER AS $$ BEGIN IF NEW.pre_pregnancy_weight IS NOT NULL
    AND NEW.height_cm > 0 THEN NEW.pre_pregnancy_bmi := ROUND(
        (
            NEW.pre_pregnancy_weight / (
                (NEW.height_cm / 100.0) * (NEW.height_cm / 100.0)
            )
        )::numeric,
        2
    );
END IF;
RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER trg_calculate_pregnancy_bmi BEFORE
INSERT
    OR
UPDATE OF pre_pregnancy_weight,
    height_cm ON pregnancies FOR EACH ROW EXECUTE FUNCTION calculate_pregnancy_bmi();
-- Inventory Auto-Deduct on Given Medications
CREATE OR REPLACE FUNCTION deduct_inventory_on_given_medication() RETURNS TRIGGER AS $$ BEGIN IF NEW.inventory_batch_id IS NOT NULL THEN
UPDATE inventory_batches
SET quantity_remaining = quantity_remaining - NEW.quantity
WHERE batch_id = NEW.inventory_batch_id;
INSERT INTO inventory_transactions (
        batch_id,
        transaction_type,
        quantity,
        reference_type,
        reference_id
    )
VALUES (
        NEW.inventory_batch_id,
        'dispense',
        - NEW.quantity,
        'given_medication',
        NEW.given_medication_id
    );
END IF;
RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER trg_deduct_inventory_medication
AFTER
INSERT ON given_medications FOR EACH ROW EXECUTE FUNCTION deduct_inventory_on_given_medication();
-- ============================================================
-- 17. PERFORMANCE INDEXES
-- ============================================================
CREATE INDEX idx_accounts_type ON accounts(account_type);
CREATE INDEX idx_accounts_status ON accounts(status);
CREATE INDEX idx_accounts_email ON accounts(email_address);
CREATE INDEX idx_accounts_phone ON accounts(phone_number);
CREATE INDEX idx_facility_assignments_account ON facility_assignments(account_id);
CREATE INDEX idx_facility_assignments_facility ON facility_assignments(facility_id);
CREATE INDEX idx_facility_assignments_active ON facility_assignments(is_active)
WHERE is_active = true;
CREATE INDEX idx_mothers_status ON mothers(status);
CREATE INDEX idx_mothers_barangay ON mothers(barangay);
CREATE INDEX idx_pregnancies_mother ON pregnancies(mother_id);
CREATE INDEX idx_pregnancies_status ON pregnancies(status);
CREATE INDEX idx_pregnancies_active ON pregnancies(status)
WHERE status = 'ongoing';
CREATE INDEX idx_clinical_encounters_pregnancy ON clinical_encounters(pregnancy_id);
CREATE INDEX idx_clinical_encounters_mother ON clinical_encounters(mother_id);
CREATE INDEX idx_clinical_encounters_type ON clinical_encounters(encounter_type);
CREATE INDEX idx_clinical_encounters_date ON clinical_encounters(mother_id, encounter_datetime DESC);
CREATE INDEX idx_clinical_encounters_recorded_by ON clinical_encounters(recorded_by);
CREATE INDEX idx_children_mother ON children(mother_id);
CREATE INDEX idx_children_guardian ON children(guardian_id);
CREATE INDEX idx_immunization_records_child ON immunization_records(child_id);
CREATE INDEX idx_immunization_records_date ON immunization_records(vaccination_date);
CREATE INDEX idx_inventory_batches_item ON inventory_batches(item_id);
CREATE INDEX idx_inventory_batches_expiry ON inventory_batches(expiration_date);
CREATE INDEX idx_inventory_batches_status ON inventory_batches(status);
CREATE INDEX idx_inventory_batches_facility ON inventory_batches(facility_id);
CREATE INDEX idx_inventory_transactions_facility ON inventory_transactions(facility_id);
CREATE INDEX idx_schedules_mother ON schedules(mother_id);
CREATE INDEX idx_schedules_date ON schedules(schedule_date, schedule_time);
CREATE INDEX idx_schedules_status ON schedules(status);
CREATE INDEX idx_notifications_account ON notifications(account_id, is_read);
CREATE INDEX idx_notifications_unread ON notifications(account_id)
WHERE is_read = false;
CREATE INDEX idx_audit_trail_account ON audit_trail(account_id);
CREATE INDEX idx_audit_trail_timestamp ON audit_trail(action_timestamp DESC);
CREATE INDEX idx_files_reference ON files(reference_type, reference_id);
CREATE INDEX idx_files_uploaded_by ON files(uploaded_by);
CREATE INDEX idx_journal_entries_mother ON journal_entries(mother_id);
CREATE INDEX idx_chatbot_messages_session ON chatbot_messages(session_id);
CREATE INDEX idx_pregnancy_risk_pregnancy ON pregnancy_risk_assessments(pregnancy_id);
-- ============================================================
-- 18. ROW LEVEL SECURITY (RLS) SETUP
-- ============================================================
ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.health_facilities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.facility_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.midwives ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mothers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.guardians ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.emergency_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.medical_conditions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.allergies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pregnancies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clinical_encounters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prenatal_checkups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lab_tests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ultrasounds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pregnancy_outcomes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.symptom_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pregnancy_symptoms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pregnancy_risk_assessments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pregnancy_risk_factors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.children ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.birth_details ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.child_growth_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vaccines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.immunization_schedule ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.immunization_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.email_queue DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.device_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_responses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_edit_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_prompt_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.weight_gain_evaluations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.files ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ocr_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chatbot_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chatbot_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.journal_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mother_medications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.given_medications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_trail ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.poster_columns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.maternal_vitals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.password_history ENABLE ROW LEVEL SECURITY;
-- ============================================================
-- 19. GRANTS & PERMISSIONS
-- ============================================================
GRANT USAGE ON SCHEMA public TO anon,
    authenticated,
    service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO service_role;
-- ============================================================
-- 20. ROW LEVEL SECURITY POLICIES
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_current_account_id() RETURNS bigint AS $$
DECLARE v_account_id bigint;
BEGIN
SELECT account_id INTO v_account_id
FROM public.accounts
WHERE auth_id = auth.uid();
RETURN v_account_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
CREATE OR REPLACE FUNCTION public.has_role(required_role text) RETURNS boolean AS $$ BEGIN RETURN EXISTS (
        SELECT 1
        FROM public.accounts
        WHERE auth_id = auth.uid()
            AND account_type = required_role
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
-- ACCOUNTS
CREATE POLICY "Users can read own account" ON public.accounts FOR
SELECT USING (auth_id = auth.uid());
CREATE POLICY "Admins and midwives can read all accounts" ON public.accounts FOR
SELECT USING (
        has_role('admin')
        OR has_role('midwife')
    );
CREATE POLICY "Users can update own account" ON public.accounts FOR
UPDATE USING (auth_id = auth.uid());
-- HEALTH FACILITIES
CREATE POLICY "Authenticated users can read facilities" ON public.health_facilities FOR
SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Admins can manage facilities" ON public.health_facilities FOR ALL USING (has_role('admin'));
-- FACILITY ASSIGNMENTS
CREATE POLICY "Users can read own assignments" ON public.facility_assignments FOR
SELECT USING (account_id = get_current_account_id());
CREATE POLICY "Midwives and admins can read facility assignments" ON public.facility_assignments FOR
SELECT USING (
        has_role('admin')
        OR has_role('midwife')
    );
CREATE POLICY "Admins can manage assignments" ON public.facility_assignments FOR ALL USING (has_role('admin'));
-- MIDWIVES
CREATE POLICY "Midwives can read own profile" ON public.midwives FOR
SELECT USING (account_id = get_current_account_id());
CREATE POLICY "Admins can manage midwives" ON public.midwives FOR ALL USING (has_role('admin'));
-- MOTHERS
CREATE POLICY "Mothers can read own profile" ON public.mothers FOR
SELECT USING (account_id = get_current_account_id());
CREATE POLICY "Mothers can update own profile" ON public.mothers FOR
UPDATE USING (account_id = get_current_account_id());
CREATE POLICY "Midwives and admins can read mothers" ON public.mothers FOR
SELECT USING (
        has_role('admin')
        OR has_role('midwife')
    );
-- PREGNANCIES
CREATE POLICY "Mothers can read own pregnancies" ON public.pregnancies FOR
SELECT USING (
        mother_id IN (
            SELECT mother_id
            FROM public.mothers
            WHERE account_id = get_current_account_id()
        )
    );
CREATE POLICY "Midwives and admins can read all pregnancies" ON public.pregnancies FOR
SELECT USING (
        has_role('admin')
        OR has_role('midwife')
    );
CREATE POLICY "Midwives and admins can manage pregnancies" ON public.pregnancies FOR ALL USING (
    has_role('admin')
    OR has_role('midwife')
);
-- CLINICAL ENCOUNTERS
CREATE POLICY "Mothers can read own encounters" ON public.clinical_encounters FOR
SELECT USING (
        mother_id IN (
            SELECT mother_id
            FROM public.mothers
            WHERE account_id = get_current_account_id()
        )
    );
CREATE POLICY "Midwives and admins can read all encounters" ON public.clinical_encounters FOR
SELECT USING (
        has_role('admin')
        OR has_role('midwife')
    );
CREATE POLICY "Midwives and admins can manage encounters" ON public.clinical_encounters FOR ALL USING (
    has_role('admin')
    OR has_role('midwife')
);
-- PRENATAL CHECKUPS
CREATE POLICY "Mothers can read own checkups" ON public.prenatal_checkups FOR
SELECT USING (
        pregnancy_id IN (
            SELECT pregnancy_id
            FROM public.pregnancies
            WHERE mother_id IN (
                    SELECT mother_id
                    FROM public.mothers
                    WHERE account_id = get_current_account_id()
                )
        )
    );
CREATE POLICY "Midwives and admins can manage checkups" ON public.prenatal_checkups FOR ALL USING (
    has_role('admin')
    OR has_role('midwife')
);
-- LAB TESTS
CREATE POLICY "Mothers can read own lab tests" ON public.lab_tests FOR
SELECT USING (
        pregnancy_id IN (
            SELECT pregnancy_id
            FROM public.pregnancies
            WHERE mother_id IN (
                    SELECT mother_id
                    FROM public.mothers
                    WHERE account_id = get_current_account_id()
                )
        )
    );
CREATE POLICY "Midwives and admins can manage lab tests" ON public.lab_tests FOR ALL USING (
    has_role('admin')
    OR has_role('midwife')
);
-- ULTRASOUNDS
CREATE POLICY "Mothers can read own ultrasounds" ON public.ultrasounds FOR
SELECT USING (
        pregnancy_id IN (
            SELECT pregnancy_id
            FROM public.pregnancies
            WHERE mother_id IN (
                    SELECT mother_id
                    FROM public.mothers
                    WHERE account_id = get_current_account_id()
                )
        )
    );
CREATE POLICY "Midwives and admins can manage ultrasounds" ON public.ultrasounds FOR ALL USING (
    has_role('admin')
    OR has_role('midwife')
);
-- DELIVERIES
CREATE POLICY "Mothers can read own deliveries" ON public.deliveries FOR
SELECT USING (
        pregnancy_id IN (
            SELECT pregnancy_id
            FROM public.pregnancies
            WHERE mother_id IN (
                    SELECT mother_id
                    FROM public.mothers
                    WHERE account_id = get_current_account_id()
                )
        )
    );
CREATE POLICY "Midwives and admins can manage deliveries" ON public.deliveries FOR ALL USING (
    has_role('admin')
    OR has_role('midwife')
);
-- CHILDREN
CREATE POLICY "Mothers can read own children" ON public.children FOR
SELECT USING (
        mother_id IN (
            SELECT mother_id
            FROM public.mothers
            WHERE account_id = get_current_account_id()
        )
    );
CREATE POLICY "Midwives and admins can manage children" ON public.children FOR ALL USING (
    has_role('admin')
    OR has_role('midwife')
);
-- IMMUNIZATION RECORDS
CREATE POLICY "Mothers can read own children's immunizations" ON public.immunization_records FOR
SELECT USING (
        child_id IN (
            SELECT child_id
            FROM public.children
            WHERE mother_id IN (
                    SELECT mother_id
                    FROM public.mothers
                    WHERE account_id = get_current_account_id()
                )
        )
    );
CREATE POLICY "Midwives and admins can manage immunizations" ON public.immunization_records FOR ALL USING (
    has_role('admin')
    OR has_role('midwife')
);
-- NOTIFICATIONS
CREATE POLICY "Users can read own notifications" ON public.notifications FOR
SELECT USING (account_id = get_current_account_id());
CREATE POLICY "Users can update own notifications" ON public.notifications FOR
UPDATE USING (account_id = get_current_account_id());
-- DEVICE TOKENS
CREATE POLICY "Users can manage own device tokens" ON public.device_tokens FOR ALL USING (account_id = get_current_account_id());
-- SCHEDULES
CREATE POLICY "Mothers can read own schedules" ON public.schedules FOR
SELECT USING (
        mother_id IN (
            SELECT mother_id
            FROM public.mothers
            WHERE account_id = get_current_account_id()
        )
    );
CREATE POLICY "Midwives and admins can manage schedules" ON public.schedules FOR ALL USING (
    has_role('admin')
    OR has_role('midwife')
);
-- CHATBOT
CREATE POLICY "Mothers can manage own chatbot sessions" ON public.chatbot_sessions FOR ALL USING (
    mother_id IN (
        SELECT mother_id
        FROM public.mothers
        WHERE account_id = get_current_account_id()
    )
);
CREATE POLICY "Mothers can manage own chatbot messages" ON public.chatbot_messages FOR ALL USING (
    session_id IN (
        SELECT session_id
        FROM public.chatbot_sessions
        WHERE mother_id IN (
                SELECT mother_id
                FROM public.mothers
                WHERE account_id = get_current_account_id()
            )
    )
);
-- JOURNAL ENTRIES
CREATE POLICY "Mothers can manage own journal entries" ON public.journal_entries FOR ALL USING (
    mother_id IN (
        SELECT mother_id
        FROM public.mothers
        WHERE account_id = get_current_account_id()
    )
);
-- EMERGENCY CONTACTS
CREATE POLICY "Mothers can read own emergency contacts" ON public.emergency_contacts FOR
SELECT USING (
        mother_id IN (
            SELECT mother_id
            FROM public.mothers
            WHERE account_id = get_current_account_id()
        )
    );
CREATE POLICY "Midwives and admins can manage medical data" ON public.emergency_contacts FOR ALL USING (
    has_role('admin')
    OR has_role('midwife')
);
-- MEDICAL CONDITIONS
CREATE POLICY "Mothers can read own medical conditions" ON public.medical_conditions FOR
SELECT USING (
        mother_id IN (
            SELECT mother_id
            FROM public.mothers
            WHERE account_id = get_current_account_id()
        )
    );
CREATE POLICY "Midwives and admins can manage medical conditions" ON public.medical_conditions FOR ALL USING (
    has_role('admin')
    OR has_role('midwife')
);
-- ALLERGIES
CREATE POLICY "Mothers can read own allergies" ON public.allergies FOR
SELECT USING (
        mother_id IN (
            SELECT mother_id
            FROM public.mothers
            WHERE account_id = get_current_account_id()
        )
    );
CREATE POLICY "Midwives and admins can manage allergies" ON public.allergies FOR ALL USING (
    has_role('admin')
    OR has_role('midwife')
);
-- MEDICATIONS
CREATE POLICY "Mothers can read own medications" ON public.mother_medications FOR
SELECT USING (
        mother_id IN (
            SELECT mother_id
            FROM public.mothers
            WHERE account_id = get_current_account_id()
        )
    );
CREATE POLICY "Midwives and admins can manage medications" ON public.mother_medications FOR ALL USING (
    has_role('admin')
    OR has_role('midwife')
);
CREATE POLICY "Mothers can read own given medications" ON public.given_medications FOR
SELECT USING (
        mother_id IN (
            SELECT mother_id
            FROM public.mothers
            WHERE account_id = get_current_account_id()
        )
    );
CREATE POLICY "Midwives and admins can manage given medications" ON public.given_medications FOR ALL USING (
    has_role('admin')
    OR has_role('midwife')
);
-- INVENTORY
CREATE POLICY "Admins and midwives can read inventory" ON public.inventory_items FOR
SELECT USING (
        has_role('admin')
        OR has_role('midwife')
    );
CREATE POLICY "Admins can manage inventory" ON public.inventory_items FOR ALL USING (has_role('admin'));
CREATE POLICY "Admins and midwives can read batches" ON public.inventory_batches FOR
SELECT USING (
        has_role('admin')
        OR has_role('midwife')
    );
CREATE POLICY "Admins can manage batches" ON public.inventory_batches FOR ALL USING (has_role('admin'));
-- PUBLIC READ TABLES
CREATE POLICY "Anyone can read symptom types" ON public.symptom_types FOR
SELECT USING (true);
CREATE POLICY "Anyone can read vaccines" ON public.vaccines FOR
SELECT USING (true);
CREATE POLICY "Anyone can read immunization schedules" ON public.immunization_schedule FOR
SELECT USING (true);
-- AUDIT TRAIL
CREATE POLICY "Admins can read audit trail" ON public.audit_trail FOR
SELECT USING (has_role('admin'));
-- FILES
CREATE POLICY "Users can read own files" ON public.files FOR
SELECT USING (uploaded_by = get_current_account_id());
CREATE POLICY "Midwives and admins can read all files" ON public.files FOR
SELECT USING (
        has_role('admin')
        OR has_role('midwife')
    );
CREATE POLICY "Authenticated users can upload files" ON public.files FOR
INSERT WITH CHECK (auth.role() = 'authenticated');