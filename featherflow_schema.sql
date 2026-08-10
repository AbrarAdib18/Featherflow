-- ============================================================
--  ███████╗███████╗ █████╗ ████████╗██╗  ██╗███████╗██████╗
--  ██╔════╝██╔════╝██╔══██╗╚══██╔══╝██║  ██║██╔════╝██╔══██╗
--  █████╗  █████╗  ███████║   ██║   ███████║█████╗  ██████╔╝
--  ██╔══╝  ██╔══╝  ██╔══██║   ██║   ██╔══██║██╔══╝  ██╔══██╗
--  ██║     ███████╗██║  ██║   ██║   ██║  ██║███████╗██║  ██║
--  ╚═╝     ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝
--
--  ███████╗██╗      ██████╗ ██╗    ██╗
--  ██╔════╝██║     ██╔═══██╗██║    ██║
--  █████╗  ██║     ██║   ██║██║ █╗ ██║
--  ██╔══╝  ██║     ██║   ██║██║███╗██║
--  ██║     ███████╗╚██████╔╝╚███╔███╔╝
--  ╚═╝     ╚══════╝ ╚═════╝  ╚══╝╚══╝
-- ============================================================
--  DATABASE  : featherflow
--  ENGINE    : PostgreSQL 15+
--  VERSION   : 2.0.0  (reviewed & corrected)
--  TABLES    : 68
--  MODULES   : 16
--  RELATIONS : 85+ Foreign Key Constraints
--  INDEXES   : 50+ Performance Indexes
-- ============================================================
--
--  BUGS FIXED IN v2.0.0:
--
--  [CRITICAL] payments.user_id was NOT NULL + ON DELETE SET NULL —
--             contradiction removed; NOT NULL dropped so the column
--             can safely become NULL when a user is deleted.
--
--  [CRITICAL] Reserved keywords used as bare column names —
--             PostgreSQL reserves 'date' and 'role'; renamed:
--               worker_attendance.date        → attendance_date
--               feed_consumption.date         → consumed_date
--               expenses.date                 → expense_date
--               revenues.date                 → revenue_date
--               delivery_attendance.date      → attendance_date
--               workers.role                  → job_role
--
--  [STRUCTURAL] Missing updated_at auto-trigger — PostgreSQL does NOT
--               auto-update updated_at on row changes. Added a shared
--               trigger function and applied it to every table that
--               has an updated_at column (24 tables total).
--
--  [STRUCTURAL] Missing explicit ON DELETE behavior on critical FK
--               columns — added ON DELETE RESTRICT explicitly to
--               consultations.farmer_id, consultations.doctor_id,
--               medicine_orders.buyer_id, medicine_orders.pharmacy_id,
--               delivery_orders.delivery_person_id,
--               delivery_earnings.delivery_person_id,
--               expenses.created_by, revenues.created_by,
--               feed_consumption.recorded_by, articles.author_id.
--               Financial/audit records must RESTRICT user deletion.
--
--  [STRUCTURAL] subscriptions.plan_id had no ON DELETE — changed to
--               ON DELETE RESTRICT (cannot delete a plan with active
--               subscriptions).
--
--  [MINOR] feed_stock had updated_at before created_at — corrected.
--
--  [MINOR] Junction tables article_authors, post_hashtags, and
--          role_permissions were missing created_at timestamps — added.
--
-- ============================================================
--
--  TABLE CREATION ORDER (dependency-safe):
--
--  MODULE 01 · Auth & Users             (users, roles, permissions,
--                                        role_permissions, user_roles)
--  MODULE 02 · Subscriptions & Payments (subscription_plans, payments,
--                                        subscriptions, feature_usage)
--  MODULE 03 · Profile Extensions       (farmer_profiles, admin_profiles,
--                                        delivery_profiles,
--                                        delivery_vehicle_details,
--                                        pharmacy_organizations,
--                                        pharmacist_profiles,
--                                        researcher_profiles,
--                                        doctor_profiles)
--  MODULE 04 · Farm Management          (farms, sheds, flocks)
--  MODULE 05 · Labor Management         (workers, worker_attendance,
--                                        worker_tasks, worker_payments)
--  MODULE 06 · Feed Management          (feed_types, feed_stock,
--                                        feed_schedules, feed_consumption)
--  MODULE 07 · Cost Management          (expense_categories, expenses,
--                                        revenue_sources, revenues,
--                                        loans, loan_installments,
--                                        tax_records)
--  MODULE 08 · Disease Detection        (diseases)
--  MODULE 09 · Chatbot                  (chatbot_sessions [partial],
--                                        disease_scans,
--                                        ALTER TABLE circular fix,
--                                        scan_chatbot_advice,
--                                        chatbot_messages)
--  MODULE 10 · Doctor & Consultations   (consultations,
--                                        consultation_case_details,
--                                        consultation_notes,
--                                        prescriptions, follow_ups,
--                                        video_calls)
--  MODULE 11 · Messaging                (conversations, messages)
--  MODULE 12 · Pharmacy & Medicines     (pharmacy_medicines,
--                                        medicine_orders,
--                                        medicine_order_items)
--  MODULE 13 · Delivery                 (delivery_orders,
--                                        delivery_earnings,
--                                        delivery_attendance)
--  MODULE 14 · Community & Blog         (post_categories, posts,
--                                        comments, reactions, hashtags,
--                                        post_hashtags, follows,
--                                        bookmarks, reports)
--  MODULE 15 · Articles & Research      (articles, article_authors)
--  MODULE 16 · Notifications & Audit    (notifications, activity_logs)
--
--  ⚠  CIRCULAR DEPENDENCY:
--     chatbot_sessions.scan_id → disease_scans
--     disease_scans.chatbot_session_id → chatbot_sessions
--     Fix: chatbot_sessions created without scan_id FK first.
--     After disease_scans is created, FK added via ALTER TABLE.
--
-- ============================================================


-- ============================================================
-- PRE-FLIGHT: EXTENSION
-- ============================================================

-- Required for gen_random_uuid() on PostgreSQL 13 and below.
-- PostgreSQL 14+ has gen_random_uuid() built in but this is harmless.
CREATE EXTENSION IF NOT EXISTS "pgcrypto";


-- ============================================================
-- SHARED TRIGGER: auto-update updated_at on every row change
-- ============================================================
-- PostgreSQL does NOT auto-update updated_at unlike MySQL.
-- This single function is reused by a trigger on every table
-- that has an updated_at column.

CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- ============================================================
-- MODULE 01 · AUTH & USERS
-- ============================================================

-- ── TABLE 01: users ──────────────────────────────────────────
-- Base identity table for ALL roles.
-- Shared signup fields (blue-marked in the design doc) live here.
-- Role-specific data lives in the profile extension tables (Module 03).
CREATE TABLE users (
    id                          UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    email                       VARCHAR(255)    NOT NULL UNIQUE,
    phone                       VARCHAR(20)     NOT NULL UNIQUE,
    password_hash               VARCHAR(255)    NOT NULL,
    full_name                   VARCHAR(150)    NOT NULL,
    profile_photo_url           TEXT,
    date_of_birth               DATE            NOT NULL,
    present_address             TEXT            NOT NULL,
    national_id_number          VARCHAR(50)     UNIQUE,
    national_id_photo_url       TEXT,
    government_id_type          VARCHAR(10)     CHECK (government_id_type IN ('nid', 'passport')),
    selfie_verification_url     TEXT,
    preferred_language          VARCHAR(10)     DEFAULT 'en',
    emergency_contact_name      VARCHAR(100),
    emergency_contact_phone     VARCHAR(20),
    two_factor_secret           VARCHAR(100),
    two_factor_enabled          BOOLEAN         DEFAULT FALSE,
    bank_mobile_payment_details JSONB,
    location_service_area       TEXT,
    consent_terms               BOOLEAN         NOT NULL,
    consent_background_check    BOOLEAN,
    account_status              VARCHAR(20)     DEFAULT 'pending'
                                                CHECK (account_status IN ('pending','active','suspended','banned')),
    is_verified                 BOOLEAN         DEFAULT FALSE,
    created_at                  TIMESTAMP       DEFAULT NOW(),
    updated_at                  TIMESTAMP       DEFAULT NOW()
);
CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── TABLE 02: roles ──────────────────────────────────────────
-- Master list of every role on the platform.
-- Covers all six panel types plus all eight admin sub-roles.
CREATE TABLE roles (
    id          SERIAL          PRIMARY KEY,
    name        VARCHAR(50)     NOT NULL UNIQUE,
    panel_type  VARCHAR(20)     CHECK (panel_type IN (
                                    'farmer','doctor','delivery',
                                    'pharmacy','pharmacist','researcher','admin'
                                )),
    description TEXT,
    created_at  TIMESTAMP       DEFAULT NOW()
);

-- ── TABLE 03: permissions ─────────────────────────────────────
-- Every possible platform action — used by RBAC to control access.
CREATE TABLE permissions (
    id          SERIAL          PRIMARY KEY,
    name        VARCHAR(100)    NOT NULL UNIQUE,
    module      VARCHAR(50)     NOT NULL,
    description TEXT
);

-- ── TABLE 04: role_permissions ────────────────────────────────
-- Junction: which role is allowed to perform which action.
-- FIX v2: added created_at timestamp (was missing in v1).
CREATE TABLE role_permissions (
    role_id       INT         NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_id INT         NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    created_at    TIMESTAMP   DEFAULT NOW(),
    PRIMARY KEY (role_id, permission_id)
);

-- ── TABLE 05: user_roles ─────────────────────────────────────
-- Assigns a role to a user. Tracks who approved the assignment.
CREATE TABLE user_roles (
    user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id     INT         NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    assigned_at TIMESTAMP   DEFAULT NOW(),
    assigned_by UUID        REFERENCES users(id) ON DELETE SET NULL,
    PRIMARY KEY (user_id, role_id)
);


