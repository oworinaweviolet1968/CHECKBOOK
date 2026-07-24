-- Migration: Create app_releases table for free OTA desktop & mobile updates
CREATE TABLE IF NOT EXISTS app_releases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    platform TEXT NOT NULL, -- 'desktop', 'android', 'ios'
    version TEXT NOT NULL,  -- e.g. '2.3.0'
    download_url TEXT NOT NULL, -- Direct URL to .msi, .exe, or .apk in Supabase Storage or website
    mandatory BOOLEAN DEFAULT false,
    release_notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS (Row Level Security) and allow public read access for version checking
ALTER TABLE app_releases ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow public read access to app_releases" 
ON app_releases FOR SELECT 
USING (true);

CREATE POLICY "Allow public insert access to app_releases" 
ON app_releases FOR INSERT 
WITH CHECK (true);

