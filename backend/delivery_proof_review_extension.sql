-- ═══════════════════════════════════════════════════════════════════════════
-- Delivery arrival + proof-review workflow (fault F-005)
--
-- Apply ONCE against the connected PostgreSQL database after
-- featherflow_schema.sql and the other *_extension.sql files. Re-running is
-- safe (idempotent):
--
--   psql "$DATABASE_URL" -f backend/delivery_proof_review_extension.sql
--
-- Lifecycle (delivery_orders.status):
--   pending -> accepted -> picked_up -> on_the_way ("out for delivery")
--     -> arrived -> proof_submitted ("proof under review")
--     -> delivered  (ONLY when an admin approves the proof)
--   proof_submitted -> proof_rejected (reason required) -> proof_submitted ...
--   failed / cancelled / rejected unchanged.
--
-- Adds:
--   * 'arrived', 'proof_submitted', 'proof_rejected' to the status CHECK;
--   * delivery_proofs        — every proof a rider ever submitted (the photo
--                              token/URL is kept even after rejection) with the
--                              admin's decision, reason, reviewer and times;
--   * delivery_order_events  — append-only state history of every transition
--                              (who, from, to, when, note) for the audit trail;
--   * feed_admin may approve/reject proofs of feed deliveries
--     (roles.permissions -> "feed-delivery": [..., "approve", "reject"]).
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE delivery_orders DROP CONSTRAINT IF EXISTS delivery_orders_status_check;
ALTER TABLE delivery_orders ADD CONSTRAINT delivery_orders_status_check CHECK (
    status::text = ANY (ARRAY[
        'pending', 'accepted', 'rejected', 'picked_up', 'on_the_way',
        'arrived', 'proof_submitted', 'proof_rejected',
        'delivered', 'failed', 'cancelled'
    ]::text[])
);

CREATE TABLE IF NOT EXISTS delivery_proofs (
    id                UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    delivery_order_id UUID         NOT NULL REFERENCES delivery_orders(id) ON DELETE RESTRICT,
    submitted_by      UUID         NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    attempt           INTEGER      NOT NULL CHECK (attempt >= 1),
    proof_url         TEXT         NOT NULL,
    note              TEXT,
    status            VARCHAR(12)  NOT NULL DEFAULT 'submitted'
                                   CHECK (status IN ('submitted', 'approved', 'rejected')),
    review_reason     TEXT,
    reviewed_by       UUID         REFERENCES users(id) ON DELETE RESTRICT,
    submitted_at      TIMESTAMP    NOT NULL DEFAULT NOW(),
    reviewed_at       TIMESTAMP,
    CONSTRAINT uq_delivery_proof_attempt UNIQUE (delivery_order_id, attempt),
    -- a rejection must carry a reason; a decision must carry its reviewer/time
    CONSTRAINT ck_delivery_proof_review CHECK (
        (status = 'submitted' AND reviewed_by IS NULL AND reviewed_at IS NULL)
        OR (status = 'approved' AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)
        OR (status = 'rejected' AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL
            AND review_reason IS NOT NULL AND length(btrim(review_reason)) > 0)
    )
);
-- at most one proof awaiting review per order
CREATE UNIQUE INDEX IF NOT EXISTS uq_delivery_proof_one_open
    ON delivery_proofs (delivery_order_id) WHERE status = 'submitted';
-- at most one approved proof per order
CREATE UNIQUE INDEX IF NOT EXISTS uq_delivery_proof_one_approved
    ON delivery_proofs (delivery_order_id) WHERE status = 'approved';
CREATE INDEX IF NOT EXISTS idx_delivery_proofs_status ON delivery_proofs (status, submitted_at);

CREATE TABLE IF NOT EXISTS delivery_order_events (
    id                UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    delivery_order_id UUID         NOT NULL REFERENCES delivery_orders(id) ON DELETE RESTRICT,
    from_status       VARCHAR(20),
    to_status         VARCHAR(20)  NOT NULL,
    actor_id          UUID         REFERENCES users(id) ON DELETE SET NULL,
    actor_role        VARCHAR(20),
    note              TEXT,
    created_at        TIMESTAMP    NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_delivery_order_events_order
    ON delivery_order_events (delivery_order_id, created_at);

-- History rows follow their order (the permanent, append-only record of every
-- proof submission and decision is also written to activity_logs).
ALTER TABLE delivery_proofs DROP CONSTRAINT IF EXISTS delivery_proofs_delivery_order_id_fkey;
ALTER TABLE delivery_proofs ADD CONSTRAINT delivery_proofs_delivery_order_id_fkey
    FOREIGN KEY (delivery_order_id) REFERENCES delivery_orders(id) ON DELETE CASCADE;
ALTER TABLE delivery_order_events DROP CONSTRAINT IF EXISTS delivery_order_events_delivery_order_id_fkey;
ALTER TABLE delivery_order_events ADD CONSTRAINT delivery_order_events_delivery_order_id_fkey
    FOREIGN KEY (delivery_order_id) REFERENCES delivery_orders(id) ON DELETE CASCADE;

-- Feed Marketplace Admin reviews proofs of feed deliveries.
UPDATE roles
   SET permissions = jsonb_set(permissions, '{feed-delivery}',
                               '["view", "assign", "approve", "reject"]'::jsonb)
 WHERE name = 'feed_admin';
