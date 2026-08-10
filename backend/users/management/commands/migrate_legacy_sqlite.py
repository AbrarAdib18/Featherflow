import json
import sqlite3
import uuid
from pathlib import Path

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError
from django.db import connection, transaction


TABLES = [
    ('users_user', 'users'),
    ('profiles_doctorprofile', 'doctor_profiles'),
    ('farms_farm', 'farms'),
    ('workers_worker', 'workers'),
    ('workers_workerattendance', 'worker_attendance'),
    ('workers_workertask', 'worker_tasks'),
    ('workers_workerpayment', 'worker_payments'),
    ('feed_feedtype', 'feed_types'),
    ('feed_feedstock', 'feed_stock'),
    ('feed_feedschedule', 'feed_schedules'),
    ('expenses_expensecategory', 'expense_categories'),
    ('expenses_revenuesource', 'revenue_sources'),
    ('expenses_expense', 'expenses'),
    ('expenses_revenue', 'revenues'),
    ('expenses_loan', 'loans'),
    ('expenses_taxrecord', 'tax_records'),
    ('consultations_consultation', 'consultations'),
    ('community_postcategory', 'post_categories'),
    ('community_post', 'posts'),
    ('community_comment', 'comments'),
    ('community_reaction', 'reactions'),
    ('community_bookmark', 'bookmarks'),
    ('community_follow', 'follows'),
    ('notifications_notification', 'notifications'),
    ('audit_adminpanelrecord', 'backend_admin_records'),
    ('audit_activitylog', 'activity_logs'),
]

COLUMN_MAP = {
    'users': {'password': 'password_hash', 'date_joined': 'created_at'},
    'activity_logs': {
        'entity_type': 'target_type', 'entity_id': 'target_id',
        'old_values': 'old_value', 'new_values': 'new_value',
    },
}

JSON_COLUMNS = {
    'users': {'bank_mobile_payment_details'},
    'doctor_profiles': set(),
    'farms': set(),
    'feed_types': {'nutritional_info'},
    'posts': {'media_urls'},
    'backend_admin_records': {'payload'},
    'activity_logs': {'old_value', 'new_value'},
}


def decode_json(value):
    if value in (None, '') or isinstance(value, (dict, list)):
        return value
    try:
        return json.loads(value)
    except (TypeError, ValueError):
        return value


def uuid_or_none(value):
    try:
        return str(uuid.UUID(str(value)))
    except (TypeError, ValueError, AttributeError):
        return None


