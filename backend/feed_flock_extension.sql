-- ─────────────────────────────────────────────────────────────────────────────
-- Featherflow — Flock lifecycle + age-based feeding guidance extension
--
-- Apply ONCE against the connected PostgreSQL database, after
-- featherflow_schema.sql / postgres_backend_extension.sql / farmers_panel_extension.sql.
-- Re-running is safe (idempotent).
--
--   psql "$DATABASE_URL" -f backend/feed_flock_extension.sql
--
-- What it adds (Priority 4 — Feed Management: flock details, age chart,
-- feeding notifications):
--   * flock_events       — immutable history log per flock: mortality, sale,
--                          transfer, vaccination, feed_consumption, weight.
--   * feeding_guidelines — age-range + bird-type feeding guidance (general
--                          reference data, NOT flock-specific and NOT a
--                          veterinary/medical recommendation — labelled as
--                          general guidance in both the API and the UI).
--
-- Flock age is deliberately NOT stored anywhere — it is always computed from
-- flocks.start_date at read time (see farms.models.Flock.age_days) so it can
-- never drift out of sync.
-- ─────────────────────────────────────────────────────────────────────────────

-- Pre-existing gap found while seeding demo flocks: the base schema's
-- `flocks.bird_type` CHECK only allowed broiler/layer/breeder/hatchery —
-- neither 'chick' (explicitly requested in Priority 4's bird-type list) nor
-- 'other' (already accepted by farmers/farm_views.py's Python-side
-- BIRD_TYPES set, meaning a farmer picking "Other" hit a 500 on the INSERT)
-- was allowed at the DB level. Widened to match what the API actually
-- validates.
ALTER TABLE flocks DROP CONSTRAINT IF EXISTS flocks_bird_type_check;
ALTER TABLE flocks ADD CONSTRAINT flocks_bird_type_check
    CHECK (bird_type IN ('broiler', 'layer', 'breeder', 'hatchery', 'chick', 'other'));

CREATE TABLE IF NOT EXISTS flock_events (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    flock_id    UUID        NOT NULL REFERENCES flocks(id) ON DELETE CASCADE,
    event_type  VARCHAR(20) NOT NULL CHECK (event_type IN (
                    'mortality', 'sale', 'transfer', 'vaccination',
                    'feed_consumption', 'weight_measurement'
                )),
    quantity    INTEGER,            -- birds affected (mortality/sale/transfer); NULL for vaccination/weight
    weight_kg   NUMERIC(8,3),       -- only meaningful for weight_measurement
    event_date  DATE        NOT NULL,
    notes       TEXT,
    recorded_by UUID        REFERENCES users(id) ON DELETE SET NULL,
    created_at  TIMESTAMP   DEFAULT NOW()
    -- No updated_at / no UPDATE path exposed by the API — event rows are an
    -- immutable log; a correction is a new event, not an edit.
);

CREATE INDEX IF NOT EXISTS idx_flock_events_flock ON flock_events(flock_id, event_date);
CREATE INDEX IF NOT EXISTS idx_flock_events_type  ON flock_events(event_type);

CREATE TABLE IF NOT EXISTS feeding_guidelines (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    bird_type           VARCHAR(20) NOT NULL CHECK (bird_type IN (
                            'broiler', 'layer', 'chick', 'breeder', 'other'
                        )),
    min_age_days        INTEGER     NOT NULL,
    max_age_days        INTEGER     NOT NULL,
    stage_label         VARCHAR(60) NOT NULL,       -- e.g. "Starter (0-10 days)"
    feed_type_label     VARCHAR(100) NOT NULL,      -- e.g. "Starter crumble, 22-24% protein"
    recommended_grams_per_bird_per_day NUMERIC(6,2),
    frequency_per_day   INTEGER     NOT NULL DEFAULT 2,
    guidance_text       TEXT        NOT NULL,       -- always general guidance, never a medical claim
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMP   DEFAULT NOW(),
    updated_at          TIMESTAMP   DEFAULT NOW(),
    CONSTRAINT chk_feeding_guideline_age_range CHECK (max_age_days >= min_age_days)
);

CREATE INDEX IF NOT EXISTS idx_feeding_guidelines_lookup
    ON feeding_guidelines(bird_type, min_age_days, max_age_days) WHERE is_active;

DROP TRIGGER IF EXISTS trg_feeding_guidelines_updated_at ON feeding_guidelines;
CREATE TRIGGER trg_feeding_guidelines_updated_at
    BEFORE UPDATE ON feeding_guidelines
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