-- ============================================================
-- MODULE 02 · SUBSCRIPTIONS & PAYMENTS
-- Created before profiles because some profiles reference payments.
-- ============================================================

-- ── TABLE 06: subscription_plans ─────────────────────────────
-- Available tiers. features_unlocked is a JSONB array of feature keys.
-- disease_scan_limit = NULL means unlimited after purchase.
CREATE TABLE subscription_plans (
    id                  SERIAL          PRIMARY KEY,
    name                VARCHAR(50)     NOT NULL,
    price               DECIMAL(10,2)   NOT NULL,
    currency            VARCHAR(5)      DEFAULT 'BDT',
    duration_days       INT,
    features_unlocked   JSONB           NOT NULL DEFAULT '[]',
    disease_scan_limit  INT,
    is_active           BOOLEAN         DEFAULT TRUE,
    created_at          TIMESTAMP       DEFAULT NOW()
);

-- ── TABLE 07: payments ───────────────────────────────────────
-- Every monetary transaction on the platform.
-- FIX v2: user_id is no longer NOT NULL — it can be set to NULL
--         via ON DELETE SET NULL when a user is deleted (the
--         original file had NOT NULL + ON DELETE SET NULL which
--         is a direct contradiction and would cause a runtime error).
CREATE TABLE payments (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID            REFERENCES users(id) ON DELETE SET NULL,
    amount          DECIMAL(12,2)   NOT NULL,
    currency        VARCHAR(5)      DEFAULT 'BDT',
    payment_method  VARCHAR(20)     CHECK (payment_method IN ('bkash','nagad','bank_transfer','card')),
    payment_type    VARCHAR(30)     CHECK (payment_type IN (
                                        'subscription','consultation','medicine_order',
                                        'delivery_fee','loan_repayment'
                                    )),
    reference_id    UUID,
    reference_type  VARCHAR(50),
    status          VARCHAR(20)     DEFAULT 'pending'
                                    CHECK (status IN ('pending','completed','failed','refunded')),
    transaction_id  VARCHAR(100)    UNIQUE,
    receipt_url     TEXT,
    notes           TEXT,
    created_at      TIMESTAMP       DEFAULT NOW()
);

-- ── TABLE 08: subscriptions ───────────────────────────────────
-- Central subscription record. Every premium feature check queries this.
-- FIX v2: plan_id now has ON DELETE RESTRICT (was missing — deleting a
--         plan with active subscriptions must be blocked).
CREATE TABLE subscriptions (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    plan_id     INT         NOT NULL REFERENCES subscription_plans(id) ON DELETE RESTRICT,
    status      VARCHAR(20) DEFAULT 'pending'
                            CHECK (status IN ('active','expired','cancelled','pending')),
    started_at  TIMESTAMP   NOT NULL,
    expires_at  TIMESTAMP,
    auto_renew  BOOLEAN     DEFAULT FALSE,
    payment_id  UUID        REFERENCES payments(id) ON DELETE SET NULL,
    created_at  TIMESTAMP   DEFAULT NOW()
);

-- ── TABLE 09: feature_usage ───────────────────────────────────
-- Per-user per-feature usage counter.
-- Tracks the 3 free disease scan limit and other gated features.
CREATE TABLE feature_usage (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    feature_name  VARCHAR(50) NOT NULL,
    usage_count   INT         DEFAULT 0,
    limit_count   INT         NOT NULL,
    last_used_at  TIMESTAMP,
    reset_at      TIMESTAMP,
    created_at    TIMESTAMP   DEFAULT NOW(),
    UNIQUE (user_id, feature_name)
);


-- ============================================================
-- MODULE 03 · PROFILE EXTENSIONS
-- Each extends users(id) with role-specific fields.
-- Shared base fields (blue-marked in design doc) are NOT repeated
-- here — they already live in the users table.
-- ============================================================

-- ── TABLE 10: farmer_profiles ─────────────────────────────────
CREATE TABLE farmer_profiles (
    id                          UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                     UUID            NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    farm_name                   VARCHAR(150)    NOT NULL,
    owner_name                  VARCHAR(150)    NOT NULL,
    farm_location               TEXT            NOT NULL,
    farm_address                TEXT            NOT NULL,
    farm_type                   VARCHAR(20)     CHECK (farm_type IN (
                                                    'broiler','layer','breeder',
                                                    'hatchery','mixed','backyard'
                                                )),
    number_of_birds             INT             DEFAULT 0,
    farm_registration_number    VARCHAR(100),
    years_in_farming            INT,
    experience_level            VARCHAR(20)     CHECK (experience_level IN ('beginner','intermediate','expert')),
    primary_diseases_faced      TEXT,
    feed_type                   VARCHAR(100),
    feed_sourcing_method        TEXT,
    existing_vet_consultant     VARCHAR(150),
    farm_photos                 JSONB           DEFAULT '[]',
    number_of_active_workers    INT             DEFAULT 0,
    consent_data_collection     BOOLEAN         NOT NULL DEFAULT FALSE,
    approved_by_admin_id        UUID            REFERENCES users(id) ON DELETE SET NULL,
    created_at                  TIMESTAMP       DEFAULT NOW(),
    updated_at                  TIMESTAMP       DEFAULT NOW()
);
CREATE TRIGGER trg_farmer_profiles_updated_at
    BEFORE UPDATE ON farmer_profiles
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── TABLE 11: admin_profiles ──────────────────────────────────
CREATE TABLE admin_profiles (
    id                                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                             UUID        NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    account_id_number                   VARCHAR(50) UNIQUE,
    job_title                           VARCHAR(100) NOT NULL,
    department                          VARCHAR(100) NOT NULL,
    reporting_manager_id                UUID        REFERENCES users(id) ON DELETE SET NULL,
    work_location                       VARCHAR(150),
    employment_type                     VARCHAR(20) CHECK (employment_type IN ('full_time','part_time','contract')),
    start_date                          DATE        NOT NULL,
    admin_sub_role                      VARCHAR(20) CHECK (admin_sub_role IN (
                                                        'super','operations','finance','content',
                                                        'research','delivery','pharmacy','support'
                                                    )),
    tech_skill_level                    VARCHAR(20) CHECK (tech_skill_level IN ('basic','intermediate','advanced')),
    confidentiality_agreement_accepted  BOOLEAN     NOT NULL DEFAULT FALSE,
    background_check_consent            BOOLEAN     NOT NULL DEFAULT FALSE,
    cv_url                              TEXT,
    previous_experience                 TEXT,
    approved_by_admin_id                UUID        REFERENCES users(id) ON DELETE SET NULL,
    created_at                          TIMESTAMP   DEFAULT NOW(),
    updated_at                          TIMESTAMP   DEFAULT NOW()
);
CREATE TRIGGER trg_admin_profiles_updated_at
    BEFORE UPDATE ON admin_profiles
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── TABLE 12: delivery_profiles ───────────────────────────────
CREATE TABLE delivery_profiles (
    id                          UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                     UUID            NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    drivers_license_number      VARCHAR(50)     NOT NULL,
    license_class               VARCHAR(20)     NOT NULL,
    license_expiry_date         DATE            NOT NULL,
    license_photo_url           TEXT            NOT NULL,
    proof_of_work_url           TEXT,
    prior_delivery_experience   TEXT,
    area_coverage               TEXT,
    availability_schedule       JSONB,
    is_online                   BOOLEAN         DEFAULT FALSE,
    current_status              VARCHAR(20)     DEFAULT 'offline'
                                                CHECK (current_status IN ('active','on_break','unavailable','offline')),
    rating                      DECIMAL(3,2)    DEFAULT 0.00,
    total_deliveries            INT             DEFAULT 0,
    approved_by_admin_id        UUID            REFERENCES users(id) ON DELETE SET NULL,
    created_at                  TIMESTAMP       DEFAULT NOW(),
    updated_at                  TIMESTAMP       DEFAULT NOW()
);
CREATE TRIGGER trg_delivery_profiles_updated_at
    BEFORE UPDATE ON delivery_profiles
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── TABLE 13: delivery_vehicle_details ───────────────────────
-- Bike/vehicle info from the rider signup form.
-- Fields match the registration form: brand, model, region, category,
-- digits, year, tax token, fitness number.
CREATE TABLE delivery_vehicle_details (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    delivery_profile_id     UUID        NOT NULL REFERENCES delivery_profiles(id) ON DELETE CASCADE,
    vehicle_brand           VARCHAR(50) NOT NULL,
    vehicle_model           VARCHAR(100) NOT NULL,
    registration_region     VARCHAR(50) NOT NULL,
    registration_category   VARCHAR(20) NOT NULL,
    registration_digits     VARCHAR(20) NOT NULL,
    manufacturing_year      INT         NOT NULL CHECK (manufacturing_year BETWEEN 1990 AND 2100),
    tax_token_number        VARCHAR(100) NOT NULL,
    fitness_number          VARCHAR(100),
    vehicle_photos          JSONB       DEFAULT '[]',
    created_at              TIMESTAMP   DEFAULT NOW()
);

