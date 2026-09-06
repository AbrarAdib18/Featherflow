-- Apply after featherflow_schema.sql when upgrading an existing PostgreSQL DB.
-- Safe to run repeatedly; it never drops or rewrites existing data.
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS backend_admin_records (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    module      VARCHAR(40) NOT NULL,
    record_id   VARCHAR(80) NOT NULL,
    payload     JSONB       NOT NULL DEFAULT '{}'::jsonb,
    created_at  TIMESTAMP   NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMP   NOT NULL DEFAULT NOW(),
    CONSTRAINT unique_backend_admin_record UNIQUE (module, record_id)
);

CREATE INDEX IF NOT EXISTS idx_backend_admin_records_module
    ON backend_admin_records(module);

CREATE OR REPLACE FUNCTION fn_backend_admin_records_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_backend_admin_records_updated_at ON backend_admin_records;
CREATE TRIGGER trg_backend_admin_records_updated_at
    BEFORE UPDATE ON backend_admin_records
    FOR EACH ROW EXECUTE FUNCTION fn_backend_admin_records_updated_at();

-- Researchers Panel backend integration: articles gained co_authors (free-text
-- co-author list, Pass 1), content_details (type-specific fields for
-- disease_study/innovation posts), review_notes (admin feedback shown to the
-- author), and is_featured (admin-curated portal highlight).
ALTER TABLE articles ADD COLUMN IF NOT EXISTS co_authors JSONB DEFAULT '[]';
ALTER TABLE articles ADD COLUMN IF NOT EXISTS content_details JSONB DEFAULT '{}';
ALTER TABLE articles ADD COLUMN IF NOT EXISTS review_notes TEXT;
ALTER TABLE articles ADD COLUMN IF NOT EXISTS is_featured BOOLEAN DEFAULT FALSE;

-- Researchers Panel hardening pass: tags, version history, profile-change
-- applications, and extending "reports" to cover article content.
CREATE TABLE IF NOT EXISTS research_tags (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name        VARCHAR(100) NOT NULL,
    slug        VARCHAR(120) NOT NULL UNIQUE,
    category    VARCHAR(20) NOT NULL CHECK (category IN (
                            'disease','breed','age_group','nutrition',
                            'research_field','market','other'
                        )),
    created_at  TIMESTAMP   DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS article_tags (
    article_id  UUID        NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
    tag_id      UUID        NOT NULL REFERENCES research_tags(id) ON DELETE CASCADE,
    PRIMARY KEY (article_id, tag_id)
);

CREATE TABLE IF NOT EXISTS article_version_snapshots (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    article_id  UUID        NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
    version     INT         NOT NULL,
    snapshot    JSONB       NOT NULL DEFAULT '{}',
    changed_by  UUID        REFERENCES users(id) ON DELETE SET NULL,
    change_note VARCHAR(200),
    changed_at  TIMESTAMP   DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS profile_change_applications (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    field_name  VARCHAR(60) NOT NULL,
    old_value   TEXT,
    new_value   TEXT        NOT NULL,
    reason      TEXT        NOT NULL,
    status      VARCHAR(15) DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
    reviewed_by UUID        REFERENCES users(id) ON DELETE SET NULL,
    review_note TEXT,
    decided_at  TIMESTAMP,
    created_at  TIMESTAMP   DEFAULT NOW(),
    updated_at  TIMESTAMP   DEFAULT NOW()
);

DROP TRIGGER IF EXISTS trg_profile_change_applications_updated_at ON profile_change_applications;
CREATE TRIGGER trg_profile_change_applications_updated_at
    BEFORE UPDATE ON profile_change_applications
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE INDEX IF NOT EXISTS idx_article_tags_tag ON article_tags(tag_id);
CREATE INDEX IF NOT EXISTS idx_research_tags_category ON research_tags(category);
CREATE INDEX IF NOT EXISTS idx_article_versions_article ON article_version_snapshots(article_id);
CREATE INDEX IF NOT EXISTS idx_profile_change_apps_user ON profile_change_applications(user_id);
CREATE INDEX IF NOT EXISTS idx_profile_change_apps_status ON profile_change_applications(status);

DO $$
BEGIN
    ALTER TABLE reports DROP CONSTRAINT IF EXISTS reports_target_type_check;
    ALTER TABLE reports ADD CONSTRAINT reports_target_type_check
        CHECK (target_type IN ('post','comment','user','article'));
EXCEPTION WHEN undefined_table THEN
    NULL;
END $$;

-- ════════════════════════════════════════════════════════════════════════════
-- Admin Panel — RBAC hierarchy, immutable audit, approval queue, support desk,
-- and polling ("changes since") indexes. Safe to run repeatedly.
-- ════════════════════════════════════════════════════════════════════════════

-- ── roles: carry a permission matrix + tier so RBAC has one source of truth ──
ALTER TABLE roles ADD COLUMN IF NOT EXISTS permissions JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE roles ADD COLUMN IF NOT EXISTS tier_level SMALLINT;
ALTER TABLE roles ADD COLUMN IF NOT EXISTS is_system BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE roles ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT NOW();

INSERT INTO roles (name, panel_type, description) VALUES
    ('admin_doctor', 'admin', 'Doctor Admin — verifies vets, manages consultation disputes and response times'),
    ('admin_team',   'admin', 'Team Admin — manages internal FeatherFlow staff (role changes need Super Admin approval)')
ON CONFLICT (name) DO NOTHING;

-- Tier levels: 1 Super, 2 Operations, 3 module admins, 4 support.
UPDATE roles SET tier_level = 1, is_system = TRUE,
    permissions = '{"*": ["*"]}'::jsonb
    WHERE name = 'admin_super';

UPDATE roles SET tier_level = 2, is_system = TRUE, permissions = '{
    "users": ["view","edit","approve","suspend","export"],
    "doctors": ["view","edit","approve","reject","suspend","export"],
    "delivery": ["view","edit","approve","reject","assign","export"],
    "pharmacy": ["view","edit","approve","reject","suspend","export"],
    "research": ["view","approve","reject"],
    "articles": ["view","approve","reject"],
    "community": ["view","edit","reject","suspend","delete"],
    "subscriptions": ["view","export"],
    "finance": ["view","export"],
    "support": ["view","edit","assign","approve"],
    "team": ["view"],
    "audit": ["view","export"],
    "approvals": ["view","approve","reject"],
    "escalations": ["view","approve"],
    "oversight": ["view"],
    "settings": ["view"]
}'::jsonb WHERE name IN ('admin_operations', 'admin');

UPDATE roles SET tier_level = 3, is_system = TRUE, permissions = '{
    "finance": ["view","edit","refund","export","approve"],
    "subscriptions": ["view","edit","approve","refund","export"],
    "users": ["view"],
    "audit": ["view"],
    "approvals": ["view"]
}'::jsonb WHERE name = 'admin_finance';

