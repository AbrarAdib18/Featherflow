"""Guards for the F-014 test-database bootstrap: the throw-away test database must be the real schema."""
import uuid
from datetime import date

from django.db import IntegrityError, InternalError, connection, transaction
from django.test import TestCase

from users.models import User

from .schema_bootstrap import BACKEND_DIR, REPO_DIR, SQL_MANIFEST


class SchemaManifestTests(TestCase):
    def test_every_sql_file_in_the_repo_is_in_the_manifest(self):
        listed = {p.name for p in SQL_MANIFEST}
        on_disk = {p.name for p in BACKEND_DIR.glob('*_extension.sql')} | {(REPO_DIR / 'featherflow_schema.sql').name}
        self.assertEqual(on_disk - listed, set(), 'add the new SQL file to schema_bootstrap.SQL_MANIFEST (in dependency order)')
        self.assertEqual(listed - on_disk, set(), 'manifest lists a file that does not exist')

    def test_manifest_has_no_duplicates_and_starts_with_the_base_schema(self):
        self.assertEqual(len(SQL_MANIFEST), len({p.name for p in SQL_MANIFEST}))
        self.assertEqual(SQL_MANIFEST[0].name, 'featherflow_schema.sql')


class ProductionConstraintsAreActiveTests(TestCase):
    """The hand-written constraints, indexes and triggers exist in the test database and are enforced."""

    def _count(self, sql, params=()):
        with connection.cursor() as cur:
            cur.execute(sql, params)
            return cur.fetchone()[0]

    def test_catalog_has_the_production_objects(self):
        self.assertGreaterEqual(self._count("select count(*) from pg_tables where schemaname='public'"), 120)
        self.assertGreaterEqual(self._count("select count(*) from pg_constraint co join pg_namespace n on n.oid=co.connamespace where n.nspname='public' and co.contype='f'"), 100)
        self.assertGreaterEqual(self._count("select count(*) from pg_constraint co join pg_namespace n on n.oid=co.connamespace where n.nspname='public' and co.contype='c'"), 100)
        self.assertGreaterEqual(self._count("select count(*) from pg_trigger where not tgisinternal"), 30)
        self.assertEqual(self._count("select count(*) from pg_constraint where convalidated is false"), 0, 'no NOT VALID constraints')

    def test_foreign_keys_are_enforced(self):
        with self.assertRaises(IntegrityError), transaction.atomic(), connection.cursor() as cur:
            cur.execute("insert into farmer_profiles (id, user_id, farm_name, owner_name, farm_location) values (%s, %s, 'f', 'o', 'l')",
                        [str(uuid.uuid4()), str(uuid.uuid4())])

    def test_check_constraints_are_enforced(self):
        from users.models import User
        u = User.objects.create_user(email='f014+check@example.com', password='x', phone='+8801900014001', full_name='F014',
                                     date_of_birth=date(1990, 1, 1), present_address='x', consent_terms=True)
        with self.assertRaises(IntegrityError), transaction.atomic(), connection.cursor() as cur:
            cur.execute("update users set account_status='not-a-status' where id=%s", [str(u.id)])

    def test_unique_constraints_are_enforced(self):
        from users.models import User
        User.objects.create_user(email='f014+dup@example.com', password='x', phone='+8801900014002', full_name='A',
                                 date_of_birth=date(1990, 1, 1), present_address='x', consent_terms=True)
        with self.assertRaises(IntegrityError), transaction.atomic():
            User.objects.create_user(email='f014+dup@example.com', password='x', phone='+8801900014003', full_name='B',
                                     date_of_birth=date(1990, 1, 1), present_address='x', consent_terms=True)

    def test_activity_log_is_append_only_by_trigger(self):
        from audit.models import ActivityLog
        row = ActivityLog.objects.create(module='f014', action='probe', action_type='edit')
        with self.assertRaises(InternalError), transaction.atomic(), connection.cursor() as cur:
            cur.execute('delete from activity_logs where id=%s', [str(row.id)])

    def test_reference_data_is_loaded(self):
        self.assertGreaterEqual(self._count('select count(*) from roles'), 15)
        self.assertGreaterEqual(self._count('select count(*) from diseases'), 10)
        self.assertGreaterEqual(self._count('select count(*) from feeding_guidelines'), 5)
        self.assertGreater(self._count('select count(*) from django_migrations'), 50)


class DemoSeedGuardTests(TestCase):
    """Demo seeds create accounts with well-known passwords: they must refuse to run when DEBUG is off."""

    def test_seed_commands_refuse_outside_debug(self):
        from django.core.management import call_command
        from django.core.management.base import CommandError
        from django.test import override_settings
        import os
        os.environ.pop('ALLOW_DEMO_SEED', None)
        with override_settings(DEBUG=False):
            for cmd in ('seed_platform_demo', 'seed_farmer_demo_data', 'seed_research_demo', 'seed_feed_marketplace_demo',
                        'seed_pharmacy_demo_data', 'seed_finance_demo_data', 'seed_news_demo'):
                with self.assertRaises(CommandError, msg=cmd):
                    call_command(cmd)
        self.assertFalse(User.objects.filter(email__endswith='@example.com', full_name='Fariha Tasnim').exists())
