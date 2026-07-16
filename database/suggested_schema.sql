CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
-- Mock/Ensure auth.users schema and table exist for standalone deployment testing
CREATE SCHEMA IF NOT EXISTS auth;
CREATE TABLE IF NOT EXISTS auth.users (
   id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
   email VARCHAR(255) UNIQUE,
   phone VARCHAR(15) UNIQUE,
   raw_user_meta_data JSONB,
   created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);
-- ----------------------------------------------------------------------------
-- 1. IDENTITY & FACILITIES DOMAIN
-- ----------------------------------------------------------------------------
-- Health Facilities: Represents the Barangay Health Centers (BHCs) or Municipal Health Offices
CREATE TABLE health_facilities (
   id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
   name VARCHAR(100) UNIQUE NOT NULL,
   facility_type VARCHAR(30) NOT NULL, -- e.g., 'BHC', 'RHU', 'District Hospital'
   address_street VARCHAR(100),
   barangay VARCHAR(50) NOT NULL,
   municipality VARCHAR(50) NOT NULL DEFAULT 'Santa Cruz',
   province VARCHAR(50) NOT NULL DEFAULT 'Laguna',
   created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
  
   CONSTRAINT chk_facility_type CHECK (facility_type IN ('BHC', 'RHU', 'District Hospital', 'Clinic', 'General Hospital'))
);
-- Profiles: The primary user table linked directly to Supabase Auth (auth.users)
CREATE TABLE profiles (
   id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
   email VARCHAR(255) UNIQUE,
   phone VARCHAR(15) UNIQUE,
   role VARCHAR(20) NOT NULL,
   first_name VARCHAR(50) NOT NULL,
   middle_name VARCHAR(50),
   last_name VARCHAR(50) NOT NULL,
   suffix VARCHAR(10),
   avatar_url TEXT,
   status VARCHAR(15) NOT NULL DEFAULT 'active',
   created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
   updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
  
   CONSTRAINT chk_profile_role CHECK (role IN ('admin', 'midwife', 'mother')),
   CONSTRAINT chk_profile_status CHECK (status IN ('active', 'inactive', 'suspended')),
   CONSTRAINT chk_contact_info CHECK (email IS NOT NULL OR phone IS NOT NULL)
);
-- Health Worker Profiles: Details specific to Midwives, Doctors, and Barangay Health Workers
CREATE TABLE health_worker_profiles (
   profile_id UUID PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
   facility_id UUID REFERENCES health_facilities(id) ON DELETE RESTRICT,
   license_number VARCHAR(50) UNIQUE,
   position VARCHAR(50) NOT NULL, -- e.g., 'Midwife II', 'Barangay Health Worker', 'Doctor'
   hire_date DATE,
   last_login_at TIMESTAMP WITH TIME ZONE
);
-- Mother Profiles: Specialized profile details for maternal patients
CREATE TABLE mother_profiles (
   profile_id UUID PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
   patient_number VARCHAR(30) UNIQUE NOT NULL, -- Auto-generated: INA-YYYY-XXXXX
   registered_facility_id UUID REFERENCES health_facilities(id) ON DELETE SET NULL,
   birthday DATE NOT NULL,
   blood_type VARCHAR(5),
   civil_status VARCHAR(20),
   emergency_contact_name VARCHAR(100),
   emergency_contact_phone VARCHAR(15),
   emergency_contact_relationship VARCHAR(30),
   philhealth_number VARCHAR(20),
   philhealth_status VARCHAR(30) DEFAULT 'Non-Member',
   is_four_ps BOOLEAN DEFAULT FALSE,
   address_street VARCHAR(100),
   barangay VARCHAR(50) NOT NULL,
   municipality VARCHAR(50) NOT NULL,
   province VARCHAR(50) NOT NULL,
  
   CONSTRAINT chk_blood_type CHECK (blood_type IN ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'Rh-')),
   CONSTRAINT chk_philhealth_status CHECK (philhealth_status IN ('Member', 'Dependent', 'Non-Member')),
   CONSTRAINT chk_civil_status CHECK (civil_status IN ('Single', 'Married', 'Widowed', 'Separated', 'Cohabiting'))
);
-- ----------------------------------------------------------------------------
-- 2. PREGNANCY & CLINICAL ENCOUNTERS DOMAIN
-- ----------------------------------------------------------------------------
-- Pregnancies: Tracks maternal history and statistics per gestation
CREATE TABLE pregnancies (
   id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
   mother_id UUID NOT NULL REFERENCES mother_profiles(profile_id) ON DELETE CASCADE,
   lmp_date DATE NOT NULL, -- Last Menstrual Period
   edd DATE NOT NULL, -- Estimated Date of Delivery
   pre_pregnancy_weight_kg NUMERIC(5,2),
   height_cm NUMERIC(5,2) NOT NULL,
   pre_pregnancy_bmi NUMERIC(4,2), -- Calculated automatically or on insert
   gravida INT NOT NULL, -- Number of pregnancies
   para INT NOT NULL, -- Number of births > 20 weeks gest.
   abortions INT NOT NULL DEFAULT 0,
   stillbirths INT NOT NULL DEFAULT 0,
   past_medical_conditions JSONB, -- High-risk flags
   allergies TEXT,
   is_active BOOLEAN NOT NULL DEFAULT TRUE,
   outcome VARCHAR(30),
   actual_delivery_date DATE,
   delivery_location VARCHAR(100),
   created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
  
   CONSTRAINT chk_pregnancy_outcome CHECK (outcome IN ('live_birth', 'stillbirth', 'miscarriage', 'ectopic')),
   CONSTRAINT chk_gravida_para CHECK (gravida >= 1 AND para >= 0 AND abortions >= 0 AND stillbirths >= 0)
);
-- Clinical Encounters: The parent table for every patient contact (checkup, lab test, ultrasound, postpartum)
CREATE TABLE clinical_encounters (
   id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
   pregnancy_id UUID NOT NULL REFERENCES pregnancies(id) ON DELETE CASCADE,
   mother_id UUID NOT NULL REFERENCES mother_profiles(profile_id) ON DELETE RESTRICT,
   facilitator_id UUID NOT NULL REFERENCES health_worker_profiles(profile_id) ON DELETE RESTRICT,
   facility_id UUID NOT NULL REFERENCES health_facilities(id) ON DELETE RESTRICT,
   encounter_type VARCHAR(30) NOT NULL,
   visit_date TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
   aog_weeks INT NOT NULL,
   aog_days INT NOT NULL,
   risk_status VARCHAR(15) NOT NULL DEFAULT 'low',
   ai_summary TEXT,
   midwife_notes TEXT,
   is_midwife_approved BOOLEAN NOT NULL DEFAULT FALSE,
  
   CONSTRAINT chk_encounter_type CHECK (encounter_type IN ('checkup', 'lab_test', 'ultrasound', 'postpartum')),
   CONSTRAINT chk_risk_status CHECK (risk_status IN ('low', 'moderate', 'high', 'critical')),
   CONSTRAINT chk_aog CHECK (aog_weeks >= 0 AND aog_weeks <= 50 AND aog_days >= 0 AND aog_days <= 6)
);
-- Symptom Types: Catalog of symptoms
CREATE TABLE symptom_types (
   id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
   name VARCHAR(50) UNIQUE NOT NULL,
   severity VARCHAR(15) NOT NULL,
  
   CONSTRAINT chk_symptom_severity CHECK (severity IN ('mild', 'moderate', 'severe'))
);
-- Encounter Symptoms: Links encounters to observed symptoms
CREATE TABLE encounter_symptoms (
   encounter_id UUID REFERENCES clinical_encounters(id) ON DELETE CASCADE,
   symptom_id UUID REFERENCES symptom_types(id) ON DELETE RESTRICT,
   notes TEXT,
   PRIMARY KEY (encounter_id, symptom_id)
);
-- Prenatal Checkups: Extends clinical_encounters with physical measurements and fetal assessment
CREATE TABLE prenatal_checkups (
   encounter_id UUID PRIMARY KEY REFERENCES clinical_encounters(id) ON DELETE CASCADE,
   weight_kg NUMERIC(5,2) NOT NULL,
   bp_systolic INT NOT NULL,
   bp_diastolic INT NOT NULL,
   fundal_height_cm NUMERIC(4,1),
   fetal_heart_rate INT, -- bpm
   fetal_heart_tone VARCHAR(30),
   fetal_presentation VARCHAR(30),
   has_edema BOOLEAN NOT NULL DEFAULT FALSE,
  
   CONSTRAINT chk_fetal_heart_tone CHECK (fetal_heart_tone IN ('regular', 'irregular', 'faint', 'absent')),
   CONSTRAINT chk_fetal_presentation CHECK (fetal_presentation IN ('cephalic', 'breech', 'transverse', 'unstable')),
   CONSTRAINT chk_blood_pressure CHECK (bp_systolic > 40 AND bp_diastolic > 20)
);
-- Lab Results: Extends clinical_encounters with diagnostic parameters
CREATE TABLE lab_results (
   encounter_id UUID PRIMARY KEY REFERENCES clinical_encounters(id) ON DELETE CASCADE,
   test_type VARCHAR(50) NOT NULL, -- e.g., 'CBC', 'OGTT', 'Urinalysis'
   hemoglobin_g_dl NUMERIC(4,1),
   hematocrit_pct NUMERIC(3,1),
   wbc_count NUMERIC(5,2),
   platelet_count INT,
   urinalysis_protein VARCHAR(15),
   urinalysis_glucose VARCHAR(15),
   hepatitis_b_status VARCHAR(15),
   hiv_status VARCHAR(15),
   syphilis_status VARCHAR(15),
   file_url TEXT,
   file_size_bytes INT,
   file_mime_type VARCHAR(50),
  
   CONSTRAINT chk_urinalysis_protein CHECK (urinalysis_protein IN ('negative', 'trace', '1+', '2+', '3+', '4+')),
   CONSTRAINT chk_hepatitis_b_status CHECK (hepatitis_b_status IN ('positive', 'negative', 'reactive', 'non-reactive')),
   CONSTRAINT chk_hiv_status CHECK (hiv_status IN ('positive', 'negative')),
   CONSTRAINT chk_syphilis_status CHECK (syphilis_status IN ('positive', 'negative', 'reactive', 'non-reactive'))
);
-- Ultrasound Records: Extends clinical_encounters with ultrasound scans
CREATE TABLE ultrasound_records (
   encounter_id UUID PRIMARY KEY REFERENCES clinical_encounters(id) ON DELETE CASCADE,
   findings_summary TEXT,
   estimated_fetal_weight_g INT,
   amniotic_fluid_index NUMERIC(3,1),
   placental_location VARCHAR(50), -- e.g., 'Anterior', 'Posterior', 'Previa'
   gestational_age_ultrasound_weeks INT,
   file_url TEXT,
   file_size_bytes INT,
   file_mime_type VARCHAR(50)
);
-- ----------------------------------------------------------------------------
-- 3. INVENTORY & PRESCRIPTIONS DOMAIN
-- ----------------------------------------------------------------------------
-- Inventory Items: Standard catalog of medical supplies (vaccines, supplements)
CREATE TABLE inventory_items (
   id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
   name VARCHAR(100) UNIQUE NOT NULL,
   type VARCHAR(20) NOT NULL,
   unit_of_measure VARCHAR(20) NOT NULL, -- e.g., 'dose', 'tablet', 'capsule'
   minimum_stock_threshold INT NOT NULL DEFAULT 50,
  
   CONSTRAINT chk_item_type CHECK (type IN ('vaccine', 'supplement', 'medical_device', 'contraceptive'))
);
-- Inventory Batches: Tracks distinct shipments, batches, and expiration dates
CREATE TABLE inventory_batches (
   id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
   item_id UUID NOT NULL REFERENCES inventory_items(id) ON DELETE CASCADE,
   batch_number VARCHAR(50) NOT NULL,
   quantity_received INT NOT NULL,
   quantity_remaining INT NOT NULL,
   received_date DATE NOT NULL DEFAULT CURRENT_DATE,
   expiration_date DATE NOT NULL,
   manufacturer VARCHAR(100),
   status VARCHAR(20) NOT NULL DEFAULT 'active',
  
   CONSTRAINT chk_quantities CHECK (quantity_received >= 0 AND quantity_remaining >= 0 AND quantity_remaining <= quantity_received),
   CONSTRAINT chk_expiration CHECK (expiration_date >= received_date),
   CONSTRAINT chk_batch_status CHECK (status IN ('active', 'expired', 'discarded'))
);
-- Inventory Transactions: Audit trail of stock movements
CREATE TABLE inventory_transactions (
   id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
   batch_id UUID NOT NULL REFERENCES inventory_batches(id) ON DELETE CASCADE,
   transaction_type VARCHAR(20) NOT NULL,
   quantity INT NOT NULL, -- Positive for receipt/adjustment, negative for dispense/loss
   reference_id UUID, -- Links to clinical_prescriptions or child_immunizations
   performed_by UUID REFERENCES profiles(id) ON DELETE SET NULL,
   logged_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
  
   CONSTRAINT chk_transaction_type CHECK (transaction_type IN ('receipt', 'dispense', 'adjustment', 'expiry_disposal'))
);
-- Clinical Prescriptions: Tracks supplements given to mothers during prenatal visits
CREATE TABLE clinical_prescriptions (
   id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
   encounter_id UUID NOT NULL REFERENCES clinical_encounters(id) ON DELETE CASCADE,
   inventory_batch_id UUID REFERENCES inventory_batches(id) ON DELETE RESTRICT,
   quantity_dispensed INT NOT NULL,
   instructions TEXT,
  
   CONSTRAINT chk_qty_dispensed CHECK (quantity_dispensed > 0)
);
-- ----------------------------------------------------------------------------
-- 4. PEDIATRICS & BABY BOOK DOMAIN
-- ----------------------------------------------------------------------------
-- Children: Patient records for children born to mothers registered in the system
CREATE TABLE children (
   id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
   mother_id UUID NOT NULL REFERENCES mother_profiles(profile_id) ON DELETE CASCADE,
   pregnancy_id UUID REFERENCES pregnancies(id) ON DELETE SET NULL,
   first_name VARCHAR(50) NOT NULL,
   middle_name VARCHAR(50),
   last_name VARCHAR(50) NOT NULL,
   suffix VARCHAR(10),
   birth_date DATE NOT NULL,
   sex VARCHAR(10) NOT NULL,
   birth_weight_kg NUMERIC(4,2) NOT NULL,
   birth_length_cm NUMERIC(4,1) NOT NULL,
   delivery_type VARCHAR(50), -- e.g., 'Normal Vaginal Delivery', 'Cesarean Section'
   apgar_score INT,
   notes TEXT,
   created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
  
   CONSTRAINT chk_child_sex CHECK (sex IN ('male', 'female')),
   CONSTRAINT chk_apgar CHECK (apgar_score >= 0 AND apgar_score <= 10)
);
-- Child Immunizations: Links childhood vaccinations directly to inventory stock
CREATE TABLE child_immunizations (
   id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
   child_id UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
   inventory_batch_id UUID REFERENCES inventory_batches(id) ON DELETE RESTRICT,
   dose_number INT NOT NULL, -- e.g., 1 (BCG-1), 2 (HepB-2)
   administered_date DATE NOT NULL,
   administered_by UUID REFERENCES health_worker_profiles(profile_id) ON DELETE SET NULL,
   next_due_date DATE,
   status VARCHAR(20) NOT NULL DEFAULT 'administered',
   created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
  
   CONSTRAINT chk_dose_number CHECK (dose_number > 0),
   CONSTRAINT chk_immunization_status CHECK (status IN ('administered', 'missed', 'scheduled'))
);
-- Child Growth Records: Growth measurements matching standard WHO Child Growth Standards
CREATE TABLE child_growth_records (
   id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
   child_id UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
   measurement_date DATE NOT NULL,
   weight_kg NUMERIC(5,2) NOT NULL,
   height_cm NUMERIC(5,1) NOT NULL,
   head_circumference_cm NUMERIC(4,1),
   weight_for_age_zscore NUMERIC(4,2),
   height_for_age_zscore NUMERIC(4,2),
   bmi_for_age_zscore NUMERIC(4,2),
   recorded_by UUID REFERENCES health_worker_profiles(profile_id) ON DELETE SET NULL,
   notes TEXT,
  
   CONSTRAINT chk_growth_measurements CHECK (weight_kg > 0 AND height_cm > 0)
);
-- Milestone Templates: Catalog of developmental milestones (for child milestones log)
CREATE TABLE milestone_templates (
   id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
   age_months_target INT NOT NULL, -- target age in months (e.g., 2, 4, 6, 12, 18, 24)
   category VARCHAR(30) NOT NULL, -- e.g., 'motor', 'language', 'social', 'cognitive'
   description_en TEXT NOT NULL,
   description_fil TEXT NOT NULL,
  
   CONSTRAINT chk_milestone_category CHECK (category IN ('motor', 'language', 'social', 'cognitive')),
   CONSTRAINT chk_age_target CHECK (age_months_target > 0)
);
-- Child Milestones: Milestones achieved by children (baby book entries)
CREATE TABLE child_milestones (
   child_id UUID REFERENCES children(id) ON DELETE CASCADE,
   milestone_id UUID REFERENCES milestone_templates(id) ON DELETE CASCADE,
   date_observed DATE NOT NULL,
   photo_url TEXT,
   notes TEXT,
   PRIMARY KEY (child_id, milestone_id)
);
-- ----------------------------------------------------------------------------
-- 5. SCHEDULES & COMMUNICATION DOMAIN
-- ----------------------------------------------------------------------------
-- Schedules: BHC calendar appointments for mothers and health workers
CREATE TABLE schedules (
   id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
   mother_id UUID NOT NULL REFERENCES mother_profiles(profile_id) ON DELETE CASCADE,
   pregnancy_id UUID REFERENCES pregnancies(id) ON DELETE CASCADE,
   facility_id UUID REFERENCES health_facilities(id) ON DELETE SET NULL,
   schedule_date DATE NOT NULL,
   schedule_time TIME NOT NULL,
   visit_type VARCHAR(30) NOT NULL,
   status VARCHAR(20) NOT NULL DEFAULT 'scheduled',
   is_automated BOOLEAN NOT NULL DEFAULT FALSE,
   notes TEXT,
   created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
  
   CONSTRAINT chk_visit_type CHECK (visit_type IN ('prenatal_checkup', 'postpartum', 'immunization', 'consultation')),
   CONSTRAINT chk_schedule_status CHECK (status IN ('scheduled', 'completed', 'cancelled', 'no_show'))
);
-- Notifications: Push and system messages targeting profiles
CREATE TABLE notifications (
   id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
   profile_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
   title VARCHAR(150) NOT NULL,
   body TEXT NOT NULL,
   is_read BOOLEAN NOT NULL DEFAULT FALSE,
   created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);
