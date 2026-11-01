-- ====================================================================
-- ABKM PRODUCTION DATABASE SECURITY & ROW LEVEL SECURITY (RLS) SETUP
-- ====================================================================
-- Run this complete script in your Supabase Dashboard:
-- Supabase -> SQL Editor -> New Query -> Paste & Click Run.
-- ====================================================================

-- 1. Helper function to check if the current requester is an Admin (2) or SuperUser (3)
CREATE OR REPLACE FUNCTION public.is_admin_or_super()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role INT;
  v_email TEXT;
BEGIN
  -- Extract email from Supabase Auth JWT
  v_email := auth.jwt() ->> 'email';
  IF v_email IS NULL OR v_email = '' THEN
    RETURN FALSE;
  END IF;

  SELECT user_role INTO v_role 
  FROM profiles 
  WHERE email = v_email 
  LIMIT 1;

  RETURN COALESCE(v_role >= 2, FALSE);
END;
$$;

-- 2. Trigger function to prevent users from self-escalating roles or positions
CREATE OR REPLACE FUNCTION public.enforce_profile_role_security()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- If user_role or position is being changed, verify caller is an Admin or SuperUser
  IF (NEW.user_role IS DISTINCT FROM OLD.user_role) OR (NEW.position IS DISTINCT FROM OLD.position) OR (NEW.is_blocked IS DISTINCT FROM OLD.is_blocked) THEN
    IF NOT public.is_admin_or_super() THEN
      -- If not admin, ignore any unauthorized changes to sensitive columns
      NEW.user_role := OLD.user_role;
      NEW.position := OLD.position;
      NEW.is_blocked := OLD.is_blocked;
      NEW.blocked_by := OLD.blocked_by;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_profile_role_security ON profiles;
CREATE TRIGGER trg_enforce_profile_role_security
BEFORE UPDATE ON profiles
FOR EACH ROW
EXECUTE FUNCTION public.enforce_profile_role_security();

-- ====================================================================
-- 3. ENABLE ROW LEVEL SECURITY (RLS) ON ALL TABLES
-- ====================================================================
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS events ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS applications ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS promotion_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS activity_logs ENABLE ROW LEVEL SECURITY;

-- ====================================================================
-- 4. POLICIES FOR PROFILES TABLE
-- ====================================================================
-- Drop existing policies if any to avoid duplicates
DROP POLICY IF EXISTS "Public can view active profiles" ON profiles;
DROP POLICY IF EXISTS "Users can insert own profile" ON profiles;
DROP POLICY IF EXISTS "Users can update own profile or admins can update" ON profiles;

-- Anyone (public directory & mobile app discovery) can view active profiles
CREATE POLICY "Public can view active profiles"
ON profiles FOR SELECT
TO public
USING (is_deleted = false OR is_deleted IS NULL);

-- Authenticated users can register/insert their own profile
CREATE POLICY "Users can insert own profile"
ON profiles FOR INSERT
TO authenticated
WITH CHECK (
  (auth.jwt() ->> 'email') = email
  OR auth.jwt() ->> 'sub' = google_id
  OR public.is_admin_or_super()
);

-- Users can update their own profile, or Admins can update any profile
CREATE POLICY "Users can update own profile or admins can update"
ON profiles FOR UPDATE
TO authenticated
USING (
  (auth.jwt() ->> 'email') = email
  OR auth.jwt() ->> 'sub' = google_id
  OR public.is_admin_or_super()
)
WITH CHECK (
  (auth.jwt() ->> 'email') = email
  OR auth.jwt() ->> 'sub' = google_id
  OR public.is_admin_or_super()
);

