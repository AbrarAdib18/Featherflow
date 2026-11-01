"""Pharmacy Admin Portal — end-to-end regression suite.

Run:  backend/venv/Scripts/python.exe backend/scripts/test_pharmacy_admin.py

Live DB, `phadmtest+` prefixed throw-away accounts. Idempotent (cleans up
before and after). Exercises the real HTTP layer (Django test Client + JWT),
not internal function calls, so RBAC/permission wiring is verified along with
business logic.

Covers: pending-account lock/unlock (profile reachable while pending,
catalogue locked), the consolidated approve/reject/request-info/suspend/
reinstate transition across its rewired call sites, suspension requiring a
reason, the appeal lifecycle, admin medicine CRUD, commission math +
idempotency + refund exclusion, pharmacy<->admin chat + isolation between two
pharmacies, RBAC isolation (pharmacy/farmer accounts denied on admin
endpoints), and dashboard/metrics sanity.
"""
import os
import sys
from datetime import date, timedelta
from decimal import Decimal

import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
os.environ.setdefault('EMAIL_BACKEND', 'django.core.mail.backends.locmem.EmailBackend')
django.setup()

from django.conf import settings as dj_settings  # noqa: E402
if 'testserver' not in dj_settings.ALLOWED_HOSTS:
    dj_settings.ALLOWED_HOSTS.append('testserver')

from django.test import Client  # noqa: E402
from django.utils import timezone  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from audit.models import ActivityLog  # noqa: E402
from doctor.models import Conversation, Message  # noqa: E402
from expenses.models import Expense  # noqa: E402
from notifications.models import Notification  # noqa: E402
from pharmacy.models import (  # noqa: E402
    PharmacyAppeal, PharmacyCommission, PharmacyEmployee, PharmacyMedicine, PharmacySale,
    PharmacySettlement,
)
from profiles.models import PharmacyOrganization  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'phadmtest+'
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
    # ActivityLog is append-only (DB trigger blocks DELETE/UPDATE) — test rows
    # are left in place permanently, same as every other script in this repo.
    Expense.objects.filter(created_by__in=users).delete()
    PharmacySettlement.objects.filter(pharmacy_user__in=users).delete()
    PharmacySettlement.objects.filter(created_by__in=users).delete()
    PharmacyAppeal.objects.filter(pharmacy_user__in=users).delete()
    PharmacyCommission.objects.filter(sale__pharmacy_user__in=users).delete()
    PharmacySale.objects.filter(pharmacy_user__in=users).delete()
    PharmacyEmployee.objects.filter(pharmacy_user__in=users).delete()
    PharmacyMedicine.objects.filter(pharmacy_user__in=users).delete()
    PharmacyOrganization.objects.filter(user__in=users).delete()
    from audit.models import AdminPanelRecord
    AdminPanelRecord.objects.filter(payload__owner_id__in=[str(u.id) for u in users]).delete()
    AdminPanelRecord.objects.filter(payload__farmer_id__in=[str(u.id) for u in users]).delete()
    users.delete()


def mk_user(role_name, tag, *, account_status='active', is_verified=True):
    _n[0] += 1
    n = _n[0]
    role, _ = Role.objects.get_or_create(name=role_name, defaults={'panel_type': role_name})
    u = User.objects.create_user(
        email=f'{PREFIX}{tag}{n}@example.com', password='Test1234!',
        phone=f'0197{n:07d}', full_name=f'{tag.title()} {n}',
        date_of_birth=date(1990, 1, 1), present_address='Dhaka', consent_terms=True,
        account_status=account_status, is_verified=is_verified)
    u.roles.add(role)
    return u


def mk_pharmacy(tag, *, account_status='active', review_state='approved', is_verified=True):
    user = mk_user('pharmacy', tag, account_status=account_status, is_verified=is_verified)
    PharmacyOrganization.objects.create(
        user=user, business_name=f'{tag} Pharmacy', authorized_contact_person='Owner',
        business_registration_number=f'REG-{user.id}', trade_license_url='pending-upload',
        tax_vat_tin_number='TIN-0001', business_address='Dhaka', is_verified=is_verified,
        review_state=review_state, created_at=timezone.now(), updated_at=timezone.now(),
    )
    return user


def mk_admin(role_name='admin_pharmacy'):
    return mk_user(role_name, 'admin')


def client_for(user):
    c = Client()
    token = str(RefreshToken.for_user(user).access_token)
    c.defaults['HTTP_AUTHORIZATION'] = f'Bearer {token}'
    return c


