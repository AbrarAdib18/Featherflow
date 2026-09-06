"""End-to-end check of the Admin Panel RBAC / audit / approval-queue backend.

Run:  backend/venv/Scripts/python.exe backend/scripts/test_admin_panel.py

Uses Django's test Client against the *live* configured database. It creates a
handful of throw-away admin/user accounts (prefixed ``adminpaneltest+``) and
leaves them; re-running is idempotent.
"""
import os
import sys
import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
os.environ.setdefault('THROTTLE_ADMIN_READ', '100000/min')
os.environ.setdefault('THROTTLE_ADMIN_WRITE', '100000/min')
os.environ.setdefault('THROTTLE_ADMIN_EXPORT', '100000/min')
os.environ.setdefault('THROTTLE_ADMIN_POLL', '100000/min')
django.setup()

from django.conf import settings as dj_settings
if 'testserver' not in dj_settings.ALLOWED_HOSTS:
    dj_settings.ALLOWED_HOSTS.append('testserver')

from datetime import date

from django.test import Client
from rest_framework_simplejwt.tokens import RefreshToken

from audit.models import AdminApprovalQueue
from profiles.models import AdminProfile, DoctorProfile
from users.models import Role, User

PASS, FAIL = 0, 0


def check(name, cond, extra=''):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f'  ok   {name}')
    else:
        FAIL += 1
        print(f'  FAIL {name}  {extra}')


def ensure_admin(email, role_name, tier_hint=3):
    role = Role.objects.get(name=role_name)
    import hashlib
    phone = '+8801' + hashlib.md5(email.encode()).hexdigest()[:9]
    user, created = User.objects.get_or_create(email=email, defaults=dict(
        full_name=email.split('@')[0].replace('adminpaneltest+', 'Test '),
        phone=phone, date_of_birth=date(1990, 1, 1),
        present_address='Test', consent_terms=True, account_status='active',
    ))
    user.set_password('Testpass!2026')
    user.account_status = 'active'
    user.save()
    user.roles.clear()
    user.roles.add(role)
    AdminProfile.objects.update_or_create(user=user, defaults=dict(
        admin_role=role, job_title='Tester', department='QA',
        start_date=date(2024, 1, 1), admin_sub_role=role_name.replace('admin_', ''),
        approval_status='approved', is_active=True, is_suspended=False,
        internal_approval_by_founder_hr=True,
    ))
    return user


def auth(client, user):
    token = str(RefreshToken.for_user(user).access_token)
    client.defaults['HTTP_AUTHORIZATION'] = f'Bearer {token}'


