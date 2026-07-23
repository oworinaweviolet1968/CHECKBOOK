-- ============================================================
-- Migration: Add desktop_last_seen heartbeat column
-- Run this once in your Supabase SQL Editor (Dashboard > SQL Editor)
-- ============================================================

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS desktop_last_seen BIGINT DEFAULT 0;

-- Optional: index for fast polling queries
CREATE INDEX IF NOT EXISTS idx_users_desktop_last_seen ON public.users(desktop_last_seen);
