"""End-to-end check of the Community blogging backend (requirements §8).

Run:  backend/venv/Scripts/python.exe backend/scripts/test_community.py

Uses Django's test Client against the *live* configured database (which must
have featherflow_schema.sql + postgres_backend_extension.sql applied). It
creates throw-away accounts prefixed ``communitytest+`` and content tagged
#e2ecommunity, cleans its own posts/reports/mutes on entry, and is idempotent.
"""
import os
import sys
from datetime import date

import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
for key in ('READ', 'WRITE', 'EXPORT', 'POLL'):
    os.environ.setdefault(f'THROTTLE_ADMIN_{key}', '100000/min')
django.setup()

from django.conf import settings as dj_settings  # noqa: E402
if 'testserver' not in dj_settings.ALLOWED_HOSTS:
    dj_settings.ALLOWED_HOSTS.append('testserver')

from django.test import Client  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from community.models import (  # noqa: E402
    Comment, CommunityMute, Follow, PollVote, Post, Reaction, Report, Repost, UserBlock,
)
from notifications.models import Notification  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'communitytest+'


def check(name, cond, extra=''):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f'  ok   {name}')
    else:
        FAIL += 1
        print(f'  FAIL {name}  {extra}')


def make_user(handle, role_name, *, verified=False):
    import hashlib

    email = f'{PREFIX}{handle}@featherflow.dev'
    phone = '+8801' + hashlib.md5(email.encode()).hexdigest()[:9]
    user, _ = User.objects.get_or_create(email=email, defaults=dict(
        full_name=f'CT {handle.title()}', phone=phone, date_of_birth=date(1990, 1, 1),
        present_address='Test', consent_terms=True, account_status='active',
        is_verified=verified,
    ))
    user.account_status = 'active'
    user.is_verified = verified
    user.set_password('Testpass!2026')
    user.save()
    role, _ = Role.objects.get_or_create(name=role_name, defaults={'panel_type': role_name})
    user.roles.clear()
    user.roles.add(role)
    return user


def auth(client, user):
    token = str(RefreshToken.for_user(user).access_token)
    client.defaults['HTTP_AUTHORIZATION'] = f'Bearer {token}'


def cleanup(users):
    ids = [u.id for u in users]
    post_ids = list(Post.objects.filter(author_id__in=ids).values_list('id', flat=True))
    Reaction.objects.filter(target_id__in=post_ids).delete()
    Report.objects.filter(target_id__in=post_ids).delete()
    PollVote.objects.filter(post_id__in=post_ids).delete()
    Repost.objects.filter(post_id__in=post_ids).delete()
    Comment.objects.filter(post_id__in=post_ids).delete()
    Post.objects.filter(id__in=post_ids).delete()
    CommunityMute.objects.filter(user_id__in=ids).delete()
    UserBlock.objects.filter(blocker_id__in=ids).delete()
    UserBlock.objects.filter(blocked_id__in=ids).delete()
    Follow.objects.filter(follower_id__in=ids).delete()
    Follow.objects.filter(following_id__in=ids).delete()
    Notification.objects.filter(user_id__in=ids).delete()