def main():
    c = Client()
    super_admin = ensure_admin('adminpaneltest+super@featherflow.dev', 'admin_super')
    ops = ensure_admin('adminpaneltest+ops@featherflow.dev', 'admin_operations')
    finance = ensure_admin('adminpaneltest+finance@featherflow.dev', 'admin_finance')
    delivery = ensure_admin('adminpaneltest+delivery@featherflow.dev', 'admin_delivery')
    support = ensure_admin('adminpaneltest+support@featherflow.dev', 'admin_support')

    print('\n== auth/login serialises an admin (regression) ==')
    finance.set_password('Testpass!2026')
    finance.save(update_fields=['password'])
    r = c.post('/api/auth/login/',
               data={'email': finance.email, 'password': 'Testpass!2026'},
               content_type='application/json')
    check('admin login 200', r.status_code == 200, r.content[:200])
    if r.status_code == 200:
        body = r.json()
        check('login payload carries roles', 'admin_finance' in body['user']['roles'], body['user']['roles'])
        check('login profile_data is json-clean', isinstance(body['user'].get('profile_data'), dict))

    print('\n== /admin-panel/me/ ==')
    auth(c, finance)
    r = c.get('/api/admin-panel/me/')
    check('finance me 200', r.status_code == 200, r.content[:200])
    body = r.json()
    check('finance tier == 3', body.get('tier') == 3, body)
    check('finance has finance perms', 'finance' in body.get('permissions', {}), body.get('permissions'))
    check('finance lacks delivery perms', 'delivery' not in body.get('permissions', {}), body.get('permissions'))
    check('finance not super', body.get('is_super_admin') is False)

    print('\n== RBAC gating ==')
    r = c.get('/api/admin-panel/payments/')
    check('finance can read payments', r.status_code == 200, r.content[:120])
    r = c.get('/api/admin-panel/riders/')
    check('finance BLOCKED from riders (403)', r.status_code == 403, r.status_code)
    auth(c, delivery)
    r = c.get('/api/admin-panel/riders/')
    check('delivery can read riders', r.status_code == 200, r.content[:120])
    r = c.get('/api/admin-panel/payments/')
    check('delivery BLOCKED from payments (403)', r.status_code == 403, r.status_code)
    auth(c, support)
    r = c.get('/api/admin-panel/audit-logs/')
    check('support can read audit', r.status_code == 200, r.status_code)
    r = c.post('/api/admin-panel/admins/', data={}, content_type='application/json')
    check('support BLOCKED from creating admin (403)', r.status_code == 403, r.status_code)

    print('\n== audit logging ==')
    auth(c, super_admin)
    before = _log_count()
    target = User.objects.filter(account_status='pending').exclude(email__startswith='adminpaneltest').first()
    if target is None:
        target = User.objects.filter(roles__name='farmer').first()
    r = c.patch(f'/api/admin-panel/users/{target.id}/',
                data={'status': 'Approved', 'reason': 'e2e test approve'},
                content_type='application/json')
    check('super approve user 200', r.status_code == 200, r.content[:200])
    check('audit row written', _log_count() > before, f'{before}->{_log_count()}')
    latest = _latest_log()
    check('audit row has reason', (latest.reason or '') == 'e2e test approve', latest.reason)
    check('audit row has action_type', latest.action_type in ('approve', 'edit'), latest.action_type)

    print('\n== immutable audit ==')
    try:
        latest.action = 'tampered'
        latest.save()
        check('audit UPDATE blocked', False, 'save() succeeded')
    except Exception:
        check('audit UPDATE blocked', True)

    print('\n== approval queue (low tier suspends verified doctor) ==')
    vd = DoctorProfile.objects.filter(is_verified=True).select_related('user').first()
    if vd is None:
        vd = DoctorProfile.objects.select_related('user').first()
        if vd:
            vd.is_verified = True
            vd.save(update_fields=['is_verified'])
    if vd is None:
        vd = _make_test_doctor()
    if vd is not None:
        # doctor-admin tier 3 suspends a verified doctor -> should queue (needs tier<=2)
        doctor_admin = ensure_admin('adminpaneltest+doc@featherflow.dev', 'admin_doctor')
        auth(c, doctor_admin)
        q_before = AdminApprovalQueue.objects.filter(status='pending').count()
        r = c.patch(f'/api/admin-panel/doctors/{vd.id}/',
                    data={'status': 'Suspended', 'reason': 'e2e queue test'},
                    content_type='application/json')
        check('suspend verified doctor -> 202 queued', r.status_code == 202, f'{r.status_code} {r.content[:160]}')
        check('queue grew', AdminApprovalQueue.objects.filter(status='pending').count() > q_before)
        qid = r.json().get('approval_id') if r.status_code == 202 else None

        # requester cannot self-approve
        if qid:
            r = c.post(f'/api/admin-panel/approval-queue/{qid}/decide/',
                       data={'decision': 'approve'}, content_type='application/json')
            check('requester cannot self-approve (400/403)', r.status_code in (400, 403), r.status_code)
            # ops approves
            auth(c, ops)
            r = c.post(f'/api/admin-panel/approval-queue/{qid}/decide/',
                       data={'decision': 'approve'}, content_type='application/json')
            check('ops approves queued action 200', r.status_code == 200, r.content[:200])
            vd.user.refresh_from_db()
            check('doctor now suspended', vd.user.account_status == 'suspended', vd.user.account_status)
            # restore for re-runs
            vd.user.account_status = 'active'
            vd.user.save(update_fields=['account_status'])

    print('\n== BUG FIX: delivery admin can assign a rider end-to-end ==')
    _delivery_assign_checks(c, ensure_admin)

    print('\n== SHIFT TIMER + HOURLY PAYMENT ==')
    _shift_payment_checks(c, ensure_admin, auth)

    print('\n== admin management (super only) ==')
    auth(c, super_admin)
    r = c.get('/api/admin-panel/admins/')
    check('list admins 200', r.status_code == 200, r.status_code)
    r = c.post('/api/admin-panel/admins/', data={
        'email': 'adminpaneltest+new@featherflow.dev', 'role': 'admin_pharmacy',
        'name': 'New Pharmacy Admin', 'job_title': 'Pharmacy Ops', 'department': 'Pharmacy',
    }, content_type='application/json')
    check('create admin 201 or 400(exists)', r.status_code in (201, 400), r.content[:200])
    auth(c, finance)
    r = c.post('/api/admin-panel/admins/', data={'email': 'x@y.z', 'role': 'admin_pharmacy'},
               content_type='application/json')
    check('finance cannot create admin (403)', r.status_code == 403, r.status_code)

    print('\n== oversight / escalations / export / polling ==')
    auth(c, ops)
    r = c.get('/api/admin-panel/oversight/')
    check('oversight 200 for ops', r.status_code == 200, r.content[:160])
    auth(c, support)
    r = c.post('/api/admin-panel/escalations/', data={
        'subject': 'e2e escalation', 'module': 'support', 'priority': 'high',
        'detail': 'testing'}, content_type='application/json')
    check('support raises escalation 201', r.status_code == 201, r.content[:160])
    eid = r.json().get('id') if r.status_code == 201 else None
    if eid:
        auth(c, ops)
        r = c.post(f'/api/admin-panel/escalations/{eid}/resolve/',
                   data={'resolution': 'handled in e2e'}, content_type='application/json')
        check('ops resolves escalation 200', r.status_code == 200, r.content[:160])
    auth(c, finance)
    r = c.get('/api/admin-panel/payments/export/')
    check('finance exports payments CSV', r.status_code == 200 and 'text/csv' in r['Content-Type'], r.status_code)
    auth(c, delivery)
    r = c.get('/api/admin-panel/payments/export/')
    check('delivery cannot export payments (403)', r.status_code == 403, r.status_code)

    print('\n== user-facing polling ==')
    farmer = User.objects.filter(roles__name='farmer').first()
    if farmer:
        auth(c, farmer)
        r = c.get('/api/me/updates/')
        check('me/updates 200', r.status_code == 200, r.content[:160])
        check('me/updates has server_time', 'server_time' in r.json())

    print(f'\n==== {PASS} passed, {FAIL} failed ====')
    sys.exit(1 if FAIL else 0)


