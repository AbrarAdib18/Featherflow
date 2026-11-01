"""Notification timing + tap-navigation suite.

Run:  backend/venv/Scripts/python.exe backend/scripts/test_notifications.py

Covers NOTIFICATION_TIMING_AND_NAVIGATION_AUDIT.md / NOTIFICATION_NAVIGATION_MATRIX.md.
Live dev DB, ONLY `notiftest+`-prefixed throw-away accounts (never the seeded
demo users — see FIND_VET_DISCOVERY_FIX.md for why). Idempotent.
"""
import hashlib
import os
import re
import sys
from datetime import date, time, timedelta

import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
django.setup()
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

from django.conf import settings as dj_settings  # noqa: E402
if 'testserver' not in dj_settings.ALLOWED_HOSTS:
    dj_settings.ALLOWED_HOSTS.append('testserver')

from django.test import Client  # noqa: E402
from django.utils import timezone  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from community.models import Post  # noqa: E402
from consultations.models import Consultation  # noqa: E402
from doctor.models import Conversation  # noqa: E402
from notifications.models import Notification  # noqa: E402
from notifications.serializers import NAVIGABLE_TYPES, _ROUTES, relative_time  # noqa: E402
from profiles.models import AdminProfile  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'notiftest+'
ISO_WITH_OFFSET = re.compile(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(\+00:00|Z)$')
# Must match lib/core/notifications/notification_navigator.dart allowedPrefixes.
FLUTTER_ALLOWED = ('/farmer', '/doctor', '/pharmacy', '/delivery', '/research',
                   '/admin', '/community', '/subscription')


def check(name, cond, extra=''):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f'  ok   {name}')
    else:
        FAIL += 1
        print(f'  FAIL {name}  {extra}')


def cleanup():
    users = User.objects.filter(email__startswith=PREFIX)
    ids = list(users.values_list('id', flat=True))
    Notification.objects.filter(user_id__in=ids).delete()
    Conversation.objects.filter(participant_one_id__in=ids).delete()
    Conversation.objects.filter(participant_two_id__in=ids).delete()
    Consultation.objects.filter(farmer_id__in=ids).delete()
    Post.objects.filter(author_id__in=ids).delete()
    AdminProfile.objects.filter(user_id__in=ids).delete()
    users.delete()


def mk(tag, role_name, panel_type=None):
    email = f'{PREFIX}{tag}@example.com'
    phone = '+8801' + hashlib.md5(email.encode()).hexdigest()[:9]
    u, _ = User.objects.get_or_create(email=email, defaults=dict(
        full_name=f'Notif {tag}', phone=phone, date_of_birth=date(1990, 1, 1),
        present_address='Dhaka', consent_terms=True, account_status='active', is_verified=True))
    role = Role.objects.get_or_create(name=role_name, defaults={'panel_type': panel_type})[0]
    u.roles.add(role)
    if role_name.startswith('admin_'):
        AdminProfile.objects.update_or_create(user=u, defaults=dict(
            admin_role=role, job_title='T', department='QA', start_date=date(2024, 1, 1),
            admin_sub_role=role_name.replace('admin_', ''), approval_status='approved',
            is_active=True, is_suspended=False, internal_approval_by_founder_hr=True))
    return u


def client(u):
    c = Client()
    c.defaults['HTTP_AUTHORIZATION'] = f'Bearer {RefreshToken.for_user(u).access_token}'
    return c


def row_for(c, n, endpoint='/api/notifications/'):
    rows = c.get(endpoint).json()['notifications']
    return next((r for r in rows if r['id'] == str(n.id)), None)


def notify(user, ref_type, ref_id=None, ntype='system', **kw):
    return Notification.objects.create(user=user, title=f'T {ref_type}', body='b',
                                       notification_type=ntype, reference_type=ref_type,
                                       reference_id=ref_id, **kw)


def backdate(n, delta):
    Notification.objects.filter(pk=n.pk).update(created_at=timezone.now() - delta)


