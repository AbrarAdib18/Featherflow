-- ─────────────────────────────────────────────────────────────────────────────
-- Featherflow — Feed marketplace UX correction extension
--
-- Apply ONCE against the connected PostgreSQL database, after
-- feed_marketplace_extension.sql. Re-running is safe (idempotent).
--
--   psql "$DATABASE_URL" -f backend/feed_marketplace_ux_extension.sql
--
-- What it adds:
--   * feed_companies: district/upazila/description/logo_url/cover_url, and
--     widens the status CHECK to (pending, active, suspended, rejected) —
--     needed for the Feed Admin "Clients" section (companies working with
--     FeatherFlow — never confused with farmers, who are order customers).
--   * feed_products: gallery_urls (JSONB list) for multi-image galleries,
--     alongside the existing single image_url.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE feed_companies ADD COLUMN IF NOT EXISTS district     VARCHAR(100) NOT NULL DEFAULT '';
ALTER TABLE feed_companies ADD COLUMN IF NOT EXISTS upazila      VARCHAR(100) NOT NULL DEFAULT '';
ALTER TABLE feed_companies ADD COLUMN IF NOT EXISTS description  TEXT;
ALTER TABLE feed_companies ADD COLUMN IF NOT EXISTS logo_url     TEXT;
ALTER TABLE feed_companies ADD COLUMN IF NOT EXISTS cover_url    TEXT;

ALTER TABLE feed_companies DROP CONSTRAINT IF EXISTS feed_companies_status_check;
ALTER TABLE feed_companies ADD CONSTRAINT feed_companies_status_check
    CHECK (status IN ('pending', 'active', 'suspended', 'rejected'));

ALTER TABLE feed_products ADD COLUMN IF NOT EXISTS gallery_urls JSONB NOT NULL DEFAULT '[]'::jsonb;
