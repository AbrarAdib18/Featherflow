"""Community feed N+1 elimination — query-count regression + response-time
baseline.

    backend/venv/Scripts/python.exe backend/scripts/test_community_feed_performance.py

Covers PERFORMANCE_BASELINE.md PC1 ("community feed: 6-10 queries per post,
on an unbounded/near-unbounded scan for trending/search"). Measured directly
against the pre-fix code (temporarily reverted via `git stash`) for the same
24-post dev feed: 232 queries / 219ms before this fix, 23 queries / 125ms
after — see PRODUCTION_READINESS_REPORT.md for the full before/after note.

This test creates its own throwaway posts (each with a reaction, a comment,
a repost, and a bookmark from a second viewer) specifically so the query
count would scale with post count under the OLD per-post-query code — the
whole point of the regression guard: an endpoint that has regressed to O(N)
queries fails this test outright once there are enough posts to blow past a
fixed ceiling, while a genuinely O(1)-queries-per-page implementation stays
comfortably under it regardless of how many throwaway posts exist.

Uses the live DB. Creates throwaway accounts/posts prefixed ``feedperf+`` /
``feedperf-`` and cleans them up on entry and exit. Idempotent.
"""
import os
import sys
import time
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

from community.models import Bookmark, Comment, Follow, Post, Reaction, Repost  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'feedperf+'
POST_COUNT = 20  # enough that an O(N) regression (was ~9 queries/post) blows
                 # well past QUERY_CEILING; an O(1)-per-page fix stays under it.
QUERY_CEILING = 40


def check(name, cond, extra=''):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f'  ok   {name}')
    else:
        FAIL += 1
        print(f'  FAIL {name}   {extra}')


def cleanup():
    posts = Post.objects.filter(content__startswith=f'{PREFIX}post ')
    post_ids = list(posts.values_list('id', flat=True))
    Reaction.objects.filter(target_id__in=post_ids, target_type='post').delete()
    Comment.objects.filter(post_id__in=post_ids).delete()
    Repost.objects.filter(post_id__in=post_ids).delete()
    Bookmark.objects.filter(target_id__in=post_ids, target_type='post').delete()
    posts.delete()
    users = User.objects.filter(email__startswith=PREFIX)
    Follow.objects.filter(follower__in=users).delete()
    Follow.objects.filter(following__in=users).delete()
    users.delete()


def mk_user(tag):
    role, _ = Role.objects.get_or_create(name='farmer', defaults={'panel_type': 'farmer'})
    u = User.objects.create_user(
        email=f'{PREFIX}{tag}@example.com', password='Test1234!',
        phone=f'+8801{770000000 + hash(tag) % 9999999:09d}'[:14],
        full_name=f'Feed Perf {tag}', date_of_birth=date(1990, 1, 1),
        present_address='Dhaka', consent_terms=True,
        account_status='active', is_verified=True)
    u.roles.add(role)
    return u


def client_for(user):
    c = Client()
    c.defaults['HTTP_AUTHORIZATION'] = f'Bearer {RefreshToken.for_user(user).access_token}'
    return c


def seed_posts(author, viewer):
    """POST_COUNT posts, each with one reaction, one comment, one repost, and
    one bookmark — real per-post engagement rows, not just bare posts, so the
    old code's per-post reaction/comment/repost/bookmark queries would have
    actually had something to fetch."""
    now = timezone.now()
    posts = []
    for i in range(POST_COUNT):
        post = Post.objects.create(
            author=author, post_type='text', content=f'{PREFIX}post {i} — hello feed',
            status='active', created_at=now, updated_at=now)
        Reaction.objects.create(user=viewer, target_id=post.id, target_type='post',
                                 reaction_type='like', created_at=now)
        Comment.objects.create(post=post, author=viewer, content='nice one',
                               status='active', created_at=now)
        Repost.objects.create(post=post, user=viewer, created_at=now)
        Bookmark.objects.create(user=viewer, target_id=post.id, target_type='post', created_at=now)
        posts.append(post)
    return posts


def timed_request(c, path):
    with CaptureQueriesContext(connection) as ctx:
        started = time.monotonic()
        r = c.get(path)
        elapsed_ms = (time.monotonic() - started) * 1000
    return r, len(ctx.captured_queries), elapsed_ms


def main():
    cleanup()
    author = mk_user('author')
    viewer = mk_user('viewer')
    Follow.objects.create(follower=viewer, following=author, created_at=timezone.now())
    seed_posts(author, viewer)
    c = client_for(viewer)

    print(f'\n== query-count ceiling across {POST_COUNT} posts (each with a '
          f'reaction + comment + repost + bookmark) ==')
    for label, path in (
        ('feed (latest tab)', '/api/community/'),
        ('feed (trending tab)', '/api/community/?tab=trending'),
        ('trending endpoint', '/api/community/trending/'),
        ('latest endpoint', '/api/community/latest/'),
        ('search (sort=popular)', '/api/community/search/?sort=popular'),
        ('following feed', '/api/community/following/'),
        ('bookmarks', '/api/community/bookmarks/'),
    ):
        r, n_queries, elapsed_ms = timed_request(c, path)
        check(f'{label}: 200', r.status_code == 200, r.status_code)
        posts_returned = len(r.json().get('posts', r.json().get('results', [])))
        check(f'{label}: query count ({n_queries}) stays under ceiling ({QUERY_CEILING}) '
              f'serving {posts_returned} posts — {elapsed_ms:.1f}ms',
              n_queries <= QUERY_CEILING, n_queries)

    print('\n== output correctness: reactions/comments/bookmarks/repost/follow survived '
          'the switch to bulk-computed context ==')
    r = c.get('/api/community/')
    rows = {p['id']: p for p in r.json()['posts']}
    sample = next(iter(rows.values()))
    check('reaction total reflects the seeded reaction', sample['reactions']['total'] >= 1, sample['reactions'])
    check('comments_count reflects the seeded comment', sample['comments_count'] >= 1, sample['comments_count'])
    check('reposts_count reflects the seeded repost', sample['reposts_count'] >= 1, sample['reposts_count'])
    check('reposted is True (viewer reposted it)', sample['reposted'] is True, sample['reposted'])
    check('bookmarked is True (viewer bookmarked it)', sample['bookmarked'] is True, sample['bookmarked'])
    check('following_author is True (viewer follows the author)',
          sample['following_author'] is True, sample['following_author'])

    cleanup()
    print(f'\n{"="*40}\n{PASS} passed, {FAIL} failed\n{"="*40}')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    main()
