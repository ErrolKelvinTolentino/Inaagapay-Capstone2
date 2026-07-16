-- modify_birth_details.sql
-- Migration: Remove estimated birthdate, head circumference, and birth complications from birth_details table

ALTER TABLE birth_details DROP COLUMN IF EXISTS is_birthdate_estimated;
ALTER TABLE birth_details DROP COLUMN IF EXISTS birth;
ALTER TABLE birth_details DROP COLUMN IF EXISTS head_circumference;
ALTER TABLE birth_details DROP COLUMN IF EXISTS birth_complications;
