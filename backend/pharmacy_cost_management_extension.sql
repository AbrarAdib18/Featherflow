-- Pharmacy order -> expense mirroring, exactly once ---------------------------
--
-- A delivered pharmacy order now mirrors into `expenses` so medicine purchases
-- reach cost management and the dashboard cash balance (previously pharmacy
-- spend was invisible to both, even though the `Medicines` expense category
-- has existed since farmers_panel_extension.sql). Pharmacy orders live on the
-- `pharmacy-orders` AdminPanelRecord JSON bridge, not a payment-intent table,
-- so they need their own idempotency key distinct from source_intent_id
-- (which is reserved for billing_payment_intents / labour payments).
--
-- The partial unique index is the idempotency guard: a repeated status-update
-- call can never create a second mirrored expense for the same order.

ALTER TABLE expenses
    ADD COLUMN IF NOT EXISTS source_pharmacy_order_id TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS uq_expenses_source_pharmacy_order
    ON expenses(source_pharmacy_order_id)
    WHERE source_pharmacy_order_id IS NOT NULL;

COMMENT ON COLUMN expenses.source_pharmacy_order_id IS
    'pharmacy-orders AdminPanelRecord payload id this expense was mirrored '
    'from, on delivery. Unique when set - the exactly-once guard for mirroring.';
