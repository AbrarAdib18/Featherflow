# PostgreSQL setup

The backend follows the `connected_DB` architecture: PostgreSQL owns the
schema and Django maps it with unmanaged models.

1. Copy `.env.example` to `.env` and enter the PostgreSQL credentials.
2. For a new database, apply `../featherflow_schema.sql`.
3. For a database that already has the connected schema, apply
   `postgres_backend_extension.sql` once. It only adds storage required by
   backend-branch admin, pharmacy, delivery, and doctor workflows. The script
   is idempotent and can be rerun after pulling backend updates.
4. Validate the connection with `python manage.py check --database default`.
5. Run the ASGI application for REST and Socket.IO support:

   ```powershell
   cd backend
   uvicorn featherflow_backend.asgi:application --host 0.0.0.0 --port 8000 --reload
   ```

   `manage.py runserver` is not the supported runtime for real-time chat.
6. Configure the `EMAIL_*` values from `.env.example` with a real SMTP
   account. Prescription records and notifications are committed even if the
   mail provider is temporarily unavailable; failed mail delivery is logged by
   Django and can be retried operationally.
7. To retain legacy SQLite data, preview and then run:

   ```powershell
   python manage.py migrate_legacy_sqlite --dry-run
   python manage.py migrate_legacy_sqlite
   ```

The importer reads `db.sqlite3` in read-only mode, uses idempotent PostgreSQL
inserts, and never deletes destination rows.