UPDATE roles SET tier_level = 3, is_system = TRUE, permissions = '{
    "articles": ["view","create","edit","approve","reject","delete"],
    "community": ["view","edit","reject","suspend","delete"],
    "research": ["view","approve","reject"],
    "audit": ["view"]
}'::jsonb WHERE name = 'admin_content';

UPDATE roles SET tier_level = 3, is_system = TRUE, permissions = '{
    "research": ["view","create","edit","approve","reject","suspend"],
    "articles": ["view","create","edit","approve","reject"],
    "audit": ["view"]
}'::jsonb WHERE name = 'admin_research';

UPDATE roles SET tier_level = 3, is_system = TRUE, permissions = '{
    "delivery": ["view","edit","approve","reject","assign","suspend","export","refund"],
    "audit": ["view"]
}'::jsonb WHERE name = 'admin_delivery';

UPDATE roles SET tier_level = 3, is_system = TRUE, permissions = '{
    "pharmacy": ["view","create","edit","approve","reject","suspend","delete","export"],
    "audit": ["view"]
}'::jsonb WHERE name = 'admin_pharmacy';

UPDATE roles SET tier_level = 3, is_system = TRUE, permissions = '{
    "doctors": ["view","edit","approve","reject","suspend","export"],
    "escalations": ["view"],
    "support": ["view"],
    "audit": ["view"]
}'::jsonb WHERE name = 'admin_doctor';

UPDATE roles SET tier_level = 3, is_system = TRUE, permissions = '{
    "team": ["view","create","edit","assign","suspend"],
    "audit": ["view"],
    "approvals": ["view"]
}'::jsonb WHERE name = 'admin_team';

UPDATE roles SET tier_level = 4, is_system = TRUE, permissions = '{
    "support": ["view","create","edit","assign"],
    "users": ["view"],
    "doctors": ["view"],
    "community": ["view"],
    "escalations": ["view","create"],
    "audit": ["view"]
}'::jsonb WHERE name = 'admin_support';

-- ── admin_profiles: account lifecycle + approval workflow ────────────────────
ALTER TABLE admin_profiles ADD COLUMN IF NOT EXISTS admin_role_id INT REFERENCES roles(id) ON DELETE SET NULL;
ALTER TABLE admin_profiles ADD COLUMN IF NOT EXISTS access_level_requested VARCHAR(30);
ALTER TABLE admin_profiles ADD COLUMN IF NOT EXISTS prior_admin_operations_experience TEXT;
ALTER TABLE admin_profiles ADD COLUMN IF NOT EXISTS internal_approval_by_founder_hr BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE admin_profiles ADD COLUMN IF NOT EXISTS strong_password_2fa_enabled BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE admin_profiles ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE admin_profiles ADD COLUMN IF NOT EXISTS is_suspended BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE admin_profiles ADD COLUMN IF NOT EXISTS suspended_at TIMESTAMP;
ALTER TABLE admin_profiles ADD COLUMN IF NOT EXISTS suspended_by UUID REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE admin_profiles ADD COLUMN IF NOT EXISTS approval_status VARCHAR(15) NOT NULL DEFAULT 'approved';

