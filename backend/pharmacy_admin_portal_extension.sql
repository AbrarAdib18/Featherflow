-- Pharmacy Admin Portal — additive schema ---------------------------------
--
-- Builds the control/approval layer described in PHARMACY_ADMIN_AUDIT.md on
-- top of the existing pharmacy_organizations / pharmacy_catalogue_medicines /
-- conversations tables, without touching their existing columns or any other
-- role's data. Every statement here is idempotent (IF NOT EXISTS / re-runnable
-- UPDATEs) so this file can be applied more than once safely.

-- ── 1. Pharmacy account review state ───────────────────────────────────────
-- account_status ('pending'/'active'/'suspended') stays untouched (shared by
-- every role). review_state is pharmacy-specific and carries the richer
-- lifecycle (pending_review / needs_more_information / approved / rejected /
-- closed) that pharmacy_lifecycle_status() in pharmacy/services.py derives
-- the spec's 8-state vocabulary from.
ALTER TABLE pharmacy_organizations
    ADD COLUMN IF NOT EXISTS review_state VARCHAR(30) DEFAULT 'approved';

COMMENT ON COLUMN pharmacy_organizations.review_state IS
    'pending_review | needs_more_information | approved | rejected | closed. '
    'Defaults to approved so existing live pharmacies are never retroactively '
    'locked by this column''s introduction.';

-- Backfill: only pharmacies that are genuinely mid-onboarding today (pending
-- account + never verified) start in pending_review. Anything already active
-- or previously verified keeps review_state='approved' from the DEFAULT above.
UPDATE pharmacy_organizations po
SET review_state = 'pending_review'
FROM users u
WHERE po.user_id = u.id
  AND u.account_status = 'pending'
  AND COALESCE(po.is_verified, FALSE) IS FALSE;