-- ── TABLE 14: pharmacy_organizations ─────────────────────────
-- The pharmacy as a business entity. Individual pharmacists are in
-- pharmacist_profiles linked back here.
CREATE TABLE pharmacy_organizations (
    id                              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                         UUID        NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    business_name                   VARCHAR(150) NOT NULL,
    authorized_contact_person       VARCHAR(150) NOT NULL,
    business_registration_number    VARCHAR(100) NOT NULL UNIQUE,
    trade_license_url               TEXT        NOT NULL,
    tax_vat_tin_number              VARCHAR(50) NOT NULL,
    business_address                TEXT        NOT NULL,
    warehouse_address               TEXT,
    number_of_pharmacists           INT         DEFAULT 0,
    responsible_pharmacist_name     VARCHAR(150),
    is_verified                     BOOLEAN     DEFAULT FALSE,
    approved_by_admin_id            UUID        REFERENCES users(id) ON DELETE SET NULL,
    created_at                      TIMESTAMP   DEFAULT NOW(),
    updated_at                      TIMESTAMP   DEFAULT NOW()
);
CREATE TRIGGER trg_pharmacy_organizations_updated_at
    BEFORE UPDATE ON pharmacy_organizations
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── TABLE 15: pharmacist_profiles ────────────────────────────
-- Individual pharmacist under a pharmacy organization.
-- Non-blue fields only — base identity fields are in users table.
CREATE TABLE pharmacist_profiles (
    id                                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                                 UUID        NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    pharmacy_id                             UUID        NOT NULL REFERENCES pharmacy_organizations(id) ON DELETE CASCADE,
    is_responsible_pharmacist               BOOLEAN     DEFAULT FALSE,
    pharmacist_license_number               VARCHAR(100) NOT NULL,
    pharmacy_council_board_reg_number       VARCHAR(100) NOT NULL,
    professional_license_expiry_date        DATE        NOT NULL,
    business_registration_certificate_url   TEXT        NOT NULL,
    pharmacy_license_certification_url      TEXT        NOT NULL,
    responsible_pharmacist_certificate_url  TEXT        NOT NULL,
    list_of_permitted_products              JSONB       DEFAULT '[]',
    storage_cold_chain_capability           BOOLEAN     DEFAULT FALSE,
    delivery_coverage_area                  TEXT,
    returns_expiry_handling_policy          TEXT,
    bank_account_for_settlement             JSONB,
    authorized_signatory_details            TEXT,
    agreement_product_quality               BOOLEAN     NOT NULL DEFAULT FALSE,
    agreement_prescription_rules            BOOLEAN     NOT NULL DEFAULT FALSE,
    agreement_audit_policies                BOOLEAN     NOT NULL DEFAULT FALSE,
    is_verified                             BOOLEAN     DEFAULT FALSE,
    approved_by_admin_id                    UUID        REFERENCES users(id) ON DELETE SET NULL,
    created_at                              TIMESTAMP   DEFAULT NOW(),
    updated_at                              TIMESTAMP   DEFAULT NOW()
);
CREATE TRIGGER trg_pharmacist_profiles_updated_at
    BEFORE UPDATE ON pharmacist_profiles
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── TABLE 16: researcher_profiles ────────────────────────────
CREATE TABLE researcher_profiles (
    id                                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                             UUID        NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    institution_name                    VARCHAR(200) NOT NULL,
    institutional_email                 VARCHAR(255) NOT NULL,
    department                          VARCHAR(150) NOT NULL,
    highest_degree                      VARCHAR(50) NOT NULL,
    field_of_study                      VARCHAR(150) NOT NULL,
    university_name                     VARCHAR(200) NOT NULL,
    graduation_year                     INT         NOT NULL,
    cv_url                              TEXT        NOT NULL,
    publications_portfolio_url          TEXT,
    areas_of_expertise                  JSONB       DEFAULT '[]',
    years_of_research_experience        INT         NOT NULL,
    poultry_specific_experience         TEXT,
    research_role_type                  VARCHAR(20) CHECK (research_role_type IN (
                                                        'nutrition','disease','genetics',
                                                        'welfare','growth','economics'
                                                    )),
    ethics_certificate_url              TEXT,
    conflict_of_interest_declaration    BOOLEAN     NOT NULL DEFAULT FALSE,
    publication_consent                 BOOLEAN     NOT NULL DEFAULT FALSE,
    ip_agreement                        BOOLEAN     NOT NULL DEFAULT FALSE,
    reference_name                      VARCHAR(150),
    reference_title                     VARCHAR(100),
    reference_email                     VARCHAR(255),
    is_verified                         BOOLEAN     DEFAULT FALSE,
    approved_by_admin_id                UUID        REFERENCES users(id) ON DELETE SET NULL,
    created_at                          TIMESTAMP   DEFAULT NOW(),
    updated_at                          TIMESTAMP   DEFAULT NOW()
);
CREATE TRIGGER trg_researcher_profiles_updated_at
    BEFORE UPDATE ON researcher_profiles
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── TABLE 17: doctor_profiles ─────────────────────────────────
-- latitude and longitude stored for vet map pin.
CREATE TABLE doctor_profiles (
    id                              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                         UUID            NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    clinic_hospital_name            VARCHAR(200)    NOT NULL,
    practice_address                TEXT            NOT NULL,
    latitude                        DECIMAL(9,6),
    longitude                       DECIMAL(9,6),
    veterinary_degree               VARCHAR(100)    NOT NULL,
    university_name                 VARCHAR(200)    NOT NULL,
    graduation_year                 INT             NOT NULL,
    license_number                  VARCHAR(100)    NOT NULL UNIQUE,
    license_issuing_authority       VARCHAR(150)    NOT NULL,
    license_expiry_date             DATE            NOT NULL,
    specialty                       VARCHAR(150)    NOT NULL,
    poultry_focus_area              TEXT,
    years_of_experience             INT             NOT NULL,
    consultation_mode               VARCHAR(10)     CHECK (consultation_mode IN ('online','offline','both')),
    cv_url                          TEXT,
    council_registration_proof_url  TEXT            NOT NULL,
    prescription_authority          BOOLEAN         DEFAULT FALSE,
    emergency_on_call_availability  BOOLEAN         DEFAULT FALSE,
    service_fee                     DECIMAL(10,2),
    referral_network                TEXT,
    consent_platform_guidelines     BOOLEAN         NOT NULL DEFAULT FALSE,
    is_verified                     BOOLEAN         DEFAULT FALSE,
    is_available                    BOOLEAN         DEFAULT TRUE,
    rating                          DECIMAL(3,2)    DEFAULT 0.00,
    approved_by_admin_id            UUID            REFERENCES users(id) ON DELETE SET NULL,
    created_at                      TIMESTAMP       DEFAULT NOW(),
    updated_at                      TIMESTAMP       DEFAULT NOW()
);
CREATE TRIGGER trg_doctor_profiles_updated_at
    BEFORE UPDATE ON doctor_profiles
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();


-- ============================================================
-- MODULE 04 · FARM MANAGEMENT
-- ============================================================

-- ── TABLE 18: farms ───────────────────────────────────────────
CREATE TABLE farms (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    farmer_id           UUID        NOT NULL REFERENCES farmer_profiles(id) ON DELETE CASCADE,
    farm_name           VARCHAR(150) NOT NULL,
    farm_type           VARCHAR(20) CHECK (farm_type IN (
                                        'broiler','layer','breeder',
                                        'hatchery','mixed','backyard'
                                    )),
    location            TEXT        NOT NULL,
    address             TEXT        NOT NULL,
    latitude            DECIMAL(9,6),
    longitude           DECIMAL(9,6),
    registration_number VARCHAR(100),
    total_sheds         INT         DEFAULT 0,
    is_active           BOOLEAN     DEFAULT TRUE,
    created_at          TIMESTAMP   DEFAULT NOW(),
    updated_at          TIMESTAMP   DEFAULT NOW()
);
CREATE TRIGGER trg_farms_updated_at
    BEFORE UPDATE ON farms
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── TABLE 19: sheds ───────────────────────────────────────────
CREATE TABLE sheds (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_id             UUID        NOT NULL REFERENCES farms(id) ON DELETE CASCADE,
    shed_name           VARCHAR(100) NOT NULL,
    capacity            INT         NOT NULL,
    current_bird_count  INT         DEFAULT 0,
    shed_type           VARCHAR(50),
    created_at          TIMESTAMP   DEFAULT NOW(),
    updated_at          TIMESTAMP   DEFAULT NOW()
);
CREATE TRIGGER trg_sheds_updated_at
    BEFORE UPDATE ON sheds
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── TABLE 20: flocks ──────────────────────────────────────────
-- Core batch unit — links feed, costs, disease scans, and consultations.
CREATE TABLE flocks (
    id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    shed_id          UUID        REFERENCES sheds(id) ON DELETE SET NULL,
    farm_id          UUID        NOT NULL REFERENCES farms(id) ON DELETE CASCADE,
    batch_name       VARCHAR(100) NOT NULL,
    bird_type        VARCHAR(20) CHECK (bird_type IN ('broiler','layer','breeder','hatchery')),
    breed            VARCHAR(100),
    quantity         INT         NOT NULL,
    current_quantity INT         NOT NULL,
    start_date       DATE        NOT NULL,
    end_date         DATE,
    status           VARCHAR(10) DEFAULT 'active' CHECK (status IN ('active','closed','sold')),
    created_at       TIMESTAMP   DEFAULT NOW(),
    updated_at       TIMESTAMP   DEFAULT NOW()
);
CREATE TRIGGER trg_flocks_updated_at
    BEFORE UPDATE ON flocks
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();


-- ============================================================
-- MODULE 05 · LABOR MANAGEMENT
-- ============================================================

-- ── TABLE 21: workers ─────────────────────────────────────────
-- Farm workers — not platform users, no login.
-- FIX v2: renamed column 'role' → 'job_role' ('role' is a reserved
--         keyword in PostgreSQL and causes query parser issues).
CREATE TABLE workers (
    id          UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_id     UUID            NOT NULL REFERENCES farms(id) ON DELETE CASCADE,
    full_name   VARCHAR(150)    NOT NULL,
    phone       VARCHAR(20),
    job_role    VARCHAR(100)    NOT NULL,
    daily_wage  DECIMAL(10,2)   NOT NULL,
    join_date   DATE            NOT NULL,
    status      VARCHAR(10)     DEFAULT 'active' CHECK (status IN ('active','inactive')),
    created_at  TIMESTAMP       DEFAULT NOW(),
    updated_at  TIMESTAMP       DEFAULT NOW()
);
CREATE TRIGGER trg_workers_updated_at
    BEFORE UPDATE ON workers
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── TABLE 22: worker_attendance ───────────────────────────────
-- FIX v2: renamed column 'date' → 'attendance_date'
--         ('date' is a reserved keyword in PostgreSQL).
CREATE TABLE worker_attendance (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    worker_id       UUID        NOT NULL REFERENCES workers(id) ON DELETE CASCADE,
    attendance_date DATE        NOT NULL,
    status          VARCHAR(10) NOT NULL CHECK (status IN ('present','absent','half_day')),
    check_in_time   TIME,
    check_out_time  TIME,
    notes           TEXT,
    created_at      TIMESTAMP   DEFAULT NOW(),
    UNIQUE (worker_id, attendance_date)
);