DO $$
BEGIN
    ALTER TABLE admin_profiles DROP CONSTRAINT IF EXISTS admin_profiles_approval_status_check;
    ALTER TABLE admin_profiles ADD CONSTRAINT admin_profiles_approval_status_check
        CHECK (approval_status IN ('pending','approved','rejected'));
    ALTER TABLE admin_profiles DROP CONSTRAINT IF EXISTS admin_profiles_admin_sub_role_check;
    ALTER TABLE admin_profiles ADD CONSTRAINT admin_profiles_admin_sub_role_check
        CHECK (admin_sub_role IN ('super','operations','finance','content','research',
                                  'delivery','pharmacy','support','doctor','team'));
END $$;

DROP TRIGGER IF EXISTS trg_admin_profiles_updated_at ON admin_profiles;
CREATE TRIGGER trg_admin_profiles_updated_at
    BEFORE UPDATE ON admin_profiles
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── activity_logs: richer + immutable ──────────────────────────────────────
ALTER TABLE activity_logs ADD COLUMN IF NOT EXISTS action_type VARCHAR(20);
ALTER TABLE activity_logs ADD COLUMN IF NOT EXISTS reason TEXT;
ALTER TABLE activity_logs ADD COLUMN IF NOT EXISTS user_agent TEXT;
ALTER TABLE activity_logs ADD COLUMN IF NOT EXISTS request_id UUID;

CREATE OR REPLACE FUNCTION fn_activity_logs_immutable()
RETURNS TRIGGER AS $$
BEGIN
    -- Allow ONLY the FK "ON DELETE SET NULL" cascade (user_id -> NULL) while the
    -- recorded facts stay byte-identical; every other UPDATE and every DELETE is
    -- rejected — the trail is append-only.
    IF TG_OP = 'UPDATE'
       AND OLD.user_id IS NOT NULL AND NEW.user_id IS NULL
       AND NEW.action IS NOT DISTINCT FROM OLD.action
       AND NEW.action_type IS NOT DISTINCT FROM OLD.action_type
       AND NEW.module IS NOT DISTINCT FROM OLD.module
       AND NEW.target_id IS NOT DISTINCT FROM OLD.target_id
       AND NEW.old_value IS NOT DISTINCT FROM OLD.old_value
       AND NEW.new_value IS NOT DISTINCT FROM OLD.new_value
       AND NEW.reason IS NOT DISTINCT FROM OLD.reason
       AND NEW.created_at IS NOT DISTINCT FROM OLD.created_at
    THEN
        RETURN NEW;
    END IF;
    RAISE EXCEPTION 'activity_logs is append-only; % on row % is not permitted', TG_OP, OLD.id;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_activity_logs_immutable ON activity_logs;
CREATE TRIGGER trg_activity_logs_immutable
    BEFORE UPDATE OR DELETE ON activity_logs
    FOR EACH ROW EXECUTE FUNCTION fn_activity_logs_immutable();

CREATE INDEX IF NOT EXISTS idx_activity_logs_created  ON activity_logs(created_at);
CREATE INDEX IF NOT EXISTS idx_activity_logs_user     ON activity_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_activity_logs_module   ON activity_logs(module);
CREATE INDEX IF NOT EXISTS idx_activity_logs_target   ON activity_logs(target_id);