def main():
    c = Client()
    farmer = make_user('farmer', 'farmer')
    vet = make_user('vet', 'doctor', verified=True)
    reporters = [make_user(f'rep{i}', 'farmer') for i in range(5)]
    admin = make_user('mod', 'admin_content')
    from profiles.models import AdminProfile
    AdminProfile.objects.update_or_create(user=admin, defaults=dict(
        job_title='Mod', department='Trust & Safety', start_date=date(2024, 1, 1),
        admin_sub_role='content', approval_status='approved', is_active=True, is_suspended=False,
        internal_approval_by_founder_hr=True,
    ))
    everyone = [farmer, vet, admin, *reporters]
    cleanup(everyone)

    print('\n== create + feed ==')
    auth(c, farmer)
    r = c.post('/api/community/', data={
        'content': 'Feed prices jumped again in Bogura #feedprices #e2ecommunity',
        'category': 'Feed Prices',
    }, content_type='application/json')
    check('create post 201', r.status_code == 201, r.content[:200])
    post_id = r.json()['id']
    check('hashtags parsed', set(r.json()['tags']) >= {'feedprices', 'e2ecommunity'}, r.json().get('tags'))

    r = c.get('/api/community/?tab=latest')
    feed = r.json()
    check('post in latest feed', any(p['id'] == post_id for p in feed['posts']), r.status_code)
    check('feed payload shape (posts/topics/trending)',
          all(k in feed for k in ('posts', 'topics', 'trending')), list(feed))
    card = next(p for p in feed['posts'] if p['id'] == post_id)
    check('post card contract keys present', all(k in card for k in (
        'author', 'post_type', 'reactions', 'comments_count', 'reposts_count',
        'bookmarked', 'reposted', 'tags', 'media_urls', 'status', 'time')),
        [k for k in ('author', 'post_type', 'reactions', 'comments_count') if k not in card])
    check('author block is nested with badge slot',
          isinstance(card['author'], dict) and 'badge' in card['author'], card['author'])

    print('\n== reactions + comments notify author ==')
    auth(c, vet)
    r = c.post('/api/community/react/', data={'post_id': post_id, 'reaction_type': 'helpful'},
               content_type='application/json')
    check('react 200', r.status_code == 200 and r.json()['count'] == 1, r.content[:200])
    r = c.post('/api/community/react/', data={'post_id': post_id, 'reaction_type': 'helpful'},
               content_type='application/json')
    check('re-react toggles off', r.json()['count'] == 0, r.content[:120])
    r = c.post('/api/community/comment/', data={'post_id': post_id, 'content': 'Same here in Rangpur.'},
               content_type='application/json')
    check('comment 201', r.status_code == 201, r.content[:200])
    check('author notified', Notification.objects.filter(
        user=farmer, reference_id=post_id).exists(), 'no notification')

    print('\n== verified badge is role-driven ==')
    r = c.get(f'/api/community/posts/{post_id}/')
    badge = next((cm['author']['badge'] for cm in r.json()['comments']), None)
    check('vet comment carries Verified Vet badge', badge and badge['type'] == 'doctor', badge)

    print('\n== poll: one vote per user, quota ==')
    auth(c, farmer)
    r = c.post('/api/community/', data={
        'post_type': 'poll', 'content': 'Best layer feed brand? #e2ecommunity',
        'poll_options': ['Brand A', 'Brand B', 'Brand C'],
    }, content_type='application/json')
    check('poll create 201', r.status_code == 201, r.content[:200])
    poll_id = r.json()['id']
    auth(c, vet)
    r = c.post('/api/community/vote/', data={'post_id': poll_id, 'option_indexes': [0]},
               content_type='application/json')
    check('vote 200', r.status_code == 200 and r.json()['total_votes'] == 1, r.content[:200])
    r = c.post('/api/community/vote/', data={'post_id': poll_id, 'option_indexes': [1]},
               content_type='application/json')
    check('second vote replaces, no dup', r.json()['total_votes'] == 1
          and r.json()['options'][1]['votes'] == 1, r.content[:200])
    r = c.post('/api/community/vote/', data={'post_id': poll_id, 'option_indexes': [0, 1]},
               content_type='application/json')
    check('multi-choice rejected on single poll', r.status_code == 400, r.status_code)

    print('\n== poll weekly quota (2/week) ==')
    auth(c, farmer)
    c.post('/api/community/', data={'post_type': 'poll', 'content': 'p2 #e2ecommunity',
           'poll_options': ['x', 'y']}, content_type='application/json')
    r = c.post('/api/community/', data={'post_type': 'poll', 'content': 'p3 #e2ecommunity',
               'poll_options': ['x', 'y']}, content_type='application/json')
    check('3rd poll in a week blocked (429)', r.status_code == 429, r.status_code)

    print('\n== question + best answer (author only) ==')
    auth(c, farmer)
    r = c.post('/api/community/', data={
        'post_type': 'question', 'title': 'Why are my hens off feed?',
        'content': 'Sudden drop in intake, no other signs. #e2ecommunity',
    }, content_type='application/json')
    q_id = r.json()['id']
    auth(c, vet)
    r = c.post('/api/community/comment/', data={'post_id': q_id, 'content': 'Check water lines and heat stress.'},
               content_type='application/json')
    ans_id = r.json()['comment']['id']
    r = c.patch(f'/api/community/comments/{ans_id}/best-answer/', data={}, content_type='application/json')
    check('non-author cannot mark best answer (403)', r.status_code == 403, r.status_code)
    auth(c, farmer)
    r = c.patch(f'/api/community/comments/{ans_id}/best-answer/', data={}, content_type='application/json')
    check('author marks best answer 200', r.status_code == 200 and r.json()['is_best_answer'], r.content[:200])

    print('\n== report threshold auto-hides ==')
    for i, rep in enumerate(reporters):
        auth(c, rep)
        r = c.post('/api/community/report/', data={
            'target_type': 'post', 'target_id': post_id, 'reason': 'spam',
        }, content_type='application/json')
        check(f'report {i + 1} accepted', r.status_code == 201, r.content[:160])
    check('post auto-hidden at 5 reports',
          Post.objects.get(pk=post_id).status == 'flagged', Post.objects.get(pk=post_id).status)
    auth(c, farmer)
    r = c.get('/api/community/?tab=latest')
    check('hidden post drops out of the public feed',
          all(p['id'] != post_id for p in r.json()['posts']), 'still visible')

    print('\n== admin moderation on real rows ==')
    auth(c, admin)
    r = c.get('/api/admin-panel/community-reports/')
    check('admin reports list 200', r.status_code == 200, r.content[:200])
    row = next((x for x in r.json()['results'] if x['target_id'] == post_id), None)
    check('report row is real (not seed)', row and row['report_count'] == 5, row)
    r = c.patch(f"/api/admin-panel/community-reports/{row['id']}/", data={
        'action': 'hide', 'reason': 'Confirmed spam',
    }, content_type='application/json')
    check('admin hide 200', r.status_code == 200, r.content[:200])
    check('post now hidden', Post.objects.get(pk=post_id).status == 'hidden')
    r = c.patch(f"/api/admin-panel/community-reports/{row['id']}/", data={'action': 'unhide'},
                content_type='application/json')
    check('admin unhide 200 + post active', r.status_code == 200
          and Post.objects.get(pk=post_id).status == 'active', r.content[:200])
    r = c.patch(f"/api/admin-panel/community-reports/{row['id']}/", data={'action': 'dismiss'},
                content_type='application/json')
    check('admin dismiss 200 (needs community.reject perm)', r.status_code == 200, r.content[:200])

    print('\n== admin mute blocks posting ==')
    r = c.get('/api/admin-panel/community-users/')
    check('admin members list 200', r.status_code == 200, r.content[:160])
    r = c.patch(f'/api/admin-panel/community-users/{farmer.id}/', data={
        'action': 'mute', 'reason': 'repeat spam',
    }, content_type='application/json')
    check('mute 200', r.status_code == 200 and r.json()['muted'], r.content[:200])
    auth(c, farmer)
    r = c.post('/api/community/', data={'content': 'trying to post while muted #e2ecommunity'},
               content_type='application/json')
    check('muted user blocked from posting (403)', r.status_code == 403, r.status_code)
    auth(c, admin)
    r = c.patch(f'/api/admin-panel/community-users/{farmer.id}/', data={'action': 'unmute'},
                content_type='application/json')
    check('unmute 200', r.status_code == 200 and not r.json()['muted'], r.content[:160])

    print('\n== discovery endpoints ==')
    auth(c, farmer)
    for path in ('trending/', 'latest/', 'following/', 'hashtags/', 'categories/',
                 'search/?q=feed', 'follows/suggestions/'):
        r = c.get(f'/api/community/{path}')
        check(f'GET community/{path} 200', r.status_code == 200, r.content[:120])
    r = c.post('/api/community/follows/', data={'user_id': str(vet.id)}, content_type='application/json')
    check('follow by user_id 200', r.status_code == 200 and r.json()['following'], r.content[:160])
    r = c.get(f'/api/community/users/{vet.id}/stats/')
    check('user stats show a follower', r.json().get('followers_count', 0) >= 1, r.content[:160])
    r = c.post('/api/community/repost/', data={'post_id': q_id}, content_type='application/json')
    check('repost 200', r.status_code == 200 and r.json()['reposted'], r.content[:160])

    print('\n== personal block hides a member ==')
    auth(c, vet)
    c.post('/api/community/', data={'content': 'vet post visible before block #e2ecommunity'},
           content_type='application/json')
    auth(c, farmer)
    r = c.get('/api/community/latest/')
    check('vet post visible before block', any(
        (p['author'].get('id') == str(vet.id)) for p in r.json()['posts']), 'not visible')
    r = c.post('/api/community/blocks/', data={'user_id': str(vet.id)}, content_type='application/json')
    check('block 201', r.status_code == 201 and r.json()['blocked'], r.content[:160])
    r = c.get('/api/community/latest/')
    check('blocked member drops out of feed', all(
        p['author'].get('id') != str(vet.id) for p in r.json()['posts']), 'still visible')
    r = c.get(f'/api/community/users/{vet.id}/stats/')
    check('stats report is_blocked', r.json().get('is_blocked') is True, r.content[:160])
    r = c.delete('/api/community/blocks/', data={'user_id': str(vet.id)}, content_type='application/json')
    check('unblock 200', r.status_code == 200 and not r.json()['blocked'], r.content[:160])
    r = c.get('/api/community/latest/')
    check('member visible again after unblock', any(
        p['author'].get('id') == str(vet.id) for p in r.json()['posts']), 'still hidden')

    print('\n== notifications feed shape (bell + screen) ==')
    r = c.get('/api/community/notifications/')
    body = r.json()
    check('notifications payload shape', 'notifications' in body and 'unread_count' in body, list(body))
    if body['notifications']:
        n = body['notifications'][0]
        check('notification row keys', all(k in n for k in ('id', 'title', 'message', 'is_read', 'time')), list(n))
    r = c.patch('/api/community/notifications/', data={}, content_type='application/json')
    check('notifications mark-read 200', r.status_code == 200 and r.json()['unread_count'] == 0, r.content[:120])

    print('\n== post detail contract (detail screen) ==')
    r = c.get(f'/api/community/posts/{q_id}/')
    d = r.json()
    check('detail returns comments list', isinstance(d.get('comments'), list), list(d))
    check('question detail exposes best-answer flags',
          'can_mark_best_answer' in d and 'best_answer_id' in d, list(d))

    cleanup(everyone)
    print(f'\n{PASS} passed, {FAIL} failed')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    main()
