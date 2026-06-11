-- Run this command in your Supabase SQL Editor to remove the languages column from the profiles table
ALTER TABLE public.profiles DROP COLUMN IF EXISTS languages;
