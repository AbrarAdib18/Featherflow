"""Feed Inventory Owner + Feed Admin<->Owner chat + feed finance mirror —
end-to-end regression suite.

Run:  backend/venv/Scripts/python.exe backend/scripts/test_feed_owner_flow.py

Live DB, `fdowntest+` prefixed throw-away accounts. Idempotent (cleans up
before and after). Exercises the real HTTP layer (Django test Client + JWT).

Covers: seed_feed_marketplace_demo fixed-account idempotency, feed_owner
login/profile access, restricted-module denial (admin-panel, other admin
chats), the owner<->admin chat lifecycle (create/reply/read/resolve/reopen),
cross-user isolation, and the feed-order -> Cost Management expense mirror
(exactly-once).
"""
import os
import sys
from datetime import date
from decimal import Decimal

import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
os.environ.setdefault('EMAIL_BACKEND', 'django.core.mail.backends.locmem.EmailBackend')
django.setup()

from django.conf import settings as dj_settings  # noqa: E402
if 'testserver' not in dj_settings.ALLOWED_HOSTS:
    dj_settings.ALLOWED_HOSTS.append('testserver')

from django.core.management import call_command  # noqa: E402
from django.test import Client  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from doctor.models import Conversation, Message  # noqa: E402
from expenses.models import Expense  # noqa: E402
from notifications.models import Notification  # noqa: E402
from profiles.models import FeedOwnerProfile  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'fdowntest+'
JSON = 'application/json'
_n = [0]


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
    convos = Conversation.objects.filter(participant_one__in=users) | \
        Conversation.objects.filter(participant_two__in=users)
    Message.objects.filter(conversation__in=convos).delete()
    convos.delete()
    Notification.objects.filter(user__in=users).delete()
    Expense.objects.filter(created_by__in=users).delete()
    FeedOwnerProfile.objects.filter(user__in=users).delete()
    users.delete()


def mk_user(role_name, tag, panel_type=None):
    _n[0] += 1
    n = _n[0]
    role, _ = Role.objects.get_or_create(name=role_name, defaults={'panel_type': panel_type or role_name})
    u = User.objects.create_user(
        email=f'{PREFIX}{tag}{n}@example.com', password='Test1234!',
        phone=f'0198{n:07d}', full_name=f'{tag.title()} {n}',
        date_of_birth=date(1990, 1, 1), present_address='Dhaka', consent_terms=True,
        account_status='active', is_verified=True)
    u.roles.add(role)
    return u


def mk_feed_owner(tag):
    user = mk_user('feed_owner', tag, panel_type='feed_owner')
    FeedOwnerProfile.objects.create(
        user=user, business_name=f'{tag} Feed Depot', inventory_location='Dhaka',
        assigned_categories=['starter', 'grower'], status='active')
    return user


def client_for(user):
    c = Client()
    token = str(RefreshToken.for_user(user).access_token)
    c.defaults['HTTP_AUTHORIZATION'] = f'Bearer {token}'
    return c