def _delivery_assign_checks(c, ensure_admin):
    """Regression for 'delivery admin cannot assign riders'. Seeds a queue row
    and an approved rider, then assigns as a delivery admin (not super)."""
    import uuid as _uuid
    from audit.models import AdminPanelRecord
    from delivery.models import DeliveryOrder
    from profiles.models import DeliveryProfile
    from datetime import date as _date

    delivery_admin = ensure_admin('adminpaneltest+deliv@featherflow.dev', 'admin_delivery')
    finance_admin = ensure_admin('adminpaneltest+fin2@featherflow.dev', 'admin_finance')

    # an approved rider
    rider_user, _ = User.objects.get_or_create(email='adminpaneltest+rider@featherflow.dev', defaults=dict(
        full_name='Test Rider', phone='+8801' + __import__('hashlib').md5(b'rider').hexdigest()[:9],
        date_of_birth=_date(1990, 1, 1), present_address='x', consent_terms=True, account_status='active'))
    rider_user.roles.add(Role.objects.get(name='delivery'))
    rider, _ = DeliveryProfile.objects.get_or_create(user=rider_user, defaults=dict(
        drivers_license_number=f'RID-{_uuid.uuid4().hex[:8]}', license_class='A',
        license_expiry_date=_date(2030, 1, 1), license_photo_url='x', current_status='active'))
    if rider.approved_by_admin_id is None:
        rider.approved_by_admin = delivery_admin
        rider.save(update_fields=['approved_by_admin'])

    # a pharmacy order + queue row (the shape _assign_from_queue expects)
    pharm_rec = AdminPanelRecord.objects.create(
        module='pharmacy-orders', record_id=f'PO-TEST-{_uuid.uuid4().hex[:6]}',
        payload={'farmer_name': 'QA Farmer', 'items': [{'name': 'Vitamins'}]})
    qid = f'DQ-TEST-{_uuid.uuid4().hex[:6]}'
    AdminPanelRecord.objects.create(module='delivery-queue', record_id=qid, payload={
        'customer': 'QA Farmer', 'pickup_address': 'Depot', 'delivery_address': 'Farm 1',
        'pharmacy_order_record_id': str(pharm_rec.id), 'otp_code': '1234',
        'is_cold_chain': False, 'is_prescription_required': False})

    auth(c, finance_admin)
    r = c.patch(f'/api/admin-panel/delivery-orders/{qid}/',
                data={'action': 'assign', 'rider_id': str(rider.id)}, content_type='application/json')
    check('finance admin BLOCKED from assigning (403)', r.status_code == 403, f'{r.status_code} {r.content[:120]}')

    auth(c, delivery_admin)
    r = c.patch(f'/api/admin-panel/delivery-orders/{qid}/',
                data={'action': 'assign', 'rider_id': str(rider.id), 'notes': 'e2e'},
                content_type='application/json')
    check('delivery admin assigns queued order (201)', r.status_code == 201, f'{r.status_code} {r.content[:200]}')
    if r.status_code == 201:
        body = r.json()
        check('order now has the assigned rider', body.get('assigned_rider_id') == str(rider.id), body.get('assigned_rider_id'))
        order = DeliveryOrder.objects.filter(pk=body['id']).first()
        check('a real delivery_orders row was created', order is not None)
        check('rider got a "new assignment" notification',
              rider_user.notifications.filter(title__icontains='assignment').exists())
        # queue row consumed
        check('queue row removed after assignment',
              not AdminPanelRecord.objects.filter(module='delivery-queue', record_id=qid).exists())


