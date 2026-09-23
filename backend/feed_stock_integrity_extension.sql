-- ─────────────────────────────────────────────────────────────────────────────
-- Featherflow — Feed stock integrity + audit trail extension
--
-- Apply ONCE against the connected PostgreSQL database, after
-- featherflow_schema.sql / postgres_backend_extension.sql / feed_flock_extension.sql.
-- Re-running is safe (idempotent).
--
--   psql "$DATABASE_URL" -f backend/feed_stock_integrity_extension.sql
--
-- What it adds, and why (see FARMER_FEED_MANAGEMENT_AND_DASHBOARD_FIXES.md):
--
--   * feed_stock_movements — an append-only audit log, one row per purchase/
--     consumption/adjustment/removal event against a farm's feed_stock line.
--     feed_stock.quantity_available remains the ONE source of truth for
--     "current stock" (unchanged, still a live-read counter) — this table is
--     never read to compute current stock, only to show real history. It
--     replaces feed/views.py's previous fake "history" (which just relabeled
--     the current stock rows as if they were purchase entries — there was no
--     actual purchase ledger before this).
--   * A DB-level CHECK that feed_stock.quantity_available can never go
--     negative — defense in depth alongside the application-level guard
--     already in farmers/feed_views.py's consumption endpoint.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS feed_stock_movements (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_id         UUID        NOT NULL REFERENCES farms(id) ON DELETE CASCADE,
    feed_type_id    UUID        NOT NULL REFERENCES feed_types(id) ON DELETE CASCADE,
    movement_type   VARCHAR(20) NOT NULL CHECK (movement_type IN (
                        'purchase', 'consumption', 'adjustment', 'removal'
                    )),
    quantity_delta  NUMERIC(10,2) NOT NULL,   -- positive for purchase/adjustment-up, negative for consumption/removal
    quantity_after  NUMERIC(10,2) NOT NULL,   -- snapshot of quantity_available immediately after this event
    unit_cost       NUMERIC(10,2),
    note            TEXT,
    created_by      UUID        REFERENCES users(id) ON DELETE SET NULL,
    created_at      TIMESTAMP   DEFAULT NOW()
    -- No updated_at / no UPDATE path — an audit log entry is immutable; a
    -- correction is a new 'adjustment' event, not an edit to a past one.
);

CREATE INDEX IF NOT EXISTS idx_feed_stock_movements_farm
    ON feed_stock_movements(farm_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_feed_stock_movements_feed_type
    ON feed_stock_movements(feed_type_id);

DO $$
BEGIN
    ALTER TABLE feed_stock DROP CONSTRAINT IF EXISTS feed_stock_quantity_nonnegative_check;
    ALTER TABLE feed_stock ADD CONSTRAINT feed_stock_quantity_nonnegative_check
        CHECK (quantity_available >= 0);
END $$;