-- ── TABLE 23: worker_tasks ────────────────────────────────────
CREATE TABLE worker_tasks (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    worker_id       UUID        NOT NULL REFERENCES workers(id) ON DELETE CASCADE,
    farm_id         UUID        NOT NULL REFERENCES farms(id) ON DELETE CASCADE,
    task_name       VARCHAR(150) NOT NULL,
    description     TEXT,
    assigned_date   DATE        NOT NULL,
    due_date        DATE,
    status          VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending','in_progress','completed')),
    created_at      TIMESTAMP   DEFAULT NOW(),
    updated_at      TIMESTAMP   DEFAULT NOW()
);
CREATE TRIGGER trg_worker_tasks_updated_at
    BEFORE UPDATE ON worker_tasks
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── TABLE 24: worker_payments ─────────────────────────────────
CREATE TABLE worker_payments (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    worker_id       UUID            NOT NULL REFERENCES workers(id) ON DELETE CASCADE,
    amount          DECIMAL(10,2)   NOT NULL,
    payment_date    DATE            NOT NULL,
    payment_method  VARCHAR(50)     NOT NULL,
    period_start    DATE            NOT NULL,
    period_end      DATE            NOT NULL,
    notes           TEXT,
    created_at      TIMESTAMP       DEFAULT NOW()
);


-- ============================================================
-- MODULE 06 · FEED MANAGEMENT
-- ============================================================

-- ── TABLE 25: feed_types ──────────────────────────────────────
CREATE TABLE feed_types (
    id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name             VARCHAR(100) NOT NULL,
    brand            VARCHAR(100),
    nutritional_info JSONB,
    unit             VARCHAR(10) CHECK (unit IN ('kg','bag','liter')),
    created_at       TIMESTAMP   DEFAULT NOW()
);

-- ── TABLE 26: feed_stock ──────────────────────────────────────
-- FIX v2: created_at now comes before updated_at (was reversed in v1).
CREATE TABLE feed_stock (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_id             UUID            NOT NULL REFERENCES farms(id) ON DELETE CASCADE,
    feed_type_id        UUID            NOT NULL REFERENCES feed_types(id) ON DELETE RESTRICT,
    quantity_available  DECIMAL(10,2)   NOT NULL DEFAULT 0,
    last_restocked_at   TIMESTAMP,
    supplier_name       VARCHAR(150),
    cost_per_unit       DECIMAL(10,2),
    created_at          TIMESTAMP       DEFAULT NOW(),
    updated_at          TIMESTAMP       DEFAULT NOW(),
    UNIQUE (farm_id, feed_type_id)
);
CREATE TRIGGER trg_feed_stock_updated_at
    BEFORE UPDATE ON feed_stock
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── TABLE 27: feed_schedules ──────────────────────────────────
CREATE TABLE feed_schedules (
    id                   UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    flock_id             UUID            NOT NULL REFERENCES flocks(id) ON DELETE CASCADE,
    feed_type_id         UUID            NOT NULL REFERENCES feed_types(id) ON DELETE RESTRICT,
    scheduled_time       TIME            NOT NULL,
    quantity_per_feeding DECIMAL(10,2)   NOT NULL,
    frequency            VARCHAR(20)     CHECK (frequency IN ('daily','twice_daily','custom')),
    created_at           TIMESTAMP       DEFAULT NOW()
);

-- ── TABLE 28: feed_consumption ────────────────────────────────
-- FIX v2: renamed column 'date' → 'consumed_date'
--         ('date' is a reserved keyword in PostgreSQL).
-- FIX v2: recorded_by now ON DELETE RESTRICT — cannot delete a user
--         who has logged feed consumption records.
CREATE TABLE feed_consumption (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    flock_id            UUID            NOT NULL REFERENCES flocks(id) ON DELETE CASCADE,
    feed_type_id        UUID            NOT NULL REFERENCES feed_types(id) ON DELETE RESTRICT,
    consumed_date       DATE            NOT NULL,
    quantity_consumed   DECIMAL(10,2)   NOT NULL,
    recorded_by         UUID            NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    notes               TEXT,
    created_at          TIMESTAMP       DEFAULT NOW()
);


-- ============================================================
-- MODULE 07 · COST MANAGEMENT
-- ============================================================

-- ── TABLE 29: expense_categories ─────────────────────────────
CREATE TABLE expense_categories (
    id              SERIAL          PRIMARY KEY,
    name            VARCHAR(100)    NOT NULL UNIQUE,
    linked_module   VARCHAR(50),
    icon            VARCHAR(50),
    created_at      TIMESTAMP       DEFAULT NOW()
);

-- ── TABLE 30: expenses ────────────────────────────────────────
-- FIX v2: renamed column 'date' → 'expense_date'.
-- FIX v2: created_by now ON DELETE RESTRICT — cannot delete a user
--         who has created expense records (financial audit integrity).
CREATE TABLE expenses (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_id         UUID            NOT NULL REFERENCES farms(id) ON DELETE CASCADE,
    category_id     INT             NOT NULL REFERENCES expense_categories(id) ON DELETE RESTRICT,
    flock_id        UUID            REFERENCES flocks(id) ON DELETE SET NULL,
    amount          DECIMAL(12,2)   NOT NULL,
    description     TEXT,
    expense_date    DATE            NOT NULL,
    payment_status  VARCHAR(10)     DEFAULT 'pending'
                                    CHECK (payment_status IN ('paid','pending','overdue')),
    payment_method  VARCHAR(50),
    supplier_name   VARCHAR(150),
    receipt_url     TEXT,
    created_by      UUID            NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    approved_by     UUID            REFERENCES users(id) ON DELETE SET NULL,
    created_at      TIMESTAMP       DEFAULT NOW()
);

-- ── TABLE 31: revenue_sources ─────────────────────────────────
CREATE TABLE revenue_sources (
    id          SERIAL          PRIMARY KEY,
    name        VARCHAR(100)    NOT NULL UNIQUE,
    created_at  TIMESTAMP       DEFAULT NOW()
);

-- ── TABLE 32: revenues ────────────────────────────────────────
-- FIX v2: renamed column 'date' → 'revenue_date'.
-- FIX v2: created_by now ON DELETE RESTRICT.
CREATE TABLE revenues (
    id           UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_id      UUID            NOT NULL REFERENCES farms(id) ON DELETE CASCADE,
    source_id    INT             NOT NULL REFERENCES revenue_sources(id) ON DELETE RESTRICT,
    flock_id     UUID            REFERENCES flocks(id) ON DELETE SET NULL,
    amount       DECIMAL(12,2)   NOT NULL,
    revenue_date DATE            NOT NULL,
    description  TEXT,
    created_by   UUID            NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    created_at   TIMESTAMP       DEFAULT NOW()
);

-- ── TABLE 33: loans ───────────────────────────────────────────
CREATE TABLE loans (
    id                UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_id           UUID            NOT NULL REFERENCES farms(id) ON DELETE CASCADE,
    lender_name       VARCHAR(150)    NOT NULL,
    loan_amount       DECIMAL(12,2)   NOT NULL,
    interest_rate     DECIMAL(5,2)    NOT NULL,
    start_date        DATE            NOT NULL,
    due_date          DATE            NOT NULL,
    remaining_balance DECIMAL(12,2)   NOT NULL,
    status            VARCHAR(10)     DEFAULT 'active' CHECK (status IN ('active','paid','overdue')),
    created_at        TIMESTAMP       DEFAULT NOW(),
    updated_at        TIMESTAMP       DEFAULT NOW()
);
CREATE TRIGGER trg_loans_updated_at
    BEFORE UPDATE ON loans
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── TABLE 34: loan_installments ───────────────────────────────
CREATE TABLE loan_installments (
    id          UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    loan_id     UUID            NOT NULL REFERENCES loans(id) ON DELETE CASCADE,
    due_date    DATE            NOT NULL,
    amount      DECIMAL(12,2)   NOT NULL,
    paid_date   DATE,
    payment_id  UUID            REFERENCES payments(id) ON DELETE SET NULL,
    status      VARCHAR(10)     DEFAULT 'pending' CHECK (status IN ('pending','paid','overdue')),
    created_at  TIMESTAMP       DEFAULT NOW()
);

-- ── TABLE 35: tax_records ─────────────────────────────────────
-- tax_month = NULL means the record is a full-year summary.
CREATE TABLE tax_records (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_id         UUID            NOT NULL REFERENCES farms(id) ON DELETE CASCADE,
    tax_year        INT             NOT NULL,
    tax_month       SMALLINT        CHECK (tax_month BETWEEN 1 AND 12),
    total_income    DECIMAL(14,2)   NOT NULL DEFAULT 0,
    total_expense   DECIMAL(14,2)   NOT NULL DEFAULT 0,
    taxable_amount  DECIMAL(14,2)   NOT NULL DEFAULT 0,
    tax_due         DECIMAL(14,2)   NOT NULL DEFAULT 0,
    tax_paid        DECIMAL(14,2)   NOT NULL DEFAULT 0,
    payment_date    DATE,
    payment_id      UUID            REFERENCES payments(id) ON DELETE SET NULL,
    status          VARCHAR(10)     DEFAULT 'pending' CHECK (status IN ('pending','paid')),
    created_at      TIMESTAMP       DEFAULT NOW(),
    updated_at      TIMESTAMP       DEFAULT NOW()
);
CREATE TRIGGER trg_tax_records_updated_at
    BEFORE UPDATE ON tax_records
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();


