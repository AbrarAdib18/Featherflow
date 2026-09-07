"""Checks for the farmer News / Research (Knowledge Portal) feed.

Run:  backend/venv/Scripts/python.exe backend/scripts/test_articles_feed.py

Uses Django's test Client against the live configured DB. Requires the
``seed_news_demo`` articles (the script seeds them itself if missing).
Creates one throw-away farmer prefixed ``newsfeedtest+`` and cleans it up.
"""
import os
import sys
import time

import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
django.setup()

from django.conf import settings as dj  # noqa: E402
if 'testserver' not in dj.ALLOWED_HOSTS:
    dj.ALLOWED_HOSTS.append('testserver')
dj.DEBUG = True  # so connection.queries is populated

from django.core.management import call_command  # noqa: E402
from django.db import connection, reset_queries  # noqa: E402
from django.test import Client  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from articles.models import Article  # noqa: E402
from users.models import Role, User, UserRole  # noqa: E402

PASS = FAIL = 0
PREFIX = 'newsfeedtest+'


def check(name, cond, extra=''):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f'  ok   {name}')
    else:
        FAIL += 1
        print(f'  FAIL {name}  {extra}')


if not Article.objects.filter(content_details__seed_marker='ff-news-seed').exists():
    call_command('seed_news_demo')

from datetime import date  # noqa: E402

role, _ = Role.objects.get_or_create(name='farmer', defaults={'panel_type': 'farmer'})
farmer, _ = User.objects.get_or_create(email=f'{PREFIX}f@featherflow.dev', defaults=dict(
    full_name='News Test', phone='+8801999900011', date_of_birth=date(1990, 1, 1),
    present_address='Dhaka', consent_terms=True, account_status='active'))
farmer.account_status = 'active'
farmer.save()
UserRole.objects.get_or_create(user=farmer, role=role)

c = Client()
c.defaults['HTTP_AUTHORIZATION'] = f'Bearer {RefreshToken.for_user(farmer).access_token}'

# ── page 1 performance + shape ────────────────────────────────────────────────
reset_queries()
t = time.time()
r = c.get('/api/articles/all/')
elapsed_ms = (time.time() - t) * 1000
check('page 1 returns 200', r.status_code == 200, r.content[:200])
j = r.json()
check('page 1 under 300ms', elapsed_ms < 300, f'{elapsed_ms:.0f}ms')
check('page 1 query count is bounded (<12)', len(connection.queries) < 12,
      f'{len(connection.queries)} queries')
check('pagination keys present',
      all(k in j for k in ('results', 'count', 'page', 'total_pages', 'has_next')), list(j.keys()))
check('page defaults to size 20', j['page'] == 1 and len(j['results']) <= 20, j.get('page'))
check('list rows omit the body blob',
      all('body' not in row for row in j['results']), j['results'][:1])
row = j['results'][0]
for field in ('title', 'summary', 'category', 'source_type', 'image_url',
              'pdf_url', 'read_minutes', 'published_at', 'updated_at'):
    check(f'row has {field}', field in row, row)
check('only published articles', Article.objects.filter(
    status='published').count() == j['count'], j['count'])

# ── pagination ───────────────────────────────────────────────────────────────
r1 = c.get('/api/articles/all/?page=1&page_size=5').json()
r2 = c.get('/api/articles/all/?page=2&page_size=5').json()
r3 = c.get('/api/articles/all/?page=3&page_size=5').json()
check('page_size respected', len(r1['results']) == 5, len(r1['results']))
check('total_pages computed', r1['total_pages'] == -(-r1['count'] // 5), r1['total_pages'])
ids1 = {x['id'] for x in r1['results']}
ids2 = {x['id'] for x in r2['results']}
check('page 2 has different rows', ids1.isdisjoint(ids2), ids1 & ids2)
check('has_next true on page 1, false on last',
      r1['has_next'] is True and r3['has_next'] is False, (r1['has_next'], r3['has_next']))
check('page past the end returns empty', c.get(
    '/api/articles/all/?page=999&page_size=5').json()['results'] == [])

# ── filtering by content_type (per-tab fetch) ────────────────────────────────
news = c.get('/api/articles/all/?type=news').json()
check('type=news only returns news', news['results']
      and all(x['content_type'] == 'news' for x in news['results']), news['results'][:1])
market = c.get('/api/articles/all/?type=market_report').json()
check('type=market_report isolates its tab',
      all(x['content_type'] == 'market_report' for x in market['results']), market['results'])

# ── sort ─────────────────────────────────────────────────────────────────────
mr = c.get('/api/articles/all/?sort=most_read&page_size=50').json()['results']
views = [x['views_count'] for x in mr]
check('sort=most_read is descending by views', views == sorted(views, reverse=True), views)
check('sort=most_bookmarked returns 200',
      c.get('/api/articles/all/?sort=most_bookmarked').status_code == 200)

# ── search ───────────────────────────────────────────────────────────────────
s = c.get('/api/articles/all/?search=vaccine').json()
check('search matches title/abstract/body', s['count'] >= 1
      and any('vaccine' in x['title'].lower() or 'vaccine' in x['summary'].lower()
              for x in s['results']), s['count'])

# ── detail ───────────────────────────────────────────────────────────────────
d = c.get(f"/api/articles/{row['content_type']}/{row['id']}/")
check('detail returns 200 with full body', d.status_code == 200 and d.json().get('body'),
      d.content[:200])
check('detail increments views',
      d.json()['views_count'] == row['views_count'] + 1, d.json()['views_count'])

# ── cleanup ──────────────────────────────────────────────────────────────────
UserRole.objects.filter(user=farmer).delete()
farmer.delete()

print(f'\n{PASS} passed, {FAIL} failed')
sys.exit(1 if FAIL else 0)
