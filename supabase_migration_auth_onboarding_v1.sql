-- ============================================================================
-- MIGRATION: AUTHENTICATION, WEB-FIRST VERIFICATION GATE & TRIAL ONBOARDING
-- ============================================================================

-- 1. Create user_profiles table if not exists
CREATE TABLE IF NOT EXISTS public.user_profiles (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT UNIQUE NOT NULL,
    full_name TEXT,
    avatar_url TEXT,
    is_web_verified BOOLEAN DEFAULT FALSE,
    billing_phone TEXT,
    trial_started_at TIMESTAMPTZ,
    trial_expires_at TIMESTAMPTZ,
    plan_tier TEXT DEFAULT 'OWNERSHIP_CLOUD',
    subscription_status TEXT DEFAULT 'UNVERIFIED', -- 'UNVERIFIED', 'TRIAL_ACTIVE', 'ACTIVE', 'EXPIRED', 'CANCELLED'
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS on user_profiles
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own profile"
    ON public.user_profiles
    FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own profile"
    ON public.user_profiles
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own profile"
    ON public.user_profiles
    FOR UPDATE
    USING (auth.uid() = user_id);

-- Trigger: Automatically grant 7-day trial and create profile on user signup
CREATE OR REPLACE FUNCTION public.handle_new_user_trial_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO public.user_profiles (
        user_id,
        email,
        is_web_verified,
        trial_started_at,
        trial_expires_at,
        plan_tier,
        subscription_status,
        created_at,
        updated_at
    ) VALUES (
        NEW.id,
        LOWER(NEW.email),
        TRUE,
        NOW(),
        NOW() + INTERVAL '7 days',
        'OWNERSHIP_CLOUD',
        'TRIAL_ACTIVE',
        NOW(),
        NOW()
    )
    ON CONFLICT (user_id) DO UPDATE SET
        is_web_verified = TRUE,
        subscription_status = 'TRIAL_ACTIVE',
        trial_expires_at = COALESCE(public.user_profiles.trial_expires_at, NOW() + INTERVAL '7 days'),
        updated_at = NOW();

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created_trial ON auth.users;
CREATE TRIGGER on_auth_user_created_trial
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_trial_profile();

-- 2. Create auth_providers tracking table
CREATE TABLE IF NOT EXISTS public.auth_providers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(user_id) ON DELETE CASCADE,
    provider TEXT NOT NULL, -- 'google', 'apple'
    provider_user_id TEXT NOT NULL,
    email TEXT NOT NULL,
    raw_claims JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(provider, provider_user_id)
);

ALTER TABLE public.auth_providers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own auth providers"
    ON public.auth_providers
    FOR SELECT
    USING (auth.uid() = user_id);

