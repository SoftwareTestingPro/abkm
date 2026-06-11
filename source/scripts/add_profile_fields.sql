-- Run these commands in your Supabase SQL Editor to update the profiles table
-- This removes the static age column and adds marital status and dob

ALTER TABLE profiles 
DROP COLUMN IF EXISTS age,
ADD COLUMN IF NOT EXISTS marital_status TEXT DEFAULT 'Unmarried',
ADD COLUMN IF NOT EXISTS dob TIMESTAMP WITH TIME ZONE;

-- Optional: Add comments to columns for better documentation
COMMENT ON COLUMN profiles.marital_status IS 'Marital status of the member (Married/Unmarried)';
COMMENT ON COLUMN profiles.dob IS 'Date of birth of the member';
