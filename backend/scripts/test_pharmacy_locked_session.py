"""F-002 regression — pending / suspended / rejected pharmacy accounts keep a
restricted session (locked panel); every other role is unchanged.

Run:  backend/venv/Scripts/python.exe backend/scripts/test_pharmacy_locked_session.py

Live DB, `lockedsess+` throw-away accounts; idempotent. Goes through the real
login endpoint (`POST /api/auth/login/`) and `/api/me/updates/` — the poll the
Flutter client uses; that poll returning `access_revoked: true` for a suspended
pharmacy is what used to eject the owner back to the login screen.

Statuses covered (actual stored values):
  pending    users.account_status='pending'   + pharmacy_organizations.review_state='pending_review'
  rejected   users.account_status='pending'   + review_state='rejected'   (what the reject action stores)
  (users.account_status has a CHECK constraint: active|pending|suspended — a raw 'rejected' cannot be stored)
  suspended  users.account_status='suspended' + review_state='approved'
  active     users.account_status='active'    + review_state='approved'
  restored   suspended -> transition_pharmacy_status('reinstate') -> active
"""
import os
import sys
from datetime import date

os.environ.setdefault('THROTTLE_AUTH_LOGIN', '100000/min')
os.environ.setdefault('EMAIL_BACKEND', 'django.core.mail.backends.locmem.EmailBackend')

import django  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
django.setup()

from django.conf import settings as dj_settings  # noqa: E402
if 'testserver' not in dj_settings.ALLOWED_HOSTS:
    dj_settings.ALLOWED_HOSTS.append('testserver')

from django.test import Client  # noqa: E402
from django.utils import timezone  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from doctor.models import Conversation, Message  # noqa: E402
from notifications.models import Notification  # noqa: E402
from pharmacy.models import PharmacyAppeal  # noqa: E402
from pharmacy.services import transition_pharmacy_status  # noqa: E402
from profiles.models import PharmacyOrganization  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'lockedsess+'
PW = 'Test1234!'
JSON = 'application/json'
_n = [0]

OPERATIONAL_GETS = [
    '/api/pharmacy/medicines/', '/api/pharmacy/orders/', '/api/pharmacy/suppliers/',
    '/api/pharmacy/inventory/summary/', '/api/pharmacy/inventory/low-stock/',
    '/api/pharmacy/analytics/sales/', '/api/pharmacy/analytics/revenue/',
]
ALWAYS_ON_GETS = [
    '/api/pharmacy/profile/', '/api/pharmacy/permissions/', '/api/pharmacy/earnings/',
    '/api/pharmacy/verification-status/', '/api/pharmacy/appeals/', '/api/pharmacy/support-conversation/',
]


def check(name, cond, extra=''):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f'  ok   {name}')
    else:
        FAIL += 1
        print(f'  FAIL {name}  {extra}')


def cleanup():
    from audit.models import AdminPanelRecord
    users = User.objects.filter(email__startswith=PREFIX)
    convos = Conversation.objects.filter(participant_one__in=users) | Conversation.objects.filter(participant_two__in=users)
    Message.objects.filter(conversation__in=convos).delete()
    convos.delete()
    Notification.objects.filter(user__in=users).delete()
    PharmacyAppeal.objects.filter(pharmacy_user__in=users).delete()
    PharmacyOrganization.objects.filter(user__in=users).delete()
    AdminPanelRecord.objects.filter(payload__owner_id__in=[str(u.id) for u in users]).delete()
    users.delete()


def mk_user(role_name, tag, *, account_status='active'):
    _n[0] += 1
    n = _n[0]
    role, _ = Role.objects.get_or_create(name=role_name, defaults={'panel_type': 'admin' if role_name.startswith('admin') else role_name})
    u = User.objects.create_user(
        email=f'{PREFIX}{tag}{n}@example.com', password=PW, phone=f'0195{n:07d}',
        full_name=f'Locked {tag} {n}', date_of_birth=date(1990, 1, 1), present_address='Dhaka',
        consent_terms=True, account_status=account_status, is_verified=(account_status == 'active'))
    u.email_verified_at = u.phone_verified_at = timezone.now()
    u.save(update_fields=['email_verified_at', 'phone_verified_at'])
    u.roles.add(role)
    return u


