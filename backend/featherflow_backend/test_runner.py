"""Test runner for the Featherflow backend (F-014).

`python manage.py test` creates a throw-away database (default `test_featherflow`) from the project's own
schema bootstrap (`schema_bootstrap.build_database`: the SQL manifest, then migrations, then reference
data), runs the tests against it, and drops it. The development database is never connected to for writes.

Options (in addition to Django's):
    --keepdb          reuse an already built test database (fast re-runs); build it if missing
    --collect-only    build the suite, print how many tests were COLLECTED, run nothing

At the end it prints one line that keeps the counts separate:
    COLLECTED n | RAN n | PASSED n | FAILURES n | ERRORS n | SKIPPED n | EXPECTED-FAILURES n | UNEXPECTED-SUCCESSES n
"""
import sys

from django.db import connections
from django.test.runner import DiscoverRunner

from .schema_bootstrap import build_database, database_exists, drop_database


class FeatherflowTestRunner(DiscoverRunner):
    @classmethod
    def add_arguments(cls, parser):
        super().add_arguments(parser)
        parser.add_argument('--collect-only', action='store_true', dest='collect_only',
                            help='Only count the collected tests; do not create a database or run anything.')

    def __init__(self, *args, collect_only=False, **kwargs):
        super().__init__(*args, **kwargs)
        self.collect_only = collect_only
        self._built = {}

    # ── database lifecycle ──────────────────────────────────────────────────────────────────────
    def setup_databases(self, **kwargs):
        config = []
        for alias in connections:
            connection = connections[alias]
            settings_dict = connection.settings_dict
            test_name = (settings_dict.get('TEST') or {}).get('NAME') or ('test_' + settings_dict['NAME'])
            if test_name == settings_dict['NAME']:
                raise RuntimeError('the test database name equals the configured database; refusing to continue')
            exists = database_exists(settings_dict, test_name)
            if self.keepdb and exists:
                if self.verbosity >= 1:
                    print(f'Reusing test database "{test_name}" (--keepdb)')
            else:
                if self.verbosity >= 1:
                    print(f'Building test database "{test_name}" from the SQL manifest + migrations...')
                build_database(alias, test_name, verbosity=max(self.verbosity - 1, 0))
            config.append((connection, settings_dict['NAME'], test_name))
            connection.close()
            settings_dict['NAME'] = test_name
        return config

    def teardown_databases(self, old_config, **kwargs):
        for connection, original, test_name in old_config:
            connection.close()
            connection.settings_dict['NAME'] = original
            if not self.keepdb:
                drop_database(connection.settings_dict, test_name)

    # ── counts ──────────────────────────────────────────────────────────────────────────────────
    def run_tests(self, test_labels, **kwargs):
        self.setup_test_environment()
        suite = self.build_suite(test_labels)
        collected = suite.countTestCases()
        if self.collect_only:
            print(f'COLLECTED {collected}')
            self.teardown_test_environment()
            return 0
        databases = self.get_databases(suite)
        old_config = self.setup_databases(aliases=databases)
        result = None
        try:
            self.run_checks(databases)
            result = self.run_suite(suite)
        finally:
            self.teardown_databases(old_config)
            self.teardown_test_environment()
        failures, errors = len(result.failures), len(result.errors)
        skipped, xfail, xsucc = len(result.skipped), len(result.expectedFailures), len(result.unexpectedSuccesses)
        passed = result.testsRun - failures - errors - skipped - xfail
        print(f'COLLECTED {collected} | RAN {result.testsRun} | PASSED {passed} | FAILURES {failures} | ERRORS {errors} | '
              f'SKIPPED {skipped} | EXPECTED-FAILURES {xfail} | UNEXPECTED-SUCCESSES {xsucc}', file=sys.stderr)
        if collected != result.testsRun + skipped * 0:
            print(f'NOTE: collected {collected} but ran {result.testsRun}', file=sys.stderr)
        return self.suite_result(suite, result)
