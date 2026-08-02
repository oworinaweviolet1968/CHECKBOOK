-- Supabase SQL Migration: RPC function to check if email exists in auth.users
-- Run this script in your Supabase SQL Editor (Project -> SQL Editor -> New Query)

CREATE OR REPLACE FUNCTION check_email_exists(email_input TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM auth.users WHERE LOWER(email) = LOWER(email_input)
  );
END;
$$;

-- Grant execute permission to anon and authenticated roles for client RPC invocation
GRANT EXECUTE ON FUNCTION check_email_exists(TEXT) TO anon, authenticated;
