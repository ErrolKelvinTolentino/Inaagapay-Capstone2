-- ============================================================
-- SUPABASE MATERNAL HEALTH SYSTEM - COMPLETE SCHEMA
-- ============================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- AUTH SETUP (Supabase auth schema)
-- ============================================================
CREATE SCHEMA IF NOT EXISTS auth;

CREATE TABLE IF NOT EXISTS auth.users (
   id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
   email VARCHAR(255) UNIQUE,
   phone VARCHAR(15) UNIQUE,
   raw_user_meta_data JSONB,
   created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

-- ============================================================
-- 1. CORE: FACILITIES & USER MANAGEMENT
-- ============================================================

-- Health Facilities (BHCs, RHUs, Hospitals)
CREATE TABLE public.health_facilities (
    facility_id bigint NOT NULL DEFAULT nextval('health_facilities_facility_id_seq'::regclass),
    name character varying NOT NULL UNIQUE,
    facility_type character varying NOT NULL DEFAULT 'BHC'::character varying 
        CHECK (facility_type::text = ANY (ARRAY['BHC'::character varying, 'RHU'::character varying, 'District Hospital'::character varying, 'Clinic'::character varying, 'General Hospital'::character varying]::text[])),
    address_street character varying,
    barangay character varying NOT NULL,
    municipality character varying NOT NULL DEFAULT 'Santa Cruz'::character varying,
    province character varying NOT NULL DEFAULT 'Laguna'::character varying,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT health_facilities_pkey PRIMARY KEY (facility_id)
);

-- Accounts (unified user accounts)
CREATE TABLE public.accounts (
    account_id bigint NOT NULL DEFAULT nextval('accounts_account_id_seq'::regclass),
    auth_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    is_verified boolean DEFAULT false,
    status character varying DEFAULT 'active'::character varying 
        CHECK (status::text = ANY (ARRAY['active'::character varying, 'inactive'::character varying, 'suspended'::character varying]::text[])),
    email_address character varying UNIQUE,
    password_hash character varying,
    account_type character varying NOT NULL 
        CHECK (account_type::text = ANY (ARRAY['admin'::character varying, 'midwife'::character varying, 'mother'::character varying]::text[])),
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
    created_by character varying DEFAULT 'self'::character varying 
        CHECK (created_by::text = ANY (ARRAY['self'::character varying, 'midwife'::character varying]::text[])),
    CONSTRAINT accounts_pkey PRIMARY KEY (account_id)
);

-- Password History
CREATE TABLE public.password_history (
    account_id bigint NOT NULL,
    password character varying NOT NULL,
    replaced_at timestamp without time zone,
    pass_history_id bigint NOT NULL DEFAULT nextval('password_history_pass_history_id_seq'::regclass),
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT password_history_pkey PRIMARY KEY (pass_history_id),
    CONSTRAINT password_history_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.accounts(account_id) ON DELETE CASCADE
);

-- Facility Assignments (links accounts to health facilities with per-BHC patient numbers)
CREATE TABLE public.facility_assignments (
    facility_assignment_id bigint NOT NULL DEFAULT nextval('facility_assignments_facility_assignment_id_seq'::regclass),
    account_id bigint NOT NULL,
    facility_id bigint NOT NULL,
    patient_number integer,
    is_active boolean DEFAULT true,
    assigned_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    ended_at timestamp without time zone,
    CONSTRAINT facility_assignments_pkey PRIMARY KEY (facility_assignment_id),
    CONSTRAINT facility_assignments_account_id_fkey FOREIGN KEY (account_id) 
        REFERENCES public.accounts(account_id) ON DELETE CASCADE,
    CONSTRAINT facility_assignments_facility_id_fkey FOREIGN KEY (facility_id) 
        REFERENCES public.health_facilities(facility_id) ON DELETE RESTRICT
);

-- Partial unique index: patient_number unique per facility (only for mothers)
CREATE UNIQUE INDEX unique_patient_number_per_facility 
    ON facility_assignments (facility_id, patient_number)
    WHERE patient_number IS NOT NULL;

-- Patient number auto-assign trigger
CREATE OR REPLACE FUNCTION set_patient_number()
RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM accounts WHERE account_id = NEW.account_id AND account_type = 'mother'
    ) THEN
        NEW.patient_number := (
            SELECT COALESCE(MAX(patient_number), 0) + 1
            FROM facility_assignments
            WHERE facility_id = NEW.facility_id
              AND patient_number IS NOT NULL
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_facility_assignments_patient_number
    BEFORE INSERT ON facility_assignments
    FOR EACH ROW
    EXECUTE FUNCTION set_patient_number();

-- ============================================================
-- 2. ROLE-SPECIFIC PROFILES
-- ============================================================

-- Midwives
CREATE TABLE public.midwives (
    account_id bigint NOT NULL UNIQUE,
    midwife_id bigint NOT NULL DEFAULT nextval('midwives_midwife_id_seq'::regclass),
    license_number character varying UNIQUE,
    position character varying,
    hire_date date,
    CONSTRAINT midwives_pkey PRIMARY KEY (midwife_id),
    CONSTRAINT midwives_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.accounts(account_id) ON DELETE CASCADE
);

-- Mothers (with OB history summary)
CREATE TABLE public.mothers (
    account_id bigint NOT NULL UNIQUE,
    birthdate date,
    house_number character varying,
    street character varying,
    barangay character varying,
    city_municipality character varying,
    province character varying,
    height numeric,
    weight numeric,
    blood_type character varying 
        CHECK (blood_type::text = ANY (ARRAY['A+'::character varying, 'A-'::character varying, 'B+'::character varying, 'B-'::character varying, 'AB+'::character varying, 'AB-'::character varying, 'O+'::character varying, 'O-'::character varying]::text[])),
    mother_id bigint NOT NULL DEFAULT nextval('mothers_mother_id_seq'::regclass),
    status character varying DEFAULT 'active'::character varying 
        CHECK (status::text = ANY (ARRAY['active'::character varying, 'inactive'::character varying]::text[])),
    gravida integer DEFAULT 0,
    para integer DEFAULT 0,
    abortus integer DEFAULT 0,
    living_children integer DEFAULT 0,
    philhealth_number character varying,
    philhealth_status character varying DEFAULT 'Non-Member'::character varying 
        CHECK (philhealth_status::text = ANY (ARRAY['Member'::character varying, 'Dependent'::character varying, 'Non-Member'::character varying]::text[])),
    is_four_ps boolean DEFAULT false,
    civil_status character varying 
        CHECK (civil_status::text = ANY (ARRAY['Single'::character varying, 'Married'::character varying, 'Widowed'::character varying, 'Separated'::character varying, 'Cohabiting'::character varying]::text[])),
    CONSTRAINT mothers_pkey PRIMARY KEY (mother_id),
    CONSTRAINT mothers_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.accounts(account_id) ON DELETE CASCADE
);

-- Guardians
CREATE TABLE public.guardians (
    first_name character varying NOT NULL,
    last_name character varying NOT NULL,
    middle_name character varying,
    extension_name character varying,
    phone_number character varying,
    address text,
    relationship character varying,
    guardian_id bigint NOT NULL DEFAULT nextval('guardians_guardian_id_seq'::regclass),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT guardians_pkey PRIMARY KEY (guardian_id)
);

-- Emergency Contacts
CREATE TABLE public.emergency_contacts (
    mother_id bigint NOT NULL,
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
    emergency_contact_id bigint NOT NULL DEFAULT nextval('emergency_contacts_emergency_contact_id_seq'::regclass),
    status character varying DEFAULT 'active'::character varying 
        CHECK (status::text = ANY (ARRAY['active'::character varying, 'inactive'::character varying]::text[])),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT emergency_contacts_pkey PRIMARY KEY (emergency_contact_id),
    CONSTRAINT emergency_contacts_mother_id_fkey FOREIGN KEY (mother_id) REFERENCES public.mothers(mother_id) ON DELETE CASCADE
);

-- ============================================================
-- 3. MEDICAL HISTORY
-- ============================================================

-- Medical Conditions
CREATE TABLE public.medical_conditions (
    mother_id bigint NOT NULL,
    condition_name character varying NOT NULL,
    diagnosis_date date,
    remarks text,
    med_condition_id bigint NOT NULL DEFAULT nextval('medical_conditions_med_condition_id_seq'::regclass),
    status character varying DEFAULT 'active'::character varying 
        CHECK (status::text = ANY (ARRAY['active'::character varying, 'resolved'::character varying]::text[])),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT medical_conditions_pkey PRIMARY KEY (med_condition_id),
    CONSTRAINT medical_conditions_mother_id_fkey FOREIGN KEY (mother_id) REFERENCES public.mothers(mother_id) ON DELETE CASCADE
);

-- Allergies
CREATE TABLE public.allergies (
    mother_id bigint NOT NULL,
    allergen character varying NOT NULL,
    diagnosis_date date,
    treatment text,
    remarks text,
    allergy_id bigint NOT NULL DEFAULT nextval('allergies_allergy_id_seq'::regclass),
    status character varying DEFAULT 'active'::character varying 
        CHECK (status::text = ANY (ARRAY['active'::character varying, 'resolved'::character varying]::text[])),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT allergies_pkey PRIMARY KEY (allergy_id),
    CONSTRAINT allergies_mother_id_fkey FOREIGN KEY (mother_id) REFERENCES public.mothers(mother_id) ON DELETE CASCADE
);

-- ============================================================
-- 4. PREGNANCY & CLINICAL ENCOUNTERS
-- ============================================================

-- Pregnancies
CREATE TABLE public.pregnancies (
    pre_pregnancy_weight numeric,
    height_cm numeric,
    pre_pregnancy_bmi numeric,
    fetal_count character varying DEFAULT 'Unknown'::character varying,
    mother_id bigint NOT NULL,
    pregnancy_risk_level character varying 
        CHECK (pregnancy_risk_level::text = ANY (ARRAY['low'::character varying, 'medium'::character varying, 'high'::character varying]::text[])),
    last_menstrual_period date,
    expected_date_of_delivery date,
    status character varying NOT NULL 
        CHECK (status::text = ANY (ARRAY['ongoing'::character varying, 'ended'::character varying]::text[])),
    gestational_age_at_end numeric,
    ended_at timestamp without time zone,
    pregnancy_id bigint NOT NULL DEFAULT nextval('pregnancies_pregnancy_id_seq'::regclass),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pregnancies_pkey PRIMARY KEY (pregnancy_id),
    CONSTRAINT pregnancies_mother_id_fkey FOREIGN KEY (mother_id) REFERENCES public.mothers(mother_id) ON DELETE CASCADE
);

-- Clinical Encounters (parent table for all checkups, labs, ultrasounds, deliveries)
CREATE TABLE public.clinical_encounters (
    encounter_id bigint NOT NULL DEFAULT nextval('clinical_encounters_encounter_id_seq'::regclass),
    pregnancy_id bigint NOT NULL,
    mother_id bigint NOT NULL,
    recorded_by bigint,
    facility_id bigint,
    encounter_type character varying NOT NULL 
        CHECK (encounter_type::text = ANY (ARRAY['checkup'::character varying, 'lab_test'::character varying, 'ultrasound'::character varying, 'delivery'::character varying, 'postpartum'::character varying]::text[])),
    encounter_datetime timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    age_of_gestation_weeks integer,
    age_of_gestation_days integer,
    risk_status character varying DEFAULT 'low'::character varying 
        CHECK (risk_status::text = ANY (ARRAY['low'::character varying, 'moderate'::character varying, 'high'::character varying, 'critical'::character varying]::text[])),
    midwife_notes text,
    ai_summary text,
    is_midwife_approved boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT clinical_encounters_pkey PRIMARY KEY (encounter_id),
    CONSTRAINT clinical_encounters_pregnancy_id_fkey FOREIGN KEY (pregnancy_id) REFERENCES public.pregnancies(pregnancy_id) ON DELETE CASCADE,
    CONSTRAINT clinical_encounters_mother_id_fkey FOREIGN KEY (mother_id) REFERENCES public.mothers(mother_id) ON DELETE CASCADE,
    CONSTRAINT clinical_encounters_recorded_by_fkey FOREIGN KEY (recorded_by) REFERENCES public.midwives(midwife_id) ON DELETE SET NULL,
    CONSTRAINT clinical_encounters_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.health_facilities(facility_id) ON DELETE SET NULL
);

-- Prenatal Checkups (extends clinical_encounters)
CREATE TABLE public.prenatal_checkups (
    encounter_id bigint NOT NULL UNIQUE,
    pregnancy_id bigint NOT NULL,
    checkup_weight numeric,
    blood_pressure_systolic integer,
    blood_pressure_diastolic integer,
    fetal_position character varying 
        CHECK (fetal_position::text = ANY (ARRAY['cephalic'::character varying, 'breech'::character varying, 'transverse'::character varying, 'unstable'::character varying]::text[])),
    fetal_heart_beat integer,
    fetal_heart_tone character varying 
        CHECK (fetal_heart_tone::text = ANY (ARRAY['regular'::character varying, 'irregular'::character varying, 'faint'::character varying, 'absent'::character varying]::text[])),
    fundal_height_cm numeric,
    td_vaccine_dose character varying,
    edema character varying DEFAULT 'none'::character varying 
        CHECK (edema::text = ANY (ARRAY['none'::character varying, 'mild'::character varying, 'moderate'::character varying, 'severe'::character varying]::text[])),
    next_schedule date,
    CONSTRAINT prenatal_checkups_pkey PRIMARY KEY (encounter_id),
    CONSTRAINT prenatal_checkups_encounter_id_fkey FOREIGN KEY (encounter_id) REFERENCES public.clinical_encounters(encounter_id) ON DELETE CASCADE,
    CONSTRAINT prenatal_checkups_pregnancy_id_fkey FOREIGN KEY (pregnancy_id) REFERENCES public.pregnancies(pregnancy_id) ON DELETE CASCADE,
    CONSTRAINT chk_blood_pressure CHECK (blood_pressure_systolic > 40 AND blood_pressure_diastolic > 20)
);

-- Lab Tests (extends clinical_encounters)
CREATE TABLE public.lab_tests (
    encounter_id bigint NOT NULL UNIQUE,
    pregnancy_id bigint NOT NULL,
    lab_test_type character varying,
    hemoglobin_g_dl numeric,
    hematocrit_pct numeric,
    wbc_count numeric,
    platelet_count integer,
    urinalysis_protein character varying 
        CHECK (urinalysis_protein::text = ANY (ARRAY['negative'::character varying, 'trace'::character varying, '1+'::character varying, '2+'::character varying, '3+'::character varying, '4+'::character varying]::text[])),
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
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT lab_tests_pkey PRIMARY KEY (encounter_id),
    CONSTRAINT lab_tests_encounter_id_fkey FOREIGN KEY (encounter_id) REFERENCES public.clinical_encounters(encounter_id) ON DELETE CASCADE,
    CONSTRAINT lab_tests_pregnancy_id_fkey FOREIGN KEY (pregnancy_id) REFERENCES public.pregnancies(pregnancy_id) ON DELETE CASCADE
);

-- Ultrasounds (extends clinical_encounters)
CREATE TABLE public.ultrasounds (
    encounter_id bigint NOT NULL UNIQUE,
    pregnancy_id bigint NOT NULL,
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
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ultrasounds_pkey PRIMARY KEY (encounter_id),
    CONSTRAINT ultrasounds_encounter_id_fkey FOREIGN KEY (encounter_id) REFERENCES public.clinical_encounters(encounter_id) ON DELETE CASCADE,
    CONSTRAINT ultrasounds_pregnancy_id_fkey FOREIGN KEY (pregnancy_id) REFERENCES public.pregnancies(pregnancy_id) ON DELETE CASCADE
);

-- Deliveries (extends clinical_encounters)
CREATE TABLE public.deliveries (
    encounter_id bigint NOT NULL UNIQUE,
    pregnancy_id bigint NOT NULL,
    delivery_date date,
    place_of_delivery character varying,
    delivery_method character varying,
    is_delivery_date_estimated boolean DEFAULT false,
    fetus_number integer DEFAULT 1,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT deliveries_pkey PRIMARY KEY (encounter_id),
    CONSTRAINT deliveries_encounter_id_fkey FOREIGN KEY (encounter_id) REFERENCES public.clinical_encounters(encounter_id) ON DELETE CASCADE,
    CONSTRAINT deliveries_pregnancy_id_fkey FOREIGN KEY (pregnancy_id) REFERENCES public.pregnancies(pregnancy_id) ON DELETE CASCADE
);

-- Pregnancy Outcomes
CREATE TABLE public.pregnancy_outcomes (
    pregnancy_id bigint NOT NULL,
    outcome character varying 
        CHECK (outcome::text = ANY (ARRAY['live_birth'::character varying, 'stillbirth'::character varying, 'miscarriage'::character varying, 'abortion'::character varying, 'ectopic'::character varying, 'fetal_loss'::character varying, 'vanishing_twin'::character varying]::text[])),
    outcome_date date,
    gestational_age_at_end numeric,
    outcome_id bigint NOT NULL DEFAULT nextval('pregnancy_outcomes_outcome_id_seq'::regclass),
    fetus_number integer DEFAULT 1,
    is_outcome_date_estimated boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pregnancy_outcomes_pkey PRIMARY KEY (outcome_id),
    CONSTRAINT pregnancy_outcomes_pregnancy_id_fkey FOREIGN KEY (pregnancy_id) REFERENCES public.pregnancies(pregnancy_id) ON DELETE CASCADE
);

-- ============================================================
-- 5. SYMPTOMS & RISK ASSESSMENT
-- ============================================================

-- Symptom Types
CREATE TABLE public.symptom_types (
    symptom_name character varying NOT NULL UNIQUE,
    risk_category character varying NOT NULL 
        CHECK (risk_category::text = ANY (ARRAY['normal'::character varying, 'warning'::character varying, 'danger'::character varying]::text[])),
    description text,
    symptom_type_id bigint NOT NULL DEFAULT nextval('symptom_types_symptom_type_id_seq'::regclass),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT symptom_types_pkey PRIMARY KEY (symptom_type_id)
);

-- Pregnancy Symptoms (links to clinical_encounters)
CREATE TABLE public.pregnancy_symptoms (
    pregnancy_id bigint NOT NULL,
    encounter_id bigint,
    symptom_type_id bigint NOT NULL,
    notes text,
    symptom_id bigint NOT NULL DEFAULT nextval('pregnancy_symptoms_symptom_id_seq'::regclass),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pregnancy_symptoms_pkey PRIMARY KEY (symptom_id),
    CONSTRAINT pregnancy_symptoms_pregnancy_id_fkey FOREIGN KEY (pregnancy_id) REFERENCES public.pregnancies(pregnancy_id) ON DELETE CASCADE,
    CONSTRAINT pregnancy_symptoms_encounter_id_fkey FOREIGN KEY (encounter_id) REFERENCES public.clinical_encounters(encounter_id) ON DELETE SET NULL,
    CONSTRAINT pregnancy_symptoms_symptom_type_id_fkey FOREIGN KEY (symptom_type_id) REFERENCES public.symptom_types(symptom_type_id) ON DELETE RESTRICT
);

-- Pregnancy Risk Assessments
CREATE TABLE public.pregnancy_risk_assessments (
    pregnancy_id bigint NOT NULL,
    ai_response_id bigint,
    risk_level character varying,
    reviewed_by bigint,
    pregnancy_risk_id bigint NOT NULL DEFAULT nextval('pregnancy_risk_assessments_pregnancy_risk_id_seq'::regclass),
    assessed_by_ai boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pregnancy_risk_assessments_pkey PRIMARY KEY (pregnancy_risk_id),
    CONSTRAINT pregnancy_risk_assessments_pregnancy_id_fkey FOREIGN KEY (pregnancy_id) REFERENCES public.pregnancies(pregnancy_id) ON DELETE CASCADE,
    CONSTRAINT pregnancy_risk_assessments_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES public.accounts(account_id) ON DELETE SET NULL
);

-- Pregnancy Risk Factors
CREATE TABLE public.pregnancy_risk_factors (
    pregnancy_risk_id bigint NOT NULL,
    factor character varying NOT NULL,
    risk_influence character varying,
    source_table character varying,
    source_id bigint,
    risk_factor_id bigint NOT NULL DEFAULT nextval('pregnancy_risk_factors_risk_factor_id_seq'::regclass),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pregnancy_risk_factors_pkey PRIMARY KEY (risk_factor_id),
    CONSTRAINT pregnancy_risk_factors_pregnancy_risk_id_fkey FOREIGN KEY (pregnancy_risk_id) REFERENCES public.pregnancy_risk_assessments(pregnancy_risk_id) ON DELETE CASCADE
);

-- ============================================================
-- 6. CHILDREN & PEDIATRICS
-- ============================================================

-- Children
CREATE TABLE public.children (
    guardian_id bigint,
    has_guardian_only boolean DEFAULT false,
    mother_id bigint,
    pregnancy_id bigint,
    first_name character varying,
    last_name character varying,
    middle_name character varying,
    extension_name character varying,
    sex character varying 
        CHECK (sex::text = ANY (ARRAY['male'::character varying, 'female'::character varying]::text[])),
    child_id bigint NOT NULL DEFAULT nextval('children_child_id_seq'::regclass),
    added_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT children_pkey PRIMARY KEY (child_id),
    CONSTRAINT children_mother_id_fkey FOREIGN KEY (mother_id) REFERENCES public.mothers(mother_id) ON DELETE SET NULL,
    CONSTRAINT children_guardian_id_fkey FOREIGN KEY (guardian_id) REFERENCES public.guardians(guardian_id) ON DELETE SET NULL,
    CONSTRAINT children_pregnancy_id_fkey FOREIGN KEY (pregnancy_id) REFERENCES public.pregnancies(pregnancy_id) ON DELETE SET NULL
);

-- Birth Details
CREATE TABLE public.birth_details (
    birthplace_facility text,
    child_id bigint NOT NULL UNIQUE,
    birthdate date,
    birth_weight numeric,
    birth_length numeric,
    birthplace_city_municipality character varying,
    birthplace_province character varying,
    delivery_type character varying,
    apgar_score integer CHECK (apgar_score >= 0 AND apgar_score <= 10),
    birth_details_id bigint NOT NULL DEFAULT nextval('birth_details_birth_details_id_seq'::regclass),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT birth_details_pkey PRIMARY KEY (birth_details_id),
    CONSTRAINT birth_details_child_id_fkey FOREIGN KEY (child_id) REFERENCES public.children(child_id) ON DELETE CASCADE
);

-- Child Growth Records (WHO standards)
CREATE TABLE public.child_growth_records (
    child_id bigint NOT NULL,
    measurement_date date NOT NULL,
    child_weight numeric,
    child_height numeric,
    head_circumference_cm numeric,
    weight_for_age_zscore numeric,
    height_for_age_zscore numeric,
    bmi_for_age_zscore numeric,
    recorded_by bigint,
    notes text,
    child_details_id bigint NOT NULL DEFAULT nextval('child_growth_records_growth_id_seq'::regclass),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT child_growth_records_pkey PRIMARY KEY (child_details_id),
    CONSTRAINT child_growth_records_child_id_fkey FOREIGN KEY (child_id) REFERENCES public.children(child_id) ON DELETE CASCADE,
    CONSTRAINT child_growth_records_recorded_by_fkey FOREIGN KEY (recorded_by) REFERENCES public.midwives(midwife_id) ON DELETE SET NULL
);

-- Vaccines Catalog
CREATE TABLE public.vaccines (
    vaccine_name character varying NOT NULL,
    dose_number integer NOT NULL,
    recommended_age_months numeric NOT NULL,
    target_recipients character varying NOT NULL 
        CHECK (target_recipients::text = ANY (ARRAY['child'::character varying, 'mother'::character varying]::text[])),
    notes text,
    vaccine_id bigint NOT NULL DEFAULT nextval('vaccines_vaccine_id_seq'::regclass),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    poster_category integer,
    CONSTRAINT vaccines_pkey PRIMARY KEY (vaccine_id)
);

-- Immunization Schedule
CREATE TABLE public.immunization_schedule (
    facility_id bigint NOT NULL,
    vaccine_id bigint NOT NULL,
    schedule_date date NOT NULL,
    immunization_schedule_id bigint NOT NULL DEFAULT nextval('immunization_schedule_immunization_schedule_id_seq'::regclass),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    notes text,
    CONSTRAINT immunization_schedule_pkey PRIMARY KEY (immunization_schedule_id),
    CONSTRAINT immunization_schedule_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.health_facilities(facility_id) ON DELETE CASCADE,
    CONSTRAINT immunization_schedule_vaccine_id_fkey FOREIGN KEY (vaccine_id) REFERENCES public.vaccines(vaccine_id) ON DELETE CASCADE
);

-- Immunization Records
CREATE TABLE public.immunization_records (
    child_id bigint NOT NULL,
    vaccine_id bigint NOT NULL,
    vaccination_date date NOT NULL,
    administered_by bigint,
    dose_number integer NOT NULL DEFAULT 1,
    next_due_date date,
    status character varying DEFAULT 'administered'::character varying 
        CHECK (status::text = ANY (ARRAY['administered'::character varying, 'missed'::character varying, 'scheduled'::character varying]::text[])),
    remarks text,
    immunization_record_id bigint NOT NULL DEFAULT nextval('immunization_records_immunization_record_id_seq'::regclass),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT immunization_records_pkey PRIMARY KEY (immunization_record_id),
    CONSTRAINT immunization_records_child_id_fkey FOREIGN KEY (child_id) REFERENCES public.children(child_id) ON DELETE CASCADE,
    CONSTRAINT immunization_records_vaccine_id_fkey FOREIGN KEY (vaccine_id) REFERENCES public.vaccines(vaccine_id) ON DELETE RESTRICT,
    CONSTRAINT immunization_records_administered_by_fkey FOREIGN KEY (administered_by) REFERENCES public.midwives(midwife_id) ON DELETE SET NULL
);

-- ============================================================
-- 7. INVENTORY SYSTEM
-- ============================================================

-- Inventory Items
CREATE TABLE public.inventory_items (
    item_id bigint NOT NULL DEFAULT nextval('inventory_items_item_id_seq'::regclass),
    name character varying NOT NULL UNIQUE,
    item_type character varying NOT NULL 
        CHECK (item_type::text = ANY (ARRAY['vaccine'::character varying, 'supplement'::character varying, 'medical_device'::character varying, 'contraceptive'::character varying]::text[])),
    unit_of_measure character varying NOT NULL,
    minimum_stock_threshold integer DEFAULT 50,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT inventory_items_pkey PRIMARY KEY (item_id)
);

-- Inventory Batches
CREATE TABLE public.inventory_batches (
    batch_id bigint NOT NULL DEFAULT nextval('inventory_batches_batch_id_seq'::regclass),
    item_id bigint NOT NULL,
    batch_number character varying NOT NULL,
    quantity_received integer NOT NULL,
    quantity_remaining integer NOT NULL,
    received_date date NOT NULL DEFAULT CURRENT_DATE,
    expiration_date date NOT NULL,
    manufacturer character varying,
    status character varying DEFAULT 'active'::character varying 
        CHECK (status::text = ANY (ARRAY['active'::character varying, 'expired'::character varying, 'discarded'::character varying]::text[])),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT inventory_batches_pkey PRIMARY KEY (batch_id),
    CONSTRAINT inventory_batches_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.inventory_items(item_id) ON DELETE CASCADE,
    CONSTRAINT chk_batch_quantities CHECK (quantity_received >= 0 AND quantity_remaining >= 0 AND quantity_remaining <= quantity_received),
    CONSTRAINT chk_batch_expiration CHECK (expiration_date >= received_date)
);

-- Inventory Transactions
CREATE TABLE public.inventory_transactions (
    transaction_id bigint NOT NULL DEFAULT nextval('inventory_transactions_transaction_id_seq'::regclass),
    batch_id bigint NOT NULL,
    transaction_type character varying NOT NULL 
        CHECK (transaction_type::text = ANY (ARRAY['receipt'::character varying, 'dispense'::character varying, 'adjustment'::character varying, 'expiry_disposal'::character varying]::text[])),
    quantity integer NOT NULL,
    reference_type character varying,
    reference_id bigint,
    performed_by bigint,
    logged_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT inventory_transactions_pkey PRIMARY KEY (transaction_id),
    CONSTRAINT inventory_transactions_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.inventory_batches(batch_id) ON DELETE CASCADE,
    CONSTRAINT inventory_transactions_performed_by_fkey FOREIGN KEY (performed_by) REFERENCES public.accounts(account_id) ON DELETE SET NULL
);

-- ============================================================
-- 8. SCHEDULING & NOTIFICATIONS
-- ============================================================

-- Schedules
CREATE TABLE public.schedules (
    schedule_id bigint NOT NULL DEFAULT nextval('schedules_schedule_id_seq'::regclass),
    mother_id bigint NOT NULL,
    pregnancy_id bigint,
    facility_id bigint,
    schedule_date date NOT NULL,
    schedule_time time,
    visit_type character varying NOT NULL 
        CHECK (visit_type::text = ANY (ARRAY['prenatal_checkup'::character varying, 'postpartum'::character varying, 'immunization'::character varying, 'consultation'::character varying]::text[])),
    status character varying DEFAULT 'scheduled'::character varying 
        CHECK (status::text = ANY (ARRAY['scheduled'::character varying, 'completed'::character varying, 'missed'::character varying, 'cancelled'::character varying]::text[])),
    is_automated boolean DEFAULT false,
    notes text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT schedules_pkey PRIMARY KEY (schedule_id),
    CONSTRAINT schedules_mother_id_fkey FOREIGN KEY (mother_id) REFERENCES public.mothers(mother_id) ON DELETE CASCADE,
    CONSTRAINT schedules_pregnancy_id_fkey FOREIGN KEY (pregnancy_id) REFERENCES public.pregnancies(pregnancy_id) ON DELETE SET NULL,
    CONSTRAINT schedules_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.health_facilities(facility_id) ON DELETE SET NULL
);

-- Notifications
CREATE TABLE public.notifications (
    notification_id bigint NOT NULL DEFAULT nextval('notifications_notification_id_seq'::regclass),
    account_id bigint NOT NULL,
    title character varying NOT NULL,
    message text NOT NULL,
    type character varying DEFAULT 'general'::character varying 
        CHECK (type::text = ANY (ARRAY['checkup_reminder'::character varying, 'vaccine_reminder'::character varying, 'general'::character varying]::text[])),
    is_read boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT notifications_pkey PRIMARY KEY (notification_id),
    CONSTRAINT notifications_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.accounts(account_id) ON DELETE CASCADE
);

-- Device Tokens (FCM)
CREATE TABLE public.device_tokens (
    device_token_id bigint NOT NULL DEFAULT nextval('device_tokens_device_token_id_seq'::regclass),
    account_id bigint NOT NULL,
    fcm_token text NOT NULL,
    platform character varying DEFAULT 'android'::character varying 
        CHECK (platform::text = ANY (ARRAY['android'::character varying, 'ios'::character varying]::text[])),
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT device_tokens_pkey PRIMARY KEY (device_token_id),
    CONSTRAINT device_tokens_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.accounts(account_id) ON DELETE CASCADE
);

-- ============================================================
-- 9. AI & ANALYTICS
-- ============================================================

-- AI Responses
CREATE TABLE public.ai_responses (
    ai_response_id bigint NOT NULL DEFAULT nextval('ai_responses_ai_response_id_seq'::regclass),
    response_type character varying NOT NULL,
    reference_table character varying,
    reference_id bigint,
    ai_model character varying,
    confidence_score numeric,
    response text NOT NULL,
    response_category character varying,
    approved_by bigint,
    status character varying DEFAULT 'generated'::character varying,
    generated_by_ai boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ai_responses_pkey PRIMARY KEY (ai_response_id),
    CONSTRAINT ai_responses_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.accounts(account_id) ON DELETE SET NULL
);

-- AI Edit History
CREATE TABLE public.ai_edit_history (
    ai_edit_history_id bigint NOT NULL DEFAULT nextval('ai_edit_history_ai_edit_history_id_seq'::regclass),
    ai_response_id bigint NOT NULL,
    old_content text,
    new_content text,
    edited_by bigint,
    edit_reason text,
    edited_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ai_edit_history_pkey PRIMARY KEY (ai_edit_history_id),
    CONSTRAINT ai_edit_history_ai_response_id_fkey FOREIGN KEY (ai_response_id) REFERENCES public.ai_responses(ai_response_id) ON DELETE CASCADE,
    CONSTRAINT ai_edit_history_edited_by_fkey FOREIGN KEY (edited_by) REFERENCES public.accounts(account_id) ON DELETE SET NULL
);

-- AI Prompt Logs
CREATE TABLE public.ai_prompt_logs (
    prompt_log_id bigint NOT NULL DEFAULT nextval('ai_prompt_logs_prompt_log_id_seq'::regclass),
    ai_response_id bigint,
    prompt text,
    model_used character varying,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ai_prompt_logs_pkey PRIMARY KEY (prompt_log_id),
    CONSTRAINT ai_prompt_logs_ai_response_id_fkey FOREIGN KEY (ai_response_id) REFERENCES public.ai_responses(ai_response_id) ON DELETE SET NULL
);

-- Weight Gain Evaluations
CREATE TABLE public.weight_gain_evaluations (
    evaluation_id bigint NOT NULL DEFAULT nextval('weight_gain_evaluations_evaluation_id_seq'::regclass),
    pregnancy_id bigint NOT NULL,
    encounter_id bigint,
    mode character varying NOT NULL 
        CHECK (mode::text = ANY (ARRAY['FULL'::character varying, 'TREND'::character varying]::text[])),
    bmi_category character varying,
    baseline_weight numeric,
    baseline_week numeric,
    current_weight numeric,
    current_week numeric,
    expected_gain numeric,
    actual_gain numeric,
    weekly_gain numeric,
    status character varying NOT NULL 
        CHECK (status::text = ANY (ARRAY['NORMAL'::character varying, 'LOW'::character varying, 'HIGH'::character varying, 'INSUFFICIENT DATA'::character varying]::text[])),
    confidence character varying NOT NULL 
        CHECK (confidence::text = ANY (ARRAY['HIGH'::character varying, 'MEDIUM'::character varying, 'LOW'::character varying]::text[])),
    message text,
    flags ARRAY,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT weight_gain_evaluations_pkey PRIMARY KEY (evaluation_id),
    CONSTRAINT weight_gain_evaluations_pregnancy_id_fkey FOREIGN KEY (pregnancy_id) REFERENCES public.pregnancies(pregnancy_id) ON DELETE CASCADE,
    CONSTRAINT weight_gain_evaluations_encounter_id_fkey FOREIGN KEY (encounter_id) REFERENCES public.clinical_encounters(encounter_id) ON DELETE SET NULL
);

-- ============================================================
-- 10. FILES & OCR
-- ============================================================

-- Files
CREATE TABLE public.files (
    file_id bigint NOT NULL DEFAULT nextval('files_file_id_seq'::regclass),
    bucket_name character varying NOT NULL,
    file_path text NOT NULL,
    file_name character varying,
    file_category character varying,
    mime_type character varying,
    file_size bigint,
    uploaded_by bigint,
    reference_type character varying,
    reference_id bigint,
    processing_type character varying,
    ai_processed boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT files_pkey PRIMARY KEY (file_id),
    CONSTRAINT files_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES public.accounts(account_id) ON DELETE SET NULL
);

-- OCR Results
CREATE TABLE public.ocr_results (
    ocr_result_id bigint NOT NULL DEFAULT nextval('ocr_results_ocr_result_id_seq'::regclass),
    file_id bigint NOT NULL,
    extracted_text text,
    structured_data jsonb,
    processed_by_ai boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ocr_results_pkey PRIMARY KEY (ocr_result_id),
    CONSTRAINT ocr_results_file_id_fkey FOREIGN KEY (file_id) REFERENCES public.files(file_id) ON DELETE CASCADE
);

-- ============================================================
-- 11. CHATBOT & JOURNAL
-- ============================================================

-- Chatbot Sessions
CREATE TABLE public.chatbot_sessions (
    session_id bigint NOT NULL DEFAULT nextval('chatbot_sessions_session_id_seq'::regclass),
    mother_id bigint NOT NULL,
    title character varying DEFAULT 'Kausap si Ate Assistant'::character varying,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chatbot_sessions_pkey PRIMARY KEY (session_id),
    CONSTRAINT chatbot_sessions_mother_id_fkey FOREIGN KEY (mother_id) REFERENCES public.mothers(mother_id) ON DELETE CASCADE
);

-- Chatbot Messages
CREATE TABLE public.chatbot_messages (
    message_id bigint NOT NULL DEFAULT nextval('chatbot_messages_message_id_seq'::regclass),
    session_id bigint NOT NULL,
    content text NOT NULL,
    is_user boolean NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chatbot_messages_pkey PRIMARY KEY (message_id),
    CONSTRAINT chatbot_messages_session_id_fkey FOREIGN KEY (session_id) REFERENCES public.chatbot_sessions(session_id) ON DELETE CASCADE
);

-- Journal Entries
CREATE TABLE public.journal_entries (
    entry_id bigint NOT NULL DEFAULT nextval('journal_entries_entry_id_seq'::regclass),
    mother_id bigint NOT NULL,
    title character varying,
    content text NOT NULL,
    mood character varying,
    entry_date date DEFAULT CURRENT_DATE,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT journal_entries_pkey PRIMARY KEY (entry_id),
    CONSTRAINT journal_entries_mother_id_fkey FOREIGN KEY (mother_id) REFERENCES public.mothers(mother_id) ON DELETE CASCADE
);

-- ============================================================
-- 12. MEDICATIONS
-- ============================================================

-- Mother Medications (prescriptions)
CREATE TABLE public.mother_medications (
    mother_medication_id bigint NOT NULL DEFAULT nextval('mother_medications_mother_medication_id_seq'::regclass),
    mother_id bigint NOT NULL,
    encounter_id bigint,
    mother_medication_name character varying NOT NULL,
    frequency character varying,
    quantity integer,
    start_date date,
    end_date date,
    status character varying DEFAULT 'active'::character varying 
        CHECK (status::text = ANY (ARRAY['active'::character varying, 'completed'::character varying, 'stopped'::character varying]::text[])),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT mother_medications_pkey PRIMARY KEY (mother_medication_id),
    CONSTRAINT mother_medications_mother_id_fkey FOREIGN KEY (mother_id) REFERENCES public.mothers(mother_id) ON DELETE CASCADE,
    CONSTRAINT mother_medications_encounter_id_fkey FOREIGN KEY (encounter_id) REFERENCES public.clinical_encounters(encounter_id) ON DELETE SET NULL
);

-- Given Medications (dispensed)
CREATE TABLE public.given_medications (
    given_medication_id bigint NOT NULL DEFAULT nextval('given_medications_given_medication_id_seq'::regclass),
    mother_id bigint NOT NULL,
    encounter_id bigint,
    inventory_batch_id bigint,
    given_medication_name character varying NOT NULL,
    quantity integer NOT NULL,
    date_given date NOT NULL,
    CONSTRAINT given_medications_pkey PRIMARY KEY (given_medication_id),
    CONSTRAINT given_medications_mother_id_fkey FOREIGN KEY (mother_id) REFERENCES public.mothers(mother_id) ON DELETE CASCADE,
    CONSTRAINT given_medications_encounter_id_fkey FOREIGN KEY (encounter_id) REFERENCES public.clinical_encounters(encounter_id) ON DELETE SET NULL,
    CONSTRAINT given_medications_inventory_batch_id_fkey FOREIGN KEY (inventory_batch_id) REFERENCES public.inventory_batches(batch_id) ON DELETE RESTRICT
);

-- ============================================================
-- 13. AUDIT TRAIL
-- ============================================================

CREATE TABLE public.audit_trail (
    audit_id bigint NOT NULL DEFAULT nextval('audit_trail_audit_id_seq'::regclass),
    account_id bigint,
    action character varying NOT NULL,
    table_name character varying,
    old_data jsonb,
    new_data jsonb,
    description text,
    ip_address character varying,
    action_timestamp timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    row_id character varying,
    CONSTRAINT audit_trail_pkey PRIMARY KEY (audit_id),
    CONSTRAINT audit_trail_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.accounts(account_id) ON DELETE SET NULL
);

-- ============================================================
-- 14. POSTER COLUMNS (fixed bhc_id → facility_id)
-- ============================================================

CREATE TABLE public.poster_columns (
    column_id integer NOT NULL DEFAULT nextval('poster_columns_column_id_seq'::regclass),
    facility_id bigint NOT NULL,
    title text NOT NULL,
    subtitle text,
    vaccine_ids ARRAY NOT NULL DEFAULT '{}'::integer[],
    display_order integer NOT NULL DEFAULT 0,
    CONSTRAINT poster_columns_pkey PRIMARY KEY (column_id),
    CONSTRAINT poster_columns_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.health_facilities(facility_id) ON DELETE CASCADE
);

-- ============================================================
-- 15. MATERNAL VITALS (timestamps fixed)
-- ============================================================

CREATE TABLE public.maternal_vitals (
    vital_id bigint NOT NULL DEFAULT nextval('maternal_vitals_vital_id_seq'::regclass),
    pregnancy_id bigint NOT NULL,
    mother_id bigint NOT NULL,
    age_of_gestation numeric,
    weight_kg numeric NOT NULL,
    height_cm numeric NOT NULL,
    notes text,
    recorded_at timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT maternal_vitals_pkey PRIMARY KEY (vital_id),
    CONSTRAINT maternal_vitals_pregnancy_id_fkey FOREIGN KEY (pregnancy_id) REFERENCES public.pregnancies(pregnancy_id) ON DELETE CASCADE,
    CONSTRAINT maternal_vitals_mother_id_fkey FOREIGN KEY (mother_id) REFERENCES public.mothers(mother_id) ON DELETE CASCADE
);

-- ============================================================
-- 16. TRIGGERS & AUTOMATION
-- ============================================================

-- OB History Auto-Update Trigger
CREATE OR REPLACE FUNCTION update_mother_ob_history()
RETURNS TRIGGER AS $$
DECLARE
    v_mother_id bigint;
    v_gravida integer;
    v_para integer;
    v_abortus integer;
    v_living_children integer;
BEGIN
    SELECT mother_id INTO v_mother_id
    FROM pregnancies
    WHERE pregnancy_id = NEW.pregnancy_id;

    -- Gravida: total pregnancies
    SELECT COUNT(*) INTO v_gravida
    FROM pregnancies
    WHERE mother_id = v_mother_id;

    -- Para: live births + stillbirths
    SELECT COUNT(*) INTO v_para
    FROM pregnancies p
    JOIN pregnancy_outcomes po ON p.pregnancy_id = po.pregnancy_id
    WHERE p.mother_id = v_mother_id
      AND po.outcome IN ('live_birth', 'stillbirth');

    -- Abortus: miscarriage/abortion/ectopic/fetal_loss/vanishing_twin
    SELECT COUNT(*) INTO v_abortus
    FROM pregnancies p
    JOIN pregnancy_outcomes po ON p.pregnancy_id = po.pregnancy_id
    WHERE p.mother_id = v_mother_id
      AND po.outcome IN ('miscarriage', 'abortion', 'ectopic', 'fetal_loss', 'vanishing_twin');

    -- Living children
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
    AFTER INSERT OR UPDATE OR DELETE ON pregnancy_outcomes
    FOR EACH ROW
    EXECUTE FUNCTION update_mother_ob_history();

-- Living Children Auto-Update
CREATE OR REPLACE FUNCTION update_mother_living_children()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        UPDATE mothers
        SET living_children = (SELECT COUNT(*) FROM children WHERE mother_id = OLD.mother_id)
        WHERE mother_id = OLD.mother_id;
    ELSE
        UPDATE mothers
        SET living_children = (SELECT COUNT(*) FROM children WHERE mother_id = NEW.mother_id)
        WHERE mother_id = NEW.mother_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_living_children
    AFTER INSERT OR DELETE ON children
    FOR EACH ROW
    EXECUTE FUNCTION update_mother_living_children();

-- Pre-pregnancy BMI Calculation
CREATE OR REPLACE FUNCTION calculate_pregnancy_bmi()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.pre_pregnancy_weight IS NOT NULL AND NEW.height_cm > 0 THEN
        NEW.pre_pregnancy_bmi := ROUND(
            (NEW.pre_pregnancy_weight / ((NEW.height_cm / 100.0) * (NEW.height_cm / 100.0)))::numeric,
            2
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_calculate_pregnancy_bmi
    BEFORE INSERT OR UPDATE OF pre_pregnancy_weight, height_cm ON pregnancies
    FOR EACH ROW
    EXECUTE FUNCTION calculate_pregnancy_bmi();

-- Inventory Auto-Deduct on Given Medications
CREATE OR REPLACE FUNCTION deduct_inventory_on_given_medication()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.inventory_batch_id IS NOT NULL THEN
        UPDATE inventory_batches
        SET quantity_remaining = quantity_remaining - NEW.quantity
        WHERE batch_id = NEW.inventory_batch_id;

        INSERT INTO inventory_transactions (batch_id, transaction_type, quantity, reference_type, reference_id)
        VALUES (NEW.inventory_batch_id, 'dispense', -NEW.quantity, 'given_medication', NEW.given_medication_id);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_deduct_inventory_medication
    AFTER INSERT ON given_medications
    FOR EACH ROW
    EXECUTE FUNCTION deduct_inventory_on_given_medication();

-- ============================================================
-- 17. PERFORMANCE INDEXES
-- ============================================================

-- Account & Profile Indexes
CREATE INDEX idx_accounts_type ON accounts(account_type);
CREATE INDEX idx_accounts_status ON accounts(status);
CREATE INDEX idx_accounts_email ON accounts(email_address);
CREATE INDEX idx_accounts_phone ON accounts(phone_number);

-- Facility Indexes
CREATE INDEX idx_facility_assignments_account ON facility_assignments(account_id);
CREATE INDEX idx_facility_assignments_facility ON facility_assignments(facility_id);
CREATE INDEX idx_facility_assignments_active ON facility_assignments(is_active) WHERE is_active = true;

-- Mother Indexes
CREATE INDEX idx_mothers_status ON mothers(status);
CREATE INDEX idx_mothers_barangay ON mothers(barangay);

-- Pregnancy Indexes
CREATE INDEX idx_pregnancies_mother ON pregnancies(mother_id);
CREATE INDEX idx_pregnancies_status ON pregnancies(status);
CREATE INDEX idx_pregnancies_active ON pregnancies(status) WHERE status = 'ongoing';

-- Clinical Encounter Indexes
CREATE INDEX idx_clinical_encounters_pregnancy ON clinical_encounters(pregnancy_id);
CREATE INDEX idx_clinical_encounters_mother ON clinical_encounters(mother_id);
CREATE INDEX idx_clinical_encounters_type ON clinical_encounters(encounter_type);
CREATE INDEX idx_clinical_encounters_date ON clinical_encounters(mother_id, encounter_datetime DESC);
CREATE INDEX idx_clinical_encounters_recorded_by ON clinical_encounters(recorded_by);

-- Children Indexes
CREATE INDEX idx_children_mother ON children(mother_id);
CREATE INDEX idx_children_guardian ON children(guardian_id);

-- Immunization Indexes
CREATE INDEX idx_immunization_records_child ON immunization_records(child_id);
CREATE INDEX idx_immunization_records_date ON immunization_records(vaccination_date);

-- Inventory Indexes
CREATE INDEX idx_inventory_batches_item ON inventory_batches(item_id);
CREATE INDEX idx_inventory_batches_expiry ON inventory_batches(expiration_date);
CREATE INDEX idx_inventory_batches_status ON inventory_batches(status);

-- Schedule Indexes
CREATE INDEX idx_schedules_mother ON schedules(mother_id);
CREATE INDEX idx_schedules_date ON schedules(schedule_date, schedule_time);
CREATE INDEX idx_schedules_status ON schedules(status);

-- Notification Indexes
CREATE INDEX idx_notifications_account ON notifications(account_id, is_read);
CREATE INDEX idx_notifications_unread ON notifications(account_id) WHERE is_read = false;

-- Audit Indexes
CREATE INDEX idx_audit_trail_account ON audit_trail(account_id);
CREATE INDEX idx_audit_trail_timestamp ON audit_trail(action_timestamp DESC);

-- File Indexes
CREATE INDEX idx_files_reference ON files(reference_type, reference_id);
CREATE INDEX idx_files_uploaded_by ON files(uploaded_by);

-- Journal Indexes
CREATE INDEX idx_journal_entries_mother ON journal_entries(mother_id);

-- Chatbot Indexes
CREATE INDEX idx_chatbot_messages_session ON chatbot_messages(session_id);

-- Risk Assessment Indexes
CREATE INDEX idx_pregnancy_risk_pregnancy ON pregnancy_risk_assessments(pregnancy_id);

-- ============================================================
-- 18. ROW LEVEL SECURITY (RLS) SETUP
-- ============================================================

-- Enable RLS on all tables
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

-- Grant usage on schema
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- Grant table permissions
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO service_role;

-- ============================================================
-- 19. ROW LEVEL SECURITY POLICIES
-- ============================================================

-- Helper: Create a function to get current user's account_id from auth.users
CREATE OR REPLACE FUNCTION public.get_current_account_id()
RETURNS bigint AS $$
DECLARE
    v_account_id bigint;
BEGIN
    SELECT account_id INTO v_account_id
    FROM public.accounts
    WHERE auth_id = auth.uid();
    RETURN v_account_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Helper: Check if current user has a specific role
CREATE OR REPLACE FUNCTION public.has_role(required_role text)
RETURNS boolean AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.accounts
        WHERE auth_id = auth.uid() AND account_type = required_role
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- ACCOUNTS - Users can read their own, admins can read all
-- ============================================================
CREATE POLICY "Users can read own account" ON public.accounts
    FOR SELECT USING (auth_id = auth.uid());

CREATE POLICY "Admins and midwives can read all accounts" ON public.accounts
    FOR SELECT USING (has_role('admin') OR has_role('midwife'));

CREATE POLICY "Users can update own account" ON public.accounts
    FOR UPDATE USING (auth_id = auth.uid());

-- ============================================================
-- HEALTH FACILITIES - All authenticated can read
-- ============================================================
CREATE POLICY "Authenticated users can read facilities" ON public.health_facilities
    FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "Admins can manage facilities" ON public.health_facilities
    FOR ALL USING (has_role('admin'));

-- ============================================================
-- FACILITY ASSIGNMENTS
-- ============================================================
CREATE POLICY "Users can read own assignments" ON public.facility_assignments
    FOR SELECT USING (account_id = get_current_account_id());

CREATE POLICY "Midwives and admins can read facility assignments" ON public.facility_assignments
    FOR SELECT USING (has_role('admin') OR has_role('midwife'));

CREATE POLICY "Admins can manage assignments" ON public.facility_assignments
    FOR ALL USING (has_role('admin'));

-- ============================================================
-- MIDWIVES - Midwives can read own, admins all
-- ============================================================
CREATE POLICY "Midwives can read own profile" ON public.midwives
    FOR SELECT USING (account_id = get_current_account_id());

CREATE POLICY "Admins can manage midwives" ON public.midwives
    FOR ALL USING (has_role('admin'));

-- ============================================================
-- MOTHERS - Mothers read own, midwives/admins read assigned
-- ============================================================
CREATE POLICY "Mothers can read own profile" ON public.mothers
    FOR SELECT USING (account_id = get_current_account_id());

CREATE POLICY "Mothers can update own profile" ON public.mothers
    FOR UPDATE USING (account_id = get_current_account_id());

CREATE POLICY "Midwives and admins can read mothers in their facility" ON public.mothers
    FOR SELECT USING (
        has_role('admin') OR has_role('midwife')
    );

-- ============================================================
-- PREGNANCIES
-- ============================================================
CREATE POLICY "Mothers can read own pregnancies" ON public.pregnancies
    FOR SELECT USING (
        mother_id IN (SELECT mother_id FROM public.mothers WHERE account_id = get_current_account_id())
    );

CREATE POLICY "Midwives and admins can read all pregnancies" ON public.pregnancies
    FOR SELECT USING (has_role('admin') OR has_role('midwife'));

CREATE POLICY "Midwives and admins can manage pregnancies" ON public.pregnancies
    FOR ALL USING (has_role('admin') OR has_role('midwife'));

-- ============================================================
-- CLINICAL ENCOUNTERS
-- ============================================================
CREATE POLICY "Mothers can read own encounters" ON public.clinical_encounters
    FOR SELECT USING (
        mother_id IN (SELECT mother_id FROM public.mothers WHERE account_id = get_current_account_id())
    );

CREATE POLICY "Midwives and admins can read all encounters" ON public.clinical_encounters
    FOR SELECT USING (has_role('admin') OR has_role('midwife'));

CREATE POLICY "Midwives and admins can manage encounters" ON public.clinical_encounters
    FOR ALL USING (has_role('admin') OR has_role('midwife'));

-- ============================================================
-- PRENATAL CHECKUPS, LAB TESTS, ULTRASOUNDS, DELIVERIES
-- Same pattern: mothers read own, midwives/admins manage
-- ============================================================
CREATE POLICY "Mothers can read own checkups" ON public.prenatal_checkups
    FOR SELECT USING (
        pregnancy_id IN (
            SELECT pregnancy_id FROM public.pregnancies 
            WHERE mother_id IN (SELECT mother_id FROM public.mothers WHERE account_id = get_current_account_id())
        )
    );

CREATE POLICY "Midwives and admins can manage checkups" ON public.prenatal_checkups
    FOR ALL USING (has_role('admin') OR has_role('midwife'));

CREATE POLICY "Mothers can read own lab tests" ON public.lab_tests
    FOR SELECT USING (
        pregnancy_id IN (
            SELECT pregnancy_id FROM public.pregnancies 
            WHERE mother_id IN (SELECT mother_id FROM public.mothers WHERE account_id = get_current_account_id())
        )
    );

CREATE POLICY "Midwives and admins can manage lab tests" ON public.lab_tests
    FOR ALL USING (has_role('admin') OR has_role('midwife'));

CREATE POLICY "Mothers can read own ultrasounds" ON public.ultrasounds
    FOR SELECT USING (
        pregnancy_id IN (
            SELECT pregnancy_id FROM public.pregnancies 
            WHERE mother_id IN (SELECT mother_id FROM public.mothers WHERE account_id = get_current_account_id())
        )
    );

CREATE POLICY "Midwives and admins can manage ultrasounds" ON public.ultrasounds
    FOR ALL USING (has_role('admin') OR has_role('midwife'));

CREATE POLICY "Mothers can read own deliveries" ON public.deliveries
    FOR SELECT USING (
        pregnancy_id IN (
            SELECT pregnancy_id FROM public.pregnancies 
            WHERE mother_id IN (SELECT mother_id FROM public.mothers WHERE account_id = get_current_account_id())
        )
    );

CREATE POLICY "Midwives and admins can manage deliveries" ON public.deliveries
    FOR ALL USING (has_role('admin') OR has_role('midwife'));

-- ============================================================
-- CHILDREN
-- ============================================================
CREATE POLICY "Mothers can read own children" ON public.children
    FOR SELECT USING (
        mother_id IN (SELECT mother_id FROM public.mothers WHERE account_id = get_current_account_id())
    );

CREATE POLICY "Midwives and admins can manage children" ON public.children
    FOR ALL USING (has_role('admin') OR has_role('midwife'));

-- ============================================================
-- IMMUNIZATION RECORDS
-- ============================================================
CREATE POLICY "Mothers can read own children's immunizations" ON public.immunization_records
    FOR SELECT USING (
        child_id IN (
            SELECT child_id FROM public.children 
            WHERE mother_id IN (SELECT mother_id FROM public.mothers WHERE account_id = get_current_account_id())
        )
    );

CREATE POLICY "Midwives and admins can manage immunizations" ON public.immunization_records
    FOR ALL USING (has_role('admin') OR has_role('midwife'));

-- ============================================================
-- NOTIFICATIONS - Users see own
-- ============================================================
CREATE POLICY "Users can read own notifications" ON public.notifications
    FOR SELECT USING (account_id = get_current_account_id());

CREATE POLICY "Users can update own notifications" ON public.notifications
    FOR UPDATE USING (account_id = get_current_account_id());

-- ============================================================
-- DEVICE TOKENS - Users manage own
-- ============================================================
CREATE POLICY "Users can manage own device tokens" ON public.device_tokens
    FOR ALL USING (account_id = get_current_account_id());

-- ============================================================
-- SCHEDULES
-- ============================================================
CREATE POLICY "Mothers can read own schedules" ON public.schedules
    FOR SELECT USING (
        mother_id IN (SELECT mother_id FROM public.mothers WHERE account_id = get_current_account_id())
    );

CREATE POLICY "Midwives and admins can manage schedules" ON public.schedules
    FOR ALL USING (has_role('admin') OR has_role('midwife'));

-- ============================================================
-- CHATBOT - Mothers manage own sessions
-- ============================================================
CREATE POLICY "Mothers can manage own chatbot sessions" ON public.chatbot_sessions
    FOR ALL USING (
        mother_id IN (SELECT mother_id FROM public.mothers WHERE account_id = get_current_account_id())
    );

CREATE POLICY "Mothers can manage own chatbot messages" ON public.chatbot_messages
    FOR ALL USING (
        session_id IN (
            SELECT session_id FROM public.chatbot_sessions
            WHERE mother_id IN (SELECT mother_id FROM public.mothers WHERE account_id = get_current_account_id())
        )
    );

-- ============================================================
-- JOURNAL ENTRIES - Mothers manage own
-- ============================================================
CREATE POLICY "Mothers can manage own journal entries" ON public.journal_entries
    FOR ALL USING (
        mother_id IN (SELECT mother_id FROM public.mothers WHERE account_id = get_current_account_id())
    );

-- ============================================================
-- EMERGENCY CONTACTS, MEDICAL CONDITIONS, ALLERGIES
-- ============================================================
CREATE POLICY "Mothers can read own emergency contacts" ON public.emergency_contacts
    FOR SELECT USING (
        mother_id IN (SELECT mother_id FROM public.mothers WHERE account_id = get_current_account_id())
    );

CREATE POLICY "Mothers can read own medical conditions" ON public.medical_conditions
    FOR SELECT USING (
        mother_id IN (SELECT mother_id FROM public.mothers WHERE account_id = get_current_account_id())
    );

CREATE POLICY "Mothers can read own allergies" ON public.allergies
    FOR SELECT USING (
        mother_id IN (SELECT mother_id FROM public.mothers WHERE account_id = get_current_account_id())
    );

CREATE POLICY "Midwives and admins can manage medical data" ON public.emergency_contacts
    FOR ALL USING (has_role('admin') OR has_role('midwife'));

CREATE POLICY "Midwives and admins can manage medical conditions" ON public.medical_conditions
    FOR ALL USING (has_role('admin') OR has_role('midwife'));

CREATE POLICY "Midwives and admins can manage allergies" ON public.allergies
    FOR ALL USING (has_role('admin') OR has_role('midwife'));

-- ============================================================
-- MEDICATIONS
-- ============================================================
CREATE POLICY "Mothers can read own medications" ON public.mother_medications
    FOR SELECT USING (
        mother_id IN (SELECT mother_id FROM public.mothers WHERE account_id = get_current_account_id())
    );

CREATE POLICY "Midwives and admins can manage medications" ON public.mother_medications
    FOR ALL USING (has_role('admin') OR has_role('midwife'));

CREATE POLICY "Mothers can read own given medications" ON public.given_medications
    FOR SELECT USING (
        mother_id IN (SELECT mother_id FROM public.mothers WHERE account_id = get_current_account_id())
    );

CREATE POLICY "Midwives and admins can manage given medications" ON public.given_medications
    FOR ALL USING (has_role('admin') OR has_role('midwife'));

-- ============================================================
-- INVENTORY - Only admins and midwives
-- ============================================================
CREATE POLICY "Admins and midwives can read inventory" ON public.inventory_items
    FOR SELECT USING (has_role('admin') OR has_role('midwife'));

CREATE POLICY "Admins can manage inventory" ON public.inventory_items
    FOR ALL USING (has_role('admin'));

CREATE POLICY "Admins and midwives can read batches" ON public.inventory_batches
    FOR SELECT USING (has_role('admin') OR has_role('midwife'));

CREATE POLICY "Admins can manage batches" ON public.inventory_batches
    FOR ALL USING (has_role('admin'));

-- ============================================================
-- PUBLIC READ TABLES (symptom types, vaccines, milestones)
-- ============================================================
CREATE POLICY "Anyone can read symptom types" ON public.symptom_types
    FOR SELECT USING (true);

CREATE POLICY "Anyone can read vaccines" ON public.vaccines
    FOR SELECT USING (true);

CREATE POLICY "Anyone can read immunization schedules" ON public.immunization_schedule
    FOR SELECT USING (true);

-- ============================================================
-- AUDIT TRAIL - Admins only
-- ============================================================
CREATE POLICY "Admins can read audit trail" ON public.audit_trail
    FOR SELECT USING (has_role('admin'));

-- ============================================================
-- FILES - Users can read own, midwives/admins can manage
-- ============================================================
CREATE POLICY "Users can read own files" ON public.files
    FOR SELECT USING (uploaded_by = get_current_account_id());

CREATE POLICY "Midwives and admins can read all files" ON public.files
    FOR SELECT USING (has_role('admin') OR has_role('midwife'));

CREATE POLICY "Authenticated users can upload files" ON public.files
    FOR INSERT WITH CHECK (auth.role() = 'authenticated');

-- ============================================================
-- SERVICE ROLE BYPASS (already default in Supabase)
-- service_role automatically bypasses RLS - no policy needed
-- ============================================================