-- ============================================================
-- MODULE 08 · DISEASE DETECTION (PART 1)
-- ============================================================

-- ── TABLE 36: diseases ────────────────────────────────────────
-- Master catalog of known poultry diseases.
-- Populated by admins and researchers; read by the ML module.
CREATE TABLE diseases (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name                    VARCHAR(150) NOT NULL UNIQUE,
    description             TEXT        NOT NULL,
    symptoms                JSONB       NOT NULL DEFAULT '[]',
    what_to_do              TEXT        NOT NULL,
    what_not_to_do          TEXT        NOT NULL,
    prevention_tips         TEXT,
    severity_level          VARCHAR(10) CHECK (severity_level IN ('low','medium','high','critical')),
    requires_immediate_vet  BOOLEAN     DEFAULT FALSE,
    created_at              TIMESTAMP   DEFAULT NOW()
);


-- ============================================================
-- MODULE 09 · CHATBOT (STEP 1)
-- ⚠ CIRCULAR DEPENDENCY FIX:
--   chatbot_sessions.scan_id → disease_scans
--   disease_scans.chatbot_session_id → chatbot_sessions
--   Solution: create chatbot_sessions WITHOUT scan_id FK first.
--   Add the FK back via ALTER TABLE after disease_scans exists.
-- ============================================================

-- ── TABLE 37: chatbot_sessions ────────────────────────────────
-- scan_id column is present but has NO FK constraint yet —
-- added below via ALTER TABLE after disease_scans is created.
CREATE TABLE chatbot_sessions (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    scan_id         UUID,
    session_type    VARCHAR(20) DEFAULT 'general'
                                CHECK (session_type IN ('general','disease_followup')),
    started_at      TIMESTAMP   DEFAULT NOW(),
    ended_at        TIMESTAMP
);


-- ============================================================
-- MODULE 08 · DISEASE DETECTION (PART 2)
-- chatbot_sessions now exists so disease_scans can reference it.
-- ============================================================

-- ── TABLE 38: disease_scans ───────────────────────────────────
CREATE TABLE disease_scans (
    id                   UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id              UUID            NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    farm_id              UUID            REFERENCES farms(id) ON DELETE SET NULL,
    flock_id             UUID            REFERENCES flocks(id) ON DELETE SET NULL,
    image_urls           JSONB           NOT NULL DEFAULT '[]',
    image_quality_status VARCHAR(20)     DEFAULT 'good'
                                         CHECK (image_quality_status IN (
                                             'good','blurry','dark','wrong_angle','rejected'
                                         )),
    detected_disease_id  UUID            REFERENCES diseases(id) ON DELETE SET NULL,
    confidence_score     DECIMAL(5,2),
    severity_level       VARCHAR(10)     CHECK (severity_level IN ('low','medium','high','critical')),
    scan_status          VARCHAR(20)     DEFAULT 'processing'
                                         CHECK (scan_status IN ('processing','completed','failed')),
    is_free_scan         BOOLEAN         NOT NULL DEFAULT TRUE,
    chatbot_session_id   UUID            REFERENCES chatbot_sessions(id) ON DELETE SET NULL,
    created_at           TIMESTAMP       DEFAULT NOW()
);

-- ── CIRCULAR DEPENDENCY FIX ───────────────────────────────────
-- Now that disease_scans exists, complete the FK on chatbot_sessions.
ALTER TABLE chatbot_sessions
    ADD CONSTRAINT fk_chatbot_sessions_scan_id
    FOREIGN KEY (scan_id)
    REFERENCES disease_scans(id)
    ON DELETE SET NULL;

-- ── TABLE 39: scan_chatbot_advice ────────────────────────────
-- AI advice auto-generated after each disease scan result.
CREATE TABLE scan_chatbot_advice (
    id                          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    scan_id                     UUID        NOT NULL UNIQUE REFERENCES disease_scans(id) ON DELETE CASCADE,
    what_to_do                  TEXT        NOT NULL,
    what_not_to_do              TEXT        NOT NULL,
    isolation_recommended       BOOLEAN     NOT NULL DEFAULT FALSE,
    emergency_warning           BOOLEAN     NOT NULL DEFAULT FALSE,
    symptom_followup_answers    JSONB,
    vet_escalation_triggered    BOOLEAN     DEFAULT FALSE,
    created_at                  TIMESTAMP   DEFAULT NOW()
);


-- ============================================================
-- MODULE 09 · CHATBOT (STEP 2)
-- ============================================================

-- ── TABLE 40: chatbot_messages ────────────────────────────────
CREATE TABLE chatbot_messages (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id  UUID        NOT NULL REFERENCES chatbot_sessions(id) ON DELETE CASCADE,
    role        VARCHAR(10) NOT NULL CHECK (role IN ('user','assistant')),
    content     TEXT        NOT NULL,
    sent_at     TIMESTAMP   DEFAULT NOW()
);


-- ============================================================
-- MODULE 10 · DOCTOR & CONSULTATIONS
-- ============================================================

-- ── TABLE 41: consultations ───────────────────────────────────
-- FIX v2: farmer_id and doctor_id now have ON DELETE RESTRICT —
--         you cannot delete a user who has consultation records.
CREATE TABLE consultations (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    farmer_id           UUID        NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    doctor_id           UUID        NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    scan_id             UUID        REFERENCES disease_scans(id) ON DELETE SET NULL,
    mode                VARCHAR(10) CHECK (mode IN ('online','offline')),
    status              VARCHAR(20) DEFAULT 'requested'
                                    CHECK (status IN (
                                        'requested','accepted','rejected',
                                        'in_progress','completed','cancelled'
                                    )),
    urgency_level       VARCHAR(15) DEFAULT 'routine'
                                    CHECK (urgency_level IN ('routine','moderate','urgent','emergency')),
    appointment_date    DATE        NOT NULL,
    appointment_time    TIME        NOT NULL,
    consultation_fee    DECIMAL(10,2),
    payment_id          UUID        REFERENCES payments(id) ON DELETE SET NULL,
    rating              SMALLINT    CHECK (rating BETWEEN 1 AND 5),
    review_text         TEXT,
    created_at          TIMESTAMP   DEFAULT NOW(),
    updated_at          TIMESTAMP   DEFAULT NOW()
);
CREATE TRIGGER trg_consultations_updated_at
    BEFORE UPDATE ON consultations
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── TABLE 42: consultation_case_details ──────────────────────
-- Poultry-specific case data: flock, breed, mortality count,
-- vaccine history, biosecurity notes.
CREATE TABLE consultation_case_details (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    consultation_id         UUID        NOT NULL UNIQUE REFERENCES consultations(id) ON DELETE CASCADE,
    flock_id                UUID        REFERENCES flocks(id) ON DELETE SET NULL,
    farm_name               VARCHAR(150),
    bird_age                VARCHAR(50),
    breed                   VARCHAR(100),
    flock_count             INT,
    mortality_count         INT,
    feed_notes              TEXT,
    vaccine_history         TEXT,
    biosecurity_notes       TEXT,
    symptoms_description    TEXT,
    created_at              TIMESTAMP   DEFAULT NOW()
);

-- ── TABLE 43: consultation_notes ─────────────────────────────
CREATE TABLE consultation_notes (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    consultation_id UUID        NOT NULL REFERENCES consultations(id) ON DELETE CASCADE,
    doctor_id       UUID        NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    symptoms        TEXT,
    diagnosis       TEXT        NOT NULL,
    treatment_plan  TEXT        NOT NULL,
    warnings        TEXT,
    next_steps      TEXT,
    created_at      TIMESTAMP   DEFAULT NOW(),
    updated_at      TIMESTAMP   DEFAULT NOW()
);
CREATE TRIGGER trg_consultation_notes_updated_at
    BEFORE UPDATE ON consultation_notes
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── TABLE 44: prescriptions ───────────────────────────────────
CREATE TABLE prescriptions (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    consultation_id UUID        NOT NULL REFERENCES consultations(id) ON DELETE CASCADE,
    doctor_id       UUID        NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    medicine_name   VARCHAR(150) NOT NULL,
    dosage          VARCHAR(100) NOT NULL,
    duration        VARCHAR(50) NOT NULL,
    instructions    TEXT,
    follow_up_date  DATE,
    created_at      TIMESTAMP   DEFAULT NOW()
);

-- ── TABLE 45: follow_ups ──────────────────────────────────────
CREATE TABLE follow_ups (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    consultation_id UUID        NOT NULL REFERENCES consultations(id) ON DELETE CASCADE,
    scheduled_date  DATE        NOT NULL,
    status          VARCHAR(15) DEFAULT 'pending' CHECK (status IN ('pending','completed','missed')),
    notes           TEXT,
    created_at      TIMESTAMP   DEFAULT NOW(),
    updated_at      TIMESTAMP   DEFAULT NOW()
);
CREATE TRIGGER trg_follow_ups_updated_at
    BEFORE UPDATE ON follow_ups
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── TABLE 46: video_calls ─────────────────────────────────────
CREATE TABLE video_calls (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    consultation_id UUID        NOT NULL UNIQUE REFERENCES consultations(id) ON DELETE CASCADE,
    started_at      TIMESTAMP,
    ended_at        TIMESTAMP,
    duration_minutes INT,
    status          VARCHAR(15) DEFAULT 'scheduled'
                                CHECK (status IN ('scheduled','ongoing','completed','failed')),
    created_at      TIMESTAMP   DEFAULT NOW()
);


-- ============================================================
-- MODULE 11 · MESSAGING
-- ============================================================

