-- ============================================================================
-- MIGRATION: ADMIN LICENSE TOGGLE SECURITY DEFINER RPC & RLS UPDATE
-- Allows Admin Web Portal to update subscription_status & plan_tier across users
-- ============================================================================

-- 1. Create SECURITY DEFINER RPC function for Admin license toggles
CREATE OR REPLACE FUNCTION public.rpc_admin_toggle_user_license(
    p_user_id UUID,
    p_status TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_plan TEXT;
BEGIN
    IF p_status = 'ACTIVE' THEN
        v_plan := 'OWNERSHIP_CLOUD';
    ELSE
        v_plan := 'FREE';
    END IF;

    -- Update user_profiles table
    UPDATE public.user_profiles
    SET subscription_status = p_status,
        plan_tier = v_plan,
        is_web_verified = (p_status = 'ACTIVE' OR is_web_verified),
        updated_at = NOW()
    WHERE user_id = p_user_id;

    RETURN jsonb_build_object(
        'success', true,
        'user_id', p_user_id,
        'subscription_status', p_status,
        'plan_tier', v_plan
    );
END;
$$;

-- Grant execution to authenticated & anon roles
GRANT EXECUTE ON FUNCTION public.rpc_admin_toggle_user_license(UUID, TEXT) TO authenticated, anon;
