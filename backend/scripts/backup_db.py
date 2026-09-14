#!/usr/bin/env python
"""Backup / restore helper for the FeatherFlow PostgreSQL database.

Wraps pg_dump/pg_restore with the project's .env credentials so there's one
correct, repeatable command instead of everyone remembering their own psql
flags. See OPERATIONS_RUNBOOK.md for the backup/retention/restore policy this
is meant to be run under (e.g. from cron / a scheduled task).

Usage:
    python scripts/backup_db.py backup [--out DIR]
    python scripts/backup_db.py restore --file PATH --into DBNAME

`backup` produces a timestamped, custom-format (-Fc) dump — compressed and
restorable with pg_restore, safe to take against a live database (pg_dump
runs inside a single consistent transaction snapshot; it doesn't block
readers/writers). `restore` always restores into --into, never the
configured POSTGRES_DB directly, so a restore rehearsal can't clobber a live
database by accident — restoring over the real database is a deliberate,
separate step (see the runbook).
"""
import argparse
import datetime
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from dotenv import load_dotenv  # noqa: E402

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
load_dotenv(os.path.join(BASE_DIR, '.env'))


def _env():
    for name in ('POSTGRES_DB', 'POSTGRES_USER', 'POSTGRES_PASSWORD', 'POSTGRES_HOST'):
        if not os.environ.get(name, '').strip():
            raise SystemExit(f'{name} must be set in backend/.env')
    env = os.environ.copy()
    env['PGPASSWORD'] = os.environ['POSTGRES_PASSWORD']
    return env


def _require_tool(name):
    if shutil.which(name) is None:
        raise SystemExit(
            f'{name} was not found on PATH. Install the PostgreSQL client tools '
            f'(the same major version as the server) and try again.')


def backup(out_dir):
    _require_tool('pg_dump')
    os.makedirs(out_dir, exist_ok=True)
    db = os.environ['POSTGRES_DB']
    host = os.environ['POSTGRES_HOST']
    port = os.environ.get('POSTGRES_PORT', '5432')
    user = os.environ['POSTGRES_USER']
    stamp = datetime.datetime.now().strftime('%Y%m%dT%H%M%S')
    out_path = os.path.join(out_dir, f'featherflow_{db}_{stamp}.dump')
    cmd = ['pg_dump', '-h', host, '-p', port, '-U', user, '-Fc', '-f', out_path, db]
    print('Running:', ' '.join(cmd))
    subprocess.run(cmd, env=_env(), check=True)
    size_mb = os.path.getsize(out_path) / (1024 * 1024)
    print(f'Backup written: {out_path} ({size_mb:.1f} MB)')
    return out_path


def restore(file_path, into_db):
    _require_tool('pg_restore')
    _require_tool('psql')
    if into_db == os.environ.get('POSTGRES_DB'):
        raise SystemExit(
            'Refusing to restore directly into POSTGRES_DB — restore into a '
            'separate database (e.g. featherflow_restore_test) and verify it '
            'first. See OPERATIONS_RUNBOOK.md for promoting a verified restore.')
    host = os.environ['POSTGRES_HOST']
    port = os.environ.get('POSTGRES_PORT', '5432')
    user = os.environ['POSTGRES_USER']
    env = _env()
    subprocess.run(
        ['psql', '-h', host, '-p', port, '-U', user, '-d', 'postgres', '-c',
         f'CREATE DATABASE {into_db};'],
        env=env, check=True)
    cmd = ['pg_restore', '-h', host, '-p', port, '-U', user,
           '-d', into_db, '--no-owner', '--no-privileges', file_path]
    print('Running:', ' '.join(cmd))
    subprocess.run(cmd, env=env, check=True)
    print(f'Restored into database: {into_db}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='cmd', required=True)

    p_backup = sub.add_parser('backup')
    p_backup.add_argument('--out', default=os.path.join(BASE_DIR, 'backups'))

    p_restore = sub.add_parser('restore')
    p_restore.add_argument('--file', required=True)
    p_restore.add_argument('--into', required=True)

    args = parser.parse_args()
    if args.cmd == 'backup':
        backup(args.out)
    elif args.cmd == 'restore':
        restore(args.file, args.into)
