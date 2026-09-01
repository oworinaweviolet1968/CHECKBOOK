-- ============================================================================
-- MIGRATION: ADMIN RLS POLICIES FOR WEB ADMIN PORTAL
-- Run this in your Supabase Dashboard SQL Editor:
-- https://supabase.com/dashboard/project/jhucvkqwenhyiveqsmtf/sql/new
-- ============================================================================

-- Allow admin (admin@gmail.com) to SELECT all user profiles
CREATE POLICY "Admin can view all profiles"
    ON public.user_profiles
    FOR SELECT
    USING (
        auth.uid() = 'a9b8316f-3960-4ed3-9306-546415bc8aaf'::uuid
        OR auth.uid() = user_id
    );

-- Allow admin (admin@gmail.com) to UPDATE all user profiles
CREATE POLICY "Admin can update all profiles"
    ON public.user_profiles
    FOR UPDATE
    USING (
        auth.uid() = 'a9b8316f-3960-4ed3-9306-546415bc8aaf'::uuid
        OR auth.uid() = user_id
    );

-- NOTE: If you get "policy already exists" errors, drop the old ones first:
-- DROP POLICY IF EXISTS "Users can view their own profile" ON public.user_profiles;
-- DROP POLICY IF EXISTS "Users can update their own profile" ON public.user_profiles;