-- FCM Tokens: Registered push tokens for mobile application targets
CREATE TABLE fcm_tokens (
   id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
   profile_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
   token TEXT UNIQUE NOT NULL,
   device_type VARCHAR(50), -- e.g., 'iOS', 'Android', 'Web'
   created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
   updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);
-- Journal Entries: Personal notes and mood diaries kept by mothers
CREATE TABLE journal_entries (
   id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
   profile_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
   title VARCHAR(150),
   content TEXT NOT NULL,
   mood VARCHAR(50), -- e.g., 'Happy', 'Anxious', 'Tired', 'Blessed'
   entry_date DATE NOT NULL DEFAULT CURRENT_DATE,
   created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);
-- Audit Logs: Record critical actions performed in the database
CREATE TABLE audit_logs (
   id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
   profile_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
   action VARCHAR(100) NOT NULL, -- e.g. 'CREATE_ENCOUNTER', 'DISPENSE_SUPPLEMENT', 'DELETE_CHILD'
   details JSONB,
   ip_address VARCHAR(45),
   created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);
-- ----------------------------------------------------------------------------
-- 6. AUTOMATION & TRIGGERS
-- ----------------------------------------------------------------------------
-- 6.1 Patient Number Auto-Generation (For mother_profiles)
CREATE SEQUENCE IF NOT EXISTS patient_number_seq START 1;
CREATE OR REPLACE FUNCTION generate_patient_number()
RETURNS TRIGGER AS $$
DECLARE
   current_year TEXT;
   seq_val INT;
