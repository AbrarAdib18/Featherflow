-- ════════════════════════════════════════════════════════════════════════════
-- Farmer / User Panel — Pass 1 (gap closure)
--
-- Additive and safe to rerun. Apply once on a database that already has
-- featherflow_schema.sql + postgres_backend_extension.sql.
--
--   psql "$DATABASE_URL" -f backend/farmers_panel_extension.sql
--
-- Covers: Cost Management (expense/revenue receipts, loan application flow,
-- cashout + expense payments through the payments table), batch cost tracking
-- (already has expenses.flock_id / revenues.flock_id), feed consumption
-- (feed_consumption already exists in the base schema).
-- ════════════════════════════════════════════════════════════════════════════

-- ── payments.payment_type: allow farm-finance movements ────────────────────
-- The base CHECK only knows subscription / consultation / medicine_order /
-- delivery_fee / loan_repayment. Cost Management records expense settlements,
-- revenue receipts and wallet cashouts here too (Pass 1 = pending row only,
-- no gateway).
DO $$
BEGIN
    ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_payment_type_check;
    ALTER TABLE payments ADD CONSTRAINT payments_payment_type_check
        CHECK (payment_type IN (
            'subscription', 'consultation', 'medicine_order', 'delivery_fee',
            'loan_repayment', 'expense_payment', 'revenue_receipt', 'cashout'
        ));
END $$;

-- Pass 1 cashouts have no gateway, so payment_method may be unset until the
-- finance admin settles them.
DO $$
BEGIN
    ALTER TABLE payments ALTER COLUMN payment_method DROP NOT NULL;
EXCEPTION WHEN others THEN NULL;
END $$;

-- ── loans: farmer "Get Loan" application workflow ──────────────────────────
-- A farmer submits a request (status='pending'); an admin approves/rejects it
-- from the admin panel. Approved loans become 'active'.
ALTER TABLE loans
    ADD COLUMN IF NOT EXISTS purpose            TEXT,
    ADD COLUMN IF NOT EXISTS term_months        INT,
    ADD COLUMN IF NOT EXISTS requested_by       UUID REFERENCES users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS decided_by         UUID REFERENCES users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS decided_at         TIMESTAMP,
    ADD COLUMN IF NOT EXISTS rejection_reason   TEXT;

DO $$
BEGIN
    ALTER TABLE loans DROP CONSTRAINT IF EXISTS loans_status_check;
    ALTER TABLE loans ADD CONSTRAINT loans_status_check
        CHECK (status IN ('pending', 'active', 'paid', 'overdue', 'rejected'));
END $$;

-- A pending application has no schedule yet.
DO $$
BEGIN
    ALTER TABLE loans ALTER COLUMN interest_rate DROP NOT NULL;
    ALTER TABLE loans ALTER COLUMN start_date    DROP NOT NULL;
    ALTER TABLE loans ALTER COLUMN due_date      DROP NOT NULL;
EXCEPTION WHEN others THEN NULL;
END $$;

-- ── revenues: match the expenses row shape (receipts + payment channel) ────
ALTER TABLE revenues
    ADD COLUMN IF NOT EXISTS payment_method  VARCHAR(50),
    ADD COLUMN IF NOT EXISTS buyer_name      VARCHAR(150),
    ADD COLUMN IF NOT EXISTS receipt_url     TEXT;

-- ── expenses: when a pending bill is settled ──────────────────────────────
ALTER TABLE expenses
    ADD COLUMN IF NOT EXISTS paid_at    TIMESTAMP,
    ADD COLUMN IF NOT EXISTS payment_id UUID REFERENCES payments(id) ON DELETE SET NULL;

-- ── helpful indexes for the farmer dashboard aggregates ───────────────────
CREATE INDEX IF NOT EXISTS idx_expenses_farm_status   ON expenses(farm_id, payment_status);
CREATE INDEX IF NOT EXISTS idx_expenses_farm_category ON expenses(farm_id, category_id);
CREATE INDEX IF NOT EXISTS idx_revenues_farm_source   ON revenues(farm_id, source_id);
CREATE INDEX IF NOT EXISTS idx_expenses_flock         ON expenses(flock_id);
CREATE INDEX IF NOT EXISTS idx_revenues_flock         ON revenues(flock_id);
CREATE INDEX IF NOT EXISTS idx_loans_requested_by     ON loans(requested_by);
CREATE INDEX IF NOT EXISTS idx_payments_ref           ON payments(reference_type, reference_id);

-- ── seed the standard Cost-Management sections (idempotent) ───────────────
INSERT INTO expense_categories (name, linked_module, icon) VALUES
    ('Feed',       'feed',    'grass'),
    ('Medicines',  'pharmacy','medical_services'),
    ('Labor',      'workers', 'people'),
    ('Utilities',  '',        'bolt'),
    ('Chicks',     '',        'egg'),
    ('Vaccines',   '',        'vaccines'),
    ('Litter',     '',        'layers'),
    ('Transport',  '',        'local_shipping'),
    ('Repairs',    '',        'build')
ON CONFLICT (name) DO NOTHING;

INSERT INTO revenue_sources (name) VALUES
    ('Bird Sales'), ('Egg Sales'), ('By-products'), ('Refunds'), ('Other')
ON CONFLICT (name) DO NOTHING;
