-- Migration: Add monitoring_classification to ultrasounds table
-- Run this in your Supabase SQL Editor.
--
-- This field stores the trimester-aware 3-tier monitoring classification
-- computed by the AI-assisted interpretation engine for each ultrasound.
--
-- Clinical Reference Standards:
--   [1] INTERGROWTH-21st: Papageorghiou AT et al.
--       "International standards for fetal growth based on serial ultrasound
--       measurements: the Fetal Growth Longitudinal Study of the
--       INTERGROWTH-21st Project." The Lancet. 2014.
--       https://intergrowth21.tghn.org
--
--   [2] WHO Fetal Growth Charts: Kiserud T et al.
--       "The World Health Organization fetal growth charts."
--       PLOS Medicine. 2017.
--       https://journals.plos.org/plosmedicine/article?id=10.1371/journal.pmed.1002220

ALTER TABLE ultrasounds
ADD COLUMN IF NOT EXISTS monitoring_classification VARCHAR(50);

COMMENT ON COLUMN ultrasounds.monitoring_classification IS
'Trimester-aware 3-tier monitoring classification (AI-assisted).
 Values: within_expected_range | requires_closer_monitoring | follow_up_recommended
 Reference: INTERGROWTH-21st (Lancet 2014); WHO Fetal Growth Charts (PLOS Medicine 2017)';
