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

-- Doctor panel storage. These statements are additive and safe to rerun.
ALTER TABLE doctor_profiles
    ADD COLUMN IF NOT EXISTS availability_status VARCHAR(15) DEFAULT 'available';

ALTER TABLE consultation_case_details
    ADD COLUMN IF NOT EXISTS disease_tags JSONB NOT NULL DEFAULT '[]'::jsonb,
    ADD COLUMN IF NOT EXISTS case_status VARCHAR(20) NOT NULL DEFAULT 'open',
    ADD COLUMN IF NOT EXISTS farmer_name VARCHAR(150),
    ADD COLUMN IF NOT EXISTS farmer_notes TEXT,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP NOT NULL DEFAULT NOW();

UPDATE consultation_case_details case_detail
SET farmer_name = COALESCE(NULLIF(BTRIM(farmer.full_name), ''), farmer.email)
FROM consultations consultation
JOIN users farmer ON farmer.id = consultation.farmer_id
WHERE case_detail.consultation_id = consultation.id
  AND (case_detail.farmer_name IS NULL OR BTRIM(case_detail.farmer_name) = '');

ALTER TABLE consultation_case_details
    ALTER COLUMN farmer_name SET NOT NULL;

CREATE TABLE IF NOT EXISTS clinical_prescriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    consultation_id UUID NOT NULL REFERENCES consultations(id) ON DELETE CASCADE,
    doctor_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    dosage_notes TEXT,
    follow_up_instructions TEXT,
    referred_to VARCHAR(200),
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

ALTER TABLE clinical_prescriptions
    ADD COLUMN IF NOT EXISTS case_advice TEXT,
    ADD COLUMN IF NOT EXISTS email_sent_at TIMESTAMP,
    ADD COLUMN IF NOT EXISTS email_error TEXT;

CREATE TABLE IF NOT EXISTS clinical_prescription_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prescription_id UUID NOT NULL REFERENCES clinical_prescriptions(id) ON DELETE CASCADE,
    medicine_name VARCHAR(150) NOT NULL,
    dosage VARCHAR(100) NOT NULL,
    duration VARCHAR(50) NOT NULL,
    instructions TEXT
);

CREATE TABLE IF NOT EXISTS doctor_earnings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    doctor_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    consultation_id UUID NOT NULL UNIQUE REFERENCES consultations(id) ON DELETE RESTRICT,
    gross_amount DECIMAL(12,2) NOT NULL,
    platform_fee DECIMAL(12,2) NOT NULL DEFAULT 0,
    net_amount DECIMAL(12,2) NOT NULL,
    payout_status VARCHAR(15) NOT NULL DEFAULT 'pending',
    payout_date DATE,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS doctor_payout_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    doctor_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    amount DECIMAL(12,2) NOT NULL CHECK (amount > 0),
    status VARCHAR(15) NOT NULL DEFAULT 'requested',
    requested_at TIMESTAMP NOT NULL DEFAULT NOW(),
    processed_at TIMESTAMP
);

CREATE TABLE IF NOT EXISTS doctor_availability_slots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    doctor_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    weekday SMALLINT NOT NULL CHECK (weekday BETWEEN 0 AND 6),
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    mode VARCHAR(10) NOT NULL DEFAULT 'online',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    CHECK (start_time < end_time)
);

ALTER TABLE follow_ups
    ADD COLUMN IF NOT EXISTS doctor_id UUID REFERENCES users(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS scheduled_time TIME;
UPDATE follow_ups follow_up
SET doctor_id = consultation.doctor_id
FROM consultations consultation
WHERE follow_up.consultation_id = consultation.id
  AND follow_up.doctor_id IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_doctor_pending_follow_up_slot
    ON follow_ups(doctor_id, scheduled_date, scheduled_time)
    WHERE status = 'pending' AND scheduled_time IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_consultation_pending_follow_up
    ON follow_ups(consultation_id)
    WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_farmer_pending_follow_up_slot
    ON follow_ups(scheduled_date, scheduled_time, status);

CREATE INDEX IF NOT EXISTS idx_doctor_earnings_doctor ON doctor_earnings(doctor_id);
CREATE INDEX IF NOT EXISTS idx_doctor_payouts_doctor ON doctor_payout_requests(doctor_id);
CREATE INDEX IF NOT EXISTS idx_doctor_availability ON doctor_availability_slots(doctor_id, weekday);
CREATE INDEX IF NOT EXISTS idx_case_details_status ON consultation_case_details(case_status);

-- A requested appointment reserves its exact slot. This unique partial index
-- is the final concurrency guard against two farmers booking the same doctor.
CREATE UNIQUE INDEX IF NOT EXISTS uq_doctor_active_consultation_slot
    ON consultations(doctor_id, appointment_date, appointment_time)
    WHERE status IN ('requested', 'accepted', 'in_progress');
CREATE UNIQUE INDEX IF NOT EXISTS uq_farmer_active_consultation_slot
    ON consultations(farmer_id, appointment_date, appointment_time)
    WHERE status IN ('requested', 'accepted', 'in_progress');

ALTER TABLE consultations
    ADD COLUMN IF NOT EXISTS proposed_date DATE,
    ADD COLUMN IF NOT EXISTS proposed_time TIME,
    ADD COLUMN IF NOT EXISTS decision_reason TEXT;
ALTER TABLE consultations ADD COLUMN IF NOT EXISTS rated_at TIMESTAMP;
ALTER TABLE consultations DROP CONSTRAINT IF EXISTS consultations_rating_check;
ALTER TABLE consultations ADD CONSTRAINT consultations_rating_check CHECK (
    rating IS NULL OR rating BETWEEN 1 AND 5
);

ALTER TABLE consultations DROP CONSTRAINT IF EXISTS consultations_status_check;
ALTER TABLE consultations ADD CONSTRAINT consultations_status_check CHECK (status IN (
    'requested','accepted','rejected','reschedule_proposed','in_progress',
    'completed','cancelled','no_show'
));

CREATE TABLE IF NOT EXISTS consultation_status_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    consultation_id UUID NOT NULL REFERENCES consultations(id) ON DELETE CASCADE,
    actor_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    from_status VARCHAR(25) NOT NULL,
    to_status VARCHAR(25) NOT NULL,
    reason TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_consultation_status_history
    ON consultation_status_history(consultation_id, created_at);

-- Cash consultation receipts use the shared payments ledger. The unique
-- partial index is the database-level duplicate-payment guard.
ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_payment_method_check;
ALTER TABLE payments ADD CONSTRAINT payments_payment_method_check CHECK (
    payment_method IN ('bkash','nagad','bank_transfer','card','cash')
);
ALTER TABLE payments
    ADD COLUMN IF NOT EXISTS platform_charge DECIMAL(12,2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS net_amount DECIMAL(12,2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS confirmed_at TIMESTAMP;
CREATE UNIQUE INDEX IF NOT EXISTS uq_consultation_payment
    ON payments(reference_id)
    WHERE payment_type = 'consultation' AND reference_type = 'consultation';

-- A farmer and doctor retain one private conversation across repeat consultations.
CREATE UNIQUE INDEX IF NOT EXISTS uq_conversation_participant_pair
    ON conversations(LEAST(participant_one_id, participant_two_id),
                     GREATEST(participant_one_id, participant_two_id));