-- 3. Create subscriptions_trials table
CREATE TABLE IF NOT EXISTS public.subscriptions_trials (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(user_id) ON DELETE CASCADE,
    license_key TEXT,
    plan_tier TEXT NOT NULL, -- 'OWNERSHIP_CLOUD', 'OWNERSHIP_LOCAL'
    has_ownership_license BOOLEAN DEFAULT FALSE,
    has_cloud_subscription BOOLEAN DEFAULT FALSE,
    trial_started_at TIMESTAMPTZ,
    trial_expires_at TIMESTAMPTZ,
    current_period_end TIMESTAMPTZ,
    pesapal_merchant_reference TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.subscriptions_trials ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own subscription details"
    ON public.subscriptions_trials
    FOR SELECT
    USING (auth.uid() = user_id);

-- 4. RPC: Setup Billing Phone and Start 7-Day Free Trial (Web Onboarding)
CREATE OR REPLACE FUNCTION public.rpc_setup_billing_phone_and_start_trial(
    p_user_id UUID,
    p_billing_phone TEXT,
    p_plan_tier TEXT DEFAULT 'OWNERSHIP_CLOUD'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_now TIMESTAMPTZ := NOW();
    v_expires TIMESTAMPTZ := NOW() + INTERVAL '7 days';
    v_profile public.user_profiles%ROWTYPE;
BEGIN
    -- Validate billing phone format (E.164 string basic length check)
    IF p_billing_phone IS NULL OR LENGTH(TRIM(p_billing_phone)) < 8 THEN
        RETURN jsonb_build_object('success', false, 'error', 'INVALID_BILLING_PHONE', 'message', 'Please provide a valid billing phone number.');
    END IF;

    -- Update or Insert User Profile
    INSERT INTO public.user_profiles (
        user_id,
        email,
        is_web_verified,
        billing_phone,
        trial_started_at,
        trial_expires_at,
        plan_tier,
        subscription_status,
        updated_at
    )
    SELECT
        p_user_id,
        u.email,
        TRUE,
        p_billing_phone,
        v_now,
        v_expires,
        p_plan_tier,
        'TRIAL_ACTIVE',
        v_now
    FROM auth.users u
    WHERE u.id = p_user_id
    ON CONFLICT (user_id) DO UPDATE SET
        is_web_verified = TRUE,
        billing_phone = EXCLUDED.billing_phone,
        trial_started_at = COALESCE(public.user_profiles.trial_started_at, v_now),
        trial_expires_at = COALESCE(public.user_profiles.trial_expires_at, v_expires),
        plan_tier = EXCLUDED.plan_tier,
        subscription_status = 'TRIAL_ACTIVE',
        updated_at = v_now;

    -- Record subscription/trial entry
    INSERT INTO public.subscriptions_trials (
        user_id,
        plan_tier,
        has_ownership_license,
        has_cloud_subscription,
        trial_started_at,
        trial_expires_at,
        current_period_end
    ) VALUES (
        p_user_id,
        p_plan_tier,
        FALSE,
        FALSE,
        v_now,
        v_expires,
        v_expires
    );

    RETURN jsonb_build_object(
        'success', true,
        'is_web_verified', true,
        'trial_started_at', v_now,
        'trial_expires_at', v_expires,
        'subscription_status', 'TRIAL_ACTIVE'
    );
END;
$$;

-- 5. RPC: Verify Mobile Login Access Gate
CREATE OR REPLACE FUNCTION public.rpc_verify_mobile_login_gate(
    p_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_profile public.user_profiles%ROWTYPE;
BEGIN
    SELECT * INTO v_profile FROM public.user_profiles WHERE user_id = p_user_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'allowed', false,
            'code', 'WEB_VERIFICATION_REQUIRED',
            'message', 'Please complete your initial account registration and verification on our website before accessing the mobile app.'
        );
    END IF;

    -- Check if account has active license or cloud backup before checking is_web_verified
    IF v_profile.subscription_status = 'ACTIVE' OR v_profile.plan_tier IN ('OWNERSHIP_CLOUD', 'ENTERPRISE') THEN
        RETURN jsonb_build_object('allowed', true, 'code', 'ACCESS_GRANTED', 'subscription_status', 'ACTIVE');
    END IF;

    IF NOT v_profile.is_web_verified THEN
        RETURN jsonb_build_object(
            'allowed', false,
            'code', 'WEB_VERIFICATION_REQUIRED',
            'message', 'Please complete your initial account registration and verification on our website before accessing the mobile app.'
        );
    END IF;

    -- Check subscription or active trial
    IF v_profile.subscription_status = 'ACTIVE' THEN
        RETURN jsonb_build_object('allowed', true, 'code', 'ACCESS_GRANTED', 'subscription_status', 'ACTIVE');
    END IF;

    IF v_profile.trial_expires_at IS NOT NULL AND v_profile.trial_expires_at > NOW() THEN
        RETURN jsonb_build_object('allowed', true, 'code', 'ACCESS_GRANTED', 'subscription_status', 'TRIAL_ACTIVE', 'trial_expires_at', v_profile.trial_expires_at);
    END IF;

    RETURN jsonb_build_object(
        'allowed', false,
        'code', 'TRIAL_EXPIRED',
        'message', 'Your 7-day free trial has expired. Please subscribe on our web portal to continue using the app.'
    );
END;
$$;
