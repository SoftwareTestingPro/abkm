-- Run these commands in your Supabase SQL Editor to add the last_login column to the profiles table
-- This is required to track the user's last login / active time accurately.

ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS last_login TIMESTAMP WITH TIME ZONE;

-- Optional: Add a comment to the column for documentation
COMMENT ON COLUMN profiles.last_login IS 'The timestamp when the user last launched or logged into the app';