-- ── admin_approval_queue: sensitive actions await a higher tier ─────────────
CREATE TABLE IF NOT EXISTS admin_approval_queue (
    id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    requested_by     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    approved_by      UUID        REFERENCES users(id) ON DELETE SET NULL,
    action_type      VARCHAR(20) NOT NULL,
    module_affected  VARCHAR(40) NOT NULL,
    target_id        UUID,
    target_type      VARCHAR(50),
    request_data     JSONB       NOT NULL DEFAULT '{}'::jsonb,
    status           VARCHAR(15) NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending','approved','rejected','overridden','cancelled')),
    required_tier    SMALLINT    NOT NULL DEFAULT 2,
    reason           TEXT,
    rejection_reason TEXT,
    result_ref_id    UUID,
    created_at       TIMESTAMP   DEFAULT NOW(),
    decided_at       TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_admin_approval_queue_status  ON admin_approval_queue(status);
CREATE INDEX IF NOT EXISTS idx_admin_approval_queue_req     ON admin_approval_queue(requested_by);
CREATE INDEX IF NOT EXISTS idx_admin_approval_queue_created ON admin_approval_queue(created_at);

-- ── admin_escalations: issues module admins push up to Operations/Super ─────
CREATE TABLE IF NOT EXISTS admin_escalations (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    raised_by    UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    assigned_to  UUID        REFERENCES users(id) ON DELETE SET NULL,
    module       VARCHAR(40) NOT NULL,
    target_id    UUID,
    target_type  VARCHAR(50),
    priority     VARCHAR(10) NOT NULL DEFAULT 'medium'
                 CHECK (priority IN ('low','medium','high','critical')),
    subject      VARCHAR(200) NOT NULL,
    detail       TEXT,
    status       VARCHAR(15) NOT NULL DEFAULT 'open'
                 CHECK (status IN ('open','in_progress','resolved')),
    resolution   TEXT,
    created_at   TIMESTAMP   DEFAULT NOW(),
    resolved_at  TIMESTAMP,
    resolved_by  UUID        REFERENCES users(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_admin_escalations_status ON admin_escalations(status);
CREATE INDEX IF NOT EXISTS idx_admin_escalations_created ON admin_escalations(created_at);

-- ── support_tickets: real support-desk entity (replaces JSON seed rows) ─────
CREATE TABLE IF NOT EXISTS support_tickets (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_number  VARCHAR(20) NOT NULL UNIQUE,
    raised_by      UUID        REFERENCES users(id) ON DELETE SET NULL,
    raised_by_name VARCHAR(150),
    assigned_to    UUID        REFERENCES users(id) ON DELETE SET NULL,
    category       VARCHAR(40) NOT NULL DEFAULT 'general',
    subject        VARCHAR(200) NOT NULL,
    description    TEXT,
    priority       VARCHAR(10) NOT NULL DEFAULT 'medium'
                   CHECK (priority IN ('low','medium','high','critical')),
    status         VARCHAR(15) NOT NULL DEFAULT 'open'
                   CHECK (status IN ('open','in_progress','escalated','resolved','closed')),
    is_escalated   BOOLEAN     NOT NULL DEFAULT FALSE,
    escalation_id  UUID        REFERENCES admin_escalations(id) ON DELETE SET NULL,
    resolution     TEXT,
    created_at     TIMESTAMP   DEFAULT NOW(),
    updated_at     TIMESTAMP   DEFAULT NOW(),
    resolved_at    TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_support_tickets_status  ON support_tickets(status);
CREATE INDEX IF NOT EXISTS idx_support_tickets_updated ON support_tickets(updated_at);
CREATE INDEX IF NOT EXISTS idx_support_tickets_assigned ON support_tickets(assigned_to);

DROP TRIGGER IF EXISTS trg_support_tickets_updated_at ON support_tickets;
CREATE TRIGGER trg_support_tickets_updated_at
    BEFORE UPDATE ON support_tickets
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TABLE IF NOT EXISTS support_ticket_replies (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id   UUID        NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
    author_id   UUID        REFERENCES users(id) ON DELETE SET NULL,
    author_role VARCHAR(30),
    body        TEXT        NOT NULL,
    is_internal BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMP   DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_support_ticket_replies_ticket ON support_ticket_replies(ticket_id);

-- ── polling: "what changed since <ts>" indexes for the user-facing tables ───
CREATE INDEX IF NOT EXISTS idx_researcher_profiles_updated   ON researcher_profiles(updated_at);
CREATE INDEX IF NOT EXISTS idx_doctor_profiles_updated       ON doctor_profiles(updated_at);
CREATE INDEX IF NOT EXISTS idx_delivery_profiles_updated     ON delivery_profiles(updated_at);
CREATE INDEX IF NOT EXISTS idx_pharmacy_organizations_updated ON pharmacy_organizations(updated_at);
CREATE INDEX IF NOT EXISTS idx_pharmacy_medicines_updated    ON pharmacy_medicines(updated_at);
CREATE INDEX IF NOT EXISTS idx_articles_updated              ON articles(updated_at);
CREATE INDEX IF NOT EXISTS idx_delivery_orders_assigned      ON delivery_orders(assigned_at);
CREATE INDEX IF NOT EXISTS idx_notifications_user_created    ON notifications(user_id, created_at);

-- ── seed the two founding admin roles onto the existing admin_profiles rows ──
UPDATE admin_profiles ap SET admin_role_id = r.id
FROM user_roles ur JOIN roles r ON r.id = ur.role_id AND r.panel_type = 'admin'
WHERE ur.user_id = ap.user_id AND ap.admin_role_id IS NULL;

-- ════════════════════════════════════════════════════════════════════════════
-- Admin Shift Timer + Hourly Payment
--  * weekly (Mon–Sun) periods, manual payroll generation
--  * unpaid breaks; midnight-spanning shifts split across both calendar days
--    (done in the query layer via overlap maths, not stored)
--  * overtime 1.5x for hours beyond admin_profiles.max_hours_per_week
--  * rate changes take effect the following Monday (pending_* columns)
--  * Super Admin (tier 1) is the owner — no shift, no payment
-- ════════════════════════════════════════════════════════════════════════════

ALTER TABLE admin_profiles ADD COLUMN IF NOT EXISTS hourly_rate DECIMAL(10,2) NOT NULL DEFAULT 0;
ALTER TABLE admin_profiles ADD COLUMN IF NOT EXISTS max_hours_per_week INTEGER;
ALTER TABLE admin_profiles ADD COLUMN IF NOT EXISTS last_shift_start TIMESTAMP;
ALTER TABLE admin_profiles ADD COLUMN IF NOT EXISTS pending_hourly_rate DECIMAL(10,2);
ALTER TABLE admin_profiles ADD COLUMN IF NOT EXISTS pending_rate_effective_from DATE;

ALTER TABLE roles ADD COLUMN IF NOT EXISTS hourly_rate_range_min DECIMAL(10,2);
ALTER TABLE roles ADD COLUMN IF NOT EXISTS hourly_rate_range_max DECIMAL(10,2);

-- indicative pay bands per tier (Super Admin excluded — owner)
UPDATE roles SET hourly_rate_range_min = 0,   hourly_rate_range_max = 0    WHERE name = 'admin_super';
UPDATE roles SET hourly_rate_range_min = 400, hourly_rate_range_max = 900  WHERE name = 'admin_operations';
UPDATE roles SET hourly_rate_range_min = 250, hourly_rate_range_max = 600
    WHERE name IN ('admin_finance','admin_content','admin_research','admin_delivery',
                   'admin_pharmacy','admin_doctor','admin_team');
UPDATE roles SET hourly_rate_range_min = 180, hourly_rate_range_max = 400  WHERE name = 'admin_support';

CREATE TABLE IF NOT EXISTS admin_shifts (
    id                     UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id               UUID        NOT NULL REFERENCES admin_profiles(id) ON DELETE CASCADE,
    shift_date             DATE        NOT NULL,
    start_time             TIMESTAMP   NOT NULL,
    end_time               TIMESTAMP,
    break_start            TIMESTAMP,
    break_end              TIMESTAMP,
    break_duration_minutes INTEGER     NOT NULL DEFAULT 0,
    total_hours            DECIMAL(6,2) NOT NULL DEFAULT 0,
    is_active              BOOLEAN     NOT NULL DEFAULT TRUE,
    auto_flagged           BOOLEAN     NOT NULL DEFAULT FALSE,
    ended_by               UUID        REFERENCES users(id) ON DELETE SET NULL,
    ip_address             VARCHAR(45),
    created_at             TIMESTAMP   DEFAULT NOW(),
    updated_at             TIMESTAMP   DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_admin_shifts_admin_date ON admin_shifts(admin_id, shift_date);
CREATE INDEX IF NOT EXISTS idx_admin_shifts_active     ON admin_shifts(is_active);
CREATE INDEX IF NOT EXISTS idx_admin_shifts_start      ON admin_shifts(start_time);
CREATE UNIQUE INDEX IF NOT EXISTS uq_admin_shifts_one_active
    ON admin_shifts(admin_id) WHERE is_active;

DROP TRIGGER IF EXISTS trg_admin_shifts_updated_at ON admin_shifts;
CREATE TRIGGER trg_admin_shifts_updated_at
    BEFORE UPDATE ON admin_shifts
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TABLE IF NOT EXISTS admin_payments (
    id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id          UUID        NOT NULL REFERENCES admin_profiles(id) ON DELETE CASCADE,
    period_start      DATE        NOT NULL,
    period_end        DATE        NOT NULL,
    total_hours       DECIMAL(7,2) NOT NULL DEFAULT 0,
    regular_hours     DECIMAL(7,2) NOT NULL DEFAULT 0,
    overtime_hours    DECIMAL(7,2) NOT NULL DEFAULT 0,
    hourly_rate       DECIMAL(10,2) NOT NULL DEFAULT 0,
    overtime_rate     DECIMAL(10,2) NOT NULL DEFAULT 0,
    total_payment     DECIMAL(12,2) NOT NULL DEFAULT 0,
    payment_status    VARCHAR(10)  NOT NULL DEFAULT 'pending'
                      CHECK (payment_status IN ('pending','paid','failed')),
    payment_date      TIMESTAMP,
    payment_method    VARCHAR(20)  CHECK (payment_method IN ('cash','bank_transfer','mobile_wallet')),
    payment_reference TEXT,
    notes             TEXT,
    generated_by      UUID        REFERENCES users(id) ON DELETE SET NULL,
    paid_by           UUID        REFERENCES users(id) ON DELETE SET NULL,
    created_at        TIMESTAMP   DEFAULT NOW(),
    updated_at        TIMESTAMP   DEFAULT NOW(),
    CONSTRAINT uq_admin_payment_period UNIQUE (admin_id, period_start)
);
CREATE INDEX IF NOT EXISTS idx_admin_payments_admin_period ON admin_payments(admin_id, period_start);
CREATE INDEX IF NOT EXISTS idx_admin_payments_status       ON admin_payments(payment_status);

DROP TRIGGER IF EXISTS trg_admin_payments_updated_at ON admin_payments;
CREATE TRIGGER trg_admin_payments_updated_at
    BEFORE UPDATE ON admin_payments
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ════════════════════════════════════════════════════════════════════════════

INSERT INTO research_tags (name, slug, category) VALUES
('Newcastle Disease',  'newcastle-disease',  'disease'),
('Avian Influenza',    'avian-influenza',    'disease'),
('Coccidiosis',        'coccidiosis',        'disease'),
('Fowl Pox',           'fowl-pox',           'disease'),
('Marek''s Disease',   'mareks-disease',     'disease'),
('Salmonellosis',      'salmonellosis',      'disease'),
('Broiler',            'broiler',            'breed'),
('Layer',              'layer',              'breed'),
('Breeder',            'breeder',            'breed'),
('Backyard/Indigenous','backyard-indigenous','breed'),
('Chick (0-4 weeks)',  'chick-0-4-weeks',    'age_group'),
('Grower (5-20 weeks)','grower-5-20-weeks',  'age_group'),
('Layer/Adult',        'layer-adult',        'age_group'),
('Feed Formulation',   'feed-formulation',   'nutrition'),
('Feed Conversion Ratio','feed-conversion-ratio','nutrition'),
('Supplements',        'supplements',        'nutrition'),
('Vaccination',        'vaccination',        'research_field'),
('Biosecurity',        'biosecurity',        'research_field'),
('Genetics',           'genetics',           'research_field'),
('Housing & Environment','housing-environment','research_field'),
('Automation',         'automation',         'research_field'),
('Economics',          'economics',          'research_field'),
('Welfare',            'welfare',            'research_field'),
('Feed Prices',        'feed-prices',        'market'),
('Market Trends',      'market-trends',      'market'),
('Other',              'other-research',     'other')
ON CONFLICT (slug) DO NOTHING;

-- ════════════════════════════════════════════════════════════════════════════
-- Pharmacy Panel — real relational catalogue, supplier coordination, and
-- expiry monitoring. Replaces the JSON-backed `pharmacy-products` module in
-- backend_admin_records (kept as a fallback during the transition). Orders stay
-- on the existing `pharmacy-orders` / `delivery-queue` bridge for now.
--
-- Pharmacies are identified by their owning users(id) row, matching the
-- `owner_id` convention already used across pharmacy/views.py and the
-- marketplace — pharmacy users do not all have a pharmacy_organizations row.
-- Safe to run repeatedly.
-- ════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS pharmacy_catalogue_medicines (
    id                        UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    pharmacy_user_id          UUID          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    legacy_record_id          VARCHAR(80),
    name                      TEXT          NOT NULL,
    generic_name              TEXT,
    manufacturer              TEXT          NOT NULL DEFAULT '',
    category                  VARCHAR(20)   NOT NULL DEFAULT 'other'
                              CHECK (category IN ('antibiotic','vaccine','vitamin','antiparasitic',
                                                  'disinfectant','feed_supplement','equipment','other')),
    prescription_required     BOOLEAN       NOT NULL DEFAULT FALSE,
    price                     DECIMAL(10,2) NOT NULL DEFAULT 0,
    stock_quantity            INT           NOT NULL DEFAULT 0,
    unit                      VARCHAR(20)   NOT NULL DEFAULT 'piece'
                              CHECK (unit IN ('tablet','capsule','ml','gram','kg',
                                              'piece','pack','bottle')),
    pack_size                 TEXT          NOT NULL DEFAULT '',
    description               TEXT,
    dosage_instructions       TEXT,
    storage_instructions      TEXT,
    cold_chain_required       BOOLEAN       NOT NULL DEFAULT FALSE,
    expiry_date               DATE          NOT NULL,
    batch_number              TEXT,
    images                    JSONB         NOT NULL DEFAULT '[]'::jsonb,
    is_active                 BOOLEAN       NOT NULL DEFAULT TRUE,
    is_approved               BOOLEAN       NOT NULL DEFAULT FALSE,
    approval_rejected_reason  TEXT,
    views_count               INT           NOT NULL DEFAULT 0,
    orders_count              INT           NOT NULL DEFAULT 0,
    created_at                TIMESTAMP     NOT NULL DEFAULT NOW(),
    updated_at                TIMESTAMP     NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pharmacy_catalogue_pharmacy      ON pharmacy_catalogue_medicines(pharmacy_user_id);
CREATE INDEX IF NOT EXISTS idx_pharmacy_catalogue_category      ON pharmacy_catalogue_medicines(category);
CREATE INDEX IF NOT EXISTS idx_pharmacy_catalogue_active        ON pharmacy_catalogue_medicines(is_active);
CREATE INDEX IF NOT EXISTS idx_pharmacy_catalogue_expiry        ON pharmacy_catalogue_medicines(expiry_date);
CREATE INDEX IF NOT EXISTS idx_pharmacy_catalogue_prescription  ON pharmacy_catalogue_medicines(prescription_required);
CREATE INDEX IF NOT EXISTS idx_pharmacy_catalogue_approved      ON pharmacy_catalogue_medicines(is_approved);
CREATE UNIQUE INDEX IF NOT EXISTS uq_pharmacy_catalogue_legacy
    ON pharmacy_catalogue_medicines(pharmacy_user_id, legacy_record_id)
    WHERE legacy_record_id IS NOT NULL;

DROP TRIGGER IF EXISTS trg_pharmacy_catalogue_medicines_updated_at ON pharmacy_catalogue_medicines;
CREATE TRIGGER trg_pharmacy_catalogue_medicines_updated_at
    BEFORE UPDATE ON pharmacy_catalogue_medicines
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();


CREATE TABLE IF NOT EXISTS pharmacy_suppliers (
    id                UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    pharmacy_user_id  UUID          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    supplier_name     TEXT          NOT NULL,
    contact_person    TEXT          NOT NULL DEFAULT '',
    phone             VARCHAR(30)   NOT NULL DEFAULT '',
    email             VARCHAR(255)  NOT NULL DEFAULT '',
    address           TEXT          NOT NULL DEFAULT '',
    products_supplied TEXT          NOT NULL DEFAULT '',
    payment_terms     TEXT,
    is_active         BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at        TIMESTAMP     NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMP     NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pharmacy_suppliers_pharmacy ON pharmacy_suppliers(pharmacy_user_id);
CREATE INDEX IF NOT EXISTS idx_pharmacy_suppliers_active   ON pharmacy_suppliers(is_active);

DROP TRIGGER IF EXISTS trg_pharmacy_suppliers_updated_at ON pharmacy_suppliers;
CREATE TRIGGER trg_pharmacy_suppliers_updated_at
    BEFORE UPDATE ON pharmacy_suppliers
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();


CREATE TABLE IF NOT EXISTS pharmacy_expiry_alerts (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    pharmacy_user_id UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    medicine_id      UUID         NOT NULL REFERENCES pharmacy_catalogue_medicines(id) ON DELETE CASCADE,
    expires_in_days  INT          NOT NULL,
    alert_level      VARCHAR(10)  NOT NULL CHECK (alert_level IN ('critical','warning','info')),
    is_acknowledged  BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at       TIMESTAMP    NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_pharmacy_expiry_alert_medicine UNIQUE (medicine_id)
);

CREATE INDEX IF NOT EXISTS idx_pharmacy_expiry_alerts_pharmacy ON pharmacy_expiry_alerts(pharmacy_user_id);
CREATE INDEX IF NOT EXISTS idx_pharmacy_expiry_alerts_level    ON pharmacy_expiry_alerts(alert_level);
CREATE INDEX IF NOT EXISTS idx_pharmacy_expiry_alerts_ack      ON pharmacy_expiry_alerts(is_acknowledged);

-- ════════════════════════════════════════════════════════════════════════════
-- Community & Blog — Pass 2. Turns the MODULE 14 tables (posts/comments/
-- reactions/follows/bookmarks/reports/hashtags) into the full X-style social
-- layer from the requirements: questions & polls, reposts, hashtag/mention
-- discovery, engagement-based trending, report-threshold auto-hide, and admin
-- moderation (hide / mute) on real rows instead of the JSON seed modules
-- `community-reports` / `community-users`. Additive and safe to run repeatedly.
-- ════════════════════════════════════════════════════════════════════════════

-- ── posts: post kind, question title, hashtags/mentions, poll payload, and the
--    moderation/trending flags the feed ranks and filters on ──────────────────
ALTER TABLE posts ADD COLUMN IF NOT EXISTS post_type     VARCHAR(10) NOT NULL DEFAULT 'text';
ALTER TABLE posts ADD COLUMN IF NOT EXISTS title         TEXT;
ALTER TABLE posts ADD COLUMN IF NOT EXISTS tags          JSONB       NOT NULL DEFAULT '[]';
ALTER TABLE posts ADD COLUMN IF NOT EXISTS mentions      JSONB       NOT NULL DEFAULT '[]';
ALTER TABLE posts ADD COLUMN IF NOT EXISTS poll_options  JSONB;
ALTER TABLE posts ADD COLUMN IF NOT EXISTS poll_multi    BOOLEAN     NOT NULL DEFAULT FALSE;
ALTER TABLE posts ADD COLUMN IF NOT EXISTS is_trending   BOOLEAN     NOT NULL DEFAULT FALSE;
ALTER TABLE posts ADD COLUMN IF NOT EXISTS hidden_reason TEXT;

DO $$
BEGIN
    ALTER TABLE posts DROP CONSTRAINT IF EXISTS posts_post_type_check;
    ALTER TABLE posts ADD CONSTRAINT posts_post_type_check
        CHECK (post_type IN ('text', 'poll', 'question'));
    -- 'flagged'  = auto-hidden once reports_count reaches the threshold, awaiting review
    -- 'hidden'   = an admin hid it after review
    -- 'removed'  = deleted by the author or an admin
    ALTER TABLE posts DROP CONSTRAINT IF EXISTS posts_status_check;
    ALTER TABLE posts ADD CONSTRAINT posts_status_check
        CHECK (status IN ('active', 'flagged', 'hidden', 'removed'));
EXCEPTION WHEN undefined_table THEN
    NULL;
END $$;

-- ── comments: anonymous replies + admin hide reason; widen the status CHECK ──
ALTER TABLE comments ADD COLUMN IF NOT EXISTS is_anonymous  BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE comments ADD COLUMN IF NOT EXISTS hidden_reason TEXT;

DO $$
BEGIN
    ALTER TABLE comments DROP CONSTRAINT IF EXISTS comments_status_check;
    ALTER TABLE comments ADD CONSTRAINT comments_status_check
        CHECK (status IN ('active', 'flagged', 'hidden', 'removed'));
EXCEPTION WHEN undefined_table THEN
    NULL;
END $$;

-- ── reactions: add 'love' alongside the existing like/helpful/insightful ─────
DO $$
BEGIN
    ALTER TABLE reactions DROP CONSTRAINT IF EXISTS reactions_reaction_type_check;
    ALTER TABLE reactions ADD CONSTRAINT reactions_reaction_type_check
        CHECK (reaction_type IN ('like', 'love', 'helpful', 'insightful'));
EXCEPTION WHEN undefined_table THEN
    NULL;
END $$;

-- ── poll_votes: one ballot per user per poll; option_indexes is a JSON array
--    of chosen positions in posts.poll_options (single- or multi-choice) ──────
CREATE TABLE IF NOT EXISTS poll_votes (
    id             UUID      PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id        UUID      NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    user_id        UUID      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    option_indexes JSONB     NOT NULL DEFAULT '[]',
    created_at     TIMESTAMP DEFAULT NOW(),
    UNIQUE (post_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_poll_votes_post ON poll_votes(post_id);

-- ── post_reposts: X-style repost / share of a post ─────────────────────────
CREATE TABLE IF NOT EXISTS post_reposts (
    id         UUID      PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id    UUID      NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    user_id    UUID      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    comment    TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE (post_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_post_reposts_post ON post_reposts(post_id);
CREATE INDEX IF NOT EXISTS idx_post_reposts_user ON post_reposts(user_id);

-- ── community_mutes: admin silences a member in the community layer without
--    suspending their whole account; expires_at NULL means indefinite ────────
CREATE TABLE IF NOT EXISTS community_mutes (
    id         UUID      PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    muted_by   UUID      REFERENCES users(id) ON DELETE SET NULL,
    reason     TEXT,
    is_active  BOOLEAN   NOT NULL DEFAULT TRUE,
    expires_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_community_mutes_active
    ON community_mutes(user_id) WHERE is_active;

DROP TRIGGER IF EXISTS trg_community_mutes_updated_at ON community_mutes;
CREATE TRIGGER trg_community_mutes_updated_at
    BEFORE UPDATE ON community_mutes
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── user_blocks: a member hides another member's posts & replies from their
--    own view (personal mute/block, distinct from the admin community_mutes) ──
CREATE TABLE IF NOT EXISTS user_blocks (
    id         UUID      PRIMARY KEY DEFAULT gen_random_uuid(),
    blocker_id UUID      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_id UUID      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE (blocker_id, blocked_id),
    CHECK (blocker_id <> blocked_id)
);
CREATE INDEX IF NOT EXISTS idx_user_blocks_blocker ON user_blocks(blocker_id);

-- ── discovery / feed-ranking indexes ──────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_posts_author      ON posts(author_id);
CREATE INDEX IF NOT EXISTS idx_posts_category    ON posts(category_id);
CREATE INDEX IF NOT EXISTS idx_posts_created     ON posts(created_at);
CREATE INDEX IF NOT EXISTS idx_posts_status      ON posts(status);
CREATE INDEX IF NOT EXISTS idx_posts_pinned      ON posts(is_pinned) WHERE is_pinned;
CREATE INDEX IF NOT EXISTS idx_posts_trending    ON posts(is_trending) WHERE is_trending;
CREATE INDEX IF NOT EXISTS idx_posts_tags        ON posts USING GIN (tags);
CREATE INDEX IF NOT EXISTS idx_comments_post     ON comments(post_id);
CREATE INDEX IF NOT EXISTS idx_comments_parent   ON comments(parent_comment_id);
CREATE INDEX IF NOT EXISTS idx_reactions_target  ON reactions(target_id, target_type);
CREATE INDEX IF NOT EXISTS idx_bookmarks_target  ON bookmarks(target_id, target_type);
CREATE INDEX IF NOT EXISTS idx_reports_status    ON reports(status);
CREATE INDEX IF NOT EXISTS idx_reports_target    ON reports(target_id, target_type);
CREATE INDEX IF NOT EXISTS idx_follows_following ON follows(following_id);