-- ====================================================================
-- 5. POLICIES FOR EVENTS TABLE
-- ====================================================================
DO $$
BEGIN
  IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'events') THEN
    DROP POLICY IF EXISTS "Public can view approved events" ON events;
    DROP POLICY IF EXISTS "Hosts and admins can view all events" ON events;
    DROP POLICY IF EXISTS "Authenticated users can create events" ON events;
    DROP POLICY IF EXISTS "Hosts or admins can update events" ON events;
    DROP POLICY IF EXISTS "Hosts or admins can delete events" ON events;

    -- Anyone can view approved events
    CREATE POLICY "Public can view approved events"
    ON events FOR SELECT
    TO public
    USING (is_approved = true);

    -- Authenticated hosts and admins can view non-approved/pending events
    CREATE POLICY "Hosts and admins can view all events"
    ON events FOR SELECT
    TO authenticated
    USING (
      is_approved = true 
      OR public.is_admin_or_super()
      OR host_id IN (SELECT id FROM profiles WHERE email = (auth.jwt() ->> 'email'))
    );

    -- Authenticated users can insert new events
    CREATE POLICY "Authenticated users can create events"
    ON events FOR INSERT
    TO authenticated
    WITH CHECK (
      host_id IN (SELECT id FROM profiles WHERE email = (auth.jwt() ->> 'email'))
      OR public.is_admin_or_super()
    );

    -- Host or Admin can update events
    CREATE POLICY "Hosts or admins can update events"
    ON events FOR UPDATE
    TO authenticated
    USING (
      host_id IN (SELECT id FROM profiles WHERE email = (auth.jwt() ->> 'email'))
      OR public.is_admin_or_super()
    );

    -- Host or Admin can delete events
    CREATE POLICY "Hosts or admins can delete events"
    ON events FOR DELETE
    TO authenticated
    USING (
      host_id IN (SELECT id FROM profiles WHERE email = (auth.jwt() ->> 'email'))
      OR public.is_admin_or_super()
    );
  END IF;
END $$;

-- ====================================================================
-- 6. POLICIES FOR APPLICATIONS & PROMOTION REQUESTS
-- ====================================================================
DO $$
BEGIN
  IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'promotion_requests') THEN
    DROP POLICY IF EXISTS "Users and admins can view promotion requests" ON promotion_requests;
    DROP POLICY IF EXISTS "Users can insert promotion requests" ON promotion_requests;
    DROP POLICY IF EXISTS "Admins can update promotion requests" ON promotion_requests;

    CREATE POLICY "Users and admins can view promotion requests"
    ON promotion_requests FOR SELECT
    TO authenticated
    USING (
      public.is_admin_or_super()
      OR "userId" IN (SELECT id FROM profiles WHERE email = (auth.jwt() ->> 'email'))
      OR "requesterId" IN (SELECT id FROM profiles WHERE email = (auth.jwt() ->> 'email'))
    );

    CREATE POLICY "Users can insert promotion requests"
    ON promotion_requests FOR INSERT
    TO authenticated
    WITH CHECK (
      "requesterId" IN (SELECT id FROM profiles WHERE email = (auth.jwt() ->> 'email'))
      OR public.is_admin_or_super()
    );

    CREATE POLICY "Admins can update promotion requests"
    ON promotion_requests FOR UPDATE
    TO authenticated
    USING (public.is_admin_or_super());
  END IF;
END $$;

-- ====================================================================
-- 7. SECURE RPC FUNCTIONS (CALLED BY FLUTTER APP)
-- ====================================================================
CREATE OR REPLACE FUNCTION public.admin_update_user_role(
  target_user_id TEXT,
  new_role_index INT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin_or_super() THEN
    RAISE EXCEPTION 'Access Denied: Only Admins or SuperUsers can change roles.';
  END IF;

  UPDATE profiles 
  SET user_role = new_role_index 
  WHERE id = target_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_update_user_position(
  target_user_id TEXT,
  new_position TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin_or_super() THEN
    RAISE EXCEPTION 'Access Denied: Only Admins or SuperUsers can change positions.';
  END IF;

  UPDATE profiles 
  SET position = new_position 
  WHERE id = target_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_toggle_user_block(
  target_user_id TEXT,
  block_status BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id TEXT;
BEGIN
  IF NOT public.is_admin_or_super() THEN
    RAISE EXCEPTION 'Access Denied: Only Admins or SuperUsers can block users.';
  END IF;

  SELECT id INTO v_admin_id 
  FROM profiles 
  WHERE email = (auth.jwt() ->> 'email') 
  LIMIT 1;

  UPDATE profiles 
  SET is_blocked = block_status,
      blocked_by = CASE WHEN block_status THEN v_admin_id ELSE NULL END
  WHERE id = target_user_id;
END;
$$;

-- Grant execution permissions on RPC functions to authenticated users
GRANT EXECUTE ON FUNCTION public.admin_update_user_role(TEXT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_user_position(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_toggle_user_block(TEXT, BOOLEAN) TO authenticated;
