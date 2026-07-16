-- Add is_temporary_password column if not exists
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS is_temporary_password BOOLEAN DEFAULT FALSE;

-- Add created_by column if not exists  
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS created_by VARCHAR(20) DEFAULT 'self';