def main():
    cleanup()
    farmer = mk('farmer', 'farmer')
    farmer2 = mk('farmer2', 'farmer')
    doctor = mk('doctor', 'doctor')
    pharmacy = mk('pharmacy', 'pharmacy')
    rider = mk('rider', 'delivery')
    researcher = mk('researcher', 'researcher')
    ops = mk('ops', 'admin_operations', 'admin')
    fin = mk('fin', 'admin_finance', 'admin')
    sup = mk('super', 'admin_super', 'admin')
    fc, dc = client(farmer), client(doctor)

    print('\n== the reported bug: brand-new notification ==')
    n = notify(farmer, 'consultation')
    r = row_for(fc, n)
    check('API returns created_at', r and r.get('created_at'), r)
    check('created_at is ISO 8601 WITH a UTC offset (no naive/offset-less value)',
          r and ISO_WITH_OFFSET.match(r['created_at'] or ''), r and r['created_at'])
    check('a just-created notification says "Just now" (was "6 hours ago")',
          r and r['time'] == 'Just now', r and r['time'])
    created = timezone.datetime.fromisoformat(r['created_at'])
    check('created_at is within a few seconds of the real current time',
          abs((timezone.now() - created).total_seconds()) < 10, r['created_at'])

    print('\n== elapsed-time labels from real persisted timestamps ==')
    for delta, expected in [(timedelta(minutes=1, seconds=5), '1 min ago'),
                            (timedelta(minutes=30, seconds=5), '30 mins ago'),
                            (timedelta(hours=6, minutes=1), '6 hours ago'),
                            (timedelta(hours=1, minutes=1), '1 hour ago'),
                            (timedelta(days=1, hours=1), '1 day ago'),
                            (timedelta(days=3, hours=1), '3 days ago')]:
        m = notify(farmer, 'loan')
        backdate(m, delta)
        check(f'{delta} old -> "{expected}"', row_for(fc, m)['time'] == expected, row_for(fc, m)['time'])
    old = notify(farmer, 'loan')
    backdate(old, timedelta(days=9))
    lbl = row_for(fc, old)['time']
    check('7+ days old -> a date like "Oct 20, 2026", not a relative label',
          re.match(r'^[A-Z][a-z]{2} \d{1,2}, \d{4}$', lbl or ''), lbl)

    print('\n== relative_time edge cases ==')
    now = timezone.now()
    check('59s -> Just now', relative_time(now - timedelta(seconds=59), now) == 'Just now')
    check('60s -> 1 min ago', relative_time(now - timedelta(seconds=60), now) == '1 min ago')
    check('2 min -> 2 mins ago (plural)', relative_time(now - timedelta(minutes=2), now) == '2 mins ago')
    check('future timestamp (clock skew) -> Just now, never negative',
          relative_time(now + timedelta(minutes=5), now) == 'Just now')

    print('\n== timestamps are persisted, distinct, and never overwritten ==')
    a = notify(farmer, 'loan')
    b = notify(farmer, 'loan')
    a.refresh_from_db()
    b.refresh_from_db()
    check('a second notification gets its own, later timestamp (not reused)', b.created_at > a.created_at)
    before = Notification.objects.get(pk=a.pk).created_at
    fc.patch('/api/notifications/', data={}, content_type='application/json')  # mark all read
    after = Notification.objects.get(pk=a.pk)
    check('marking read does not touch created_at', after.created_at == before and after.is_read)

    print('\n== every feed carries the corrected timestamp ==')
    m = notify(farmer, 'consultation')
    up = row_for(fc, m, '/api/me/updates/')
    check('/api/me/updates/ created_at has an offset (was naive .isoformat())',
          up and ISO_WITH_OFFSET.match(up['created_at'] or ''), up and up['created_at'])
    post = Post.objects.create(author=farmer, content='hello', status='active',
                               created_at=timezone.now(), updated_at=timezone.now())
    cn = notify(farmer, 'community_post', post.id, ntype='message')
    crow = row_for(fc, cn, '/api/community/notifications/')
    check('community feed: "Just now" + offset timestamp',
          crow and crow['time'] == 'Just now' and ISO_WITH_OFFSET.match(crow['created_at'] or ''), crow)
    check('community feed keeps its legacy fields (message, post_id)',
          crow and crow['message'] == 'b' and crow['post_id'] == str(post.id))

    print('\n== every notification type in the DB serializes with a valid timestamp ==')
    types = set(Notification.objects.values_list('reference_type', flat=True)) | set(NAVIGABLE_TYPES)
    for t in sorted(x for x in types if x):
        m = notify(farmer, t)
        rr = row_for(fc, m)
        check(f'type {t!r} -> offset timestamp + "Just now"',
              rr and ISO_WITH_OFFSET.match(rr['created_at'] or '') and rr['time'] == 'Just now', rr)

    print('\n== navigation: resolved per recipient role ==')
    cons = Consultation.objects.create(farmer=farmer, doctor=doctor, mode='online',
                                       appointment_date=date.today() + timedelta(days=3),
                                       appointment_time=time(10, 0))
    conv = Conversation.objects.create(participant_one=farmer, participant_two=doctor, consultation=cons)

    def nav(user, ref_type, ref_id=None):
        m = notify(user, ref_type, ref_id)
        return row_for(client(user), m)['navigation']

    cases = [
        (farmer, 'consultation', cons.id, '/farmer/find-vet/consultations'),
        (doctor, 'consultation', cons.id, '/doctor/appointments'),
        (farmer, 'conversation', conv.id, '/farmer/find-vet/chats'),
        (doctor, 'conversation', conv.id, '/doctor/messenger'),
        (doctor, 'consultation_rating', None, '/doctor/earnings'),
        (doctor, 'consultation_payment', None, '/doctor/earnings'),
        (farmer, 'consultation_payment', None, '/farmer/find-vet/consultations'),
        (doctor, 'follow_up', None, '/doctor/followups'),
        (farmer, 'pharmacy_order', None, '/farmer/pharmacy'),
        (pharmacy, 'pharmacy_order', None, '/pharmacy/orders'),
        (rider, 'delivery_order', None, '/delivery/orders'),
        (rider, 'delivery_payout', None, '/delivery/earnings'),
        (ops, 'delivery_order', None, '/admin/delivery'),
        (researcher, 'article', None, '/research/papers'),
        (farmer, 'feed_order', None, '/farmer/feed-management/marketplace'),
        (farmer, 'loan', None, '/farmer/cost-management/loans'),
        (farmer, 'subscription_plan', None, '/subscription'),
        (farmer, 'community_post', post.id, f'/community/post/{post.id}'),
        (ops, 'admin_approval_queue', None, '/admin/approvals'),
        (fin, 'cashout', None, '/admin/cashouts/pending'),
        (sup, 'admin_shift', None, '/admin/payroll'),
    ]
    for user, t, rid, expected in cases:
        got = nav(user, t, rid)
        role = user.email.split('+')[1].split('@')[0]
        check(f'{role} / {t} -> {expected}', got and got['route'] == expected, got)

    print('\n== navigation respects admin RBAC (no route the role cannot open) ==')
    check('Finance Admin gets NO route for the operational approval queue',
          nav(fin, 'admin_approval_queue') is None, nav(fin, 'admin_approval_queue'))
    check('Operations Admin gets NO route to Super-Admin-only payroll',
          nav(ops, 'admin_shift') is None, nav(ops, 'admin_shift'))
    check('a type with no meaningful destination returns navigation=null',
          nav(farmer, 'community_follow') is None)

    print('\n== object-level access + deleted targets ==')
    other = Consultation.objects.create(farmer=farmer2, doctor=doctor, mode='online',
                                        appointment_date=date.today() + timedelta(days=4),
                                        appointment_time=time(11, 0))
    g = nav(farmer, 'consultation', other.id)
    check("a notification pointing at ANOTHER farmer's consultation is not openable",
          g and g['available'] is False and g['route'] is None, g)
    check('own consultation is available', nav(farmer, 'consultation', cons.id)['available'] is True)
    dead = Post.objects.create(author=farmer, content='x', status='active',
                               created_at=timezone.now(), updated_at=timezone.now())
    dn = notify(farmer, 'community_post', dead.id)
    Post.objects.filter(pk=dead.pk).update(status='removed')
    d = row_for(fc, dn)['navigation']
    check('a removed community post -> available=false, route=null (safe, no crash)',
          d and d['available'] is False and d['route'] is None, d)

    print('\n== isolation + payload safety ==')
    foreign = notify(farmer2, 'consultation', other.id)
    check("a user's feed never contains another user's notification",
          row_for(fc, foreign) is None)
    keys = set(nav(farmer, 'consultation', cons.id))
    check('navigation exposes only route/target_type/target_id/available',
          keys == {'route', 'target_type', 'target_id', 'available'}, keys)

    print('\n== backend routes stay inside the Flutter allow-list ==')
    for panel, routes in _ROUTES.items():
        for t, (route, _tt, _m) in routes.items():
            check(f'{panel}/{t} route {route} is client-allowed',
                  any(route == p or route.startswith(p + '/') for p in FLUTTER_ALLOWED))

    print(f'\n{PASS} passed, {FAIL} failed')
    cleanup()
    if FAIL:
        sys.exit(1)


if __name__ == '__main__':
    main()
