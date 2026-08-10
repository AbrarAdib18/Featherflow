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
