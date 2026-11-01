"""Deterministic database bootstrap for tests (F-014).

The schema is owned by hand-written SQL (`featherflow_schema.sql` + `*_extension.sql`; most models are
`managed = False`), plus real Django migrations for the apps the SQL does not touch. Production is built
by applying the SQL files in order and then running `manage.py migrate` (see backend/DATABASE_SETUP.md).
`build_database()` does exactly that into an empty database, so a test database is the *same* schema as
production, with every foreign key, CHECK, unique index and trigger active - nothing is relaxed.

`SQL_MANIFEST` is the single, ordered list of SQL files. `FeatherflowSchemaTests` fails if an
`*_extension.sql` file is added to the repo without being listed here.
"""
import os
from pathlib import Path

import psycopg2
from django.core.management import call_command
from django.db import connections

BACKEND_DIR = Path(__file__).resolve().parent.parent
REPO_DIR = BACKEND_DIR.parent

# Order matters (each later file depends on tables/columns the earlier ones create). The first five are
# the documented production order; the rest were verified (all apply cleanly, schema identical to the
# development database) and keep the dependency order of the features they extend.
SQL_MANIFEST = [
    REPO_DIR / 'featherflow_schema.sql',
    BACKEND_DIR / 'postgres_backend_extension.sql',
    BACKEND_DIR / 'verification_extension.sql',
    BACKEND_DIR / 'farmers_panel_extension.sql',
    BACKEND_DIR / 'production_hardening_extension.sql',
    BACKEND_DIR / 'farms_natural_key_extension.sql',
    BACKEND_DIR / 'feed_flock_extension.sql',
    BACKEND_DIR / 'feed_marketplace_extension.sql',
    BACKEND_DIR / 'feed_marketplace_ux_extension.sql',
    BACKEND_DIR / 'feed_owner_extension.sql',
    BACKEND_DIR / 'feed_stock_integrity_extension.sql',
    BACKEND_DIR / 'finance_admin_extension.sql',
    BACKEND_DIR / 'pharmacy_admin_portal_extension.sql',
    BACKEND_DIR / 'pharmacy_cost_management_extension.sql',
    BACKEND_DIR / 'pharmacy_marketplace_ui_extension.sql',
    BACKEND_DIR / 'delivery_proof_review_extension.sql',
    BACKEND_DIR / 'farmer_panel_integrity_extension.sql',
    BACKEND_DIR / 'repairs_nf_extension.sql',
]

# Reference rows the application expects to exist (loaded by the project's own idempotent commands).
REFERENCE_COMMANDS = ['seed_disease_reference', 'seed_feeding_guidelines']


# Demo accounts/data some of the custom script suites (scripts/test_*.py) expect to exist. All of these
# commands are create-only and idempotent. Not loaded for `manage.py test`.
DEMO_FIXTURE_COMMANDS = [
    'seed_platform_demo', 'seed_farmer_demo_data', 'seed_research_demo', 'seed_feed_marketplace_demo',
    'seed_pharmacy_demo_data', 'seed_finance_demo_data',
]


def _admin_connection(settings_dict):
    conn = psycopg2.connect(
        dbname='postgres', user=settings_dict['USER'], password=settings_dict['PASSWORD'],
        host=settings_dict['HOST'], port=settings_dict['PORT'])
    conn.autocommit = True
    return conn


def database_exists(settings_dict, name):
    with _admin_connection(settings_dict) as conn, conn.cursor() as cur:
        cur.execute('SELECT 1 FROM pg_database WHERE datname = %s', (name,))
        return cur.fetchone() is not None


def drop_database(settings_dict, name):
    conn = _admin_connection(settings_dict)
    with conn.cursor() as cur:
        cur.execute('SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = %s AND pid <> pg_backend_pid()', (name,))
        cur.execute(f'DROP DATABASE IF EXISTS "{name}"')
    conn.close()


def apply_sql_files(settings_dict, name, files=SQL_MANIFEST):
    conn = psycopg2.connect(dbname=name, user=settings_dict['USER'], password=settings_dict['PASSWORD'],
                            host=settings_dict['HOST'], port=settings_dict['PORT'])
    conn.autocommit = True
    try:
        with conn.cursor() as cur:
            for path in files:
                try:
                    cur.execute(Path(path).read_text(encoding='utf-8'))
                except psycopg2.Error as exc:
                    raise RuntimeError(f'{Path(path).name} failed while building {name}: {exc}') from exc
    finally:
        conn.close()


def build_database(alias, name, *, verbosity=0, recreate=True, demo_data=False):
    """Create `name` on `alias`'s server from SQL_MANIFEST + migrations + reference data.
    The development database is never touched; only the server connection settings are read."""
    connection = connections[alias]
    settings_dict = connection.settings_dict
    if name == settings_dict['NAME'] and not os.environ.get('ALLOW_BOOTSTRAP_ON_CONFIGURED_DB'):
        raise RuntimeError(f'refusing to rebuild the configured database "{name}"')
    if recreate:
        drop_database(settings_dict, name)
    conn = _admin_connection(settings_dict)
    with conn.cursor() as cur:
        cur.execute(f'CREATE DATABASE "{name}"')
    conn.close()
    apply_sql_files(settings_dict, name)
    # run Django's migrations (the apps the SQL does not own) against the new database
    original = settings_dict['NAME']
    connection.close()
    settings_dict['NAME'] = name
    try:
        call_command('migrate', database=alias, interactive=False, verbosity=verbosity)
        for cmd in REFERENCE_COMMANDS + (DEMO_FIXTURE_COMMANDS if demo_data else []):
            if cmd in DEMO_FIXTURE_COMMANDS:
                os.environ['ALLOW_DEMO_SEED'] = '1'  # throw-away database built here
            call_command(cmd, verbosity=0)
    finally:
        connection.close()
        settings_dict['NAME'] = original
    return name
