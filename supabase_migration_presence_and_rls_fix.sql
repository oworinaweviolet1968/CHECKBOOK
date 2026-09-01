-- ============================================================================
-- MIGRATION: PRESENCE, BACKUP TIMESTAMP & STOCK/SALES RLS FIX
-- Run this in your Supabase Dashboard SQL Editor:
-- https://supabase.com/dashboard/project/jhucvkqwenhyiveqsmtf/sql/new
-- ============================================================================

-- 1. Ensure desktop_last_seen and last_backup_timestamp exist on user_profiles and users
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS desktop_last_seen BIGINT DEFAULT 0;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS last_backup_timestamp BIGINT DEFAULT 0;

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS desktop_last_seen BIGINT DEFAULT 0;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS last_backup_timestamp BIGINT DEFAULT 0;

-- 2. Indexes for fast status lookups
CREATE INDEX IF NOT EXISTS idx_user_profiles_desktop_last_seen ON public.user_profiles(desktop_last_seen);
CREATE INDEX IF NOT EXISTS idx_user_profiles_last_backup_timestamp ON public.user_profiles(last_backup_timestamp);

-- 3. Enable RLS and grant open access policies for user_profiles
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow read user_profiles" ON public.user_profiles;
CREATE POLICY "Allow read user_profiles" ON public.user_profiles 
FOR SELECT USING (true);

DROP POLICY IF EXISTS "Allow update user_profiles" ON public.user_profiles;
CREATE POLICY "Allow update user_profiles" ON public.user_profiles 
FOR UPDATE USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow insert user_profiles" ON public.user_profiles;
CREATE POLICY "Allow insert user_profiles" ON public.user_profiles 
FOR INSERT WITH CHECK (true);

-- 4. Enable RLS and strict single-tenant access policies for sales table
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow read sales" ON public.sales;
DROP POLICY IF EXISTS "Allow insert sales" ON public.sales;
DROP POLICY IF EXISTS "Allow update sales" ON public.sales;
DROP POLICY IF EXISTS "Allow delete sales" ON public.sales;
DROP POLICY IF EXISTS "Users can view their own sales" ON public.sales;
DROP POLICY IF EXISTS "Users can insert their own sales" ON public.sales;
DROP POLICY IF EXISTS "Users can update their own sales" ON public.sales;
DROP POLICY IF EXISTS "Users can delete their own sales" ON public.sales;

CREATE POLICY "Users can view their own sales" ON public.sales 
FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own sales" ON public.sales 
FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own sales" ON public.sales 
FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own sales" ON public.sales 
FOR DELETE USING (auth.uid() = user_id);

-- 5. Enable RLS and strict single-tenant access policies for stock table
ALTER TABLE public.stock ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow read stock" ON public.stock;
DROP POLICY IF EXISTS "Allow insert stock" ON public.stock;
DROP POLICY IF EXISTS "Allow update stock" ON public.stock;
DROP POLICY IF EXISTS "Allow delete stock" ON public.stock;
DROP POLICY IF EXISTS "Users can view their own stock" ON public.stock;
DROP POLICY IF EXISTS "Users can insert their own stock" ON public.stock;
DROP POLICY IF EXISTS "Users can update their own stock" ON public.stock;
DROP POLICY IF EXISTS "Users can delete their own stock" ON public.stock;

CREATE POLICY "Users can view their own stock" ON public.stock 
FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own stock" ON public.stock 
FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own stock" ON public.stock 
FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own stock" ON public.stock 
FOR DELETE USING (auth.uid() = user_id);

-- 6. RPC Function for Server-Side Desktop Presence Calculation
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
GRANT EXECUTE ON FUNCTION get_desktop_status(UUID) TO anon;

-- 7. RPC Function for Desktop Heartbeat Presence Update
CREATE OR REPLACE FUNCTION public.rpc_update_desktop_presence(
    p_user_id UUID,
    p_timestamp BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE public.user_profiles
    SET desktop_last_seen = p_timestamp,
        updated_at = NOW()
    WHERE user_id = p_user_id;

    RETURN jsonb_build_object('success', true, 'user_id', p_user_id, 'desktop_last_seen', p_timestamp);
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_update_desktop_presence(UUID, BIGINT) TO anon, authenticated, service_role;