-- ── TABLE 47: conversations ───────────────────────────────────
CREATE TABLE conversations (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    participant_one_id  UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    participant_two_id  UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    consultation_id     UUID        REFERENCES consultations(id) ON DELETE SET NULL,
    last_message_at     TIMESTAMP,
    created_at          TIMESTAMP   DEFAULT NOW()
);

-- ── TABLE 48: messages ────────────────────────────────────────
CREATE TABLE messages (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID        NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id       UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    content         TEXT,
    message_type    VARCHAR(10) DEFAULT 'text' CHECK (message_type IN ('text','image','video','file')),
    file_url        TEXT,
    is_read         BOOLEAN     DEFAULT FALSE,
    sent_at         TIMESTAMP   DEFAULT NOW()
);


-- ============================================================
-- MODULE 12 · PHARMACY & MEDICINES
-- ============================================================

-- ── TABLE 49: pharmacy_medicines ─────────────────────────────
CREATE TABLE pharmacy_medicines (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    pharmacy_id             UUID            NOT NULL REFERENCES pharmacy_organizations(id) ON DELETE CASCADE,
    added_by_pharmacist_id  UUID            REFERENCES pharmacist_profiles(id) ON DELETE SET NULL,
    name                    VARCHAR(150)    NOT NULL,
    category                VARCHAR(100)    NOT NULL,
    description             TEXT,
    price                   DECIMAL(10,2)   NOT NULL,
    stock_quantity          INT             NOT NULL DEFAULT 0,
    unit                    VARCHAR(20)     NOT NULL,
    requires_prescription   BOOLEAN         DEFAULT FALSE,
    storage_requirements    TEXT,
    expiry_date             DATE,
    is_available            BOOLEAN         DEFAULT TRUE,
    created_at              TIMESTAMP       DEFAULT NOW(),
    updated_at              TIMESTAMP       DEFAULT NOW()
);
CREATE TRIGGER trg_pharmacy_medicines_updated_at
    BEFORE UPDATE ON pharmacy_medicines
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── TABLE 50: medicine_orders ─────────────────────────────────
-- FIX v2: buyer_id and pharmacy_id now have explicit ON DELETE RESTRICT —
--         financial order records must be preserved even if the user
--         or pharmacy is deactivated.
CREATE TABLE medicine_orders (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    buyer_id            UUID        NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    pharmacy_id         UUID        NOT NULL REFERENCES pharmacy_organizations(id) ON DELETE RESTRICT,
    delivery_person_id  UUID        REFERENCES delivery_profiles(id) ON DELETE SET NULL,
    status              VARCHAR(20) DEFAULT 'pending'
                                    CHECK (status IN (
                                        'pending','confirmed','dispatched',
                                        'delivered','returned','cancelled'
                                    )),
    total_amount        DECIMAL(12,2) NOT NULL,
    payment_id          UUID        REFERENCES payments(id) ON DELETE SET NULL,
    delivery_address    TEXT        NOT NULL,
    prescription_url    TEXT,
    notes               TEXT,
    created_at          TIMESTAMP   DEFAULT NOW(),
    updated_at          TIMESTAMP   DEFAULT NOW()
);
CREATE TRIGGER trg_medicine_orders_updated_at
    BEFORE UPDATE ON medicine_orders
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── TABLE 51: medicine_order_items ───────────────────────────
-- unit_price is a snapshot of price at the time of order.
CREATE TABLE medicine_order_items (
    id          UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id    UUID            NOT NULL REFERENCES medicine_orders(id) ON DELETE CASCADE,
    medicine_id UUID            NOT NULL REFERENCES pharmacy_medicines(id) ON DELETE RESTRICT,
    quantity    INT             NOT NULL,
    unit_price  DECIMAL(10,2)   NOT NULL,
    created_at  TIMESTAMP       DEFAULT NOW()
);


-- ============================================================
-- MODULE 13 · DELIVERY
-- ============================================================

-- ── TABLE 52: delivery_orders ─────────────────────────────────
-- FIX v2: delivery_person_id now ON DELETE RESTRICT — cannot delete
--         a rider profile with active delivery records.
CREATE TABLE delivery_orders (
    id                       UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    delivery_person_id       UUID        NOT NULL REFERENCES delivery_profiles(id) ON DELETE RESTRICT,
    order_reference_id       UUID        NOT NULL,
    order_type               VARCHAR(15) CHECK (order_type IN ('medicine','marketplace')),
    pickup_address           TEXT        NOT NULL,
    delivery_address         TEXT        NOT NULL,
    pickup_lat               DECIMAL(9,6),
    pickup_lng               DECIMAL(9,6),
    delivery_lat             DECIMAL(9,6),
    delivery_lng             DECIMAL(9,6),
    status                   VARCHAR(20) DEFAULT 'pending'
                                         CHECK (status IN (
                                             'pending','accepted','rejected','picked_up',
                                             'on_the_way','delivered','failed','cancelled'
                                         )),
    otp_code                 VARCHAR(10),
    proof_of_delivery_url    TEXT,
    failure_reason           TEXT,
    is_pharmacy_delivery     BOOLEAN     DEFAULT FALSE,
    is_cold_chain            BOOLEAN     DEFAULT FALSE,
    is_prescription_required BOOLEAN     DEFAULT FALSE,
    notes                    TEXT,
    assigned_at              TIMESTAMP,
    delivered_at             TIMESTAMP,
    created_at               TIMESTAMP   DEFAULT NOW()
);

-- ── TABLE 53: delivery_earnings ───────────────────────────────
-- FIX v2: delivery_person_id now ON DELETE RESTRICT.
CREATE TABLE delivery_earnings (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    delivery_person_id  UUID            NOT NULL REFERENCES delivery_profiles(id) ON DELETE RESTRICT,
    delivery_order_id   UUID            NOT NULL UNIQUE REFERENCES delivery_orders(id) ON DELETE RESTRICT,
    base_pay            DECIMAL(10,2)   NOT NULL,
    bonus               DECIMAL(10,2)   DEFAULT 0.00,
    penalty             DECIMAL(10,2)   DEFAULT 0.00,
    total_earned        DECIMAL(10,2)   NOT NULL,
    payout_status       VARCHAR(10)     DEFAULT 'pending' CHECK (payout_status IN ('pending','paid')),
    payout_date         DATE,
    created_at          TIMESTAMP       DEFAULT NOW()
);

-- ── TABLE 54: delivery_attendance ────────────────────────────
-- FIX v2: renamed column 'date' → 'attendance_date'.
CREATE TABLE delivery_attendance (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    delivery_person_id  UUID        NOT NULL REFERENCES delivery_profiles(id) ON DELETE CASCADE,
    attendance_date     DATE        NOT NULL,
    check_in_time       TIMESTAMP,
    check_out_time      TIMESTAMP,
    status              VARCHAR(10) DEFAULT 'present' CHECK (status IN ('present','absent')),
    created_at          TIMESTAMP   DEFAULT NOW(),
    UNIQUE (delivery_person_id, attendance_date)
);


-- ============================================================
-- MODULE 14 · COMMUNITY & BLOG
-- ============================================================

-- ── TABLE 55: post_categories ─────────────────────────────────
CREATE TABLE post_categories (
    id          SERIAL          PRIMARY KEY,
    name        VARCHAR(50)     NOT NULL UNIQUE,
    created_at  TIMESTAMP       DEFAULT NOW()
);

-- ── TABLE 56: posts ───────────────────────────────────────────
CREATE TABLE posts (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    author_id   UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    content     TEXT        NOT NULL,
    media_urls  JSONB       DEFAULT '[]',
    category_id INT         REFERENCES post_categories(id) ON DELETE SET NULL,
    is_anonymous BOOLEAN    DEFAULT FALSE,
    is_pinned   BOOLEAN     DEFAULT FALSE,
    is_official BOOLEAN     DEFAULT FALSE,
    status      VARCHAR(10) DEFAULT 'active' CHECK (status IN ('active','removed','flagged')),
    created_at  TIMESTAMP   DEFAULT NOW(),
    updated_at  TIMESTAMP   DEFAULT NOW()
);
CREATE TRIGGER trg_posts_updated_at
    BEFORE UPDATE ON posts
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── TABLE 57: comments ────────────────────────────────────────
-- Self-referencing parent_comment_id supports nested replies.
CREATE TABLE comments (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id             UUID        NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    author_id           UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    parent_comment_id   UUID        REFERENCES comments(id) ON DELETE CASCADE,
    content             TEXT        NOT NULL,
    is_best_answer      BOOLEAN     DEFAULT FALSE,
    status              VARCHAR(10) DEFAULT 'active' CHECK (status IN ('active','removed')),
    created_at          TIMESTAMP   DEFAULT NOW(),
    updated_at          TIMESTAMP   DEFAULT NOW()
);
CREATE TRIGGER trg_comments_updated_at
    BEFORE UPDATE ON comments
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── TABLE 58: reactions ───────────────────────────────────────
-- Polymorphic: target_type indicates whether target_id is a post or comment.
CREATE TABLE reactions (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    target_id     UUID        NOT NULL,
    target_type   VARCHAR(10) NOT NULL CHECK (target_type IN ('post','comment')),
    reaction_type VARCHAR(20) NOT NULL CHECK (reaction_type IN ('like','helpful','insightful')),
    created_at    TIMESTAMP   DEFAULT NOW(),
    UNIQUE (user_id, target_id, target_type)
);

-- ── TABLE 59: hashtags ────────────────────────────────────────
CREATE TABLE hashtags (
    id          SERIAL          PRIMARY KEY,
    name        VARCHAR(100)    NOT NULL UNIQUE,
    usage_count INT             DEFAULT 0,
    created_at  TIMESTAMP       DEFAULT NOW()
);