class Command(BaseCommand):
    help = 'Copy legacy backend/db.sqlite3 data into the connected PostgreSQL schema.'

    def add_arguments(self, parser):
        parser.add_argument('--source', default=str(settings.BASE_DIR / 'db.sqlite3'))
        parser.add_argument('--dry-run', action='store_true')

    def handle(self, *args, **options):
        source = Path(options['source']).resolve()
        if not source.is_file():
            raise CommandError(f'Legacy SQLite database not found: {source}')
        if connection.vendor != 'postgresql':
            raise CommandError('The destination database must be PostgreSQL.')

        legacy = sqlite3.connect(f'file:{source.as_posix()}?mode=ro', uri=True)
        legacy.row_factory = sqlite3.Row
        legacy_tables = {
            row['name'] for row in legacy.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            )
        }
        counts = {}

        with transaction.atomic():
            role_map = self._roles(legacy, legacy_tables, options['dry_run'])
            counts['roles'] = len(role_map)
            if 'users_user' in legacy_tables:
                counts['users'] = self._copy_table(
                    legacy, 'users_user', 'users', options['dry_run']
                )
            self.farmer_map = self._farmer_profiles(
                legacy, legacy_tables, options['dry_run']
            )
            counts['farmer_profiles'] = len(self.farmer_map)
            for source_table, target_table in TABLES:
                if source_table == 'users_user':
                    continue
                if source_table not in legacy_tables:
                    continue
                count = self._copy_table(
                    legacy, source_table, target_table, options['dry_run']
                )
                counts[target_table] = count
            counts['user_roles'] = self._user_roles(
                legacy, legacy_tables, role_map, options['dry_run']
            )
            if options['dry_run']:
                transaction.set_rollback(True)

        legacy.close()
        mode = 'Would migrate' if options['dry_run'] else 'Migrated'
        for table, count in counts.items():
            self.stdout.write(f'{mode} {count} row(s) into {table}.')

    def _target_columns(self, table):
        with connection.cursor() as cursor:
            cursor.execute(
                "SELECT column_name FROM information_schema.columns "
                "WHERE table_schema = current_schema() AND table_name = %s",
                [table],
            )
            columns = {row[0] for row in cursor.fetchall()}
        if not columns:
            raise CommandError(
                f'Missing PostgreSQL table {table}. Apply featherflow_schema.sql '
                'and postgres_backend_extension.sql first.'
            )
        return columns

    def _roles(self, legacy, tables, dry_run):
        if 'users_role' not in tables:
            return {}
        role_map = {}
        with connection.cursor() as cursor:
            for row in legacy.execute('SELECT id, name, description, created_at FROM users_role'):
                panel = row['name'].split('_', 1)[0]
                if panel.startswith('admin') or row['name'].startswith('admin_'):
                    panel = 'admin'
                if panel not in {'farmer', 'doctor', 'delivery', 'pharmacy', 'pharmacist', 'researcher', 'admin'}:
                    panel = 'admin'
                cursor.execute(
                    'INSERT INTO roles (name, panel_type, description, created_at) '
                    'VALUES (%s, %s, %s, %s) ON CONFLICT (name) DO UPDATE '
                    'SET description = COALESCE(roles.description, EXCLUDED.description) '
                    'RETURNING id',
                    [row['name'], panel, row['description'], row['created_at']],
                )
                role_map[row['id']] = cursor.fetchone()[0]
        return role_map

    def _copy_table(self, legacy, source, target, dry_run):
        rows = legacy.execute(f'SELECT * FROM "{source}"').fetchall()
        if not rows:
            return 0
        target_columns = self._target_columns(target)
        rename = COLUMN_MAP.get(target, {})
        json_columns = JSON_COLUMNS.get(target, set())
        copied = 0
        with connection.cursor() as cursor:
            for row in rows:
                data = {}
                for old_name in row.keys():
                    name = rename.get(old_name, old_name)
                    if name not in target_columns:
                        continue
                    value = row[old_name]
                    if name in json_columns:
                        value = decode_json(value)
                    data[name] = value

                if target == 'users':
                    profile = decode_json(row['profile_data']) if 'profile_data' in row.keys() else {}
                    payment = decode_json(data.get('bank_mobile_payment_details')) or {}
                    if not isinstance(payment, dict):
                        payment = {'legacy_payment_details': payment}
                    if profile:
                        payment['_backend_profile_data'] = profile
                    data['bank_mobile_payment_details'] = payment or None
                elif target in {'reactions', 'bookmarks'} and 'post_id' in row.keys():
                    data['target_id'] = row['post_id']
                    data['target_type'] = 'post'
                elif target == 'activity_logs':
                    data['target_id'] = uuid_or_none(data.get('target_id'))
                elif target == 'farms':
                    data['farmer_id'] = self.farmer_map.get(data.get('farmer_id'))
                    if data['farmer_id'] is None:
                        continue

                columns = list(data)
                placeholders = ', '.join(['%s'] * len(columns))
                names = ', '.join(f'"{name}"' for name in columns)
                cursor.execute(
                    f'INSERT INTO "{target}" ({names}) VALUES ({placeholders}) '
                    'ON CONFLICT DO NOTHING',
                    [data[name] for name in columns],
                )
                copied += max(cursor.rowcount, 0)
        return copied

    def _farmer_profiles(self, legacy, tables, dry_run):
        required = {'users_user', 'users_userrole', 'users_role'}
        if not required.issubset(tables):
            return {}
        rows = legacy.execute(
            "SELECT u.*, ur.user_id AS legacy_user_id FROM users_user u "
            "JOIN users_userrole ur ON ur.user_id = u.id "
            "JOIN users_role r ON r.id = ur.role_id WHERE r.name = 'farmer'"
        ).fetchall()
        mapping = {}
        with connection.cursor() as cursor:
            for row in rows:
                profile = decode_json(row['profile_data']) or {}
                profile_id = str(uuid.uuid5(uuid.NAMESPACE_URL, f'featherflow:farmer:{row["id"]}'))
                cursor.execute(
                    'INSERT INTO farmer_profiles '
                    '(id, user_id, farm_name, owner_name, farm_location, farm_address, '
                    'farm_type, number_of_birds, consent_data_collection, created_at, updated_at) '
                    'VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) '
                    'ON CONFLICT (user_id) DO UPDATE SET farm_name = EXCLUDED.farm_name '
                    'RETURNING id',
                    [
                        profile_id, row['id'],
                        profile.get('farm_name') or f'{row["full_name"]} Farm',
                        row['full_name'], row['present_address'], row['present_address'],
                        str(profile.get('farm_type') or 'mixed').lower(),
                        profile.get('flock_size'), True,
                        row['date_joined'], row['updated_at'],
                    ],
                )
                mapping[row['id']] = str(cursor.fetchone()[0])
        return mapping

    def _user_roles(self, legacy, tables, role_map, dry_run):
        if 'users_userrole' not in tables:
            return 0
        copied = 0
        with connection.cursor() as cursor:
            for row in legacy.execute(
                'SELECT user_id, role_id, assigned_at FROM users_userrole'
            ):
                role_id = role_map.get(row['role_id'])
                if role_id is None:
                    continue
                cursor.execute(
                    'INSERT INTO user_roles (user_id, role_id, assigned_at) '
                    'VALUES (%s, %s, %s) ON CONFLICT (user_id, role_id) DO NOTHING',
                    [row['user_id'], role_id, row['assigned_at']],
                )
                copied += max(cursor.rowcount, 0)
        return copied
