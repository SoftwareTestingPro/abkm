-- Run these commands in your Supabase SQL Editor to support the Aadhar card front and back upload fields
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS aadhar_front_url TEXT,
ADD COLUMN IF NOT EXISTS aadhar_back_url TEXT;

-- Optional: Add comments to columns for documentation
COMMENT ON COLUMN profiles.aadhar_front_url IS 'Base64 encoded image or URL of the front side of the user Aadhar card';
COMMENT ON COLUMN profiles.aadhar_back_url IS 'Base64 encoded image or URL of the back side of the user Aadhar card';
