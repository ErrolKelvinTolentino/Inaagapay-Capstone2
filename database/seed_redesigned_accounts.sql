-- ============================================================
-- InaAgapay — Seed Redesigned Schema & Compatibility Layer
-- Run this script in the Supabase SQL Editor
-- ============================================================

-- 1. Create a compatibility view for BHC (so legacy client code doesn't break)
CREATE OR REPLACE VIEW public.bhc AS
SELECT facility_id AS bhc_id, name AS bhc_name
FROM public.health_facilities;

-- 2. Add compatibility columns to midwives and mothers tables
ALTER TABLE public.midwives ADD COLUMN IF NOT EXISTS assigned_bhc_id bigint REFERENCES public.health_facilities(facility_id);
ALTER TABLE public.mothers ADD COLUMN IF NOT EXISTS assigned_bhc_id bigint REFERENCES public.health_facilities(facility_id);

-- 3. Create synchronization triggers to map assigned_bhc_id to facility_assignments
CREATE OR REPLACE FUNCTION sync_midwife_facility_assignment()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.assigned_bhc_id IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM public.facility_assignments WHERE account_id = NEW.account_id AND is_active = true) THEN
      UPDATE public.facility_assignments
      SET facility_id = NEW.assigned_bhc_id
      WHERE account_id = NEW.account_id AND is_active = true;
    ELSE
      INSERT INTO public.facility_assignments (account_id, facility_id, is_active)
      VALUES (NEW.account_id, NEW.assigned_bhc_id, true);
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_sync_midwife_facility ON public.midwives;
CREATE TRIGGER trg_sync_midwife_facility
AFTER INSERT OR UPDATE OF assigned_bhc_id ON public.midwives
FOR EACH ROW EXECUTE FUNCTION sync_midwife_facility_assignment();

CREATE OR REPLACE FUNCTION sync_mother_facility_assignment()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.assigned_bhc_id IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM public.facility_assignments WHERE account_id = NEW.account_id AND is_active = true) THEN
      UPDATE public.facility_assignments
      SET facility_id = NEW.assigned_bhc_id
      WHERE account_id = NEW.account_id AND is_active = true;
    ELSE
      INSERT INTO public.facility_assignments (account_id, facility_id, is_active)
      VALUES (NEW.account_id, NEW.assigned_bhc_id, true);
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_sync_mother_facility ON public.mothers;
CREATE TRIGGER trg_sync_mother_facility
AFTER INSERT OR UPDATE OF assigned_bhc_id ON public.mothers
FOR EACH ROW EXECUTE FUNCTION sync_mother_facility_assignment();

-- 4. Seed Health Facilities (Tiaong, Tarcan, Pinagbarilan, Makinabang, Sta. Barbara)
-- Baliuag municipality and Bulacan province matching client expectations
INSERT INTO public.health_facilities (facility_id, name, facility_type, barangay, municipality, province)
VALUES
  (1, 'Tiaong BHC', 'BHC', 'Tiaong', 'Baliuag', 'Bulacan'),
  (2, 'Tarcan BHC', 'BHC', 'Tarcan', 'Baliuag', 'Bulacan'),
  (3, 'Pinagbarilan BHC', 'BHC', 'Pinagbarilan', 'Baliuag', 'Bulacan'),
  (4, 'Makinabang BHC', 'BHC', 'Makinabang', 'Baliuag', 'Bulacan'),
  (5, 'Sta. Barbara BHC', 'BHC', 'Sta. Barbara', 'Baliuag', 'Bulacan')
ON CONFLICT (facility_id) DO UPDATE SET
  name = EXCLUDED.name,
  barangay = EXCLUDED.barangay,
  municipality = EXCLUDED.municipality,
  province = EXCLUDED.province;

-- Restart sequence for health_facilities to avoid conflicts on future auto-inserts
SELECT setval(pg_get_serial_sequence('public.health_facilities', 'facility_id'), COALESCE(MAX(facility_id), 1)) FROM public.health_facilities;

-- 5. Seed Admin Account
-- Email: admin@inaagapay.com
-- Password: Password@123
INSERT INTO public.accounts (email_address, password_hash, account_type, first_name, last_name, is_verified, status, is_temporary_password, created_by)
VALUES (
  'admin@inaagapay.com',
  '$2a$10$UVpnA.yrMW7WlJa6olxznOTtocVFcw05hDXh5PCLINnSKLTmfG4FK',
  'admin',
  'System',
  'Admin',
  true,
  'active',
  false,
  'self'
)
ON CONFLICT (email_address) DO UPDATE SET
  password_hash = EXCLUDED.password_hash,
  first_name = EXCLUDED.first_name,
  last_name = EXCLUDED.last_name,
  is_verified = EXCLUDED.is_verified,
  status = EXCLUDED.status;

