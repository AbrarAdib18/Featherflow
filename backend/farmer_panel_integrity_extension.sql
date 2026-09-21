-- ---------------------------------------------------------------------------
-- Farmer Panel — data integrity & consultation access pass.
--
-- Idempotent. Apply after featherflow_schema.sql, postgres_backend_extension.sql,
-- farmers_panel_extension.sql and feed_flock_extension.sql.
--
--   psql "$DATABASE_URL" -f farmer_panel_integrity_extension.sql
-- ---------------------------------------------------------------------------


-- 1. Consultation requests no longer require a preferred date/time -----------
--
-- Availability (doctor_availability_slots, doctor_profiles.is_available) is
-- display-only now: a farmer raises a request at any time and the doctor
-- accepts / rejects / reschedules it later. A request with no preferred slot
-- leaves these NULL until the doctor proposes one, so the NOT NULL that the
-- base schema declared has to go.
--
-- The uq_doctor_active_consultation_slot / uq_farmer_active_consultation_slot
-- partial unique indexes stay correct: PostgreSQL treats NULLs as distinct, so
-- any number of open-ended requests coexist while two requests naming the same
-- concrete slot still collide.
ALTER TABLE consultations ALTER COLUMN appointment_date DROP NOT NULL;
ALTER TABLE consultations ALTER COLUMN appointment_time DROP NOT NULL;


-- 2. One canonical bird type across the platform -----------------------------
--
-- 'hatchery' is a FARM type (farms.farm_type), not a bird type. It was allowed
-- on flocks.bird_type, but no feeding_guidelines row can ever carry it
-- (feeding_guidelines.bird_type CHECK excludes it), so a 'hatchery' flock
-- silently returned an empty feed chart and was skipped by feed notifications.
-- Migrate those rows to 'other' and narrow the CHECK to the canonical set,
-- which now matches feeding_guidelines and feed_products exactly.
UPDATE flocks SET bird_type = 'other' WHERE bird_type = 'hatchery';

ALTER TABLE flocks DROP CONSTRAINT IF EXISTS flocks_bird_type_check;
ALTER TABLE flocks ADD CONSTRAINT flocks_bird_type_check
    CHECK (bird_type IS NULL OR bird_type IN (
        'broiler', 'layer', 'chick', 'breeder', 'other'
    ));


-- 3. Labour payment -> expense mirroring, exactly once ------------------------
--
-- A settled labour payment now mirrors into `expenses` so wages reach cost
-- management and the dashboard cash balance (previously worker wages were
-- invisible to both). expenses.payment_id already exists but references
-- payments(id); the labour flow settles through billing_payment_intents
-- instead, so it needs its own key.
--
-- The partial unique index is the idempotency guard: a replayed webhook or a
-- duplicate confirm can never create a second mirrored expense for the same
-- intent.
ALTER TABLE expenses
    ADD COLUMN IF NOT EXISTS source_intent_id UUID;

CREATE UNIQUE INDEX IF NOT EXISTS uq_expenses_source_intent
    ON expenses(source_intent_id)
    WHERE source_intent_id IS NOT NULL;

COMMENT ON COLUMN expenses.source_intent_id IS
    'billing_payment_intents.id this expense was mirrored from (labour payments). '
    'Unique when set - the exactly-once guard for mirroring.';
