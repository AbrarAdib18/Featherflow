# PostgreSQL setup

The backend follows the `connected_DB` architecture: PostgreSQL owns the
schema and Django maps it with unmanaged models.

1. Copy `.env.example` to `.env` and enter the PostgreSQL credentials.
2. For a new database, apply `../featherflow_schema.sql`.
3. For a database that already has the connected schema, apply
   `postgres_backend_extension.sql` once. It only adds storage required by
   backend-branch admin, pharmacy, delivery, and community workflows
   (`posts`/`comments` columns, `poll_votes`, `post_reposts`, `community_mutes`,
   `user_blocks`).
   Re-running it is safe.
4. Validate the connection with `python manage.py check --database default`,
   then `python manage.py migrate` to sync the state-only migrations for the
   unmanaged apps (no DDL runs — the router blocks it).
5. To retain legacy SQLite data, preview and then run:

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
