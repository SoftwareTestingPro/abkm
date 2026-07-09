-- Run these commands in your Supabase SQL Editor to support login via Google
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS google_id TEXT,
ADD COLUMN IF NOT EXISTS email TEXT;

-- Add a unique constraint to google_id to enforce quick lookups and prevent duplicates
CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_google_id ON profiles(google_id) WHERE google_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_profiles_email ON profiles(email) WHERE email IS NOT NULL;

-- Optional: Add comments to columns for documentation
COMMENT ON COLUMN profiles.google_id IS 'Unique identifier representing the linked Google account';
COMMENT ON COLUMN profiles.email IS 'User email address associated with the Google account';
