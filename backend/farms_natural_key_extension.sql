-- ═══════════════════════════════════════════════════════════════════════════
-- Farm natural key: one farm per (farmer, name)  [seed_platform_demo fix]
--
-- `farms` had no uniqueness rule, so seeds/tests that matched on name could
-- create exact duplicates and later `get_or_create` raised MultipleObjects.
-- A farmer may still own SEVERAL farms - they just can't own two with the same
-- name.
--
-- Apply AFTER removing existing exact duplicates:
--     python manage.py dedupe_farms           (report)
--     python manage.py dedupe_farms --apply   (deletes only empty duplicates)
--     psql "$DATABASE_URL" -f backend/farms_natural_key_extension.sql
-- Re-running is safe.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE UNIQUE INDEX IF NOT EXISTS uq_farms_farmer_name
    ON farms (farmer_id, lower(btrim(farm_name)));