-- ── TABLE 60: post_hashtags ───────────────────────────────────
-- FIX v2: added created_at (was missing in v1).
CREATE TABLE post_hashtags (
    post_id     UUID        NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    hashtag_id  INT         NOT NULL REFERENCES hashtags(id) ON DELETE CASCADE,
    created_at  TIMESTAMP   DEFAULT NOW(),
    PRIMARY KEY (post_id, hashtag_id)
);

-- ── TABLE 61: follows ─────────────────────────────────────────
-- CHECK prevents self-following.
CREATE TABLE follows (
    follower_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    following_id    UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at      TIMESTAMP   DEFAULT NOW(),
    PRIMARY KEY (follower_id, following_id),
    CHECK (follower_id <> following_id)
);

-- ── TABLE 62: bookmarks ───────────────────────────────────────
CREATE TABLE bookmarks (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    target_id   UUID        NOT NULL,
    target_type VARCHAR(10) NOT NULL CHECK (target_type IN ('post','article')),
    created_at  TIMESTAMP   DEFAULT NOW(),
    UNIQUE (user_id, target_id, target_type)
);

-- ── TABLE 63: reports ─────────────────────────────────────────
CREATE TABLE reports (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    target_id   UUID        NOT NULL,
    target_type VARCHAR(10) NOT NULL CHECK (target_type IN ('post','comment','user')),
    reason      TEXT        NOT NULL,
    status      VARCHAR(15) DEFAULT 'pending' CHECK (status IN ('pending','reviewed','resolved')),
    reviewed_by UUID        REFERENCES users(id) ON DELETE SET NULL,
    created_at  TIMESTAMP   DEFAULT NOW(),
    updated_at  TIMESTAMP   DEFAULT NOW()
);
CREATE TRIGGER trg_reports_updated_at
    BEFORE UPDATE ON reports
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();


-- ============================================================
-- MODULE 15 · ARTICLES & RESEARCH
-- ============================================================

-- ── TABLE 64: articles ────────────────────────────────────────
-- Only researchers and admins can publish. Everyone else read-only.
-- FIX v2: author_id now ON DELETE RESTRICT — cannot delete a user
--         who has authored published research articles.
CREATE TABLE articles (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    author_id       UUID        NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    title           VARCHAR(300) NOT NULL,
    abstract        TEXT        NOT NULL,
    body            TEXT        NOT NULL,
    content_type    VARCHAR(20) CHECK (content_type IN (
                                    'research_paper','news','innovation',
                                    'disease_study','feed_study','market_report','team_update'
                                )),
    category        VARCHAR(100),
    keywords        JSONB       DEFAULT '[]',
    references_list JSONB       DEFAULT '[]',
    pdf_url         TEXT,
    farmer_summary  TEXT,
    status          VARCHAR(20) DEFAULT 'draft'
                                CHECK (status IN (
                                    'draft','pending_review','needs_revision','published','archived'
                                )),
    version         INT         DEFAULT 1,
    read_count      INT         DEFAULT 0,
    published_at    TIMESTAMP,
    created_at      TIMESTAMP   DEFAULT NOW(),
    updated_at      TIMESTAMP   DEFAULT NOW()
);
CREATE TRIGGER trg_articles_updated_at
    BEFORE UPDATE ON articles
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── TABLE 65: article_authors ─────────────────────────────────
-- Multi-author support: lead, co-author, editor per paper.
-- FIX v2: added created_at (was missing in v1).
CREATE TABLE article_authors (
    article_id  UUID        NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
    user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    author_role VARCHAR(15) NOT NULL CHECK (author_role IN ('lead_author','co_author','editor')),
    created_at  TIMESTAMP   DEFAULT NOW(),
    PRIMARY KEY (article_id, user_id)
);


-- ============================================================
-- MODULE 16 · NOTIFICATIONS & AUDIT
-- ============================================================

-- ── TABLE 66: notifications ───────────────────────────────────
CREATE TABLE notifications (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title           VARCHAR(200) NOT NULL,
    body            TEXT        NOT NULL,
    notification_type VARCHAR(20) NOT NULL
                                CHECK (notification_type IN (
                                    'alert','reminder','message','system',
                                    'approval','bill_due','tax_due','loan_due'
                                )),
    reference_id    UUID,
    reference_type  VARCHAR(50),
    is_read         BOOLEAN     DEFAULT FALSE,
    created_at      TIMESTAMP   DEFAULT NOW()
);

-- ── TABLE 67: activity_logs ───────────────────────────────────
-- Full audit trail. user_id can be NULL for system-triggered actions.
-- old_value and new_value capture before/after state as JSONB.
CREATE TABLE activity_logs (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID        REFERENCES users(id) ON DELETE SET NULL,
    action      VARCHAR(100) NOT NULL,
    module      VARCHAR(50) NOT NULL,
    target_id   UUID,
    target_type VARCHAR(50),
    old_value   JSONB,
    new_value   JSONB,
    ip_address  VARCHAR(45),
    created_at  TIMESTAMP   DEFAULT NOW()
);

-- Backend branch compatibility store. Newer admin, pharmacy and delivery
-- workflows keep flexible UI records here while remaining PostgreSQL-backed.
-- This table is additive and does not replace any domain table above.
CREATE TABLE backend_admin_records (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    module      VARCHAR(40) NOT NULL,
    record_id   VARCHAR(80) NOT NULL,
    payload     JSONB       NOT NULL DEFAULT '{}'::jsonb,
    created_at  TIMESTAMP   NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMP   NOT NULL DEFAULT NOW(),
    UNIQUE (module, record_id)
);
CREATE TRIGGER trg_backend_admin_records_updated_at
    BEFORE UPDATE ON backend_admin_records
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE INDEX idx_backend_admin_records_module ON backend_admin_records(module);


-- ============================================================
-- PERFORMANCE INDEXES
-- ============================================================

-- ── Auth & Users ─────────────────────────────────────────────
CREATE INDEX idx_users_email           ON users(email);
CREATE INDEX idx_users_phone           ON users(phone);
CREATE INDEX idx_users_account_status  ON users(account_status);
CREATE INDEX idx_users_is_verified     ON users(is_verified);

-- ── Profile Extensions ───────────────────────────────────────
CREATE INDEX idx_farmer_profiles_user       ON farmer_profiles(user_id);
CREATE INDEX idx_admin_profiles_user        ON admin_profiles(user_id);
CREATE INDEX idx_delivery_profiles_user     ON delivery_profiles(user_id);
CREATE INDEX idx_delivery_profiles_online   ON delivery_profiles(is_online);
CREATE INDEX idx_pharmacy_orgs_user         ON pharmacy_organizations(user_id);
CREATE INDEX idx_pharmacist_pharmacy        ON pharmacist_profiles(pharmacy_id);
CREATE INDEX idx_researcher_profiles_user   ON researcher_profiles(user_id);
CREATE INDEX idx_doctor_profiles_user       ON doctor_profiles(user_id);
CREATE INDEX idx_doctor_profiles_location   ON doctor_profiles(latitude, longitude);
CREATE INDEX idx_doctor_profiles_available  ON doctor_profiles(is_available);
CREATE INDEX idx_doctor_profiles_verified   ON doctor_profiles(is_verified);

-- ── Subscriptions & Payments ─────────────────────────────────
CREATE INDEX idx_subscriptions_user     ON subscriptions(user_id);
CREATE INDEX idx_subscriptions_status   ON subscriptions(status);
CREATE INDEX idx_subscriptions_expires  ON subscriptions(expires_at);
CREATE INDEX idx_payments_user          ON payments(user_id);
CREATE INDEX idx_payments_status        ON payments(status);
CREATE INDEX idx_feature_usage_user     ON feature_usage(user_id);

-- ── Farm Management ──────────────────────────────────────────
CREATE INDEX idx_farms_farmer           ON farms(farmer_id);
CREATE INDEX idx_farms_active           ON farms(is_active);
CREATE INDEX idx_sheds_farm             ON sheds(farm_id);
CREATE INDEX idx_flocks_farm            ON flocks(farm_id);
CREATE INDEX idx_flocks_shed            ON flocks(shed_id);
CREATE INDEX idx_flocks_status          ON flocks(status);

-- ── Labor Management ─────────────────────────────────────────
CREATE INDEX idx_workers_farm               ON workers(farm_id);
CREATE INDEX idx_worker_attendance_worker   ON worker_attendance(worker_id, attendance_date);
CREATE INDEX idx_worker_tasks_worker        ON worker_tasks(worker_id);

-- ── Feed Management ──────────────────────────────────────────
CREATE INDEX idx_feed_stock_farm        ON feed_stock(farm_id);
CREATE INDEX idx_feed_consumption_flock ON feed_consumption(flock_id, consumed_date);

-- ── Cost Management ──────────────────────────────────────────
CREATE INDEX idx_expenses_farm          ON expenses(farm_id);
CREATE INDEX idx_expenses_date          ON expenses(farm_id, expense_date);
CREATE INDEX idx_revenues_farm          ON revenues(farm_id);
CREATE INDEX idx_revenues_date          ON revenues(farm_id, revenue_date);
CREATE INDEX idx_loans_farm             ON loans(farm_id);
CREATE INDEX idx_loans_status           ON loans(status);
CREATE INDEX idx_tax_records_farm_year  ON tax_records(farm_id, tax_year);

-- ── Disease Detection ────────────────────────────────────────
CREATE INDEX idx_disease_scans_user     ON disease_scans(user_id);
CREATE INDEX idx_disease_scans_status   ON disease_scans(scan_status);
CREATE INDEX idx_disease_scans_created  ON disease_scans(created_at DESC);

-- ── Doctor & Consultations ───────────────────────────────────
CREATE INDEX idx_consultations_farmer   ON consultations(farmer_id);
CREATE INDEX idx_consultations_doctor   ON consultations(doctor_id);
CREATE INDEX idx_consultations_status   ON consultations(status);
CREATE INDEX idx_consultations_date     ON consultations(appointment_date);
CREATE INDEX idx_consultations_urgency  ON consultations(urgency_level);

