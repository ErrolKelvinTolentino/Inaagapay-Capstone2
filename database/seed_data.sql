
-- Seed data for symptom types
INSERT INTO symptom_types (symptom_name, risk_category, description)
VALUES -- ======================
    -- DANGER SIGNS (EMERGENCY)
    -- ======================
    (
        'Vaginal Bleeding',
        'danger',
        'Possible miscarriage or placental complication'
    ),
    ('Convulsions', 'danger', 'Possible eclampsia'),
    (
        'Severe Headache',
        'danger',
        'Possible preeclampsia'
    ),
    (
        'Blurred Vision',
        'danger',
        'Possible preeclampsia'
    ),
    (
        'Severe Abdominal Pain',
        'danger',
        'Possible placental abruption or ectopic pregnancy'
    ),
    (
        'Leaking Vaginal Fluid',
        'danger',
        'Possible premature rupture of membranes'
    ),
    (
        'No Fetal Movement',
        'danger',
        'Possible fetal distress or fetal death'
    ),
    (
        'Difficulty Breathing',
        'danger',
        'Possible cardiopulmonary complication'
    ),
    (
        'High Fever',
        'danger',
        'Possible maternal infection'
    ),
    (
        'Severe Swelling of Face or Hands',
        'danger',
        'Possible preeclampsia'
    ),
    -- ======================
    -- WARNING SIGNS (MONITOR CLOSELY)
    -- ======================
    (
        'Reduced Fetal Movement',
        'warning',
        'Possible fetal distress'
    ),
    (
        'Persistent Vomiting',
        'warning',
        'Possible hyperemesis gravidarum'
    ),
    (
        'Painful Urination',
        'warning',
        'Possible urinary tract infection'
    ),
    (
        'Pelvic Pain',
        'warning',
        'Possible infection or ligament strain'
    ),
    (
        'Severe Itching',
        'warning',
        'Possible intrahepatic cholestasis'
    ),
    (
        'Dizziness',
        'warning',
        'Possible anemia or hypotension'
    ),
    (
        'Chest Pain',
        'warning',
        'Possible cardiovascular complication'
    ),
    (
        'Moderate Swelling',
        'warning',
        'May indicate developing preeclampsia'
    ),
    -- ======================
    -- NORMAL PREGNANCY SYMPTOMS
    -- ======================
    (
        'Back Pain',
        'normal',
        'Common musculoskeletal discomfort during pregnancy'
    ),
    (
        'Nausea',
        'normal',
        'Morning sickness due to hormonal changes'
    ),
    (
        'Vomiting',
        'normal',
        'Common early pregnancy symptom'
    ),
    (
        'Fatigue',
        'normal',
        'Hormonal and metabolic changes during pregnancy'
    ),
    (
        'Frequent Urination',
        'normal',
        'Pressure from the uterus on the bladder'
    ),
    (
        'Heartburn',
        'normal',
        'Gastroesophageal reflux due to pregnancy hormones'
    ),
    (
        'Constipation',
        'normal',
        'Hormonal digestion changes'
    ),
    (
        'Skin Rash',
        'normal',
        'Hormonal skin reactions during pregnancy'
    );

-- Seed data for vaccines (DOH Expanded Program on Immunization)
-- Only insert if not already present
INSERT INTO vaccines (vaccine_name, dose_number, recommended_age_months, target_recipients, notes)
VALUES
    -- PCV (Pneumococcal Conjugate Vaccine)
    ('PCV', 1, 1.5, 'child', 'Pneumococcal Conjugate Vaccine - 1st dose'),
    ('PCV', 2, 2.5, 'child', 'Pneumococcal Conjugate Vaccine - 2nd dose'),
    ('PCV', 3, 3.5, 'child', 'Pneumococcal Conjugate Vaccine - 3rd dose'),
    -- Rotavirus
    ('Rotavirus', 1, 1.5, 'child', 'Rotavirus Vaccine - 1st dose'),
    ('Rotavirus', 2, 2.5, 'child', 'Rotavirus Vaccine - 2nd dose'),
    -- IPV (Inactivated Polio Vaccine)
    ('IPV', 1, 3.5, 'child', 'Inactivated Polio Vaccine'),
    -- Vitamin A
    ('Vitamin A', 1, 6.0, 'child', 'Vitamin A Supplementation - 1st dose'),
    ('Vitamin A', 2, 12.0, 'child', 'Vitamin A Supplementation - 2nd dose'),
    -- MCV2 (Measles-Containing Vaccine 2nd dose)
    ('Measles', 2, 12.0, 'child', 'Measles-Containing Vaccine - 2nd dose'),
    -- MMR
    ('MMR', 1, 12.0, 'child', 'Measles, Mumps, Rubella Vaccine')
ON CONFLICT (vaccine_name, dose_number) DO NOTHING;