def _shift_payment_checks(c, ensure_admin, auth):
    from datetime import timedelta
    from django.utils import timezone
    from profiles.models import AdminProfile, AdminShift, AdminPayment

    worker = ensure_admin('adminpaneltest+shift@featherflow.dev', 'admin_content')
    sup = ensure_admin('adminpaneltest+super@featherflow.dev', 'admin_super')
    prof = worker.admin_profile
    prof.shifts.all().delete()
    prof.payments.all().delete()
    AdminProfile.objects.filter(id=prof.id).update(
        hourly_rate=0, pending_hourly_rate=None, pending_rate_effective_from=None, max_hours_per_week=None)

    auth(c, worker)
    r = c.get('/api/admin-panel/my-shift/status/')
    check('shift status 200', r.status_code == 200, r.content[:120])
    check('starts off shift', r.json()['is_on_shift'] is False)
    r = c.post('/api/admin-panel/my-shift/start/')
    check('start shift 201', r.status_code == 201, r.content[:160])
    r = c.post('/api/admin-panel/my-shift/start/')
    check('double start blocked (409)', r.status_code == 409)

    sh = prof.shifts.get(is_active=True)
    AdminShift.objects.filter(id=sh.id).update(
        start_time=timezone.now() - timedelta(hours=3),
        break_start=timezone.now() - timedelta(hours=2),
        break_end=timezone.now() - timedelta(hours=1, minutes=30),
        break_duration_minutes=30)
    r = c.get('/api/admin-panel/my-shift/status/')
    check('live elapsed = 3h worked - 0.5h break = 2.5h', abs(r.json()['hours_today'] - 2.5) < 0.05, r.json()['hours_today'])
    r = c.post('/api/admin-panel/my-shift/end/')
    check('end shift 200', r.status_code == 200)
    r = c.get('/api/admin-panel/my-shift/hours/')
    check('week hours stable at 2.5 after close (no tz drift)', abs(r.json()['hours_this_week'] - 2.5) < 0.05, r.json()['hours_this_week'])

    # midnight split: one shift 22:00 -> 02:00 counts 2h to each calendar day
    midnight = timezone.localtime(timezone.now()).replace(hour=0, minute=0, second=0, microsecond=0)
    span = AdminShift.objects.create(
        admin=prof, shift_date=(midnight - timedelta(days=1)).date(),
        start_time=midnight - timedelta(hours=2), end_time=midnight + timedelta(hours=2),
        break_duration_minutes=0, total_hours=4, is_active=False)
    auth(c, sup)
    r = c.get('/api/admin-panel/shifts/', {'admin_id': str(prof.id)})
    check('super can list shifts', r.status_code == 200)
    from api.admin_shifts import _shift_hours_in_range
    d_before = (midnight - timedelta(days=1), midnight)
    d_after = (midnight, midnight + timedelta(days=1))
    h1 = _shift_hours_in_range(AdminShift.objects.get(id=span.id), *d_before)
    h2 = _shift_hours_in_range(AdminShift.objects.get(id=span.id), *d_after)
    check('midnight shift splits 2h + 2h', abs(h1 - 2.0) < 0.05 and abs(h2 - 2.0) < 0.05, (h1, h2))
    span.delete()

    print('  -- payroll --')
    auth(c, sup)
    r = c.get('/api/admin-panel/all-admins/')
    check('all-admins 200 for super', r.status_code == 200)
    check('all-admins excludes super admin', not any(x['role'] == 'admin_super' for x in r.json()['results']))
    row = [x for x in r.json()['results'] if x['email'] == worker.email][0]
    check('worker shows ~2.5 h this week', abs(row['hours_this_week'] - 2.5) < 0.05, row['hours_this_week'])

    r = c.patch(f'/api/admin-panel/admins/{prof.id}/hourly-rate/', data={'hourly_rate': 999999},
                content_type='application/json')
    check('rate outside band rejected (400)', r.status_code == 400)
    r = c.patch(f'/api/admin-panel/admins/{prof.id}/hourly-rate/', data={'hourly_rate': 300},
                content_type='application/json')
    check('first rate applies immediately (200)', r.status_code == 200, r.content[:120])
    r = c.patch(f'/api/admin-panel/admins/{prof.id}/hourly-rate/', data={'hourly_rate': 350},
                content_type='application/json')
    prof.refresh_from_db()
    check('rate change queued for next Monday', prof.pending_hourly_rate is not None and prof.pending_rate_effective_from is not None)

    AdminProfile.objects.filter(id=prof.id).update(max_hours_per_week=2)
    r = c.post('/api/admin-panel/admin-payments/', data={'period_start': sh.shift_date.isoformat()},
               content_type='application/json')
    check('generate payroll (201)', r.status_code == 201, r.content[:160])
    pay = AdminPayment.objects.filter(admin=prof).first()
    check('overtime split: 2.0 regular + 0.5 OT', pay and float(pay.regular_hours) == 2.0 and float(pay.overtime_hours) == 0.5,
          (pay.regular_hours, pay.overtime_hours) if pay else None)
    check('total = 2*300 + 0.5*300*1.5 = 825', pay and abs(float(pay.total_payment) - 825.0) < 0.01,
          pay.total_payment if pay else None)
    r = c.patch(f'/api/admin-panel/admin-payments/{pay.id}/',
                data={'action': 'mark_paid', 'payment_method': 'bank_transfer', 'payment_reference': 'TXN-QA'},
                content_type='application/json')
    check('mark paid (200)', r.status_code == 200 and r.json()['status'] == 'paid', r.content[:120])
    r = c.post('/api/admin-panel/admin-payments/', data={'period_start': sh.shift_date.isoformat()},
               content_type='application/json')
    check('re-generate skips the already-paid row', r.json().get('skipped_paid', 0) >= 1, r.json())
    r = c.get('/api/admin-panel/admin-payments/export/')
    check('payroll CSV export', r.status_code == 200 and 'csv' in r['Content-Type'])

    auth(c, sup)
    r = c.post('/api/admin-panel/my-shift/start/')
    check('super admin CANNOT clock in (403)', r.status_code == 403, r.status_code)
    r = c.get('/api/admin-panel/my-shift/status/')
    check('super admin has no shift timer (403)', r.status_code == 403)

    # force-end
    auth(c, worker)
    c.post('/api/admin-panel/my-shift/start/')
    open_shift = prof.shifts.get(is_active=True)
    auth(c, sup)
    r = c.post('/api/admin-panel/shifts/force-end/', data={'shift_id': str(open_shift.id), 'reason': 'forgot'},
               content_type='application/json')
    check('super force-ends a forgotten shift (200)', r.status_code == 200, r.content[:120])
    open_shift.refresh_from_db()
    check('force-ended shift is closed + attributed', not open_shift.is_active and open_shift.ended_by_id == sup.id)

    prof.shifts.all().delete()
    prof.payments.all().delete()
    AdminProfile.objects.filter(id=prof.id).update(
        hourly_rate=0, max_hours_per_week=None, pending_hourly_rate=None, pending_rate_effective_from=None)


