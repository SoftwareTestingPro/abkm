-- Run this command in your Supabase SQL Editor to add the blocked_by column to the profiles table
-- This allows the application to directly and securely record which administrator performed a block,
-- enabling unauthenticated/logging-in users to fetch their blocker details without encountering activity_logs RLS issues.

ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS blocked_by TEXT;

-- Optional: Add a comment documenting the column
COMMENT ON COLUMN profiles.blocked_by IS 'Stores the ID/mobile of the admin who blocked this user';
