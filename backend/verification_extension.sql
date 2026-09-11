-- ─────────────────────────────────────────────────────────────────────────────
-- Featherflow — Verification / password-reset / document-access extension
--
-- Apply ONCE against the connected PostgreSQL database, after
-- featherflow_schema.sql / postgres_backend_extension.sql. Re-running is safe.
--
--   psql "$DATABASE_URL" -f backend/verification_extension.sql
--
-- What it adds:
--   * users.email_verified_at / users.phone_verified_at — set when the account
--     owner confirms an OTP for that channel. NULL = not yet verified.
--
-- One-time verification codes and password-reset codes are NOT stored here —
-- they live in Django's cache (10-minute TTL); configure a shared cache
-- (Redis) for multi-process deployments. Uploaded signup documents are stored
-- on the private filesystem (backend/private_media/) and access is resolved by
-- looking up which profile row references the document, so no table is needed.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS email_verified_at timestamptz,
    ADD COLUMN IF NOT EXISTS phone_verified_at timestamptz;