def _make_test_doctor():
    import hashlib
    email = 'adminpaneltest+vet@featherflow.dev'
    phone = '+8801' + hashlib.md5(email.encode()).hexdigest()[:9]
    user, _ = User.objects.get_or_create(email=email, defaults=dict(
        full_name='Test Vet', phone=phone, date_of_birth=date(1985, 1, 1),
        present_address='Test', consent_terms=True, account_status='active'))
    role = Role.objects.get(name='doctor')
    user.roles.add(role)
    profile, _ = DoctorProfile.objects.get_or_create(user=user, defaults=dict(
        clinic_hospital_name='Test Clinic', practice_address='Test',
        veterinary_degree='DVM', university_name='Test U', graduation_year=2010,
        license_number=f'TEST-{phone[-6:]}', license_issuing_authority='Test',
        license_expiry_date=date(2030, 1, 1), specialty='Poultry',
        years_of_experience=5, council_registration_proof_url='x',
        consent_platform_guidelines=True, is_verified=True))
    profile.is_verified = True
    profile.save(update_fields=['is_verified'])
    return DoctorProfile.objects.select_related('user').get(pk=profile.pk)


def _log_count():
    from audit.models import ActivityLog
    return ActivityLog.objects.count()


def _latest_log():
    from audit.models import ActivityLog
    return ActivityLog.objects.order_by('-created_at').first()


if __name__ == '__main__':
    main()
