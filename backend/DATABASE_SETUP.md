# PostgreSQL setup

The backend follows the `connected_DB` architecture: PostgreSQL owns the
schema and Django maps it with unmanaged models.

1. Copy `.env.example` to `.env` and enter the PostgreSQL credentials (and
   every other value the app needs — `.env.example` is the full list).
2. For a new database, apply the schema files **in this exact order** (each
   later file depends on tables/columns the earlier ones create):
   ```
   psql "$DATABASE_URL" -f ../featherflow_schema.sql
   psql "$DATABASE_URL" -f postgres_backend_extension.sql
   psql "$DATABASE_URL" -f verification_extension.sql
   psql "$DATABASE_URL" -f farmers_panel_extension.sql
   psql "$DATABASE_URL" -f production_hardening_extension.sql
   ```
   All four extension files are additive and safe to re-run (`IF NOT EXISTS` /
   `DROP CONSTRAINT IF EXISTS` + re-`ADD CONSTRAINT` throughout). This exact
   sequence is verified end-to-end against a brand-new database as part of
   the production-readiness pass — see PRODUCTION_READINESS_REPORT.md §1.
   - `postgres_backend_extension.sql` — storage for backend-branch admin,
     pharmacy, delivery, community, and doctor workflows (`posts`/`comments`
     columns, `poll_votes`, `post_reposts`, `community_mutes`, `user_blocks`,
     `clinical_prescriptions`, `doctor_earnings`, `doctor_availability_slots`,
     `consultation_status_history`, …).
   - `verification_extension.sql` — signup/contact-verification support.
   - `farmers_panel_extension.sql` — Cost Management (expense/revenue
     receipts, loan application flow, cashout/expense payments).
   - `production_hardening_extension.sql` — fixes and hardening found during
     the 2026-09-14 production-readiness audit: widens `subscriptions.status`
     to allow `'replaced'` (a renewal/upgrade 500'd without this — see
     PRODUCTION_READINESS_REPORT.md §5), a unique index enforcing one active
     subscription per user, `amount > 0` checks on `payments`/`expenses`/
     `revenues`/`loans`, and an index for `backend_admin_records` owner-id
     lookups.
3. For a database that already has an older subset of these applied, apply
   only the extension file(s) you're missing (in order) — check
   `\d subscriptions` / `\d expenses` etc. in `psql`, or just re-run all four;
   every statement is idempotent.
4. Validate the connection with `python manage.py check --database default`,
   then `python manage.py migrate` to apply the real (managed) migrations —
   `billing`, `tax`, `audit`, `community`, `consultations`, `profiles`, and
   several other newer apps own real Django-migrated tables that
   `featherflow_schema.sql` does not touch at all; this is not a no-op for
   those apps. `token_blacklist` (ships with `djangorestframework-simplejwt`,
   backs the logout endpoint) also needs this migrate step.
5. Run the ASGI application for REST + Socket.IO real-time chat:

   ```powershell
   cd backend
   uvicorn featherflow_backend.asgi:application --host 0.0.0.0 --port 8000 --reload
   ```

   `manage.py runserver` still serves the REST API, but the farmer↔doctor
   real-time chat needs the ASGI/Socket.IO runtime above.
6. Configure the `EMAIL_*` values from `.env.example` with a real SMTP account.
   Prescription records and notifications are committed even if the mail
   provider is unavailable; failed delivery is logged and can be retried.
7. To retain legacy SQLite data, preview and then run:

   ```powershell
   python manage.py migrate_legacy_sqlite --dry-run
   python manage.py migrate_legacy_sqlite
   ```

The importer reads `db.sqlite3` in read-only mode, uses idempotent PostgreSQL
inserts, and never deletes destination rows.

6. To move the pharmacy medicine catalogue from the JSON `pharmacy-products`
   module into the real `pharmacy_catalogue_medicines` table (added by
   `postgres_backend_extension.sql`), preview and then run:

   ```powershell
   python manage.py migrate_pharmacy_catalogue --dry-run
   python manage.py migrate_pharmacy_catalogue
   ```

   It is idempotent (rows matched on `pharmacy_user` + `legacy_record_id`) and
   leaves the source JSON records intact as a fallback.
