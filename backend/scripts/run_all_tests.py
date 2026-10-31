"""Run the whole backend test suite WITHOUT touching the development database (F-014).

    python scripts/run_all_tests.py [--only substr] [--keep] [--clone-dev]

1. `manage.py test` (Django unittest suite): the runner builds its own throw-away database from the SQL
   manifest + migrations + reference data (featherflow_backend/schema_bootstrap.py) and drops it.
2. every `scripts/test_*.py` (custom PASS/FAIL scripts) runs against a throw-away database built the same
   way (`featherflow_scripts`), or - for scripts that need an EMPTY platform - `featherflow_scripts_clean`.
   `--clone-dev` instead clones the configured development database for step 2 (read-only on the source;
   needs demo data some scripts expect).
3. prints one summary table and exits non-zero if anything failed. Collected / ran / failed are reported
   separately for step 1 and per file for step 2.

See TESTING.md.
"""
import glob
import os
import re
import subprocess
import sys
import time

import django

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, ROOT)
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
django.setup()

import psycopg2  # noqa: E402
from django.conf import settings  # noqa: E402

from featherflow_backend.schema_bootstrap import build_database, drop_database  # noqa: E402

CFG = settings.DATABASES['default']
SOURCE = CFG['NAME']
SCRIPTS_DB = 'featherflow_scripts'
CLEAN_DB = 'featherflow_scripts_clean'
# scripts that need an EMPTY platform (they seed it themselves)
NEEDS_CLEAN = {'test_seed_platform_demo.py', 'test_seed_research_demo.py'}


def admin_conn():
    c = psycopg2.connect(dbname='postgres', user=CFG['USER'], password=CFG['PASSWORD'], host=CFG['HOST'], port=CFG['PORT'])
    c.autocommit = True
    return c


def clone_dev(name):
    cur = admin_conn().cursor()
    cur.execute('SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname IN (%s,%s) AND pid <> pg_backend_pid()', (name, SOURCE))
    cur.execute(f'DROP DATABASE IF EXISTS "{name}"')
    cur.execute(f'CREATE DATABASE "{name}" TEMPLATE "{SOURCE}"')


def run(cmd, env_extra=None, timeout=1800):
    env = {**os.environ, **(env_extra or {})}
    t = time.time()
    p = subprocess.run(cmd, cwd=ROOT, env=env, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=timeout)
    return p, round(time.time() - t, 1)


def main():
    keep = '--keep' in sys.argv
    use_dev_clone = '--clone-dev' in sys.argv
    only = sys.argv[sys.argv.index('--only') + 1] if '--only' in sys.argv else None
    py = sys.executable
    rows, failed = [], False

    p, t = run([py, 'manage.py', 'test', '--noinput'])
    out = (p.stderr or '') + (p.stdout or '')
    line = next((l for l in reversed(out.splitlines()) if l.startswith('COLLECTED')), 'no COLLECTED line')
    rows.append(('manage.py test', line, p.returncode, t))
    failed |= p.returncode != 0

    def prepare(name):
        if use_dev_clone and name == SCRIPTS_DB:
            clone_dev(name)
        else:
            build_database('default', name, demo_data=True)

    prepare(SCRIPTS_DB)
    for f in sorted(glob.glob(os.path.join(HERE, 'test_*.py'))):
        name = os.path.basename(f)
        if only and only not in name:
            continue
        db = SCRIPTS_DB
        if name in NEEDS_CLEAN:
            build_database('default', CLEAN_DB)  # schema + reference data only
            db = CLEAN_DB
        p, t = run([py, f], {'POSTGRES_DB': db})
        m = re.findall(r'(\d+) passed, (\d+) failed', p.stdout)
        res = f'{m[-1][0]} passed, {m[-1][1]} failed' if m else 'no summary'
        bad = p.returncode != 0 or not m or int(m[-1][1]) > 0
        rows.append((name, res, p.returncode, t))
        failed |= bool(bad)
    if not keep:
        for n in (SCRIPTS_DB, CLEAN_DB):
            drop_database(CFG, n)

    w = max(len(r[0]) for r in rows)
    print('\n' + '-' * (w + 70))
    for name, res, code, t in rows:
        print(f'{"FAIL" if code else "ok  "}  {name:<{w}}  {res:<60} {t:>6}s')
    print('-' * (w + 70))
    print('RESULT:', 'FAILED' if failed else 'all green')
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
