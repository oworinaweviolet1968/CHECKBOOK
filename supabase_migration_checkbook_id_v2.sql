-- ============================================================================
-- MIGRATION: CHECKBOOK ID (CK-******) AUTHENTICATION & SECURITY
-- ============================================================================

-- 1. Add checkbook_id column to public.user_profiles if not exists
ALTER TABLE public.user_profiles 
ADD COLUMN IF NOT EXISTS checkbook_id TEXT UNIQUE;

-- Create index for fast lookups
CREATE INDEX IF NOT EXISTS idx_user_profiles_checkbook_id 
ON public.user_profiles(checkbook_id);

-- 2. Function to generate a unique CK-****** identifier
CREATE OR REPLACE FUNCTION public.generate_unique_checkbook_id()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_chars TEXT := '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    v_code TEXT;
    v_exists BOOLEAN;
    v_i INT;
BEGIN
    LOOP
        v_code := 'CK-';
        FOR v_i IN 1..6 LOOP
            v_code := v_code || substr(v_chars, floor(random() * length(v_chars) + 1)::int, 1);
        END LOOP;

        -- Check uniqueness in user_profiles
        SELECT EXISTS (
            SELECT 1 FROM public.user_profiles WHERE checkbook_id = v_code
        ) INTO v_exists;

        IF NOT v_exists THEN
            RETURN v_code;
        END IF;
    END LOOP;
END;
$$;

-- 3. Backfill existing user accounts that do not have a checkbook_id
DO $$
DECLARE
    r RECORD;
    v_new_id TEXT;
BEGIN
    FOR r IN SELECT user_id, email FROM public.user_profiles WHERE checkbook_id IS NULL OR checkbook_id = '' OR checkbook_id LIKE '%*%' LOOP
        v_new_id := public.generate_unique_checkbook_id();
        
        -- Update user_profiles
        UPDATE public.user_profiles 
        SET checkbook_id = v_new_id, updated_at = NOW() 
        WHERE user_id = r.user_id;

        -- Also update auth.users raw_user_meta_data
        UPDATE auth.users 
        SET raw_user_meta_data = COALESCE(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('checkbook_id', v_new_id)
        WHERE id = r.user_id;
    END LOOP;

    -- Also backfill any auth.users that might not be in user_profiles yet or have literal asterisk placeholder
    FOR r IN SELECT id, email, raw_user_meta_data FROM auth.users WHERE (raw_user_meta_data->>'checkbook_id') IS NULL OR (raw_user_meta_data->>'checkbook_id') LIKE '%*%' LOOP
        v_new_id := public.generate_unique_checkbook_id();
        
        UPDATE auth.users 
        SET raw_user_meta_data = COALESCE(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('checkbook_id', v_new_id)
        WHERE id = r.id;

        INSERT INTO public.user_profiles (user_id, email, checkbook_id, created_at, updated_at)
        VALUES (r.id, LOWER(r.email), v_new_id, NOW(), NOW())
        ON CONFLICT (user_id) DO UPDATE SET checkbook_id = v_new_id;
    END LOOP;
END $$;

-- 4. Update handle_new_user_trial_profile trigger to generate checkbook_id on signup
CREATE OR REPLACE FUNCTION public.handle_new_user_trial_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_checkbook_id TEXT;
BEGIN
    -- Check if user metadata already has a checkbook_id
    v_checkbook_id := NEW.raw_user_meta_data->>'checkbook_id';
    
    IF v_checkbook_id IS NULL OR v_checkbook_id = '' THEN
        v_checkbook_id := public.generate_unique_checkbook_id();
    END IF;

    -- Update auth.users metadata with generated checkbook_id
    NEW.raw_user_meta_data := COALESCE(NEW.raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('checkbook_id', v_checkbook_id);

    INSERT INTO public.user_profiles (
        user_id,
        email,
        checkbook_id,
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
        v_checkbook_id,
        TRUE,
        NOW(),
        NOW() + INTERVAL '7 days',
        'OWNERSHIP_CLOUD',
        'TRIAL_ACTIVE',
        NOW(),
        NOW()
    )
    ON CONFLICT (user_id) DO UPDATE SET
        checkbook_id = COALESCE(public.user_profiles.checkbook_id, EXCLUDED.checkbook_id),
        is_web_verified = TRUE,
        subscription_status = 'TRIAL_ACTIVE',
        trial_expires_at = COALESCE(public.user_profiles.trial_expires_at, NOW() + INTERVAL '7 days'),
        updated_at = NOW();

    RETURN NEW;
END;
$$;

-- Ensure trigger is active
DROP TRIGGER IF EXISTS on_auth_user_created_trial ON auth.users;
CREATE TRIGGER on_auth_user_created_trial
    BEFORE INSERT OR UPDATE ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_trial_profile();

-- 5. Security RPC Endpoint: Lookup User Email & Profile by Checkbook ID
CREATE OR REPLACE FUNCTION public.rpc_lookup_user_by_checkbook_id(
    p_checkbook_id TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_formatted_id TEXT;
    v_raw_digits TEXT;
    v_profile RECORD;
BEGIN
    IF p_checkbook_id IS NULL OR TRIM(p_checkbook_id) = '' THEN
        RETURN jsonb_build_object('found', false, 'error', 'INVALID_INPUT', 'message', 'Please enter a valid Checkbook ID.');
    END IF;

    -- Format input: uppercase and generate both prefixed and raw digit variations
    v_formatted_id := UPPER(TRIM(p_checkbook_id));
    IF NOT (v_formatted_id LIKE 'CK-%') THEN
        v_formatted_id := 'CK-' || v_formatted_id;
    END IF;
    v_raw_digits := REPLACE(v_formatted_id, 'CK-', '');

    -- 1. Try public.user_profiles
    SELECT user_id, email INTO v_profile 
    FROM public.user_profiles 
    WHERE UPPER(checkbook_id) = v_formatted_id
       OR UPPER(checkbook_id) = v_raw_digits
       OR checkbook_id LIKE '%' || v_raw_digits || '%';

    -- 2. Fallback: check auth.users metadata directly
    IF v_profile.email IS NULL THEN
        SELECT id AS user_id, email INTO v_profile
        FROM auth.users
        WHERE UPPER(raw_user_meta_data->>'checkbook_id') = v_formatted_id
           OR UPPER(raw_user_meta_data->>'checkbook_id') = v_raw_digits
           OR (raw_user_meta_data->>'checkbook_id') LIKE '%' || v_raw_digits || '%';
    END IF;

    IF v_profile.email IS NOT NULL THEN
        RETURN jsonb_build_object(
            'found', true,
            'checkbook_id', v_formatted_id,
            'user_id', v_profile.user_id,
            'email', LOWER(v_profile.email)
        );
    ELSE
        RETURN jsonb_build_object(
            'found', false, 
            'error', 'CHECKBOOK_ID_NOT_FOUND', 
            'message', 'Checkbook ID not found. Please check your Mobile App under Settings > Checkbook ID.'
        );
    END IF;
END;
$$;

-- Grant permissions for public API access
GRANT EXECUTE ON FUNCTION public.rpc_lookup_user_by_checkbook_id(TEXT) TO anon, authenticated, service_role;