def mk_pharmacy(tag, account_status, review_state):
    u = mk_user('pharmacy', tag, account_status=account_status)
    PharmacyOrganization.objects.create(
        user=u, business_name=f'{tag} Pharmacy', authorized_contact_person='Owner',
        business_registration_number=f'REG-{u.id}', trade_license_url='x', tax_vat_tin_number='T',
        business_address='Dhaka', is_verified=(review_state == 'approved' and account_status == 'active'),
        review_state=review_state, created_at=timezone.now(), updated_at=timezone.now())
    return u


def login(user):
    return Client().post('/api/auth/login/', {'email': user.email, 'password': PW}, content_type=JSON)


def bearer(token):
    c = Client()
    c.defaults['HTTP_AUTHORIZATION'] = f'Bearer {token}'
    return c


def run():
    print('\n== F-002: restricted session for non-active pharmacies ==\n')
    cleanup()
    admin = mk_user('admin_pharmacy', 'admin')

    cases = [
        ('pending', 'pending', 'pending_review', 'PENDING_REVIEW'),
        ('rejected', 'pending', 'rejected', 'REJECTED'),
        ('suspended', 'suspended', 'approved', 'SUSPENDED'),
    ]
    suspended_user = None
    for label, acct, review, expected in cases:
        print(f'-- {label}: account_status={acct!r} review_state={review!r}')
        u = mk_pharmacy(label, acct, review)
        if label == 'suspended':
            suspended_user = u
        r = login(u)
        j = r.json()
        check(f'{label}: login -> 200 with a session', r.status_code == 200 and bool(j.get('access')) and bool(j.get('refresh')), r.content[:200])
        check(f'{label}: login says next=pending_approval, account_status={acct}', j.get('next') == 'pending_approval' and j.get('account_status') == acct, j.get('next'))
        check(f'{label}: role is pharmacy', j.get('user', {}).get('roles') == ['pharmacy'], j.get('user', {}).get('roles'))
        c = bearer(j['access'])
        r = c.get('/api/me/updates/')
        check(f'{label}: /api/me/updates/ 200 and access_revoked == false (no client ejection)',
              r.status_code == 200 and r.json().get('access_revoked') is False, r.content[:200])
        check(f'{label}: /me/updates reports account_status {acct}', r.json().get('account_status') == acct)
        r = c.get('/api/pharmacy/permissions/')
        p = r.json()
        check(f'{label}: permissions status == {expected}', r.status_code == 200 and p.get('status') == expected, p.get('status'))
        check(f'{label}: operational flags locked, always-on flags open',
              not any(p['can'].get(k) for k in ('catalogue', 'orders', 'suppliers', 'analytics', 'employees'))
              and p['can'].get('chat') and p['can'].get('profile'), p.get('can'))
        for url in ALWAYS_ON_GETS:
            rr = c.get(url) if 'support-conversation' not in url else c.post(url)
            check(f'{label}: allowed {url} -> 2xx', rr.status_code in (200, 201), (rr.status_code, rr.content[:120]))
        r = c.get('/api/pharmacy/earnings/')
        check(f'{label}: earnings are real zeros', r.json() == {'total_orders': 0, 'gross_sales': '0.00', 'featherflow_commission': '0.00', 'pharmacy_earnings': '0.00'}, r.json())
        for url in OPERATIONAL_GETS:
            rr = c.get(url)
            check(f'{label}: DENIED {url} -> 401/403 (default auth rejects the non-active token)', rr.status_code in (401, 403), rr.status_code)
        rr = c.post('/api/pharmacy/medicines/', {'name': 'x', 'category': 'antibiotic', 'unit': 'b', 'price': 1, 'stock_quantity': 1, 'expiry_date': '2030-01-01'}, content_type=JSON)
        check(f'{label}: DENIED create medicine -> 401/403', rr.status_code in (401, 403), rr.status_code)
        # chat with Pharmacy Admin works
        conv = c.post('/api/pharmacy/support-conversation/').json()
        cid = conv.get('id') or conv.get('conversation_id')
        rr = c.post(f'/api/pharmacy/support-conversation/{cid}/', {'content': f'hello from {label}'}, content_type=JSON)
        check(f'{label}: can send a Pharmacy Admin chat message', rr.status_code in (200, 201), (rr.status_code, rr.content[:160]))

    # appeal flow while suspended; then restore.
    print('-- suspended: appeal, then restored')
    c = bearer(login(suspended_user).json()['access'])
    r = c.post('/api/pharmacy/appeals/', {'reason': 'other', 'explanation': 'Please reconsider my suspension.'}, content_type=JSON)
    check('suspended: submit appeal -> 201', r.status_code == 201, (r.status_code, r.content[:200]))
    r = c.get('/api/pharmacy/permissions/')
    check('suspended after appeal: status APPEAL_PENDING (or SUSPENDED) and still locked', r.json().get('status') in ('APPEAL_PENDING', 'SUSPENDED') and not r.json()['can'].get('catalogue'), r.json().get('status'))
    transition_pharmacy_status(admin, suspended_user, 'reinstate', request=None)
    suspended_user.refresh_from_db()
    r = login(suspended_user)
    check('restored: account_status active, login next=dashboard', suspended_user.account_status == 'active' and r.json().get('next') == 'dashboard', (suspended_user.account_status, r.json().get('next')))
    c = bearer(r.json()['access'])
    p = c.get('/api/pharmacy/permissions/').json()
    check('restored: permissions ACTIVE with operational flags open', p['status'] == 'ACTIVE' and p['can']['catalogue'] and p['can']['orders'], p)
    check('restored: operational endpoints reachable (200)', all(c.get(u).status_code == 200 for u in ('/api/pharmacy/medicines/', '/api/pharmacy/orders/', '/api/pharmacy/suppliers/')))
    check('restored: /me/updates access_revoked false', c.get('/api/me/updates/').json().get('access_revoked') is False)

    # Active pharmacy unchanged.
    print('-- active pharmacy unchanged')
    a = mk_pharmacy('active', 'active', 'approved')
    r = login(a)
    check('active: login 200, next=dashboard', r.status_code == 200 and r.json().get('next') == 'dashboard', r.content[:150])
    check('active: operational endpoints 200', all(bearer(r.json()['access']).get(u).status_code == 200 for u in OPERATIONAL_GETS[:3]))

    # Other roles unchanged.
    print('-- other roles unchanged')
    for role in ('farmer', 'doctor', 'delivery', 'researcher', 'admin_content'):
        for st in ('pending', 'suspended'):
            u = mk_user(role, f'{role}-{st}', account_status=st)
            r = login(u)
            j = r.json()
            check(f'{role}/{st}: login -> 403, no tokens, next=pending_approval',
                  r.status_code == 403 and 'access' not in j and 'refresh' not in j and j.get('next') == 'pending_approval', (r.status_code, list(j)))
            # A token minted for the inactive account is rejected by the poll (401) -> client signs out, as before.
            tok = str(RefreshToken.for_user(u).access_token)
            rr = bearer(tok).get('/api/me/updates/')
            check(f'{role}/{st}: token for inactive non-pharmacy account -> 401 on /me/updates', rr.status_code == 401, rr.status_code)
        u = mk_user(role, f'{role}-active')
        r = login(u)
        check(f'{role}/active: login 200 with session, next=dashboard', r.status_code == 200 and bool(r.json().get('access')) and r.json().get('next') == 'dashboard', r.content[:120])
    # the server-side revoke flag for non-pharmacy suspended stays true (unit-level via payload builder)
    from api.admin_extra import me_updates  # noqa: F401  (import check only)
    check('operational pharmacy endpoints reject another role (farmer 403)',
          bearer(str(RefreshToken.for_user(mk_user('farmer', 'probe')).access_token)).get('/api/pharmacy/medicines/').status_code == 403)
    r = Client().post('/api/auth/login/', {'email': suspended_user.email, 'password': 'wrong'}, content_type=JSON)
    check('wrong password still 401 (no session leak)', r.status_code == 401, r.status_code)

    cleanup()
    print(f'\n== {PASS} passed, {FAIL} failed ==')
    return FAIL == 0


if __name__ == '__main__':
    try:
        ok = run()
    finally:
        cleanup()
    sys.exit(0 if ok else 1)