def run():
    print('\n== Feed Inventory Owner + Feed Admin chat regression ==\n')
    cleanup()

    # ── 1. Seed idempotency + fixed accounts ────────────────────────────────
    print('-- seed idempotency --')
    call_command('seed_feed_marketplace_demo')
    admin_before = User.objects.filter(email='feed.admin@featherflow.local').count()
    owner_before = User.objects.filter(email='feed.owner@featherflow.local').count()
    profile_before = FeedOwnerProfile.objects.filter(user__email='feed.owner@featherflow.local').count()
    call_command('seed_feed_marketplace_demo')
    check('feed.admin@featherflow.local not duplicated', admin_before == 1 and
          User.objects.filter(email='feed.admin@featherflow.local').count() == 1)
    check('feed.owner@featherflow.local not duplicated', owner_before == 1 and
          User.objects.filter(email='feed.owner@featherflow.local').count() == 1)
    check('FeedOwnerProfile not duplicated', profile_before == 1 and
          FeedOwnerProfile.objects.filter(user__email='feed.owner@featherflow.local').count() == 1)

    fixed_admin = User.objects.get(email='feed.admin@featherflow.local')
    fixed_owner = User.objects.get(email='feed.owner@featherflow.local')
    check('fixed admin has feed_admin role', fixed_admin.roles.filter(name='feed_admin').exists())
    check('fixed owner has feed_owner role', fixed_owner.roles.filter(name='feed_owner').exists())

    # ── 2. Login + profile access ───────────────────────────────────────────
    print('-- login + profile --')
    admin = mk_user('feed_admin', 'admin', panel_type='admin')
    owner = mk_feed_owner('owner')
    other_owner = mk_feed_owner('otherowner')
    farmer = mk_user('farmer', 'farmer')
    pharmacy_admin = mk_user('admin_pharmacy', 'phadmin', panel_type='admin')
    delivery = mk_user('delivery', 'rider')

    ac, oc, ooc, fc, pc, dc = (client_for(u) for u in (admin, owner, other_owner, farmer, pharmacy_admin, delivery))

    r = oc.get('/api/feed-owner/profile/')
    check('owner profile GET 200', r.status_code == 200, r.content[:200])
    body = r.json()
    check('profile role label correct', body.get('role') == 'feed_owner')
    check('profile has business_name', body.get('business_name') == 'owner Feed Depot')

    r = oc.patch('/api/feed-owner/profile/', data={'inventory_location': 'Gazipur'}, content_type=JSON)
    check('owner can edit own profile', r.status_code == 200 and r.json()['inventory_location'] == 'Gazipur', r.content[:200])

    # ── 3. Restricted-module denial (server-side, not just nav hiding) ─────
    print('-- restricted access --')
    r = oc.get('/api/admin-panel/feed-catalogue/products/')
    check('feed_owner denied on Feed Admin catalogue endpoint', r.status_code in (401, 403), r.status_code)
    r = oc.get('/api/admin-panel/pharmacy-chats/')
    check('feed_owner denied on Pharmacy Admin chat inbox', r.status_code in (401, 403), r.status_code)
    r = fc.get('/api/feed-owner/profile/')
    check('farmer denied on feed-owner profile endpoint', r.status_code in (401, 403), r.status_code)
    r = dc.get('/api/feed-owner/profile/')
    check('delivery person denied on feed-owner profile endpoint', r.status_code in (401, 403), r.status_code)

    # ── 4. Chat lifecycle ────────────────────────────────────────────────────
    print('-- chat lifecycle --')
    r = oc.get('/api/feed-owner/chat/')
    check('no conversation yet', r.status_code == 200 and r.json()['exists'] is False, r.content[:200])

    r = oc.post('/api/feed-owner/chat/', data={}, content_type=JSON)
    check('owner opens conversation', r.status_code == 201, r.content[:200])
    convo_id = r.json()['id']
    check('feed_admin notified of new conversation',
          Notification.objects.filter(user=admin, reference_type='feed_owner_conversation').exists())

    r = oc.post(f'/api/feed-owner/chat/{convo_id}/', data={'content': 'Low on starter feed stock.'}, content_type=JSON)
    check('owner sends message', r.status_code == 201, r.content[:200])

    r = ac.get('/api/admin-panel/feed-chats/')
    check('admin inbox lists conversation', r.status_code == 200 and
          any(row['id'] == convo_id for row in r.json()['results']), r.content[:300])

    r = ac.get(f'/api/admin-panel/feed-chats/{convo_id}/')
    check('admin can read conversation detail', r.status_code == 200 and
          any(m['content'] == 'Low on starter feed stock.' for m in r.json()['messages']), r.content[:300])

    r = ac.post(f'/api/admin-panel/feed-chats/{convo_id}/messages/', data={'content': 'Restocking today.'}, content_type=JSON)
    check('admin replies', r.status_code == 201, r.content[:200])
    check('owner notified of admin reply',
          Notification.objects.filter(user=owner, reference_type='feed_owner_conversation').exists())

    r = oc.get('/api/feed-owner/chat/')
    check('owner sees admin reply', r.status_code == 200 and
          any(m['content'] == 'Restocking today.' for m in r.json()['messages']), r.content[:300])

    r = oc.patch(f'/api/feed-owner/chat/{convo_id}/', data={}, content_type=JSON)
    check('owner marks read', r.status_code == 200 and r.json()['unread_count'] == 0, r.content[:200])

    r = ac.patch(f'/api/admin-panel/feed-chats/{convo_id}/status/', data={'status': 'resolved'}, content_type=JSON)
    check('admin resolves conversation', r.status_code == 200 and r.json()['status'] == 'resolved', r.content[:200])

    r = ac.patch(f'/api/admin-panel/feed-chats/{convo_id}/status/', data={'status': 'reopened'}, content_type=JSON)
    check('admin reopens conversation', r.status_code == 200 and r.json()['status'] == 'reopened', r.content[:200])

    # ── 5. Cross-user / cross-role isolation ─────────────────────────────────
    print('-- isolation --')
    r = ooc.get(f'/api/feed-owner/chat/')
    check("another feed_owner has no conversation of their own", r.status_code == 200 and r.json()['exists'] is False)
    r = ooc.post(f'/api/feed-owner/chat/{convo_id}/', data={'content': 'snoop'}, content_type=JSON)
    check("another feed_owner cannot post into someone else's conversation", r.status_code == 404, r.status_code)
    r = pc.get('/api/admin-panel/feed-chats/')
    check('pharmacy admin denied on feed chat inbox (no feed-orders permission)', r.status_code == 403, r.status_code)
    r = fc.get('/api/admin-panel/feed-chats/')
    check('farmer denied on feed chat inbox', r.status_code in (401, 403), r.status_code)

    # ── 6. Feed order -> Cost Management mirror (exactly-once) ─────────────
    print('-- finance mirror --')
    from feed_catalogue.services import mirror_feed_expense
    payload = {
        'id': 'FEEDOWNTEST-001', 'order_number': '#FD-OWNTEST',
        'farmer_id': str(farmer.id), 'total_amount': 1500.0,
        'items': [{'company_name': 'Test Feed Co', 'product_name': 'Starter', 'quantity': 1}],
        'delivered_at': None,
    }
    expense = mirror_feed_expense(payload)
    check('expense mirrored on delivery', expense is not None and expense.amount == Decimal('1500.00'))
    check('expense category is Feed', expense is not None and expense.category.name == 'Feed')
    expense_again = mirror_feed_expense(payload)
    check('mirroring is idempotent (exactly once)',
          expense_again is not None and expense_again.id == expense.id and
          Expense.objects.filter(source_feed_order_id='FEEDOWNTEST-001').count() == 1)

    cleanup()
    Expense.objects.filter(source_feed_order_id='FEEDOWNTEST-001').delete()

    print(f'\n== {PASS} passed, {FAIL} failed ==\n')
    return FAIL == 0


if __name__ == '__main__':
    sys.exit(0 if run() else 1)
