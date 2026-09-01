-- ============================================================================
-- MIGRATION: DESKTOP PRESENCE TRACKING
-- Run this in your Supabase Dashboard SQL Editor:
-- https://supabase.com/dashboard/project/jhucvkqwenhyiveqsmtf/sql/new
-- ============================================================================

-- Add desktop_last_seen to user_profiles (primary table) and users (fallback)
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS desktop_last_seen BIGINT DEFAULT 0;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS desktop_last_seen BIGINT DEFAULT 0;

-- Index for presence queries
CREATE INDEX IF NOT EXISTS idx_user_profiles_desktop_last_seen ON public.user_profiles(desktop_last_seen);

-- Function for server-side presence evaluation (eliminates client clock skew)
CREATE OR REPLACE FUNCTION get_desktop_status(p_user_id UUID)
RETURNS TEXT AS $$
DECLARE
    v_last_seen BIGINT;
BEGIN
    SELECT desktop_last_seen INTO v_last_seen 
    FROM public.user_profiles 
    WHERE user_id = p_user_id;
    
    IF v_last_seen IS NULL THEN
        SELECT desktop_last_seen INTO v_last_seen 
        FROM public.users 
        WHERE id = p_user_id;
    END IF;
    
    IF v_last_seen IS NULL OR v_last_seen = 0 THEN
        RETURN 'unknown';
    ELSIF (EXTRACT(EPOCH FROM NOW()) * 1000 - v_last_seen) < 60000 THEN
        RETURN 'online';
    ELSE
        RETURN 'offline';
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_desktop_status(UUID) TO authenticated;
