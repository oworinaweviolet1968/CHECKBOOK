-- ============================================================================
-- MIGRATION: CHECKBOOK ID DEVICE PAIRING & PUSH-APPROVAL LOGIN
-- ============================================================================

-- 1. Create device_pairing_requests table
CREATE TABLE IF NOT EXISTS public.device_pairing_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    checkbook_id TEXT NOT NULL,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    user_email TEXT,
    device_name TEXT NOT NULL,
    device_fingerprint TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'PENDING', -- 'PENDING', 'APPROVED', 'REJECTED', 'EXPIRED'
    pairing_token TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '2 minutes')
);

-- Index for fast status polling and cleanup
CREATE INDEX IF NOT EXISTS idx_pairing_checkbook_id ON public.device_pairing_requests(checkbook_id);
CREATE INDEX IF NOT EXISTS idx_pairing_status ON public.device_pairing_requests(status);
CREATE INDEX IF NOT EXISTS idx_pairing_token ON public.device_pairing_requests(pairing_token);

-- Enable RLS
ALTER TABLE public.device_pairing_requests ENABLE ROW LEVEL SECURITY;

-- RLS Policies allowing desktop and mobile app to interact with pairing requests
DROP POLICY IF EXISTS "Public access to pairing requests" ON public.device_pairing_requests;
CREATE POLICY "Public access to pairing requests"
    ON public.device_pairing_requests
    FOR ALL
    USING (true)
    WITH CHECK (true);

-- 2. RPC: Initiate Desktop Pairing Request
CREATE OR REPLACE FUNCTION public.rpc_initiate_pairing_request(
    p_checkbook_id TEXT,
    p_device_name TEXT DEFAULT 'Desktop PC',
    p_device_fingerprint TEXT DEFAULT 'Desktop-Client'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_formatted_id TEXT;
    v_user_id UUID;
    v_email TEXT;
    v_session_id UUID;
    v_expires_at TIMESTAMPTZ := NOW() + INTERVAL '2 minutes';
BEGIN
    IF p_checkbook_id IS NULL OR TRIM(p_checkbook_id) = '' THEN
        RETURN jsonb_build_object('success', false, 'error', 'INVALID_INPUT', 'message', 'Checkbook ID is required.');
    END IF;

    v_formatted_id := UPPER(TRIM(p_checkbook_id));
    IF NOT (v_formatted_id LIKE 'CK-%') THEN
        v_formatted_id := 'CK-' || v_formatted_id;
    END IF;

    -- Lookup user profile
    SELECT user_id, email INTO v_user_id, v_email
    FROM public.user_profiles
    WHERE UPPER(checkbook_id) = v_formatted_id;

    IF v_user_id IS NULL THEN
        -- Fallback to auth.users metadata
        SELECT id, email INTO v_user_id, v_email
        FROM auth.users
        WHERE UPPER(raw_user_meta_data->>'checkbook_id') = v_formatted_id;
    END IF;

    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'CHECKBOOK_ID_NOT_FOUND',
            'message', 'Checkbook ID not found. Find your ID in your Mobile App under Settings > Checkbook ID.'
        );
    END IF;

    -- Clean up previous pending requests for this device/checkbook_id
    UPDATE public.device_pairing_requests
    SET status = 'EXPIRED'
    WHERE UPPER(checkbook_id) = v_formatted_id AND status = 'PENDING';

    -- Insert new pairing request
    INSERT INTO public.device_pairing_requests (
        checkbook_id,
        user_id,
        user_email,
        device_name,
        device_fingerprint,
        status,
        expires_at
    ) VALUES (
        v_formatted_id,
        v_user_id,
        v_email,
        p_device_name,
        p_device_fingerprint,
        'PENDING',
        v_expires_at
    ) RETURNING id INTO v_session_id;

    RETURN jsonb_build_object(
        'success', true,
        'session_id', v_session_id,
        'checkbook_id', v_formatted_id,
        'user_id', v_user_id,
        'email', v_email,
        'expires_at', v_expires_at
    );
END;
$$;

-- 3. RPC: Respond to Desktop Pairing Request (Mobile App Accept / Reject)
CREATE OR REPLACE FUNCTION public.rpc_respond_pairing_request(
    p_session_id UUID,
    p_action TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_req public.device_pairing_requests%ROWTYPE;
    v_token TEXT;
BEGIN
    SELECT * INTO v_req FROM public.device_pairing_requests WHERE id = p_session_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'NOT_FOUND', 'message', 'Pairing request not found.');
    END IF;

    IF v_req.status != 'PENDING' OR NOW() > v_req.expires_at THEN
        UPDATE public.device_pairing_requests SET status = 'EXPIRED' WHERE id = p_session_id;
        RETURN jsonb_build_object('success', false, 'error', 'EXPIRED', 'message', 'Pairing request expired or already processed.');
    END IF;

    IF UPPER(p_action) = 'ACCEPT' OR UPPER(p_action) = 'APPROVED' THEN
        v_token := 'DT-' || gen_random_uuid()::text;
        
        UPDATE public.device_pairing_requests
        SET status = 'APPROVED', pairing_token = v_token
        WHERE id = p_session_id;

        RETURN jsonb_build_object(
            'success', true,
            'status', 'APPROVED',
            'pairing_token', v_token,
            'user_id', v_req.user_id,
            'email', v_req.user_email
        );
    ELSE
        UPDATE public.device_pairing_requests
        SET status = 'REJECTED'
        WHERE id = p_session_id;

        RETURN jsonb_build_object(
            'success', true,
            'status', 'REJECTED'
        );
    END IF;
END;
$$;

-- 4. RPC: Check Pairing Status (Desktop Polling / Listener)
CREATE OR REPLACE FUNCTION public.rpc_check_pairing_status(
    p_session_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_req public.device_pairing_requests%ROWTYPE;
BEGIN
    SELECT * INTO v_req FROM public.device_pairing_requests WHERE id = p_session_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('found', false, 'status', 'NOT_FOUND');
    END IF;

    IF v_req.status = 'PENDING' AND NOW() > v_req.expires_at THEN
        UPDATE public.device_pairing_requests SET status = 'EXPIRED' WHERE id = p_session_id;
        RETURN jsonb_build_object('found', true, 'status', 'EXPIRED');
    END IF;

    RETURN jsonb_build_object(
        'found', true,
        'status', v_req.status,
        'pairing_token', v_req.pairing_token,
        'user_id', v_req.user_id,
        'email', v_req.user_email
    );
END;
$$;

-- 5. RPC: Verify Device Token on Desktop Startup
CREATE OR REPLACE FUNCTION public.rpc_verify_device_token(
    p_pairing_token TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_req public.device_pairing_requests%ROWTYPE;
BEGIN
    IF p_pairing_token IS NULL OR TRIM(p_pairing_token) = '' THEN
        RETURN jsonb_build_object('valid', false, 'error', 'MISSING_TOKEN');
    END IF;

    SELECT * INTO v_req 
    FROM public.device_pairing_requests 
    WHERE pairing_token = p_pairing_token AND status = 'APPROVED'
    ORDER BY created_at DESC LIMIT 1;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('valid', false, 'error', 'INVALID_TOKEN');
    END IF;

    RETURN jsonb_build_object(
        'valid', true,
        'user_id', v_req.user_id,
        'email', v_req.user_email,
        'checkbook_id', v_req.checkbook_id
    );
END;
$$;

-- Grant permissions for public API access
GRANT EXECUTE ON FUNCTION public.rpc_initiate_pairing_request TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.rpc_respond_pairing_request TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.rpc_check_pairing_status TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.rpc_verify_device_token TO anon, authenticated, service_role;
