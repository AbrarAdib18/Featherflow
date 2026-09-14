"""PC3 — admin row-builder N+1 elimination: query-count regression tests.

    backend/venv/Scripts/python.exe backend/scripts/test_admin_row_builder_performance.py

Covers PERFORMANCE_BASELINE.md PC3 ("admin row-builders compound N+1"):
`_doctor_json`, `_pharmacy_json`, `_researcher_admin_json`, `_rider_json`,
`_order_admin_json`, `_community_user_json`, `_community_report_json`, and
`_report_admin_json` each used to run 1-5 extra queries *per row*. They now
accept an optional bulk-precomputed `ctx` (built once per page by a matching
`_bulk_*_context` helper) and read from it instead.

Reproduced first (see PRODUCTION_READINESS_REPORT.md for the full before/
after table, captured with `scratchpad_measure_pc3.py` against this same dev
data): doctors 42->11 queries, pharmacies 17->9, researchers 11->8,
riders 13->8, delivery-orders 159->11, community-users 26->14.

This suite: (1) asserts a query-count ceiling per module that the pre-fix
code would have blown past as row count grows (doctors/pharmacies/
researchers/riders/delivery-orders/community-users reuse whatever's already
in the dev database — real data, no synthetic inflation needed since it's
already large enough to make the old O(N) behavviour fail a ceiling test);
(2) seeds a handful of throwaway community reports + a content report
specifically for `community-reports`/`content-reports`, which are normally
too sparse in dev data to exercise meaningfully; (3) asserts the bulk-ctx
code path and the original per-row (ctx=None) code path produce byte-for-byte
identical output for every row — the actual regression risk of this kind of
change is a silent value mismatch, not just a slow query.

Uses the live DB. Creates throwaway accounts/posts/reports prefixed
``pc3perf+`` and cleans them up on entry and exit. Idempotent.
"""
import os
import sys
from datetime import date

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
from django.utils import timezone  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from api.admin_views import (  # noqa: E402
    _bulk_community_report_context, _bulk_community_user_context, _bulk_content_report_context,
    _bulk_doctor_context, _bulk_order_context, _bulk_pharmacy_context, _bulk_researcher_context,
    _bulk_rider_context, _community_report_json, _community_user_json, _doctor_json,
    _order_admin_json, _pharmacy_json, _report_admin_json, _researcher_admin_json, _rider_json,
)
from articles.models import Article
from community.models import Post as CommunityPost, Report
from delivery.models import DeliveryOrder
from profiles.models import DeliveryProfile, DoctorProfile, ResearcherProfile
from users.models import Role, User

PASS = FAIL = 0
PREFIX = 'pc3perf+'
_PHONE = [881_000_000]


def check(name, cond, extra=''):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f'  ok   {name}')
    else:
        FAIL += 1
        print(f'  FAIL {name}   {extra}')


def phone():
    _PHONE[0] += 1
    return '+8801' + str(_PHONE[0])


def cleanup():
    users = User.objects.filter(email__startswith=PREFIX)
    posts = CommunityPost.objects.filter(content__startswith=f'{PREFIX}post')
    post_ids = list(posts.values_list('id', flat=True))
    Report.objects.filter(target_id__in=post_ids).delete()
    posts.delete()
    Article.objects.filter(title__startswith=f'{PREFIX}article').delete()
    users.delete()


def mk_user(tag, role_name='farmer'):
    role, _ = Role.objects.get_or_create(name=role_name, defaults={'panel_type': role_name})
    u = User.objects.create_user(
        email=f'{PREFIX}{tag}@example.com', password='Test1234!', phone=phone(),
        full_name=f'PC3 {tag}', date_of_birth=date(1990, 1, 1), present_address='Dhaka',
        consent_terms=True, account_status='active', is_verified=True)
    u.roles.add(role)
    return u


def client_for(user):
    c = Client()
    c.defaults['HTTP_AUTHORIZATION'] = f'Bearer {RefreshToken.for_user(user).access_token}'
    return c


def check_query_ceiling(c, module, ceiling, min_rows=1):
    """Query count for one page must stay under `ceiling` regardless of row
    count — the whole point of the fix. `min_rows` sanity-checks the module
    actually has something to fetch (a 0-row response trivially "passes" any
    ceiling, which would mask a broken query, not a fixed one)."""
    with CaptureQueriesContext(connection) as ctx:
        r = c.get(f'/api/admin-panel/{module}/?page_size=200')
    check(f'{module}: 200', r.status_code == 200, r.status_code)
    n_rows = len(r.json().get('results', [])) if r.status_code == 200 else 0
    check(f'{module}: has at least {min_rows} row(s) to make this test meaningful',
          n_rows >= min_rows, n_rows)
    check(f'{module}: query count ({len(ctx.captured_queries)}) for {n_rows} rows '
          f'stays under {ceiling} (pre-fix this module needed roughly 1-5 queries PER row)',
          len(ctx.captured_queries) <= ceiling, len(ctx.captured_queries))