BEGIN
   current_year := TO_CHAR(CURRENT_DATE, 'YYYY');
   SELECT nextval('patient_number_seq') INTO seq_val;
  
   NEW.patient_number := 'INA-' || current_year || '-' || LPAD(seq_val::TEXT, 5, '0');
   RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE OR REPLACE TRIGGER trigger_generate_patient_number
BEFORE INSERT ON mother_profiles
FOR EACH ROW
WHEN (NEW.patient_number IS NULL)
EXECUTE FUNCTION generate_patient_number();
-- 6.2 Pre-pregnancy BMI Calculation (For pregnancies)
CREATE OR REPLACE FUNCTION calculate_pregnancy_bmi()
RETURNS TRIGGER AS $$
BEGIN
   IF NEW.pre_pregnancy_weight_kg IS NOT NULL AND NEW.height_cm > 0 THEN
       -- BMI = Weight(kg) / (Height(m) ^ 2)
       NEW.pre_pregnancy_bmi := ROUND(
           (NEW.pre_pregnancy_weight_kg / ((NEW.height_cm / 100.0) * (NEW.height_cm / 100.0)))::NUMERIC,
           2
       );
   END IF;
   RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE OR REPLACE TRIGGER trigger_calculate_pregnancy_bmi
BEFORE INSERT OR UPDATE OF pre_pregnancy_weight_kg, height_cm ON pregnancies
FOR EACH ROW
EXECUTE FUNCTION calculate_pregnancy_bmi();
-- 6.3 Auto-Deducting Inventory (For clinical_prescriptions)
CREATE OR REPLACE FUNCTION deduct_inventory_stock_prescription()
RETURNS TRIGGER AS $$
BEGIN
   -- Only run if there is a stock item assigned
   IF NEW.inventory_batch_id IS NOT NULL THEN
       -- Deduct remaining quantity in the referenced batch
       UPDATE inventory_batches
       SET quantity_remaining = quantity_remaining - NEW.quantity_dispensed
       WHERE id = NEW.inventory_batch_id;
      
       -- Log transaction automatically
       INSERT INTO inventory_transactions (batch_id, transaction_type, quantity, reference_id)
       VALUES (NEW.inventory_batch_id, 'dispense', -NEW.quantity_dispensed, NEW.id);
   END IF;
   RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE OR REPLACE TRIGGER trigger_prescriptions_inventory_deduct