-- 6. Seed Midwife Accounts
-- All Midwives Password: Password@123
DO $$
DECLARE
  v_acct_id bigint;
BEGIN
  -- Midwife 1 (Tiaong)
  INSERT INTO public.accounts (email_address, password_hash, account_type, first_name, last_name, phone_number, is_verified, status, is_temporary_password, created_by)
  VALUES ('midwife.tiaong@inaagapay.com', '$2a$10$UVpnA.yrMW7WlJa6olxznOTtocVFcw05hDXh5PCLINnSKLTmfG4FK', 'midwife', 'Tiaong', 'Midwife', '09111111111', true, 'active', false, 'self')
  ON CONFLICT (email_address) DO UPDATE SET password_hash = EXCLUDED.password_hash RETURNING account_id INTO v_acct_id;
  
  INSERT INTO public.midwives (account_id, assigned_bhc_id)
  VALUES (v_acct_id, 1)
  ON CONFLICT (account_id) DO UPDATE SET assigned_bhc_id = EXCLUDED.assigned_bhc_id;

  -- Midwife 2 (Tarcan)
  INSERT INTO public.accounts (email_address, password_hash, account_type, first_name, last_name, phone_number, is_verified, status, is_temporary_password, created_by)
  VALUES ('midwife.tarcan@inaagapay.com', '$2a$10$UVpnA.yrMW7WlJa6olxznOTtocVFcw05hDXh5PCLINnSKLTmfG4FK', 'midwife', 'Tarcan', 'Midwife', '09222222222', true, 'active', false, 'self')
  ON CONFLICT (email_address) DO UPDATE SET password_hash = EXCLUDED.password_hash RETURNING account_id INTO v_acct_id;
  
  INSERT INTO public.midwives (account_id, assigned_bhc_id)
  VALUES (v_acct_id, 2)
  ON CONFLICT (account_id) DO UPDATE SET assigned_bhc_id = EXCLUDED.assigned_bhc_id;

  -- Midwife 3 (Pinagbarilan)
  INSERT INTO public.accounts (email_address, password_hash, account_type, first_name, last_name, phone_number, is_verified, status, is_temporary_password, created_by)
  VALUES ('midwife.pinagbarilan@inaagapay.com', '$2a$10$UVpnA.yrMW7WlJa6olxznOTtocVFcw05hDXh5PCLINnSKLTmfG4FK', 'midwife', 'Pinagbarilan', 'Midwife', '09333333333', true, 'active', false, 'self')
  ON CONFLICT (email_address) DO UPDATE SET password_hash = EXCLUDED.password_hash RETURNING account_id INTO v_acct_id;
  
  INSERT INTO public.midwives (account_id, assigned_bhc_id)
  VALUES (v_acct_id, 3)
  ON CONFLICT (account_id) DO UPDATE SET assigned_bhc_id = EXCLUDED.assigned_bhc_id;

  -- Midwife 4 (Makinabang)
  INSERT INTO public.accounts (email_address, password_hash, account_type, first_name, last_name, phone_number, is_verified, status, is_temporary_password, created_by)
  VALUES ('midwife.makinabang@inaagapay.com', '$2a$10$UVpnA.yrMW7WlJa6olxznOTtocVFcw05hDXh5PCLINnSKLTmfG4FK', 'midwife', 'Makinabang', 'Midwife', '09444444444', true, 'active', false, 'self')
  ON CONFLICT (email_address) DO UPDATE SET password_hash = EXCLUDED.password_hash RETURNING account_id INTO v_acct_id;
  
  INSERT INTO public.midwives (account_id, assigned_bhc_id)
  VALUES (v_acct_id, 4)
  ON CONFLICT (account_id) DO UPDATE SET assigned_bhc_id = EXCLUDED.assigned_bhc_id;

  -- Midwife 5 (Sta. Barbara)
  INSERT INTO public.accounts (email_address, password_hash, account_type, first_name, last_name, phone_number, is_verified, status, is_temporary_password, created_by)
  VALUES ('midwife.stabarbara@inaagapay.com', '$2a$10$UVpnA.yrMW7WlJa6olxznOTtocVFcw05hDXh5PCLINnSKLTmfG4FK', 'midwife', 'Sta. Barbara', 'Midwife', '09555555555', true, 'active', false, 'self')
  ON CONFLICT (email_address) DO UPDATE SET password_hash = EXCLUDED.password_hash RETURNING account_id INTO v_acct_id;
  
  INSERT INTO public.midwives (account_id, assigned_bhc_id)
  VALUES (v_acct_id, 5)
  ON CONFLICT (account_id) DO UPDATE SET assigned_bhc_id = EXCLUDED.assigned_bhc_id;
END $$;
