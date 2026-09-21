-- ════════════════════════════════════════════════════════════════════════════
-- Production hardening — Pass 1 (schema-level fixes found during the
-- production-readiness audit, 2026-09-14)
--
-- Additive and safe to rerun. Apply once on a database that already has
-- featherflow_schema.sql + postgres_backend_extension.sql (+ verification_extension.sql
-- + farmers_panel_extension.sql if present):
--
--   psql "$DATABASE_URL" -f backend/production_hardening_extension.sql
--
-- See PRODUCTION_READINESS_REPORT.md / SECURITY_HARDENING_REPORT.md for the
-- full findings each block below fixes.
-- ════════════════════════════════════════════════════════════════════════════

-- ── subscriptions.status: allow "replaced" ──────────────────────────────────
-- billing/services.py:_activate() retires a user's previous active subscription
-- with status='replaced' (distinct from a user-initiated 'cancelled' or a
-- time-based 'expired', for accurate finance reporting) whenever they check out
-- again. The base CHECK only allowed active/expired/cancelled/pending, so every
-- renewal/upgrade/downgrade after a first subscription raised a Postgres
-- CheckViolation inside the atomic activation block and the whole payment
-- confirmation 500'd (first-time signups were unaffected — nothing to retire).
DO $$
BEGIN
    ALTER TABLE subscriptions DROP CONSTRAINT IF EXISTS subscriptions_status_check;
    ALTER TABLE subscriptions ADD CONSTRAINT subscriptions_status_check
        CHECK (status IN ('active', 'expired', 'cancelled', 'pending', 'replaced'));
END $$;

-- Only one row may be 'active' per user at a time — backstops the retire-then-
-- create logic in billing/services.py:_activate() at the database level (that
-- logic already runs inside select_for_update(), but a future bug, direct DB
-- write, or an intent confirmed via two different code paths without locking
-- should not be able to leave two simultaneously-active subscriptions).
CREATE UNIQUE INDEX IF NOT EXISTS uq_subscriptions_one_active_per_user
    ON subscriptions(user_id) WHERE status = 'active';

-- ── Positive-amount guards ───────────────────────────────────────────────────
-- App-level checks already reject <= 0 amounts on the modern write paths
-- (farmers/services.py:money(), tax/serializers.py) but nothing stopped a
-- negative/zero amount reaching these tables via any other path (the legacy
-- expenses/workers/feed apps, a direct admin edit, a future bug). Belt-and-
-- suspenders at the column level, matching the CHECK-constraint style already
-- used elsewhere in this schema.
DO $$
BEGIN
    ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_amount_positive_check;
    ALTER TABLE payments ADD CONSTRAINT payments_amount_positive_check
        CHECK (amount > 0);
END $$;

DO $$
BEGIN
    ALTER TABLE expenses DROP CONSTRAINT IF EXISTS expenses_amount_positive_check;
    ALTER TABLE expenses ADD CONSTRAINT expenses_amount_positive_check
        CHECK (amount > 0);
END $$;

DO $$
BEGIN
    ALTER TABLE revenues DROP CONSTRAINT IF EXISTS revenues_amount_positive_check;
    ALTER TABLE revenues ADD CONSTRAINT revenues_amount_positive_check
        CHECK (amount > 0);
END $$;

DO $$
BEGIN
    ALTER TABLE loans DROP CONSTRAINT IF EXISTS loans_amount_positive_check;
    ALTER TABLE loans ADD CONSTRAINT loans_amount_positive_check
        CHECK (loan_amount > 0);
END $$;

-- ── backend_admin_records: owner_id lookups ─────────────────────────────────
-- pharmacy/views.py and the admin pharmacy-oversight endpoints filter this JSON
-- "bridge" table on payload->>'owner_id' within a module constantly; the only
-- existing index is on the low-cardinality `module` column, so every such
-- lookup falls back to a JSON scan of every row in that module.
CREATE INDEX IF NOT EXISTS idx_backend_admin_records_owner
    ON backend_admin_records ((payload ->> 'owner_id'));

-- ── Pass 2 (2026-09-14): admin-list pagination + ordering indexes ──────────
-- api/admin_views.py's admin oversight lists (users, doctors, pharmacies,
-- team, researchers, riders, articles/research-papers/etc., subscriptions)
-- now paginate with LIMIT/OFFSET and order by `-created_at` (see
-- PERFORMANCE_BASELINE.md PC2) — these tables had no index at all on
-- `created_at`, so every paginated page still required a full sort of the
-- whole table before the LIMIT/OFFSET could apply.
CREATE INDEX IF NOT EXISTS idx_users_created_at ON users(created_at);
CREATE INDEX IF NOT EXISTS idx_doctor_profiles_created ON doctor_profiles(created_at);
CREATE INDEX IF NOT EXISTS idx_researcher_profiles_created ON researcher_profiles(created_at);
CREATE INDEX IF NOT EXISTS idx_delivery_profiles_created ON delivery_profiles(created_at);
CREATE INDEX IF NOT EXISTS idx_articles_created ON articles(created_at);
CREATE INDEX IF NOT EXISTS idx_subscriptions_created ON subscriptions(created_at);
CREATE INDEX IF NOT EXISTS idx_reports_created ON reports(created_at);
CREATE INDEX IF NOT EXISTS idx_consultation_disputes_created ON consultation_disputes(created_at);
-- consultations already has idx_consultations_date (appointment_date); the
-- admin list additionally orders by appointment_time as a tiebreaker.
CREATE INDEX IF NOT EXISTS idx_consultations_appointment_time ON consultations(appointment_time);
-- The delivery-queue / pharmacy-orders / pharmacy-products "bridge" table
-- (backend_admin_records) is always filtered by module and ordered by
-- created_at together — a composite index serves that access pattern
-- directly instead of the query planner combining two single-column ones.
CREATE INDEX IF NOT EXISTS idx_backend_admin_records_module_created
    ON backend_admin_records(module, created_at DESC);

-- ── Pass 3 (2026-09-20): delivery_profiles live-location columns ───────────
-- A database created from a `featherflow_schema.sql` snapshot older than the
-- one currently in the repo never got `current_lat`/`current_lng`/
-- `location_updated_at` on `delivery_profiles` — the current base schema's
-- `CREATE TABLE delivery_profiles` already includes them (they're not new),
-- but unlike every other schema addition since, this one had no matching
-- `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` here to bring an
-- already-created database up to date. That silently broke
-- `GET /api/me/updates/` (api/admin_extra.py::_me_updates_payload) for
-- *every* account that isn't a researcher or doctor — it walks
-- researcher_profile -> doctor_profile -> delivery_profile ->
-- pharmacy_organization looking for the caller's profile, and the query
-- against `delivery_profiles` 500'd before it could even determine the row
-- doesn't exist for that user, since Django builds the SELECT from the
-- model's full column list regardless. `/api/me/updates/` backs
-- `UserUpdatesService`, which `refreshListenable`s the top-level router
-- redirect on every app — so this could 500 on navigation for any
-- farmer/pharmacy/delivery/admin account.
ALTER TABLE delivery_profiles ADD COLUMN IF NOT EXISTS current_lat DECIMAL(9,6);
ALTER TABLE delivery_profiles ADD COLUMN IF NOT EXISTS current_lng DECIMAL(9,6);
ALTER TABLE delivery_profiles ADD COLUMN IF NOT EXISTS location_updated_at TIMESTAMP;
