-- Migration: Create poster_columns table for dynamic poster columns
CREATE TABLE IF NOT EXISTS poster_columns (
    column_id SERIAL PRIMARY KEY,
    bhc_id INT NOT NULL REFERENCES bhc(bhc_id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    subtitle TEXT,
    vaccine_ids INT [] NOT NULL DEFAULT '{}',
    display_order INT NOT NULL DEFAULT 0
);

ALTER TABLE poster_columns DISABLE ROW LEVEL SECURITY;