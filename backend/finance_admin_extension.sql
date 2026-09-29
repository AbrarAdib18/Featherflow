-- Finance Admin dashboard/subscriptions/cashout extension.
-- See FINANCE_ADMIN_DASHBOARD_AND_SUBSCRIPTIONS.md and
-- FINANCE_ADMIN_CASHOUT_WORKFLOW.md for the design this backs.

-- ── revenue ledger ───────────────────────────────────────────────────────────
-- One row per recognized revenue event. Idempotency: at most one row per
-- (source_payment_id, category) — the original recognition and its refund
-- reversal (if any) are two different categories on the same payment, so
-- both can exist, but neither can be duplicated.
CREATE TABLE IF NOT EXISTS revenue_entries (
    id UUID PRIMARY KEY,
    source_payment_id UUID NOT NULL,
    amount DECIMAL(12,2) NOT NULL,
    currency VARCHAR(5) NOT NULL DEFAULT 'BDT',
    category VARCHAR(30) NOT NULL DEFAULT 'subscription',
    recognized_at TIMESTAMP NOT NULL,
    user_id UUID,
    subscription_id UUID,
    plan_id INTEGER,
    created_by UUID,
    created_at TIMESTAMP NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_revenue_entries_payment_category
    ON revenue_entries(source_payment_id, category);
CREATE INDEX IF NOT EXISTS idx_revenue_entries_recognized_at ON revenue_entries(recognized_at);

-- ── cashout review workflow ──────────────────────────────────────────────────
-- One row per cashout-type `payments` row (payment_type='cashout'), extending
-- it with the finance review state machine rather than duplicating the
-- amount/currency/requester fields that already live on `payments`.
CREATE TABLE IF NOT EXISTS cashout_reviews (
    id UUID PRIMARY KEY,
    payment_id UUID NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'requested',
    requested_at TIMESTAMP NOT NULL DEFAULT now(),
    reviewed_by UUID,
    reviewed_at TIMESTAMP,
    rejection_reason TEXT,
    notes TEXT,
    settled_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    updated_at TIMESTAMP NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_cashout_reviews_payment ON cashout_reviews(payment_id);
CREATE INDEX IF NOT EXISTS idx_cashout_reviews_status ON cashout_reviews(status);

-- ── subscription_plans: audit trail needs an updated_at ──────────────────────
ALTER TABLE subscription_plans ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP;

-- ── Finance Admin RBAC correction ────────────────────────────────────────────
-- Removes 'users' (user-list read access) and 'approvals' (the generic
-- operational approval queue — farmer/doctor/pharmacy/delivery/researcher
-- verification) entirely. Adds a dedicated 'cashouts' module and
-- 'manage' action on 'subscriptions' for plan management.
-- See FINANCE_ADMIN_RBAC_CHANGES.md.
UPDATE roles SET permissions = '{
  "finance": ["view","edit","refund","export","approve"],
  "subscriptions": ["view","edit","approve","refund","export","manage"],
  "cashouts": ["view","review","approve","reject"],
  "audit": ["view"]
}'::jsonb WHERE name = 'admin_finance';
