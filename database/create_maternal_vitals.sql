-- SQL Migration to create maternal_vitals table
-- Run this in your Supabase SQL Editor to DROP and RECREATE the table.

DROP TABLE IF EXISTS maternal_vitals CASCADE;

CREATE TABLE maternal_vitals (
  vital_id          BIGSERIAL PRIMARY KEY,
  pregnancy_id      BIGINT NOT NULL REFERENCES pregnancies(pregnancy_id) ON DELETE CASCADE,
  mother_id         BIGINT NOT NULL REFERENCES mothers(mother_id) ON DELETE CASCADE,
  recorded_at       TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  age_of_gestation  DECIMAL(4, 1), -- weeks, computed from LMP
  weight_kg         DECIMAL(5, 2) NOT NULL,
  height_cm         DECIMAL(5, 2) NOT NULL,
  notes             TEXT,
  created_at        TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Indexing for fast chronological querying per pregnancy/mother
CREATE INDEX idx_maternal_vitals_pregnancy_date ON maternal_vitals(pregnancy_id, recorded_at DESC);
CREATE INDEX idx_maternal_vitals_mother ON maternal_vitals(mother_id);

-- Disable Row Level Security (consistent with the rest of this Capstone project's setup for custom auth using anon key)
ALTER TABLE maternal_vitals DISABLE ROW LEVEL SECURITY;