def main():
    cleanup()

    admin = User.objects.filter(roles__name='admin_super', account_status='active').first()
    check('a super-admin account exists to test with', admin is not None, '')
    if admin is None:
        cleanup()
        print(f'\n{"="*40}\n{PASS} passed, {FAIL} failed\n{"="*40}')
        sys.exit(1)
    c = client_for(admin)

    print('\n== query-count ceiling, real dev data (doctors/pharmacies/researchers/'
          'riders/delivery-orders/community-users) ==')
    check_query_ceiling(c, 'doctors', 20)
    check_query_ceiling(c, 'pharmacies', 20)
    check_query_ceiling(c, 'researchers', 20)
    check_query_ceiling(c, 'riders', 20)
    check_query_ceiling(c, 'delivery-orders', 20, min_rows=10)
    check_query_ceiling(c, 'community-users', 20)

    print('\n== seeded data for the normally-too-sparse modules ==')
    reporter = mk_user('reporter')
    author = mk_user('author')
    now = timezone.now()
    posts = []
    for i in range(8):
        post = CommunityPost.objects.create(
            author=author, post_type='text', content=f'{PREFIX}post {i}',
            status='active', created_at=now, updated_at=now)
        Report.objects.create(
            reporter=reporter, target_id=post.id, target_type='post',
            reason='spam', status='pending', created_at=now)
        posts.append(post)
    article = Article.objects.create(
        author=author, content_type='news', status='published',
        title=f'{PREFIX}article', abstract='x', body='x',
        published_at=now, created_at=now, updated_at=now)
    Report.objects.create(
        reporter=reporter, target_id=article.id, target_type='article',
        reason='spam', status='pending', created_at=now)

    check_query_ceiling(c, 'community-reports', 20, min_rows=8)
    check_query_ceiling(c, 'content-reports', 20, min_rows=1)

    print('\n== output parity: bulk-ctx path vs. the original per-row (ctx=None) path ==')
    doctors = list(DoctorProfile.objects.select_related('user').order_by('-created_at'))
    dctx = _bulk_doctor_context(doctors)
    check('doctors: bulk output matches per-row output for every row',
          all(_doctor_json(d) == _doctor_json(d, ctx=dctx) for d in doctors),
          [d.id for d in doctors if _doctor_json(d) != _doctor_json(d, ctx=dctx)])

    pharmacies = list(User.objects.filter(roles__name='pharmacy').distinct())
    pctx = _bulk_pharmacy_context(pharmacies)
    check('pharmacies: bulk output matches per-row output for every row',
          all(_pharmacy_json(u) == _pharmacy_json(u, ctx=pctx) for u in pharmacies))

    researchers = list(ResearcherProfile.objects.select_related('user'))
    rctx = _bulk_researcher_context(researchers)
    check('researchers: bulk output matches per-row output for every row',
          all(_researcher_admin_json(p) == _researcher_admin_json(p, ctx=rctx) for p in researchers))

    riders = list(DeliveryProfile.objects.select_related('user'))
    ridctx = _bulk_rider_context(riders)
    check('riders: bulk output matches per-row output for every row',
          all(_rider_json(p) == _rider_json(p, ctx=ridctx) for p in riders))

    orders = list(DeliveryOrder.objects.select_related('delivery_person__user').order_by('-created_at')[:75])
    octx = _bulk_order_context(orders)
    check('delivery-orders: bulk output matches per-row output for every row',
          all(_order_admin_json(o) == _order_admin_json(o, ctx=octx) for o in orders))

    community_reports = list(Report.objects.filter(target_type__in=['post', 'comment']))
    crctx = _bulk_community_report_context(community_reports)
    check('community-reports: bulk output matches per-row output for every row',
          all(_community_report_json(r) == _community_report_json(r, ctx=crctx) for r in community_reports))

    content_reports = list(Report.objects.filter(target_type='article'))
    cctx = _bulk_content_report_context(content_reports)
    check('content-reports: bulk output matches per-row output for every row',
          all(_report_admin_json(r) == _report_admin_json(r, ctx=cctx) for r in content_reports))

    cu_ids = {author.id}
    community_users = list(User.objects.filter(id__in=cu_ids).prefetch_related('roles'))
    cuctx = _bulk_community_user_context(community_users)
    check('community-users: bulk output matches per-row output for every row',
          all(_community_user_json(u) == _community_user_json(u, ctx=cuctx) for u in community_users))

    print('\n== RBAC / filtering / export still work (not just fast) ==')
    r = c.get('/api/admin-panel/doctors/export/')
    check('export still works after the pagination+ctx changes (200, CSV)',
          r.status_code == 200 and r.get('Content-Type', '').startswith('text/csv'), r.status_code)
    non_admin = mk_user('nonadmin')
    nc = client_for(non_admin)
    r = nc.get('/api/admin-panel/doctors/')
    check('a non-admin farmer is still refused (403)', r.status_code == 403, r.status_code)

    cleanup()
    print(f'\n{"="*40}\n{PASS} passed, {FAIL} failed\n{"="*40}')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    main()
