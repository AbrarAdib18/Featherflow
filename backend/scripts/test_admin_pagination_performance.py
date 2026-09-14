"""Admin list pagination + query-count regression suite.

    backend/venv/Scripts/python.exe backend/scripts/test_admin_pagination_performance.py

Covers PERFORMANCE_BASELINE.md PC2 ("~15 admin oversight list endpoints
return the entire table, unbounded"): every module dispatched through
``api.admin_views._collection_rows`` now returns bounded, paginated results
with ``count``/``page``/``page_size``/``has_more`` metadata, honours
``?page_size=`` up to a hard cap, and CSV export is capped rather than
literally unbounded.

The query-count assertions don't require N+1 to be fully eliminated (that's a
separate, larger fix tracked in PERFORMANCE_BASELINE.md PC3 and deliberately
NOT attempted in this pass) — they assert a *ceiling* scaled to the page size
requested, so a future regression that makes an endpoint scan/paginate at the
full-table level instead of the requested page gets caught immediately.

Uses the live DB. Read-only against existing data — makes no throw-away rows
of its own, so there is nothing to clean up.
"""
import os
import sys

import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
django.setup()

from django.conf import settings as dj_settings  # noqa: E402
if 'testserver' not in dj_settings.ALLOWED_HOSTS:
    dj_settings.ALLOWED_HOSTS.append('testserver')

from django.db import connection  # noqa: E402
from django.test import Client  # noqa: E402
from django.test.utils import CaptureQueriesContext  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from api.admin_views import DEFAULT_ADMIN_PAGE_SIZE, MAX_ADMIN_PAGE_SIZE, ADMIN_EXPORT_MAX_ROWS  # noqa: E402
from users.models import User  # noqa: E402

PASS = FAIL = 0


def check(name, cond, extra=''):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f'  ok   {name}')
    else:
        FAIL += 1
        print(f'  FAIL {name}   {extra}')


def client_for(user):
    c = Client()
    token = str(RefreshToken.for_user(user).access_token)
    c.defaults['HTTP_AUTHORIZATION'] = f'Bearer {token}'
    return c


# Query-count ceiling per page of results, independent of total table size —
# generous enough to tolerate the still-open per-row N+1s tracked as
# PERFORMANCE_BASELINE.md PC3/PC4 (not fixed in this pass), tight enough that
# an endpoint regressing to a full-table, non-paginated scan (proportional to
# thousands of rows instead of one page) fails loudly.
QUERY_CEILING = 60


def check_module(c, module, *, page_size=5):
    r = c.get(f'/api/admin-panel/{module}/?page=1&page_size={page_size}')
    check(f'{module}: 200', r.status_code == 200, r.status_code)
    if r.status_code != 200:
        return
    data = r.json()
    for key in ('results', 'count', 'page', 'page_size', 'has_more'):
        check(f'{module}: response has "{key}"', key in data, list(data.keys()))
    check(f'{module}: page_size honoured (<= {page_size})',
          len(data.get('results', [])) <= page_size, len(data.get('results', [])))
    check(f'{module}: page_size echoed correctly', data.get('page_size') == page_size, data.get('page_size'))

    with CaptureQueriesContext(connection) as ctx:
        c.get(f'/api/admin-panel/{module}/?page=1&page_size={page_size}')
    check(f'{module}: query count for one page of {page_size} stays under {QUERY_CEILING} '
          f'(actual {len(ctx.captured_queries)})',
          len(ctx.captured_queries) <= QUERY_CEILING, len(ctx.captured_queries))


def main():
    admin = User.objects.filter(roles__name='admin_super', account_status='active').first()
    check('a super-admin account exists to test with', admin is not None, '')
    if admin is None:
        print(f'\n{"="*40}\n{PASS} passed, {FAIL} failed\n{"="*40}')
        sys.exit(1)
    c = client_for(admin)

    print('\n== pagination shape + query-count ceiling, per module ==')
    for module in ('users', 'doctors', 'pharmacies', 'team', 'riders', 'researchers',
                    'articles', 'subscriptions', 'consultations', 'community-users'):
        check_module(c, module)

    print('\n== page_size caps at MAX_ADMIN_PAGE_SIZE ==')
    r = c.get(f'/api/admin-panel/users/?page_size={MAX_ADMIN_PAGE_SIZE + 5000}')
    check('oversized page_size request still succeeds (200)', r.status_code == 200, r.status_code)
    check(f'page_size capped at MAX_ADMIN_PAGE_SIZE ({MAX_ADMIN_PAGE_SIZE})',
          r.json().get('page_size') == MAX_ADMIN_PAGE_SIZE, r.json().get('page_size'))

    print('\n== default page_size (no query params) ==')
    r = c.get('/api/admin-panel/users/')
    check('default page_size applied', r.json().get('page_size') == DEFAULT_ADMIN_PAGE_SIZE,
          r.json().get('page_size'))

    print('\n== CSV export is capped, not literally unbounded ==')
    r = c.get('/api/admin-panel/users/export/')
    check('export 200', r.status_code == 200, r.status_code)
    check('export returns CSV', r.get('Content-Type', '').startswith('text/csv'), r.get('Content-Type'))
    exported_rows = r.content.decode('utf-8', errors='replace').count('\n') - 1  # minus header
    check(f'export row count <= ADMIN_EXPORT_MAX_ROWS ({ADMIN_EXPORT_MAX_ROWS})',
          exported_rows <= ADMIN_EXPORT_MAX_ROWS, exported_rows)

    print('\n== has_more is accurate ==')
    total = c.get('/api/admin-panel/users/').json()['count']
    if total > 3:
        r = c.get('/api/admin-panel/users/?page=1&page_size=3')
        check('has_more=true when more rows exist beyond this page',
              r.json()['has_more'] is True, r.json())
        import math
        last_page = math.ceil(total / 3)
        r_last = c.get(f'/api/admin-panel/users/?page={last_page}&page_size=3')
        check('has_more=false on the last page',
              r_last.json()['has_more'] is False, r_last.json())
    else:
        check('enough users exist to test has_more meaningfully (skipped, <=3 users)', True)

    print(f'\n{"="*40}\n{PASS} passed, {FAIL} failed\n{"="*40}')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    main()
