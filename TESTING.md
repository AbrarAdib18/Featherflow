# Featherflow testing

## Why this is not plain Django

The schema is owned by hand-written SQL (`featherflow_schema.sql` + `backend/*_extension.sql`; most models
are `managed = False`), plus real Django migrations for the apps the SQL does not touch. Production is built
by applying the SQL files in order and then running `migrate` (`backend/DATABASE_SETUP.md`). Django's stock
test-database creation only runs migrations, so it fails with `relation "users" does not exist` (F-014).

**Supported fix (a combination):** a deterministic bootstrap that performs the *production* build sequence
into a throw-away database, driven by a custom test runner, plus a documented runner for the script suites.

## Commands

    cd backend
    python manage.py check
    python manage.py migrate --check          # reads the configured database only
    python manage.py test                     # builds test_featherflow, runs the Django suite, drops it
    python manage.py test --collect-only      # prints COLLECTED n, runs nothing, builds nothing
    python manage.py test --keepdb            # reuse test_featherflow between runs (faster)
    python scripts/run_all_tests.py           # Django suite + every scripts/test_*.py (see below)

`manage.py test` ends with one line that keeps the counts separate:

    COLLECTED n | RAN n | PASSED n | FAILURES n | ERRORS n | SKIPPED n | EXPECTED-FAILURES n | UNEXPECTED-SUCCESSES n

## What the bootstrap does (`featherflow_backend/schema_bootstrap.py`)

1. `CREATE DATABASE test_featherflow` (on the configured server; the configured database is only used for
   its connection settings and is never written - the runner refuses a test name equal to it);
2. applies `SQL_MANIFEST` (ordered list of the SQL files) with psycopg2 - no `psql` binary needed;
3. runs `manage.py migrate` against it (the managed apps);
4. loads reference data with the project's own idempotent commands (`seed_disease_reference`,
   `seed_feeding_guidelines`).

Nothing is relaxed: every foreign key, CHECK, unique index and trigger of production is active (guarded by
`featherflow_backend/tests.py`). When you add a `*_extension.sql` file, add it to `SQL_MANIFEST` in dependency
order - `FeatherflowSchemaTests` fails if the manifest and the files on disk disagree.

## The two kinds of tests

* **Django unittest suite** (`manage.py test`): collected and run by the runner above.
* **Script suites** (`backend/scripts/test_*.py`, custom PASS/FAIL scripts that drive the API with Django's test
  client): not unittest, so Django does not collect them. `scripts/run_all_tests.py` runs every one in its own
  process against a throw-away database built the same way (`featherflow_scripts`, loaded with the demo
  fixture = the create-only seed commands in `DEMO_FIXTURE_COMMANDS`), and the scripts that need an empty
  platform (`test_seed_*`) against `featherflow_scripts_clean`. It prints one row per file
  (`N passed, M failed`) and exits non-zero on any failure. `--clone-dev` clones the development database for
  the scripts instead (read-only on the source). Run a single script by hand with
  `POSTGRES_DB=<scratch_db> python scripts/test_x.py` - never point one at a database you care about.

## Applying schema changes

New SQL goes in a new `backend/<name>_extension.sql`, idempotent (`IF NOT EXISTS`), appended to
`SQL_MANIFEST`. Apply to a real database with `psql -d <db> -f ...` (see `backend/DATABASE_SETUP.md`).

## Scheduled maintenance commands

    python manage.py expire_stale_offers   # release unanswered delivery offers (also swept lazily)
    python manage.py close_stale_shifts    # close admin shifts left open > 16 h
    python manage.py prune_old_data --dry-run

## Frontend

    flutter analyze
    flutter test
    flutter build web --release