-- ── Messaging ────────────────────────────────────────────────
CREATE INDEX idx_conversations_p1       ON conversations(participant_one_id);
CREATE INDEX idx_conversations_p2       ON conversations(participant_two_id);
CREATE INDEX idx_messages_conversation  ON messages(conversation_id, sent_at DESC);
CREATE INDEX idx_messages_unread        ON messages(conversation_id, is_read);

-- ── Pharmacy & Delivery ──────────────────────────────────────
CREATE INDEX idx_pharmacy_medicines_pharm   ON pharmacy_medicines(pharmacy_id);
CREATE INDEX idx_pharmacy_medicines_avail   ON pharmacy_medicines(is_available);
CREATE INDEX idx_medicine_orders_buyer      ON medicine_orders(buyer_id);
CREATE INDEX idx_medicine_orders_pharmacy   ON medicine_orders(pharmacy_id);
CREATE INDEX idx_delivery_orders_person     ON delivery_orders(delivery_person_id);
CREATE INDEX idx_delivery_orders_status     ON delivery_orders(status);

-- ── Community & Blog ─────────────────────────────────────────
CREATE INDEX idx_posts_author       ON posts(author_id);
CREATE INDEX idx_posts_category     ON posts(category_id);
CREATE INDEX idx_posts_created      ON posts(created_at DESC);
CREATE INDEX idx_posts_status       ON posts(status);
CREATE INDEX idx_comments_post      ON comments(post_id);
CREATE INDEX idx_hashtags_name      ON hashtags(name);
CREATE INDEX idx_hashtags_usage     ON hashtags(usage_count DESC);

-- ── Articles & Research ──────────────────────────────────────
CREATE INDEX idx_articles_author        ON articles(author_id);
CREATE INDEX idx_articles_status        ON articles(status);
CREATE INDEX idx_articles_content_type  ON articles(content_type);
CREATE INDEX idx_articles_published     ON articles(published_at DESC);

-- ── Notifications & Audit ────────────────────────────────────
CREATE INDEX idx_notifications_user     ON notifications(user_id);
CREATE INDEX idx_notifications_unread   ON notifications(user_id, is_read);
CREATE INDEX idx_activity_logs_user     ON activity_logs(user_id);
CREATE INDEX idx_activity_logs_module   ON activity_logs(module);
CREATE INDEX idx_activity_logs_created  ON activity_logs(created_at DESC);


-- ============================================================
-- SEED DATA
-- ============================================================

-- ── Default Roles ─────────────────────────────────────────────
INSERT INTO roles (name, panel_type, description) VALUES
('farmer',           'farmer',     'Standard poultry farmer / farm owner'),
('doctor',           'doctor',     'Registered veterinary doctor'),
('delivery',         'delivery',   'Delivery rider'),
('pharmacy',         'pharmacy',   'Pharmacy organization account'),
('pharmacist',       'pharmacist', 'Individual pharmacist under a pharmacy'),
('researcher',       'researcher', 'Verified academic or industry researcher'),
('admin_super',      'admin',      'Super admin — full platform access'),
('admin_operations', 'admin',      'Operations — users, doctors, delivery, pharmacy, support'),
('admin_finance',    'admin',      'Finance — subscriptions, payments, refunds, cashouts'),
('admin_content',    'admin',      'Content — blog, articles, research moderation'),
('admin_research',   'admin',      'Research — verify researchers and approve publications'),
('admin_delivery',   'admin',      'Delivery — assign riders and monitor operations'),
('admin_pharmacy',   'admin',      'Pharmacy — medicines, pricing, suppliers'),
('admin_support',    'admin',      'Support agent — user issues, complaints, escalations');

-- ── Default Expense Categories ───────────────────────────────
INSERT INTO expense_categories (name, linked_module, icon) VALUES
('Feed',        'feed_management',  'grain'),
('Medicines',   'pharmacy',         'pill'),
('Labor',       'labor_management', 'users'),
('Utilities',   NULL,               'lightning'),
('Chicks',      NULL,               'egg'),
('Vaccines',    'pharmacy',         'syringe'),
('Litter',      NULL,               'layers'),
('Transport',   NULL,               'truck'),
('Repairs',     NULL,               'tool'),
('Other',       NULL,               'dots');

-- ── Default Revenue Sources ───────────────────────────────────
INSERT INTO revenue_sources (name) VALUES
('Bird Sales'),
('Egg Sales'),
('By-Products'),
('Refunds'),
('Other');

-- ── Default Subscription Plans ───────────────────────────────
INSERT INTO subscription_plans
    (name, price, currency, duration_days, features_unlocked, disease_scan_limit)
VALUES
('free',
 0.00, 'BDT', NULL,
 '["disease_scan_free"]',
 3),
('monthly_basic',
 299.00, 'BDT', 30,
 '["disease_scan","cost_management","labor_management"]',
 50),
('monthly_premium',
 599.00, 'BDT', 30,
 '["disease_scan","cost_management","labor_management","tax_calculation","blog","researcher_panel"]',
 NULL),
('yearly',
 4999.00, 'BDT', 365,
 '["disease_scan","cost_management","labor_management","tax_calculation","blog","researcher_panel"]',
 NULL),
('one_time_scan',
 49.00, 'BDT', NULL,
 '["disease_scan"]',
 5);

-- ── Default Post Categories ───────────────────────────────────
INSERT INTO post_categories (name) VALUES
('Feed Prices'),
('Disease Help'),
('Market News'),
('Equipment'),
('Birds'),
('Success Stories'),
('Team Featherflow');

-- ── Sample Disease Reference Data ────────────────────────────
INSERT INTO diseases
    (name, description, symptoms, what_to_do, what_not_to_do, severity_level, requires_immediate_vet)
VALUES
('Newcastle Disease',
 'Highly contagious viral disease affecting respiratory, nervous, and digestive systems.',
 '["Sudden death","Twisted neck","Breathing difficulty","Green diarrhea","Drop in egg production"]',
 'Isolate affected birds immediately. Contact vet urgently. Begin supportive care. Vaccinate healthy flock.',
 'Do not move birds between farms. Do not sell affected birds. Avoid contact with other poultry flocks.',
 'critical', TRUE),

('Fowl Pox',
 'Slow-spreading viral infection characterized by wart-like scabs on unfeathered skin areas.',
 '["Wart-like lesions on comb and wattles","Lesions in mouth and throat","Reduced feed intake","Drop in egg production"]',
 'Separate affected birds. Keep lesions clean and dry. Ensure dry housing. Vaccinate healthy unaffected birds.',
 'Do not puncture or squeeze lesions. Avoid overcrowding. Minimize bird stress.',
 'medium', FALSE),

('Coccidiosis',
 'Intestinal parasitic disease caused by Eimeria species — especially common in young broilers.',
 '["Bloody diarrhea","Lethargy","Ruffled feathers","Weight loss","Dehydration","High mortality in young birds"]',
 'Administer anticoccidial medication immediately. Provide clean fresh water. Improve litter management.',
 'Do not reuse contaminated litter. Avoid wet or damp litter conditions. Do not delay treatment.',
 'high', TRUE),

('Avian Influenza',
 'Highly contagious viral infection with potential for rapid flock mortality and zoonotic risk.',
 '["Sudden high mortality","Severe respiratory distress","Swollen head and face","Discoloration of comb and wattles","Neurological signs"]',
 'Report to government veterinary authority immediately. Quarantine the farm. Do not move birds or eggs.',
 'Do not attempt home treatment. Do not visit other farms. Do not sell or consume birds from affected flock.',
 'critical', TRUE),

('Marek Disease',
 'Viral disease causing tumors and paralysis — spreads via feather follicle dander.',
 '["Progressive leg or wing paralysis","Weight loss","Enlarged feather follicles","Eye lesions","Sudden death"]',
 'Vaccinate chicks at hatch (day-old). Improve biosecurity. Remove and dispose of affected birds properly.',
 'Do not introduce unvaccinated birds into vaccinated flocks. Do not delay vaccination at hatch.',
 'high', FALSE);


-- ============================================================
-- VERIFICATION QUERY
-- Run this after executing the schema to confirm all 68 tables exist.
-- Expected result: 68 rows.
-- ============================================================
--
--   SELECT COUNT(*) AS total_tables
--   FROM information_schema.tables
--   WHERE table_schema = 'public'
--     AND table_type = 'BASE TABLE';
--
--   -- Or list all tables by name:
--   SELECT table_name
--   FROM information_schema.tables
--   WHERE table_schema = 'public'
--     AND table_type = 'BASE TABLE'
--   ORDER BY table_name;
--
-- ============================================================
-- SCHEMA SUMMARY
-- ============================================================
--
--  ✅ Total Tables        : 68
--  ✅ Total Modules       : 16
--  ✅ Foreign Keys        : 85+
--  ✅ Indexes             : 55+
--  ✅ Trigger Function    : fn_set_updated_at() applied to 24 tables
--  ✅ Seed Data           : Roles (14), Expense Categories (10),
--                           Revenue Sources (5), Subscription Plans (5),
--                           Post Categories (7), Sample Diseases (5)
--
--  ⚠  Circular Dependency Handled:
--     chatbot_sessions ↔ disease_scans — resolved via ALTER TABLE.
--
--  📌 HOW TO RUN IN PGADMIN:
--     1. Create database:  CREATE DATABASE featherflow;
--     2. Open pgAdmin → Connect to featherflow
--     3. Open Query Tool
--     4. Paste this entire file
--     5. Press F5
--     6. Check Messages — should say "Query returned successfully"
--     7. Run the verification query above to confirm 68 tables
--
-- ============================================================
-- END OF FEATHERFLOW SCHEMA v2.0.0
-- ============================================================
