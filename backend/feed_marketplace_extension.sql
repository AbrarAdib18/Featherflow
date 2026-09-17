-- ─────────────────────────────────────────────────────────────────────────────
-- Featherflow — Feed catalogue + marketplace + Feed Admin role extension
--
-- Apply ONCE against the connected PostgreSQL database, after
-- featherflow_schema.sql / postgres_backend_extension.sql / farmers_panel_extension.sql /
-- feed_flock_extension.sql. Re-running is safe (idempotent).
--
--   psql "$DATABASE_URL" -f backend/feed_marketplace_extension.sql
--
-- What it adds (Priorities 5-9):
--   * feed_companies / feed_products — real relational admin-approved feed
--     catalogue, mirroring pharmacy_catalogue_medicines' shape/approval
--     workflow (see postgres_backend_extension.sql). Farmers may only ever
--     order approved, active products — enforced server-side in
--     feed_catalogue/order_views.py, never trusted from the client.
--   * feed_admin role — a normal admin-panel sub-role (panel_type='admin',
--     tier 3, like admin_pharmacy/admin_doctor), scoped to the
--     feed-catalogue/feed-orders/feed-delivery permission modules only.
--
-- Feed ORDERS deliberately do NOT get a new table here: they reuse the
-- existing backend_admin_records JSON-bridge (module='feed-orders') exactly
-- like pharmacy-orders, and the existing delivery_orders table
-- (order_type='marketplace', already a valid choice) once a rider is
-- assigned — see FEED_MARKETPLACE_INTEGRATION.md for the full flow.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS feed_companies (
    id                UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    name              TEXT          NOT NULL,
    contact_person    TEXT          NOT NULL DEFAULT '',
    contact_phone     VARCHAR(20)   NOT NULL DEFAULT '',
    contact_email     VARCHAR(255)  NOT NULL DEFAULT '',
    address           TEXT          NOT NULL DEFAULT '',
    license_number    VARCHAR(100),
    status            VARCHAR(20)   NOT NULL DEFAULT 'active'
                      CHECK (status IN ('active', 'suspended')),
    admin_notes       TEXT,
    created_by        UUID          REFERENCES users(id) ON DELETE SET NULL,
    created_at        TIMESTAMP     DEFAULT NOW(),
    updated_at        TIMESTAMP     DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS feed_products (
    id                        UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id                UUID          NOT NULL REFERENCES feed_companies(id) ON DELETE CASCADE,
    product_name              TEXT          NOT NULL,
    brand                     TEXT          NOT NULL DEFAULT '',
    feed_type                 VARCHAR(30)   NOT NULL DEFAULT 'other'
                              CHECK (feed_type IN ('starter', 'grower', 'finisher', 'layer',
                                                    'breeder', 'supplement', 'other')),
    bird_type                 VARCHAR(20)   NOT NULL DEFAULT 'other'
                              CHECK (bird_type IN ('broiler', 'layer', 'chick', 'breeder', 'other')),
    description               TEXT,
    ingredients               TEXT,
    nutritional_info          JSONB         NOT NULL DEFAULT '{}'::jsonb,
    unit                      VARCHAR(20)   NOT NULL DEFAULT 'kg'
                              CHECK (unit IN ('kg', 'bag_25kg', 'bag_50kg', 'ton', 'piece')),
    price                     DECIMAL(10,2) NOT NULL DEFAULT 0 CHECK (price >= 0),
    stock_quantity            INT           NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0),
    min_order_quantity        INT           NOT NULL DEFAULT 1 CHECK (min_order_quantity >= 1),
    image_url                 TEXT,
    approval_status           VARCHAR(20)   NOT NULL DEFAULT 'draft'
                              CHECK (approval_status IN ('draft', 'pending_review', 'approved',
                                                          'rejected', 'suspended')),
    rejection_reason          TEXT,
    created_by                UUID          REFERENCES users(id) ON DELETE SET NULL,
    approved_by               UUID          REFERENCES users(id) ON DELETE SET NULL,
    orders_count              INT           NOT NULL DEFAULT 0,
    created_at                TIMESTAMP     DEFAULT NOW(),
    updated_at                TIMESTAMP     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_feed_products_company  ON feed_products(company_id);
CREATE INDEX IF NOT EXISTS idx_feed_products_approval  ON feed_products(approval_status);
CREATE INDEX IF NOT EXISTS idx_feed_products_bird_type ON feed_products(bird_type);
CREATE INDEX IF NOT EXISTS idx_feed_products_feed_type ON feed_products(feed_type);
-- The farmer-facing browse endpoint always filters approval_status='approved';
-- this partial index makes that (by far the hottest) query fast.
CREATE INDEX IF NOT EXISTS idx_feed_products_available
    ON feed_products(bird_type, feed_type) WHERE approval_status = 'approved';

DROP TRIGGER IF EXISTS trg_feed_companies_updated_at ON feed_companies;
CREATE TRIGGER trg_feed_companies_updated_at
    BEFORE UPDATE ON feed_companies
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

DROP TRIGGER IF EXISTS trg_feed_products_updated_at ON feed_products;
CREATE TRIGGER trg_feed_products_updated_at
    BEFORE UPDATE ON feed_products
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── Feed Admin role (Priority 6) — a normal admin-panel sub-role, exactly
-- like admin_pharmacy/admin_doctor: panel_type='admin' (required by the
-- roles.panel_type CHECK constraint), tier 3 (module admin), scoped
-- permissions. This is enforced by backend/api/admin_rbac.py's existing
-- can_perform_action() — nothing frontend-only about it.
INSERT INTO roles (name, panel_type, description)
VALUES ('feed_admin', 'admin', 'Feed Admin — feed companies, catalogue, inventory, and feed order delivery')
ON CONFLICT (name) DO NOTHING;

UPDATE roles SET tier_level = 3, is_system = TRUE, permissions = '{
    "feed-catalogue": ["view", "create", "edit", "approve", "reject", "suspend", "delete", "export"],
    "feed-orders": ["view", "edit", "assign", "export"],
    "feed-delivery": ["view", "assign"],
    "audit": ["view"]
}'::jsonb WHERE name = 'feed_admin';

UPDATE roles SET hourly_rate_range_min = 250, hourly_rate_range_max = 600 WHERE name = 'feed_admin';