-- ── 2. Employee roster (headcount only — no login credentials) ─────────────
CREATE TABLE IF NOT EXISTS pharmacy_employees (
    id UUID PRIMARY KEY,
    pharmacy_user_id UUID NOT NULL REFERENCES users(id),
    name TEXT NOT NULL,
    role_title TEXT NOT NULL DEFAULT '',
    phone VARCHAR(30) NOT NULL DEFAULT '',
    email VARCHAR(255) NOT NULL DEFAULT '',
    license_number TEXT,
    access_level VARCHAR(20) NOT NULL DEFAULT 'staff',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    added_by_id UUID REFERENCES users(id),
    added_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_pharmacy_employees_pharmacy
    ON pharmacy_employees(pharmacy_user_id);

COMMENT ON TABLE pharmacy_employees IS
    'Roster/count only, not real login accounts — employees act under the '
    'owner''s account. Distinct from the declared number_of_pharmacists '
    'captured at signup, which stays a static onboarding figure.';

-- ── 3. Sales & commission (exactly-once per delivered order) ───────────────
CREATE TABLE IF NOT EXISTS pharmacy_sales (
    id UUID PRIMARY KEY,
    order_reference TEXT NOT NULL,
    pharmacy_user_id UUID NOT NULL REFERENCES users(id),
    gross_amount NUMERIC(12, 2) NOT NULL DEFAULT 0,
    status VARCHAR(20) NOT NULL DEFAULT 'completed',
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_pharmacy_sales_order_reference
    ON pharmacy_sales(order_reference);
CREATE INDEX IF NOT EXISTS idx_pharmacy_sales_pharmacy
    ON pharmacy_sales(pharmacy_user_id, status);

COMMENT ON COLUMN pharmacy_sales.order_reference IS
    'The pharmacy-orders AdminPanelRecord id this sale was created from. '
    'Unique — the idempotency guard so a repeated "delivered" status update '
    'can never create a second sale, mirroring uq_expenses_source_pharmacy_order.';

CREATE TABLE IF NOT EXISTS pharmacy_commissions (
    id UUID PRIMARY KEY,
    sale_id UUID NOT NULL REFERENCES pharmacy_sales(id),
    rate NUMERIC(5, 4) NOT NULL,
    gross_amount NUMERIC(12, 2) NOT NULL,
    commission_amount NUMERIC(12, 2) NOT NULL,
    pharmacy_amount NUMERIC(12, 2) NOT NULL,
    created_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_pharmacy_commissions_sale
    ON pharmacy_commissions(sale_id);

COMMENT ON COLUMN pharmacy_commissions.rate IS
    'The commission rate in effect AT THE TIME of this sale (e.g. 0.2000 for '
    '20%), stored so a later PHARMACY_COMMISSION_RATE change never rewrites '
    'historical commission records.';
COMMENT ON TABLE pharmacy_commissions IS
    'Append-only, like activity_logs. A refund never mutates or deletes a row '
    'here — pharmacy_sales.status flips to refunded instead, and every '
    'aggregate query filters status=completed so refunded sales simply stop '
    'counting going forward.';

-- ── 4. Settlements (periodic payout batches) ────────────────────────────────
CREATE TABLE IF NOT EXISTS pharmacy_settlements (
    id UUID PRIMARY KEY,
    pharmacy_user_id UUID NOT NULL REFERENCES users(id),
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    gross_sales NUMERIC(12, 2) NOT NULL DEFAULT 0,
    commission NUMERIC(12, 2) NOT NULL DEFAULT 0,
    payable_amount NUMERIC(12, 2) NOT NULL DEFAULT 0,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    paid_at TIMESTAMPTZ,
    payment_reference TEXT,
    created_by_id UUID REFERENCES users(id),
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_pharmacy_settlements_pharmacy
    ON pharmacy_settlements(pharmacy_user_id, period_start);

-- ── 5. Appeals ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pharmacy_appeals (
    id UUID PRIMARY KEY,
    pharmacy_user_id UUID NOT NULL REFERENCES users(id),
    suspension_log_id UUID,
    reason TEXT NOT NULL DEFAULT '',
    explanation TEXT NOT NULL DEFAULT '',
    attachments JSONB NOT NULL DEFAULT '[]'::jsonb,
    status VARCHAR(20) NOT NULL DEFAULT 'submitted',
    admin_response TEXT,
    resolved_by_id UUID REFERENCES users(id),
    resolved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_pharmacy_appeals_pharmacy
    ON pharmacy_appeals(pharmacy_user_id, status);

COMMENT ON COLUMN pharmacy_appeals.suspension_log_id IS
    'Best-effort pointer into activity_logs.id for the suspension being '
    'appealed. No FK constraint: activity_logs is a generic, append-only, '
    'cross-module table (audit.ActivityLog) not scoped to any one app.';

-- ── 6. Pharmacy-admin support chat (reuses doctor.Conversation/Message) ────
-- These two columns are only ever set on pharmacy<->admin threads; every
-- doctor-farmer consultation conversation leaves them at their defaults.
ALTER TABLE conversations
    ADD COLUMN IF NOT EXISTS pharmacy_chat_status VARCHAR(20) DEFAULT 'open';
ALTER TABLE conversations
    ADD COLUMN IF NOT EXISTS assigned_admin_id UUID REFERENCES users(id);

COMMENT ON COLUMN conversations.pharmacy_chat_status IS
    'open | waiting_for_pharmacy | waiting_for_admin | resolved | reopened. '
    'Pharmacy-admin support threads only.';
COMMENT ON COLUMN conversations.assigned_admin_id IS
    'Which admin owns this pharmacy support thread. Kept separate from '
    'participant_two so reassigning ownership never rewrites historical '
    'message sender attribution.';

-- ── 7. RBAC — add the actions this build needs ──────────────────────────────
-- The admin_pharmacy DB role already grants create/edit/approve/reject/
-- suspend/delete/export; only "assign" (delivery assignment) and "refund"
-- (order refunds) are new. Re-runnable: uses jsonb_set, not a blind overwrite,
-- so any future manually-added pharmacy permission survives a re-run.
UPDATE roles
SET permissions = jsonb_set(
    permissions, '{pharmacy}',
    to_jsonb(
        ARRAY(SELECT DISTINCT unnest(
            COALESCE(ARRAY(SELECT jsonb_array_elements_text(permissions->'pharmacy')), ARRAY[]::text[])
            || ARRAY['view','create','edit','approve','reject','suspend','delete','export','assign','refund']
        ))
    )
)
WHERE name IN ('admin_pharmacy', 'admin_operations', 'admin')
  AND permissions IS NOT NULL;