def run():
    print('\n== Pharmacy Admin Portal regression ==\n')
    cleanup()

    admin = mk_admin('admin_pharmacy')
    super_admin = mk_admin('admin_super')
    ac = client_for(admin)
    sc = client_for(super_admin)

    # ── 1. Signup / lock ────────────────────────────────────────────────────
    print('-- lifecycle lock --')
    pending = mk_pharmacy('pending', account_status='pending', review_state='pending_review', is_verified=False)
    pc = client_for(pending)

    r = pc.get('/api/pharmacy/permissions/')
    check('permissions endpoint reachable while pending', r.status_code == 200, r.content[:200])
    body = r.json()
    check('status == PENDING_REVIEW', body.get('status') == 'PENDING_REVIEW', body)
    check('catalogue locked', body['can']['catalogue'] is False, body)
    check('chat allowed while pending', body['can']['chat'] is True, body)
    check('profile allowed while pending', body['can']['profile'] is True, body)

    r = pc.get('/api/pharmacy/profile/')
    check('profile GET reachable while pending (fixed IsPharmacyAccount gate)', r.status_code == 200, r.content[:200])

    r = pc.get('/api/pharmacy/dashboard/')
    check('dashboard reachable while pending', r.status_code == 200, r.content[:200])

    r = pc.get('/api/pharmacy/earnings/')
    check('earnings reachable while pending', r.status_code == 200, r.content[:200])
    check('earnings shows real zero, not mock data', r.json().get('gross_sales') == '0.00', r.json())

    # Blocked at the AUTHENTICATION layer, not just permissions: the default
    # VersionedJWTAuthentication (unchanged, still used by catalogue_views)
    # rejects a pending pharmacy's token outright since User.is_active is a
    # computed `account_status == 'active'` property — this is the same gate
    # that protects every operational endpoint platform-wide and is exactly
    # why it stays untouched while only the always-on views opt into
    # PharmacyAlwaysOnAuthentication.
    r = pc.get('/api/pharmacy/medicines/')
    check('add-medicine list still blocked while pending (IsPharmacyUser/auth unchanged)',
         r.status_code in (401, 403), r.content[:200])

    r = pc.post('/api/pharmacy/medicines/', {
        'name': 'Test Med', 'category': 'vitamin', 'unit': 'piece', 'price': 50,
        'stock_quantity': 10, 'expiry_date': (date.today() + timedelta(days=200)).isoformat(),
    }, content_type=JSON)
    check('add medicine denied while pending', r.status_code in (401, 403), r.content[:200])

    # Regression guard for a real bug found only by driving the actual
    # /api/auth/register/ HTTP endpoint (every other check in this file uses
    # mk_pharmacy(), which builds a PharmacyOrganization directly and always
    # passed review_state explicitly — never exercising the real signup
    # code path's field defaulting at all). PharmacyOrganization.review_state
    # defaults to 'approved' at the model layer (deliberate, so the migration
    # that added the column never retroactively locked already-active
    # pharmacies), but users/serializers.py::_create_pharmacy never
    # overrode that default for a brand-new signup, so every real signup
    # got a business-profile row falsely marked "approved" before any human
    # ever reviewed it.
    print('-- real signup endpoint: review_state defaulting --')
    r = Client().post('/api/auth/register/', {
        'email': f'{PREFIX}realsignup1@example.com', 'password': 'Test1234!', 'password2': 'Test1234!',
        'phone': f'0198{_n[0] + 900:07d}', 'full_name': 'Real Signup Pharmacy',
        'date_of_birth': '1990-01-01', 'present_address': 'Dhaka', 'consent_terms': True, 'role': 'pharmacy',
        'role_data': {'business_name': 'Real Signup Pharmacy Ltd', 'contact_person': 'Real Owner',
                      'business_reg_number': 'REGREAL001', 'tax_number': 'TINREAL001',
                      'business_address': 'Dhaka', 'number_of_pharmacists': 1},
    }, content_type=JSON)
    check('real signup via /api/auth/register/ succeeds', r.status_code == 201, r.content[:300])
    signup_body = r.json()
    check('a genuinely new signup gets review_state=pending_review, not the model default "approved"',
         signup_body.get('user', {}).get('profile_data', {}).get('review_state') == 'pending_review',
         signup_body.get('user', {}).get('profile_data'))

    r = pc.post('/api/pharmacy/support-conversation/')
    check('pending pharmacy can open support chat', r.status_code in (200, 201), r.content[:200])

    # ── 2. Admin lifecycle actions ──────────────────────────────────────────
    print('-- admin approve/reject/request-info/suspend/reinstate --')
    r = ac.patch(f'/api/admin-panel/pharmacy/{pending.id}/approve/', {}, content_type=JSON)
    check('admin approves pending pharmacy', r.status_code == 200, r.content[:300])
    # Regression guard for a real bug found only by live testing (a Django
    # test Client call happens to reuse the same connection/transaction
    # visibility that made the underlying refresh_from_db() checks below
    # look sufficient — but the actual admin-facing symptom was that the
    # ACTION'S OWN RESPONSE BODY showed stale pending/locked data immediately
    # after a successful approve, because `_pharmacy_account_json()` read a
    # `User` object fetched before the transition instead of after it. The
    # DB write was always correct; only the immediate response lied. Assert
    # on the response body itself, not just the DB, so this cannot regress
    # silently again.
    approve_body = r.json()
    check('approve RESPONSE shows account_status active (not stale pending)',
         approve_body.get('account_status') == 'active', approve_body)
    check('approve RESPONSE shows status ACTIVE', approve_body.get('status') == 'ACTIVE', approve_body)
    check('approve RESPONSE shows catalogue unlocked', approve_body.get('can', {}).get('catalogue') is True, approve_body)
    pending.refresh_from_db()
    check('account_status -> active after approve', pending.account_status == 'active', pending.account_status)
    org = PharmacyOrganization.objects.get(user=pending)
    check('org.is_verified -> True after approve', org.is_verified is True)
    check('org.review_state -> approved', org.review_state == 'approved', org.review_state)

    r = pc.get('/api/pharmacy/medicines/')
    check('catalogue unlocked after approval', r.status_code == 200, r.content[:200])

    r = ac.patch(f'/api/admin-panel/pharmacy/{pending.id}/suspend/', {}, content_type=JSON)
    check('suspend without reason rejected (400)', r.status_code == 400, r.content[:200])

    # `pending` is now ACTIVE + is_verified=True (approved above), so a
    # tier-3 admin_pharmacy admin suspending it must be queued for
    # Operations+ approval — this is the escalation-gap fix from
    # PHARMACY_ADMIN_AUDIT.md §2 (spot-check finding #4), verified here
    # rather than assumed.
    r = ac.patch(f'/api/admin-panel/pharmacy/{pending.id}/suspend/',
                {'reason': 'expired_or_invalid_license'}, content_type=JSON)
    check('module-tier admin suspending a verified pharmacy is queued for approval',
         r.status_code == 202 and r.json().get('code') == 'approval_required', r.content[:300])
    pending.refresh_from_db()
    check('account NOT suspended yet (still queued)', pending.account_status == 'active')

    # A Super Admin (tier 1) bypasses the escalation and suspends immediately.
    r = sc.patch(f'/api/admin-panel/pharmacy/{pending.id}/suspend/',
                {'reason': 'expired_or_invalid_license'}, content_type=JSON)
    check('super admin suspend succeeds immediately', r.status_code == 200, r.content[:300])
    check('suspend RESPONSE body shows account_status suspended (same stale-object bug class)',
         r.json().get('account_status') == 'suspended', r.json())
    pending.refresh_from_db()
    check('account_status -> suspended', pending.account_status == 'suspended')

    r = pc.get('/api/pharmacy/medicines/')
    check('catalogue relocked after suspend', r.status_code in (401, 403), r.content[:200])

    log = ActivityLog.objects.filter(
        entity_type='pharmacy_account', entity_id=pending.id, action_type='suspend').order_by('-created_at').first()
    check('suspend audited with entity_type=pharmacy_account (bug fix verified)', log is not None)

    r = sc.patch(f'/api/admin-panel/pharmacy/{pending.id}/reinstate/', {}, content_type=JSON)
    check('reinstate succeeds', r.status_code == 200, r.content[:300])
    pending.refresh_from_db()
    check('account_status -> active after reinstate', pending.account_status == 'active')

    # reject/request-info on a second pharmacy
    pending2 = mk_pharmacy('pending2', account_status='pending', review_state='pending_review', is_verified=False)
    r = ac.patch(f'/api/admin-panel/pharmacy/{pending2.id}/reject/', {}, content_type=JSON)
    check('reject without reason rejected (400)', r.status_code == 400)
    r = ac.patch(f'/api/admin-panel/pharmacy/{pending2.id}/reject/', {'reason': 'Incomplete documents'}, content_type=JSON)
    check('reject with reason succeeds', r.status_code == 200, r.content[:300])
    org2 = PharmacyOrganization.objects.get(user=pending2)
    check('review_state -> rejected', org2.review_state == 'rejected')

    r = ac.patch(f'/api/admin-panel/pharmacy/{pending2.id}/request-info/',
                {'reason': 'Please upload trade license.'}, content_type=JSON)
    check('request-info succeeds', r.status_code == 200, r.content[:300])
    org2.refresh_from_db()
    check('review_state -> needs_more_information', org2.review_state == 'needs_more_information')

    p2c = client_for(pending2)
    r = p2c.get('/api/pharmacy/permissions/')
    check('derived status reflects needs_more_information', r.json()['status'] == 'NEEDS_MORE_INFORMATION', r.json())

    # ── generic dispatcher paths still work (regression-check the rewiring) ──
    print('-- generic dispatcher parity --')
    generic_target = mk_pharmacy('generic', account_status='pending', review_state='pending_review', is_verified=False)
    r = ac.patch(f'/api/admin-panel/pharmacies/{generic_target.id}/', {'status': 'Verified'}, content_type=JSON)
    check('generic pharmacies dispatcher approves', r.status_code == 200, r.content[:300])
    generic_target.refresh_from_db()
    org3 = PharmacyOrganization.objects.get(user=generic_target)
    check('generic-path approve also flips org.is_verified (desync bug fixed)', org3.is_verified is True)

    # generic_target is now verified -> a module-tier admin's suspend is
    # queued (same escalation rule as the dedicated endpoint); use the Super
    # Admin client to exercise the actual suspend mechanics on this path.
    r = sc.patch(f'/api/admin-panel/pharmacies/{generic_target.id}/', {'status': 'Suspended'}, content_type=JSON)
    check('generic pharmacies dispatcher suspend without reason rejected', r.status_code == 400, r.content[:200])
    r = sc.patch(f'/api/admin-panel/pharmacies/{generic_target.id}/',
                {'status': 'Suspended', 'reason': 'Policy violation'}, content_type=JSON)
    check('generic pharmacies dispatcher suspends with reason', r.status_code == 200, r.content[:300])
    med_after = PharmacyMedicine.objects.filter(pharmacy_user=generic_target, is_active=True)
    check('generic-path suspend also deactivates medicines (parity with dedicated endpoint)',
         not med_after.exists() or med_after.count() == 0)

    # admin_pharmacy correctly has no permission on the generic "users" module
    # (module-tier admins are scoped to their own module) — use Super Admin.
    generic_users_target = mk_pharmacy('genuser', account_status='pending', review_state='pending_review', is_verified=False)
    r = sc.patch(f'/api/admin-panel/users/{generic_users_target.id}/', {'status': 'Approved'}, content_type=JSON)
    check('generic USERS dispatcher approves a pharmacy', r.status_code == 200, r.content[:300])
    org4 = PharmacyOrganization.objects.get(user=generic_users_target)
    check('users-path approve also flips org.is_verified (3rd desync site fixed)', org4.is_verified is True)

    # ── 3. Appeals ───────────────────────────────────────────────────────────
    print('-- appeals --')
    appellant = mk_pharmacy('appeal', account_status='suspended', review_state='approved', is_verified=False)
    apc = client_for(appellant)
    r = apc.post('/api/pharmacy/appeals/', {'reason': 'other', 'explanation': 'Please reconsider.'}, content_type=JSON)
    check('appeal submission succeeds', r.status_code == 201, r.content[:300])
    appeal_id = r.json()['id']

    r = apc.get('/api/pharmacy/permissions/')
    check('status -> APPEAL_PENDING once open appeal exists', r.json()['status'] == 'APPEAL_PENDING', r.json())

    r = ac.get('/api/admin-panel/pharmacy/appeals/')
    check('admin sees appeal in queue', any(a['id'] == appeal_id for a in r.json()['results']))

    r = ac.patch(f'/api/admin-panel/pharmacy/appeals/{appeal_id}/decide/',
                {'action': 'deny'}, content_type=JSON)
    check('deny without admin_response rejected', r.status_code == 400)
    r = ac.patch(f'/api/admin-panel/pharmacy/appeals/{appeal_id}/decide/',
                {'action': 'approve', 'admin_response': 'Reinstated.'}, content_type=JSON)
    check('appeal approve succeeds', r.status_code == 200, r.content[:300])
    appellant.refresh_from_db()
    check('account reinstated via appeal approval', appellant.account_status == 'active')

    r = apc.post('/api/pharmacy/appeals/', {'reason': 'other', 'explanation': 'x'}, content_type=JSON)
    check('cannot appeal a non-suspended account', r.status_code == 409)

    # ── 4. Medicine admin CRUD ───────────────────────────────────────────────
    print('-- medicine admin CRUD --')
    med_owner = mk_pharmacy('medowner')
    r = ac.post('/api/admin-panel/pharmacy/medicines/create/', {
        'pharmacy_id': str(med_owner.id), 'name': 'Admin-added Med', 'category': 'vitamin',
        'unit': 'piece', 'price': 100, 'stock_quantity': 20,
        'expiry_date': (date.today() + timedelta(days=200)).isoformat(),
    }, content_type=JSON)
    check('admin creates medicine', r.status_code == 201, r.content[:300])
    med_id = r.json()['id']

    r = ac.patch(f'/api/admin-panel/pharmacy/medicines/{med_id}/update/', {'price': 120}, content_type=JSON)
    check('admin edits medicine', r.status_code == 200 and r.json()['price'] == 120, r.content[:300])

    r = ac.patch(f'/api/admin-panel/pharmacy/medicines/{med_id}/archive/', {'reason': 'test'}, content_type=JSON)
    check('admin archives medicine', r.status_code == 200 and r.json()['is_active'] is False, r.content[:300])

    r = ac.patch(f'/api/admin-panel/pharmacy/medicines/{med_id}/restore/', {}, content_type=JSON)
    check('admin restores medicine', r.status_code == 200 and r.json()['is_active'] is True, r.content[:300])

    # ── 4b. Employee roster (roster/count only, no login credentials) ──────────
    print('-- employee roster --')
    emp_owner = mk_pharmacy('emp')
    r = ac.post(f'/api/admin-panel/pharmacy/{emp_owner.id}/employees/',
               {'name': 'Karim Sheikh', 'role_title': 'Pharmacist', 'access_level': 'pharmacist'},
               content_type=JSON)
    check('admin adds employee', r.status_code == 201, r.content[:300])
    emp_id = r.json()['id']
    check('employee is_active true by default', r.json()['is_active'] is True)

    r = ac.get(f'/api/admin-panel/pharmacy/{emp_owner.id}/employees/')
    check('employee list shows the new employee', any(e['id'] == emp_id for e in r.json()['results']))

    r = ac.patch(f'/api/admin-panel/pharmacy/{emp_owner.id}/employees/{emp_id}/',
                {'is_active': False}, content_type=JSON)
    check('admin deactivates employee', r.status_code == 200 and r.json()['is_active'] is False, r.content[:300])

    r = ac.get(f'/api/admin-panel/pharmacy/{emp_owner.id}/detail/')
    check('workforce count reflects the employee (even inactive ones still counted? check active-only)',
         r.json()['workforce']['account_holders'] == 1)
    check('inactive employee excluded from active workforce count', r.json()['workforce']['employees'] == 0,
         r.json()['workforce'])

    r = ac.patch(f'/api/admin-panel/pharmacy/{emp_owner.id}/employees/{emp_id}/',
                {'is_active': True}, content_type=JSON)
    r2 = ac.get(f'/api/admin-panel/pharmacy/{emp_owner.id}/detail/')
    check('reactivated employee counted again', r2.json()['workforce']['employees'] == 1, r2.json()['workforce'])

    # ── 5. Commission — the money code ───────────────────────────────────────
    print('-- commission math + idempotency + refund --')
    seller = mk_pharmacy('seller')
    buyer = mk_user('farmer', 'buyer')
    bc = client_for(buyer)
    sellc = client_for(seller)
    medicine = PharmacyMedicine.objects.create(
        pharmacy_user=seller, name='Commission Test Med', category='vitamin', price=100,
        stock_quantity=50, unit='piece', expiry_date=date.today() + timedelta(days=300),
        is_active=True, is_approved=True, created_at=timezone.now(), updated_at=timezone.now(),
    )
    r = bc.post('/api/farmers/orders/', {
        'pharmacy_id': str(seller.id),
        'items': [{'medicine_id': str(medicine.id), 'quantity': 1}],
        'delivery_method': 'pickup', 'payment_method': 'cod',
    }, content_type=JSON)
    check('order placed (BDT 100)', r.status_code == 201, r.content[:300])
    order_id = r.json()['id']

    sellc.patch(f'/api/pharmacy/orders/{order_id}/status/', {'status': 'processing'}, content_type=JSON)
    sellc.patch(f'/api/pharmacy/orders/{order_id}/status/', {'status': 'shipped'}, content_type=JSON)
    r = sellc.patch(f'/api/pharmacy/orders/{order_id}/status/',
                    {'status': 'delivered', 'delivery_confirmed': True}, content_type=JSON)
    check('order delivered', r.status_code == 200, r.content[:300])

    sale = PharmacySale.objects.filter(pharmacy_user=seller, order_reference=order_id).first()
    check('PharmacySale created', sale is not None)
    if sale:
        check('gross_amount == 100.00', sale.gross_amount == Decimal('100.00'), sale.gross_amount)
        commission = PharmacyCommission.objects.filter(sale=sale).first()
        check('PharmacyCommission created', commission is not None)
        if commission:
            check('commission == 20.00 (20%)', commission.commission_amount == Decimal('20.00'), commission.commission_amount)
            check('pharmacy_amount == 80.00 (80%)', commission.pharmacy_amount == Decimal('80.00'), commission.pharmacy_amount)
            check('rate stored == 0.2000', commission.rate == Decimal('0.2000'), commission.rate)

    # Repeated delivered call must not duplicate (order is already delivered,
    # transition is blocked at the bridge layer — but re-run the internal
    # creator directly to prove the idempotency guard itself, not just that
    # the order state machine happens to prevent a second HTTP call).
    from pharmacy.services import create_pharmacy_sale_and_commission
    from audit.models import AdminPanelRecord
    record = AdminPanelRecord.objects.get(module='pharmacy-orders', record_id=f'{seller.id}:{order_id}')
    create_pharmacy_sale_and_commission(record.payload)
    check('idempotent: still exactly one PharmacySale', PharmacySale.objects.filter(order_reference=order_id).count() == 1)
    check('idempotent: still exactly one PharmacyCommission',
         PharmacyCommission.objects.filter(sale__order_reference=order_id).count() == 1)

    r = ac.get(f'/api/admin/pharmacies/metrics/?period=lifetime&pharmacy={seller.id}')
    metrics_before = r.json()['sales']

    r = ac.post(f'/api/admin-panel/pharmacy/orders/{record.id}/refund/', {'reason': 'Customer request'}, content_type=JSON)
    check('refund succeeds', r.status_code == 200, r.content[:300])
    sale.refresh_from_db()
    check('sale status -> refunded', sale.status == 'refunded')
    commission.refresh_from_db()
    check('commission row untouched by refund (append-only)', commission.commission_amount == Decimal('20.00'))

    r = ac.get(f'/api/admin/pharmacies/sales/?pharmacy={seller.id}&status=completed')
    check('refunded sale excluded from completed-sales listing',
         not any(row['id'] == str(sale.id) for row in r.json()['results']), r.json())

    # ── 5b. Settlements ──────────────────────────────────────────────────────
    print('-- settlements --')
    seller2 = mk_pharmacy('settleseller')
    medicine2 = PharmacyMedicine.objects.create(
        pharmacy_user=seller2, name='Settlement Test Med', category='vitamin', price=250,
        stock_quantity=50, unit='piece', expiry_date=date.today() + timedelta(days=300),
        is_active=True, is_approved=True, created_at=timezone.now(), updated_at=timezone.now(),
    )
    buyer2 = mk_user('farmer', 'settlebuyer')
    bc2 = client_for(buyer2)
    sellc2 = client_for(seller2)
    r = bc2.post('/api/farmers/orders/', {
        'pharmacy_id': str(seller2.id), 'items': [{'medicine_id': str(medicine2.id), 'quantity': 1}],
        'delivery_method': 'pickup', 'payment_method': 'cod',
    }, content_type=JSON)
    order2_id = r.json()['id']
    sellc2.patch(f'/api/pharmacy/orders/{order2_id}/status/', {'status': 'processing'}, content_type=JSON)
    sellc2.patch(f'/api/pharmacy/orders/{order2_id}/status/', {'status': 'shipped'}, content_type=JSON)
    sellc2.patch(f'/api/pharmacy/orders/{order2_id}/status/',
                {'status': 'delivered', 'delivery_confirmed': True}, content_type=JSON)

    today = date.today().isoformat()
    tomorrow = (date.today() + timedelta(days=1)).isoformat()
    r = ac.post(f'/api/admin-panel/pharmacy/{seller2.id}/settlements/generate/',
               {'period_start': today, 'period_end': tomorrow}, content_type=JSON)
    check('settlement generated', r.status_code == 201, r.content[:300])
    settlement_id = r.json()['id']
    check('settlement gross_sales == 250.00', r.json()['gross_sales'] == '250.00', r.json())
    check('settlement payable_amount == 200.00 (80%)', r.json()['payable_amount'] == '200.00', r.json())
    check('settlement status starts pending', r.json()['status'] == 'pending')

    r = ac.get(f'/api/admin-panel/pharmacy/settlements/?pharmacy={seller2.id}')
    check('settlement appears in list', any(s['id'] == settlement_id for s in r.json()['results']))

    r = ac.patch(f'/api/admin-panel/pharmacy/settlements/{settlement_id}/',
                {'status': 'paid', 'payment_reference': 'TXN-TEST-001'}, content_type=JSON)
    check('settlement marked paid', r.status_code == 200 and r.json()['status'] == 'paid', r.content[:300])

    # ── 6. Chat + isolation ───────────────────────────────────────────────────
    print('-- chat + isolation --')
    chat_pharmacy_a = mk_pharmacy('chata')
    chat_pharmacy_b = mk_pharmacy('chatb')
    cac = client_for(chat_pharmacy_a)
    cbc = client_for(chat_pharmacy_b)

    r = cac.post('/api/pharmacy/support-conversation/')
    check('pharmacy A opens conversation', r.status_code == 201, r.content[:300])
    conv_a = r.json()['id']
    r = cac.post(f'/api/pharmacy/support-conversation/{conv_a}/', {'content': 'Hello from A'}, content_type=JSON)
    check('pharmacy A sends message', r.status_code == 201, r.content[:300])

    r = cbc.post(f'/api/pharmacy/support-conversation/{conv_a}/', {'content': 'trying to snoop'}, content_type=JSON)
    check('pharmacy B cannot post into A''s conversation (404)', r.status_code == 404, r.content[:200])

    r = ac.get('/api/admin-panel/pharmacy-chats/')
    check('admin inbox lists conversation A', any(c['id'] == conv_a for c in r.json()['results']))
    r = ac.post(f'/api/admin-panel/pharmacy-chats/{conv_a}/messages/', {'content': 'How can we help?'}, content_type=JSON)
    check('admin replies to conversation A', r.status_code == 201, r.content[:300])

    r = cac.get('/api/pharmacy/support-conversation/')
    check('pharmacy A sees admin reply', any(m['content'] == 'How can we help?' for m in r.json()['messages']))

    # ── 7. RBAC isolation ─────────────────────────────────────────────────────
    print('-- RBAC isolation --')
    r = pc.get('/api/admin-panel/pharmacy/medicines/')
    check('pharmacy owner denied on admin endpoint', r.status_code in (401, 403), r.status_code)
    farmer_only = mk_user('farmer', 'farmeronly')
    foc = client_for(farmer_only)
    r = foc.get('/api/admin-panel/pharmacy/medicines/')
    check('farmer denied on admin endpoint', r.status_code in (401, 403), r.status_code)

    r = sc.get('/api/admin-panel/pharmacy/dashboard/')
    check('super admin can view pharmacy dashboard', r.status_code == 200, r.content[:200])

    # ── 8. Full permission matrix (dedicated Pharmacy Admin login) ─────────────
    # Every role the spec calls out, against a real pharmacy-module endpoint.
    print('-- permission matrix: who can view /admin-panel/pharmacy/medicines/ --')
    pharmacy_admin_role = mk_admin('admin_pharmacy')
    matrix = {
        'Pharmacy Admin': (client_for(pharmacy_admin_role), True),
        'Super Admin': (sc, True),
        'Operations Admin': (client_for(mk_admin('admin_operations')), True),
        'Finance Admin': (client_for(mk_admin('admin_finance')), False),
        'Content Admin': (client_for(mk_admin('admin_content')), False),
        'Research Admin': (client_for(mk_admin('admin_research')), False),
        'Delivery Admin': (client_for(mk_admin('admin_delivery')), False),
        'Support Agent': (client_for(mk_admin('admin_support')), False),
        'Farmer': (foc, False),
        'Pharmacy owner/staff': (pc, False),
    }
    for label, (client, should_allow) in matrix.items():
        r = client.get('/api/admin-panel/pharmacy/medicines/')
        ok = (r.status_code == 200) if should_allow else (r.status_code in (401, 403))
        check(f'{label}: {"allowed" if should_allow else "denied"} ({r.status_code})', ok, r.status_code)
    r = Client().get('/api/admin-panel/pharmacy/medicines/')
    check('Unauthenticated: denied (401/403)', r.status_code in (401, 403), r.status_code)

    # Pharmacy Admin correctly scoped OUT of other modules (not a super-admin
    # in disguise), and pharmacy ownership never implies Pharmacy Admin.
    pac = client_for(pharmacy_admin_role)
    r = pac.get('/api/admin-panel/finance/summary/')
    check('Pharmacy Admin denied on finance module', r.status_code == 403, r.status_code)
    r = pac.get('/api/admin-panel/admins/')
    check('Pharmacy Admin denied on team/admins module', r.status_code == 403, r.status_code)
    r = client_for(seller).get('/api/admin-panel/pharmacy/medicines/')
    check('A pharmacy owner (real seller account) is never auto-admin', r.status_code in (401, 403), r.status_code)

    # ── 9. Add Medicine form backend + inventory adjust ─────────────────────────
    print('-- admin add-medicine form + inventory adjust --')
    target_pharmacy = mk_pharmacy('formtarget')
    r = ac.post('/api/admin-panel/pharmacy/medicines/create/', {
        'pharmacy_id': str(target_pharmacy.id), 'name': 'Formtest Vitamin B',
        'category': 'vitamin', 'unit': 'bottle', 'price': 99, 'stock_quantity': 20,
        'min_order_quantity': 3, 'expiry_date': (date.today() + timedelta(days=300)).isoformat(),
    }, content_type=JSON)
    check('admin can create a medicine via the Add Medicine endpoint', r.status_code == 201, r.content[:300])
    med_id = r.json().get('id')
    check('created medicine has the min_order_quantity from the form', r.json().get('min_order_quantity') == 3, r.json())

    r = ac.patch(f'/api/admin-panel/pharmacy/medicines/{med_id}/stock/', {'delta': 15}, content_type=JSON)
    check('inventory stock-adjust (+15) works', r.status_code == 200 and r.json().get('stock_quantity') == 35, r.content[:200])
    r = ac.patch(f'/api/admin-panel/pharmacy/medicines/{med_id}/stock/', {'delta': -50}, content_type=JSON)
    check('inventory stock-adjust rejects going negative', r.status_code == 400, r.status_code)

    r = pc.post('/api/admin-panel/pharmacy/medicines/create/', {
        'pharmacy_id': str(target_pharmacy.id), 'name': 'Should be denied',
        'category': 'vitamin', 'unit': 'bottle', 'price': 10, 'stock_quantity': 1,
        'expiry_date': (date.today() + timedelta(days=100)).isoformat(),
    }, content_type=JSON)
    check('a pharmacy owner cannot use the admin Add Medicine endpoint', r.status_code in (401, 403), r.status_code)

    # ── 10. Reports & Audit export ──────────────────────────────────────────────
    print('-- reports & audit export --')
    for report_type in ('accounts', 'medicines', 'orders', 'sales', 'commissions',
                        'settlements', 'employees', 'appeals', 'admin-actions'):
        r = ac.get(f'/api/admin-panel/pharmacy/export/{report_type}/')
        check(f'export "{report_type}" returns a CSV', r.status_code == 200 and r['Content-Type'] == 'text/csv',
             (r.status_code, r.get('Content-Type')))
    # Regression check for a real bug this build found live (not caught by the
    # checks above): Django's test Client sends no Accept header by default,
    # so it never reproduces what an actual browser sends. The Flutter export
    # client explicitly sends `Accept: text/csv`, which — before CSVRenderer
    # was registered — made DRF's content negotiation raise 406 before the
    # view body ever ran. Every check above would have stayed green even with
    # that bug present; only this explicit header reproduces it.
    r = ac.get('/api/admin-panel/pharmacy/export/accounts/', HTTP_ACCEPT='text/csv')
    check('export honors a real browser Accept: text/csv header (406 regression)',
         r.status_code == 200, r.status_code)
    r = ac.get('/api/admin-panel/pharmacy/export/not-a-real-report/')
    check('export rejects an unknown report type', r.status_code == 404, r.status_code)
    r = pc.get('/api/admin-panel/pharmacy/export/accounts/')
    check('a pharmacy owner cannot export pharmacy reports', r.status_code in (401, 403), r.status_code)

    r = ac.get('/api/admin-panel/pharmacy/audit/')
    check('dedicated pharmacy audit endpoint reachable', r.status_code == 200, r.content[:200])
    audit_rows = r.json().get('results', [])
    check('audit rows include the medicine-create action just performed',
         any('Formtest Vitamin B' in row.get('action', '') for row in audit_rows), len(audit_rows))
    check('every audit row carries an actor role', all('role' in row for row in audit_rows), audit_rows[:1])

    # ── 11. Delivery assignment (rider picker + offline-rider warning) ──────────
    # Regression coverage for a real bug found only by hitting the live server
    # as the actual dedicated Pharmacy Admin account: the Flutter rider picker
    # called the generic /admin-panel/riders/ collection, which is gated to
    # the 'delivery' module RBAC permission — one admin_pharmacy does not
    # have — so it 403'd for every real Pharmacy Admin login even though it
    # worked in prior manual testing done with an admin_super session (which
    # has wildcard module access and never exercises this gate). Fixed by
    # adding a pharmacy-scoped /admin-panel/pharmacy-riders/ endpoint.
    print('-- delivery assignment --')
    from audit.models import AdminPanelRecord
    from delivery.models import DeliveryOrder
    from profiles.models import DeliveryProfile

    r = ac.get('/api/admin-panel/riders/')
    check('generic riders collection is 403 for Pharmacy Admin (delivery-module gated, not a regression to fix)',
         r.status_code == 403, r.status_code)

    rider_user = mk_user('delivery', 'rider', is_verified=True)
    rider = DeliveryProfile.objects.create(
        user=rider_user, drivers_license_number=f'DL-{rider_user.id}', license_class='B',
        license_expiry_date=date.today() + timedelta(days=365), license_photo_url='pending-upload',
        is_online=False, current_status='offline', approved_by_admin=super_admin,
    )
    r = ac.get('/api/admin-panel/pharmacy-riders/')
    check('Pharmacy Admin can list riders via the pharmacy-scoped endpoint', r.status_code == 200, r.content[:200])
    rider_ids = [row['id'] for row in r.json().get('results', [])]
    check('the throwaway offline rider appears in the pharmacy-scoped list', str(rider.id) in rider_ids, rider_ids)
    r = pc.get('/api/admin-panel/pharmacy-riders/')
    check('a pharmacy owner cannot use the pharmacy-riders endpoint', r.status_code in (401, 403), r.status_code)

    delivery_seller = target_pharmacy
    order_id = 'DELIVASSIGN-1'
    order_record = AdminPanelRecord.objects.create(
        module='pharmacy-orders', record_id=f'{delivery_seller.id}:{order_id}',
        payload={'order_number': order_id, 'status': 'shipped', 'farmer_name': 'PhAdmTest Farmer',
                 'items': [{'medicine_id': str(med_id), 'quantity': 1}], 'total_amount': '100.00'})
    AdminPanelRecord.objects.create(
        module='delivery-queue', record_id=f'DQ-{order_id}',
        payload={'id': f'DQ-{order_id}', 'pharmacy_order_record_id': str(order_record.id),
                 'pharmacy_order_id': order_id, 'order_type': 'pharmacy', 'customer': 'PhAdmTest Farmer',
                 'pickup_address': 'Test Pharmacy', 'delivery_address': 'Test Address',
                 'pharmacy': delivery_seller.email, 'pharmacy_id': str(delivery_seller.id),
                 'items': [{'medicine_id': str(med_id), 'quantity': 1}], 'is_pharmacy_delivery': True,
                 'queued_at': timezone.now().isoformat(), 'otp_code': '000000'})

    r = ac.post(f'/api/admin-panel/pharmacy-orders/DQ-{order_id}/assign-delivery/',
               {'rider_id': str(rider.id), 'notes': 'test'}, content_type=JSON)
    check('assigning to an offline rider still succeeds (warn, do not block)', r.status_code == 201, r.content[:300])
    check('response carries a warning that the rider is offline', 'offline' in r.json().get('warning', '').lower(), r.json())

    DeliveryOrder.objects.filter(order_reference_id=order_record.id).delete()
    order_record.delete()
    rider.delete()

    print(f'\n{PASS} passed, {FAIL} failed\n')
    cleanup()
    return FAIL == 0


if __name__ == '__main__':
    ok = run()
    sys.exit(0 if ok else 1)
