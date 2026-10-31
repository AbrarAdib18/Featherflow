-- ═══════════════════════════════════════════════════════════════════════════
-- Repairs NF-3 / NF-5 / NF-6 / NF-7 (post-repair verification findings)
-- Idempotent; apply once per database:
--     psql "$DATABASE_URL" -f backend/repairs_nf_extension.sql
--
--  * feed_companies.latitude/longitude : routable pickup location of a feed
--    supplier (NF-7). Delivery orders for feed take their pickup from here.
--  * consultation_note_history         : append-only audit history of every
--    edit to a doctor's case notes (NF-6): who, when, which fields, before/after.
-- ═══════════════════════════════════════════════════════════════════════════
ALTER TABLE feed_companies ADD COLUMN IF NOT EXISTS latitude  NUMERIC(9,6);
ALTER TABLE feed_companies ADD COLUMN IF NOT EXISTS longitude NUMERIC(9,6);
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_feed_company_coords') THEN
    ALTER TABLE feed_companies ADD CONSTRAINT ck_feed_company_coords CHECK (
      (latitude IS NULL AND longitude IS NULL) OR
      (latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180));
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS consultation_note_history (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    consultation_id UUID        NOT NULL REFERENCES consultations(id) ON DELETE CASCADE,
    edited_by       UUID        REFERENCES users(id) ON DELETE SET NULL,
    editor_role     VARCHAR(30),
    action          VARCHAR(20) NOT NULL DEFAULT 'edit',
    changes         JSONB       NOT NULL,
    created_at      TIMESTAMP   NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_note_history_consultation
    ON consultation_note_history (consultation_id, created_at);
