-- ─────────────────────────────────────────────────────────────────────────────
-- Featherflow — Feed Inventory Owner role + profile + finance-mirror extension
--
-- Apply ONCE against the connected PostgreSQL database, after
-- featherflow_schema.sql / postgres_backend_extension.sql /
-- feed_marketplace_extension.sql / pharmacy_cost_management_extension.sql.
-- Re-running is safe (idempotent).
--
--   psql "$DATABASE_URL" -f backend/feed_owner_extension.sql
--
-- What it adds:
--   * 'feed_owner' role — a restricted, non-admin business account (same
--     shape as the 'pharmacy' role: NOT panel_type='admin', so it never
--     passes api.admin_rbac.IsAdminUser / can_perform_action — every
--     restriction the spec asks for ("must not access Pharmacy Admin, Super
--     Admin, other admin panels, ...") is therefore already the default,
--     server-side, before any view-level check is even written).
--   * feed_owner_profiles — the owner's real profile (org name, inventory
--     location, assigned feed categories, status, photo).
--   * expenses.source_feed_order_id — mirrors
--     pharmacy_cost_management_extension.sql's source_pharmacy_order_id, so a
--     delivered feed order can be mirrored into Cost Management exactly once
--     (feed_catalogue.services.mirror_feed_expense).
-- ─────────────────────────────────────────────────────────────────────────────

-- roles.panel_type's CHECK constraint (featherflow_schema.sql) only allows a
-- fixed enum. Widen it to include 'feed_owner' rather than misusing an
-- unrelated existing value (e.g. 'pharmacist') for a role that isn't one.
DO $$
DECLARE
    con_name text;
BEGIN
    SELECT con.conname INTO con_name
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    JOIN pg_attribute att ON att.attrelid = rel.oid AND att.attnum = ANY(con.conkey)
    WHERE rel.relname = 'roles' AND con.contype = 'c' AND att.attname = 'panel_type';
    IF con_name IS NOT NULL THEN
        EXECUTE format('ALTER TABLE roles DROP CONSTRAINT %I', con_name);
    END IF;
END $$;

ALTER TABLE roles ADD CONSTRAINT roles_panel_type_check CHECK (panel_type IN (
    'farmer', 'doctor', 'delivery', 'pharmacy', 'pharmacist', 'researcher', 'admin', 'feed_owner'
));

INSERT INTO roles (name, panel_type, description)
VALUES ('feed_owner', 'feed_owner', 'Feed Inventory Owner — restricted feed-inventory profile + Feed Admin chat access only')
ON CONFLICT (name) DO NOTHING;
UPDATE roles SET tier_level = 4, is_system = TRUE WHERE name = 'feed_owner';

CREATE TABLE IF NOT EXISTS feed_owner_profiles (
    id                   UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id              UUID          NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    business_name        TEXT          NOT NULL DEFAULT '',
    inventory_location   TEXT          NOT NULL DEFAULT '',
    assigned_categories  JSONB         NOT NULL DEFAULT '[]'::jsonb,
    profile_photo_url    TEXT,
    status               VARCHAR(20)   NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
    approved_by_admin_id UUID          REFERENCES users(id) ON DELETE SET NULL,
    created_at           TIMESTAMP     DEFAULT NOW(),
    updated_at           TIMESTAMP     DEFAULT NOW()
);

DROP TRIGGER IF EXISTS trg_feed_owner_profiles_updated_at ON feed_owner_profiles;
CREATE TRIGGER trg_feed_owner_profiles_updated_at
    BEFORE UPDATE ON feed_owner_profiles
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- Feed Admin <-> Feed Inventory Owner chat reuses doctor.Conversation/Message
-- verbatim (consultation=NULL) plus the two generic columns already added by
-- pharmacy_admin_portal_extension.sql (pharmacy_chat_status/assigned_admin) —
-- no new chat schema needed. The admin/owner query sides simply filter by
-- roles__name='feed_owner' instead of 'pharmacy'.

-- Feed order -> Cost Management mirror (exactly-once on delivery), mirroring
-- pharmacy_cost_management_extension.sql's source_pharmacy_order_id.
ALTER TABLE expenses ADD COLUMN IF NOT EXISTS source_feed_order_id TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS uq_expenses_source_feed_order
    ON expenses(source_feed_order_id)
    WHERE source_feed_order_id IS NOT NULL;

COMMENT ON COLUMN expenses.source_feed_order_id IS
    'feed-orders AdminPanelRecord payload id this expense was mirrored '
    'from, on delivery. Unique when set - the exactly-once guard for mirroring.';