AFTER INSERT ON clinical_prescriptions
FOR EACH ROW
EXECUTE FUNCTION deduct_inventory_stock_prescription();
-- 6.4 Auto-Deducting Inventory (For child_immunizations)
CREATE OR REPLACE FUNCTION deduct_inventory_stock_immunization()
RETURNS TRIGGER AS $$
BEGIN
   -- Only run if there is a stock vaccine batch assigned
   IF NEW.inventory_batch_id IS NOT NULL THEN
       -- Deduct remaining quantity in the referenced batch (1 dose)
       UPDATE inventory_batches
       SET quantity_remaining = quantity_remaining - 1
       WHERE id = NEW.inventory_batch_id;
      
       -- Log transaction automatically
       INSERT INTO inventory_transactions (batch_id, transaction_type, quantity, reference_id)
       VALUES (NEW.inventory_batch_id, 'dispense', -1, NEW.id);
   END IF;
   RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE OR REPLACE TRIGGER trigger_immunization_inventory_deduct
AFTER INSERT ON child_immunizations
FOR EACH ROW
EXECUTE FUNCTION deduct_inventory_stock_immunization();
-- ----------------------------------------------------------------------------
-- 7. PERFORMANCE INDEXES
-- ----------------------------------------------------------------------------
-- Identity Domain Indexes
CREATE INDEX idx_profiles_role ON profiles(role);
CREATE INDEX idx_mother_profiles_facility ON mother_profiles(registered_facility_id);
-- Pregnancy & Encounter Indexes
CREATE INDEX idx_pregnancies_mother ON pregnancies(mother_id);
CREATE INDEX idx_pregnancies_active ON pregnancies(is_active);
CREATE INDEX idx_clinical_encounters_pregnancy ON clinical_encounters(pregnancy_id);
CREATE INDEX idx_clinical_encounters_mother ON clinical_encounters(mother_id);
CREATE INDEX idx_clinical_encounters_facilitator ON clinical_encounters(facilitator_id);
CREATE INDEX idx_clinical_encounters_timeline ON clinical_encounters(mother_id, visit_date DESC);
CREATE INDEX idx_encounter_symptoms_encounter ON encounter_symptoms(encounter_id);
-- Inventory & Prescription Indexes
CREATE INDEX idx_inventory_batches_item ON inventory_batches(item_id);
CREATE INDEX idx_inventory_batches_expiry ON inventory_batches(expiration_date);
CREATE INDEX idx_inventory_transactions_batch ON inventory_transactions(batch_id);
CREATE INDEX idx_clinical_prescriptions_encounter ON clinical_prescriptions(encounter_id);
-- Pediatric Indexes
CREATE INDEX idx_children_mother ON children(mother_id);
CREATE INDEX idx_child_immunizations_child ON child_immunizations(child_id);
CREATE INDEX idx_child_growth_records_child ON child_growth_records(child_id);
CREATE INDEX idx_child_growth_timeline ON child_growth_records(child_id, measurement_date DESC);
CREATE INDEX idx_child_milestones_child ON child_milestones(child_id);
-- Scheduling & Notification Indexes
CREATE INDEX idx_schedules_mother ON schedules(mother_id);
CREATE INDEX idx_schedules_date_time ON schedules(schedule_date, schedule_time);
CREATE INDEX idx_notifications_profile_unread ON notifications(profile_id) WHERE is_read = FALSE;
CREATE INDEX idx_fcm_tokens_profile ON fcm_tokens(profile_id);
CREATE INDEX idx_journal_entries_profile ON journal_entries(profile_id);
CREATE INDEX idx_audit_logs_profile ON audit_logs(profile_id);


