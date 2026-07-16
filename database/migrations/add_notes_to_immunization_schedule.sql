-- Migration: Add notes column to immunization_schedule table
ALTER TABLE immunization_schedule ADD COLUMN notes TEXT;
