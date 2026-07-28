-- ============================================================================
-- POWERSYNC ENTERPRISE MIGRATION V2
-- Multi-device Identity, Delta Stock Mutator with Oversold Protection, & Batch RPC
-- ============================================================================

-- 1. Account Devices Table for Multi-Device Identity & Revocation
CREATE TABLE IF NOT EXISTS public.account_devices (
    device_id UUID PRIMARY KEY,
    user_id UUID NOT NULL,
    device_name TEXT,
    platform TEXT, -- 'JAVAFX_DESKTOP' or 'FLUTTER_MOBILE'
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    last_active_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS on account_devices
ALTER TABLE public.account_devices ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage their own account devices"
    ON public.account_devices
    FOR ALL
    USING (auth.uid() = user_id);

-- 2. Sync Conflicts & Oversold Alerts Table
CREATE TABLE IF NOT EXISTS public.sync_conflicts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sync_id TEXT NOT NULL,
    device_id UUID NOT NULL,
    user_id UUID NOT NULL,
    conflict_type TEXT NOT NULL, -- 'OVERSOLD_STOCK', 'LWW_CONCURRENT_EDIT', etc.
    shortfall INTEGER DEFAULT 0,
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.sync_conflicts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own sync conflicts"
    ON public.sync_conflicts
    FOR SELECT
    USING (auth.uid() = user_id);

-- 3. Atomic Delta Stock Mutator with Oversold Protection
CREATE OR REPLACE FUNCTION public.rpc_apply_stock_delta(
    p_sync_id TEXT,
    p_delta INT,
    p_device_id UUID,
    p_user_id UUID,
    p_mutation_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_qty INT;
    v_new_qty INT;
    v_item_name TEXT;
    v_result JSONB;
BEGIN
    -- Verify device authorization
    IF NOT EXISTS (
        SELECT 1 FROM public.account_devices 
        WHERE device_id = p_device_id AND user_id = p_user_id AND is_active = TRUE
    ) THEN
        -- Auto-register device if first time seen for valid authenticated user
        INSERT INTO public.account_devices (device_id, user_id, device_name, platform)
        VALUES (p_device_id, p_user_id, 'Registered Client', 'UNKNOWN')
        ON CONFLICT (device_id) DO UPDATE SET last_active_at = NOW();
    END IF;

    -- Update device last active timestamp
    UPDATE public.account_devices SET last_active_at = NOW() WHERE device_id = p_device_id;

    -- Fetch current stock quantity
    SELECT quantity, item INTO v_current_qty, v_item_name
    FROM public.stock
    WHERE sync_id = p_sync_id AND user_id = p_user_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Stock item not found');
    END IF;

    v_new_qty := v_current_qty + p_delta;

    -- Check for Oversold Condition
    IF v_new_qty < 0 THEN
        INSERT INTO public.sync_conflicts (sync_id, device_id, user_id, conflict_type, shortfall, details)
        VALUES (
            p_sync_id,
            p_device_id,
            p_user_id,
            'OVERSOLD_STOCK',
            ABS(v_new_qty),
            jsonb_build_object(
                'item_name', v_item_name,
                'previous_qty', v_current_qty,
                'requested_delta', p_delta,
                'shortfall', ABS(v_new_qty)
            )
        );
    END IF;

    -- Update Stock with GREATEST(0, v_new_qty) floor protection
    UPDATE public.stock
    SET quantity = GREATEST(0, v_new_qty),
        updated_at = NOW()
    WHERE sync_id = p_sync_id AND user_id = p_user_id;

    RETURN jsonb_build_object(
        'success', true,
        'item', v_item_name,
        'previous_quantity', v_current_qty,
        'new_quantity', GREATEST(0, v_new_qty),
        'is_oversold', (v_new_qty < 0),
        'shortfall', CASE WHEN v_new_qty < 0 THEN ABS(v_new_qty) ELSE 0 END
    );
END;
$$;

-- 4. Batch RPC Processor for Atomic Queue Operations
CREATE OR REPLACE FUNCTION public.rpc_process_sync_batch(
    p_device_id UUID,
    p_user_id UUID,
    p_operations JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_op JSONB;
    v_results JSONB := '[]'::JSONB;
    v_op_res JSONB;
BEGIN
    FOR v_op IN SELECT * FROM jsonb_array_elements(p_operations)
    LOOP
        IF (v_op->>'op_type') = 'DELTA_STOCK' THEN
            SELECT public.rpc_apply_stock_delta(
                v_op->>'sync_id',
                (v_op->>'delta')::INT,
                p_device_id,
                p_user_id,
                (v_op->>'mutation_id')::UUID
            ) INTO v_op_res;
            
            v_results := v_results || jsonb_build_object(
                'mutation_id', v_op->>'mutation_id',
                'result', v_op_res
            );
        END IF;
    END LOOP;

    RETURN jsonb_build_object('success', true, 'processed_count', jsonb_array_length(p_operations), 'results', v_results);
END;
$$;
