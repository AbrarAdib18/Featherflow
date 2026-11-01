"""Regression suite for the post-repair findings NF-3, NF-6 and NF-7.

NF-3  feed checkout requires + validates a delivery location (Bangladesh bounds)
NF-7  feed deliveries get a routable pickup (supplier coordinates / address) and
      unanswered / rejected offers are released back to an actionable order
NF-6  doctor case notes: permissions, locking, audit history

Runs against the dev DB with throw-away `nfrepair+` accounts (self-cleaning):
    python scripts/test_nf_repairs.py
"""
import os
import sys
from datetime import date, timedelta
from decimal import Decimal

import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
os.environ.setdefault('EMAIL_BACKEND', 'django.core.mail.backends.locmem.EmailBackend')
for key in ('READ', 'WRITE', 'EXPORT', 'POLL'):
    os.environ.setdefault(f'THROTTLE_ADMIN_{key}', '100000/min')
django.setup()

from django.conf import settings as dj_settings  # noqa: E402
if 'testserver' not in dj_settings.ALLOWED_HOSTS:
    dj_settings.ALLOWED_HOSTS.append('testserver')

from django.core.management import call_command  # noqa: E402
from django.test import Client  # noqa: E402
from django.utils import timezone  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from audit.models import ActivityLog, AdminPanelRecord  # noqa: E402
from consultations.models import Consultation  # noqa: E402
from delivery.geo import LocationError, parse_location  # noqa: E402
from delivery.models import DeliveryOrder  # noqa: E402
from doctor.models import CaseDetail, ConsultationNote, ConsultationNoteHistory  # noqa: E402
from feed_catalogue.models import FeedCompany, FeedProduct  # noqa: E402
from notifications.models import Notification  # noqa: E402
from profiles.models import DeliveryProfile  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'nfrepair+'
JSON = 'application/json'


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
    cons = list(Consultation.objects.filter(doctor_id__in=ids).values_list('id', flat=True))
    ConsultationNote.objects.filter(consultation_id__in=cons).delete()
    CaseDetail.objects.filter(consultation_id__in=cons).delete()
    Consultation.objects.filter(id__in=cons).delete()
    orders = DeliveryOrder.objects.filter(delivery_person__user__in=users)
    orders.delete()
    DeliveryProfile.objects.filter(user__in=users).delete()
    AdminPanelRecord.objects.filter(module='feed-orders', payload__farmer_id__in=[str(i) for i in ids]).delete()
    FeedProduct.objects.filter(company__name__startswith='nfrepair+').delete()
    FeedCompany.objects.filter(name__startswith='nfrepair+').delete()
    Notification.objects.filter(user__in=users).delete()
    users.delete()


_n = [0]


def mk_user(tag, role_name, panel=None):
    _n[0] += 1
    role, _ = Role.objects.get_or_create(name=role_name, defaults={'panel_type': panel or role_name})
    u = User.objects.create_user(
        email=f'{PREFIX}{tag}@example.com', password='Test1234!',
        phone=f'0195{os.getpid() % 1000:03d}{_n[0]:04d}', full_name=tag.title(),
        date_of_birth=date(1990, 1, 1), present_address='Dhaka', consent_terms=True,
        account_status='active', is_verified=True)
    u.roles.add(role)
    return u


def client_for(user):
    c = Client()
    c.defaults['HTTP_AUTHORIZATION'] = f'Bearer {RefreshToken.for_user(user).access_token}'
    return c


def main():
    cleanup()
    farmer = mk_user('farmer', 'farmer')
    feed_admin = mk_user('feedadmin', 'feed_admin', panel='admin')
    rider_u = mk_user('rider', 'delivery')
    rider2_u = mk_user('rider2', 'delivery')
    doctor = mk_user('doctor', 'doctor')
    doctor2 = mk_user('doctor2', 'doctor')
    fc, fa, rc, r2c = client_for(farmer), client_for(feed_admin), client_for(rider_u), client_for(rider2_u)
    for u in (rider_u, rider2_u):
        DeliveryProfile.objects.create(
            user=u, drivers_license_number=f'DL-{u.id}', license_class='B',
            license_expiry_date=date(2031, 1, 1), license_photo_url='x', approved_by_admin=feed_admin)
    rprof = DeliveryProfile.objects.get(user=rider_u)

    print('\n== NF-3: geo validation unit ==')
    cases = [
        ((None, None), 'delivery_location_required'), (('23.8', None), 'delivery_location_incomplete'),
        (('abc', '90'), 'delivery_location_invalid'), (('nan', '90'), 'delivery_location_invalid'),
        (('inf', '90'), 'delivery_location_invalid'), ((95, 90), 'delivery_location_invalid'),
        ((40.7, -74.0), 'delivery_location_invalid' if False else 'delivery_location_outside_service_area'),
        ((23.8, 120.0), 'delivery_location_outside_service_area'),
    ]
    for (la, lo), code in cases:
        try:
            parse_location(la, lo)
            check(f'parse_location({la},{lo}) raises {code}', False)
        except LocationError as e:
            check(f'parse_location({la},{lo}) -> {code}', e.code == code, e.code)
    check('valid Dhaka location parses', parse_location('23.81', '90.41') == (23.81, 90.41))
    check('optional + absent -> (None, None)', parse_location(None, None, required=False) == (None, None))

    print('\n== NF-3: feed checkout ==')
    company = FeedCompany.objects.create(
        name='nfrepair+Co', status='active', address='Savar Industrial Area', district='Dhaka', upazila='Savar',
        latitude=Decimal('23.842000'), longitude=Decimal('90.257000'), created_at=timezone.now(), updated_at=timezone.now())
    company2 = FeedCompany.objects.create(
        name='nfrepair+Co2', status='active', address='Gazipur Mill Road', district='Gazipur', upazila='Gazipur Sadar',
        created_at=timezone.now(), updated_at=timezone.now())
    product = FeedProduct.objects.create(company=company, product_name='NF Layer Feed', price=1000,
                                         stock_quantity=100, approval_status='approved')
    product2 = FeedProduct.objects.create(company=company2, product_name='NF Broiler Feed', price=900,
                                          stock_quantity=100, approval_status='approved')
    base = {'items': [{'product_id': str(product.id), 'quantity': 1}], 'delivery_address': 'Village Road 5',
            'payment_method': 'cod', 'contact_phone': '01711111111'}
    stock0 = FeedProduct.objects.get(pk=product.id).stock_quantity

    def place(**extra):
        return fc.post('/api/farmers/feed-catalogue/orders/', {**base, **extra}, content_type=JSON)

    for label, extra, code in [
        ('no location', {}, 'delivery_location_required'),
        ('only latitude', {'latitude': 23.8}, 'delivery_location_incomplete'),
        ('non-numeric', {'latitude': 'x', 'longitude': 'y'}, 'delivery_location_invalid'),
        ('latitude out of range', {'latitude': 123, 'longitude': 90}, 'delivery_location_invalid'),
        ('outside Bangladesh', {'latitude': 51.5, 'longitude': -0.12}, 'delivery_location_outside_service_area'),
    ]:
        r = place(**extra)
        check(f'checkout with {label} -> 400 {code}', r.status_code == 400 and r.json().get('code') == code, r.content[:200])
    check('rejected checkouts did not reduce stock', FeedProduct.objects.get(pk=product.id).stock_quantity == stock0)
    check('rejected checkouts created no order',
          AdminPanelRecord.objects.filter(module='feed-orders', payload__farmer_id=str(farmer.id)).count() == 0)
    r = place(latitude=23.81, longitude=90.41)
    order_id = r.json().get('id')
    check('valid location -> 201 with the coordinates stored',
          r.status_code == 201 and r.json()['latitude'] == 23.81 and r.json()['longitude'] == 90.41, r.content[:200])

    print('\n== NF-3: supplier coordinates are validated ==')
    r = fa.post('/api/admin-panel/feed-catalogue/companies/',
                {'name': 'nfrepair+BadGeo', 'latitude': 10, 'longitude': 10}, content_type=JSON)
    check('company outside Bangladesh -> 400', r.status_code == 400 and 'outside' in r.json().get('detail', '').lower(), r.content[:200])
    r = fa.post('/api/admin-panel/feed-catalogue/companies/',
                {'name': 'nfrepair+HalfGeo', 'latitude': 23.8}, content_type=JSON)
    check('company with only latitude -> 400', r.status_code == 400, r.content[:200])
    r = fa.post('/api/admin-panel/feed-catalogue/companies/',
                {'name': 'nfrepair+GoodGeo', 'address': 'Mill Rd', 'latitude': 23.9, 'longitude': 90.3}, content_type=JSON)
    check('company with valid coordinates -> 201 and returns them',
          r.status_code == 201 and r.json()['latitude'] == 23.9 and r.json()['longitude'] == 90.3, r.content[:200])
    cid = r.json().get('id')
    r = fa.patch(f'/api/admin-panel/feed-catalogue/companies/{cid}/', {'latitude': 99, 'longitude': 90}, content_type=JSON)
    check('company PATCH with invalid coordinates -> 400', r.status_code == 400, r.content[:200])
    FeedCompany.objects.filter(name='nfrepair+GoodGeo').delete()

    print('\n== NF-7: routable pickup ==')
    r = fa.post(f'/api/admin-panel/feed-catalogue/orders/{order_id}/assign/', {'rider_id': str(rprof.id)}, content_type=JSON)
    check('assign -> 201', r.status_code == 201, r.content[:200])
    d = DeliveryOrder.objects.get(pk=r.json()['delivery_order_id'])
    check('pickup coordinates come from the supplier', float(d.pickup_lat) == 23.842 and float(d.pickup_lng) == 90.257,
          (d.pickup_lat, d.pickup_lng))
    check('pickup address is the supplier address, not the old placeholder',
          'Savar Industrial Area' in d.pickup_address and 'Feed warehouse' not in d.pickup_address, d.pickup_address)
    check('delivery coordinates are the farmer location', float(d.delivery_lat) == 23.81 and float(d.delivery_lng) == 90.41)
    rec = AdminPanelRecord.objects.get(module='feed-orders', payload__id=order_id)
    check('order remembers its pre-assignment status', rec.payload.get('status_before_assignment') == 'created', rec.payload)
    # supplier without coordinates -> address text only
    base2 = {**base, 'items': [{'product_id': str(product2.id), 'quantity': 1}], 'latitude': 23.9, 'longitude': 90.4}
    o2 = fc.post('/api/farmers/feed-catalogue/orders/', base2, content_type=JSON).json()['id']
    r = fa.post(f'/api/admin-panel/feed-catalogue/orders/{o2}/assign/', {'rider_id': str(rprof.id)}, content_type=JSON)
    d2 = DeliveryOrder.objects.get(pk=r.json()['delivery_order_id'])
    check('supplier without coordinates -> pickup by address (no coordinates)',
          d2.pickup_lat is None and 'Gazipur Mill Road' in d2.pickup_address, (d2.pickup_lat, d2.pickup_address))

    print('\n== NF-7: expired offers return to an actionable state ==')
    DeliveryOrder.objects.filter(pk=d.pk).update(assigned_at=timezone.now() - timedelta(minutes=10))
    check('before the sweep the order still says assigned',
          AdminPanelRecord.objects.get(module='feed-orders', payload__id=order_id).payload['status'] == 'assigned')
    r = fa.get('/api/admin-panel/feed-catalogue/orders/')  # lazy sweep
    row = next(x for x in r.json()['results'] if x['id'] == order_id)
    check('admin list sweeps the stale offer: status restored, delivery_status=offer_expired, can assign',
          row['status'] == 'created' and row['delivery_status'] == 'offer_expired' and row['can_assign_rider'] is True, row)
    d.refresh_from_db()
    check('delivery order is rejected with reason "Offer expired"', d.status == 'rejected' and d.failure_reason == 'Offer expired')
    check('the rider can no longer accept the expired offer',
          rc.patch(f'/api/delivery/requests/{d.id}/respond/', {'action': 'accept'}, content_type=JSON).status_code == 409)
    check('feed admin was notified of the expiry',
          Notification.objects.filter(user=feed_admin, title__icontains='expired').exists())
    r = fa.post(f'/api/admin-panel/feed-catalogue/orders/{order_id}/assign/', {'rider_id': str(rider2_u.delivery_profile.id if hasattr(rider2_u, 'delivery_profile') else DeliveryProfile.objects.get(user=rider2_u).id)}, content_type=JSON)
    check('the order can be assigned again to another rider -> 201', r.status_code == 201, r.content[:200])
    new_do = r.json()['delivery_order_id']
    check('an accepted (non-pending) delivery is never swept',
          r2c.patch(f'/api/delivery/requests/{new_do}/respond/', {'action': 'accept'}, content_type=JSON).status_code == 200)
    DeliveryOrder.objects.filter(pk=new_do).update(assigned_at=timezone.now() - timedelta(minutes=30))
    from delivery.offers import sweep_stale_offers
    check('sweep ignores accepted deliveries', sweep_stale_offers() == 0 and DeliveryOrder.objects.get(pk=new_do).status == 'accepted')
    # rider reject path
    DeliveryOrder.objects.filter(pk=d2.pk).update(assigned_at=timezone.now())
    check('rider reject -> 200', rc.patch(f'/api/delivery/requests/{d2.id}/respond/', {'action': 'reject'}, content_type=JSON).status_code == 200)
    row = fa.get(f'/api/admin-panel/feed-catalogue/orders/{o2}/').json()
    check('rejected offer: status restored + delivery_status=offer_rejected + can assign',
          row['status'] == 'created' and row['delivery_status'] == 'offer_rejected' and row['can_assign_rider'] is True, row)
    # management command
    d3 = fa.post(f'/api/admin-panel/feed-catalogue/orders/{o2}/assign/', {'rider_id': str(rprof.id)}, content_type=JSON).json()['delivery_order_id']
    DeliveryOrder.objects.filter(pk=d3).update(assigned_at=timezone.now() - timedelta(minutes=9))
    call_command('expire_stale_offers')
    check('expire_stale_offers command releases stale offers', DeliveryOrder.objects.get(pk=d3).status == 'rejected')

    print('\n== NF-3/NF-4/NF-7: access control, idempotency, consistent state, per-order routes ==')
    from delivery import offers as offers_mod
    anon = Client()
    check('anonymous checkout -> 401', anon.post('/api/farmers/feed-catalogue/orders/', {**base, 'latitude': 23.8, 'longitude': 90.4}, content_type=JSON).status_code == 401)
    check('a rider cannot place a feed order -> 403', rc.post('/api/farmers/feed-catalogue/orders/', {**base, 'latitude': 23.8, 'longitude': 90.4}, content_type=JSON).status_code == 403)
    o3 = fc.post('/api/farmers/feed-catalogue/orders/', {**base, 'latitude': 23.79, 'longitude': 90.38}, content_type=JSON).json()['id']
    check('a farmer cannot assign a rider -> 403', fc.post(f'/api/admin-panel/feed-catalogue/orders/{o3}/assign/', {'rider_id': str(rprof.id)}, content_type=JSON).status_code == 403)
    check('a rider cannot assign a rider -> 403', rc.post(f'/api/admin-panel/feed-catalogue/orders/{o3}/assign/', {'rider_id': str(rprof.id)}, content_type=JSON).status_code == 403)
    check('anonymous cannot assign -> 401', anon.post(f'/api/admin-panel/feed-catalogue/orders/{o3}/assign/', {}, content_type=JSON).status_code == 401)
    other = mk_user('farmer3', 'farmer')
    check('another farmer cannot read the order -> 404', client_for(other).get(f'/api/farmers/feed-catalogue/orders/{o3}/').status_code == 404)

    d_a = fa.post(f'/api/admin-panel/feed-catalogue/orders/{o3}/assign/', {'rider_id': str(rprof.id)}, content_type=JSON).json()['delivery_order_id']
    check('assigned: rider sees the pending offer', any(x['id'] == str(d_a) for x in rc.get('/api/delivery/requests/').json()['results']))
    check('another rider cannot respond to it -> 404', r2c.patch(f'/api/delivery/requests/{d_a}/respond/', {'action': 'accept'}, content_type=JSON).status_code == 404)
    check('another rider cannot read its route -> 404', r2c.get(f'/api/delivery/orders/{d_a}/route/').status_code == 404)
    check('farmer sees "assigned" while the offer is live', fc.get(f'/api/farmers/feed-catalogue/orders/{o3}/').json().get('status') == 'assigned')

    DeliveryOrder.objects.filter(pk=d_a).update(assigned_at=timezone.now() - timedelta(minutes=10))
    n_notes = Notification.objects.filter(user=feed_admin, title__icontains='expired').count()
    check('first release returns True', offers_mod.release_offer(d_a, 'offer_expired') is True)
    check('second release is a no-op (idempotent)', offers_mod.release_offer(d_a, 'offer_expired') is False)
    check('sweeping again releases nothing', offers_mod.sweep_stale_offers() == 0)
    for _ in range(3):
        fa.get('/api/admin-panel/feed-catalogue/orders/')
    check('repeated processing sent exactly one admin notification',
          Notification.objects.filter(user=feed_admin, title__icontains='expired').count() == n_notes + 1)
    rec3 = AdminPanelRecord.objects.get(module='feed-orders', payload__id=o3).payload
    expiry_events = [h for h in rec3.get('status_history', []) if 'xpired' in str(h)]
    check('repeated processing wrote exactly one history entry', len(expiry_events) == 1, rec3.get('status_history'))
    check('rider list no longer shows the expired offer', not any(x['id'] == str(d_a) for x in rc.get('/api/delivery/requests/').json()['results']))
    farmer_view = fc.get(f'/api/farmers/feed-catalogue/orders/{o3}/').json()
    admin_view = fa.get(f'/api/admin-panel/feed-catalogue/orders/{o3}/').json()
    check('farmer view: no stale "assigned" status', farmer_view.get('status') == 'created' and not farmer_view.get('assigned_rider_id'), farmer_view)
    check('admin view: actionable (offer_expired, can assign)',
          admin_view['status'] == 'created' and admin_view['delivery_status'] == 'offer_expired' and admin_view['can_assign_rider'] is True, admin_view)
    check('farmer and admin agree on the status', farmer_view.get('status') == admin_view['status'])

    # NF-4 backend: the route is computed for the REQUESTED order only
    import delivery.views as dv
    calls = []
    real_get_route = dv.routing.get_route
    dv.routing.get_route = lambda *a, **k: (calls.append(a) or {'distance_m': 1000, 'duration_s': 600, 'polyline': '', 'eta_minutes': 10})
    try:
        rider_orders = []
        for oid, la, lo in [(o3, 23.79, 90.38), (o2, 23.9, 90.4)]:
            did = fa.post(f'/api/admin-panel/feed-catalogue/orders/{oid}/assign/', {'rider_id': str(rprof.id)}, content_type=JSON).json()['delivery_order_id']
            check('multi-active: rider accepts', rc.patch(f'/api/delivery/requests/{did}/respond/', {'action': 'accept'}, content_type=JSON).status_code == 200)
            rider_orders.append((did, la, lo))
        for did, la, lo in rider_orders:
            calls.clear()
            r = rc.get(f'/api/delivery/orders/{did}/route/')
            ok = r.status_code == 200 and bool(calls) and float(calls[0][3]) == la and float(calls[0][4]) == lo
            check(f'route {str(did)[:8]} uses its own drop-off coordinates', ok, calls)
    finally:
        dv.routing.get_route = real_get_route

    print('\n== NF-7: farmer and rider views release a stale offer on their own (no admin visit needed) ==')
    o4 = fc.post('/api/farmers/feed-catalogue/orders/', {**base, 'latitude': 23.77, 'longitude': 90.37}, content_type=JSON).json()['id']
    d_s = fa.post(f'/api/admin-panel/feed-catalogue/orders/{o4}/assign/', {'rider_id': str(DeliveryProfile.objects.get(user=rider2_u).id)}, content_type=JSON).json()['delivery_order_id']
    check('farmer sees "assigned" while the offer is live', fc.get(f'/api/farmers/feed-catalogue/orders/{o4}/').json().get('status') == 'assigned')
    check('rider dashboard counts the live offer', r2c.get('/api/delivery/dashboard/').json().get('pending_requests') == 1)
    DeliveryOrder.objects.filter(pk=d_s).update(assigned_at=timezone.now() - timedelta(minutes=10))
    fv = fc.get(f'/api/farmers/feed-catalogue/orders/{o4}/').json()  # first reader is the FARMER, not an admin
    check('farmer detail: stale offer already released (status created, delivery_status offer_expired)',
          fv.get('status') == 'created' and fv.get('delivery_status') == 'offer_expired' and not fv.get('assigned_rider_id'), fv)
    check('farmer list agrees', next(x for x in fc.get('/api/farmers/feed-catalogue/orders/').json()['results'] if x['id'] == o4)['status'] == 'created')
    check('rider dashboard no longer counts it', r2c.get('/api/delivery/dashboard/').json().get('pending_requests') == 0)
    check('the delivery row is rejected exactly once', DeliveryOrder.objects.get(pk=d_s).status == 'rejected')

    print('\n== NF-6: doctor case notes ==')
    farmer2 = mk_user('farmer2', 'farmer')
    cons = Consultation.objects.create(
        farmer=farmer2, doctor=doctor, mode='online', status='accepted', urgency_level='routine',
        consultation_fee=Decimal('900'), created_at=timezone.now(), updated_at=timezone.now())
    case = CaseDetail.objects.create(consultation=cons, farmer_name='Farmer2', case_status='open', farm_name='F2')
    dc, d2c, fc2 = client_for(doctor), client_for(doctor2), client_for(farmer2)
    url = f'/api/doctor/cases/{case.id}/'
    body = {'consultation_id': str(cons.id), 'diagnosis': 'Infectious bronchitis (suspected)',
            'treatment_plan': 'Supportive care', 'warnings': 'Isolate', 'next_steps': 'Recheck in 3 days', 'status': 'in_progress'}
    check('another doctor cannot edit (404)', d2c.patch(url, body, content_type=JSON).status_code == 404)
    check('a farmer cannot edit (403)', fc2.patch(url, body, content_type=JSON).status_code == 403)
    check('another doctor cannot read the history (404)', d2c.get(url + 'history/').status_code == 404)
    r = dc.patch(url, body, content_type=JSON)
    check('owner doctor edits notes -> 200 with the new values',
          r.status_code == 200 and r.json()['diagnosis'] == body['diagnosis'] and r.json()['status'] == 'in_progress', r.content[:200])
    h = dc.get(url + 'history/').json()['history']
    check('one history row recorded with from/to values', len(h) == 1 and h[0]['changes']['diagnosis']['to'] == body['diagnosis']
          and h[0]['changes']['diagnosis']['from'] == '' and h[0]['editor'], h)
    check('activity log entry written', ActivityLog.objects.filter(module='case-notes', entity_id=cons.id).count() == 1)
    r = dc.patch(url, body, content_type=JSON)
    check('re-saving identical content adds no history row', len(dc.get(url + 'history/').json()['history']) == 1)
    body2 = {**body, 'diagnosis': 'Newcastle disease (confirmed)', 'status': 'in_progress'}
    dc.patch(url, body2, content_type=JSON)
    h = dc.get(url + 'history/').json()['history']
    check('second edit appended (newest first) and keeps the previous value',
          len(h) == 2 and h[0]['changes']['diagnosis']['from'] == body['diagnosis'] and h[0]['changes']['diagnosis']['to'] == body2['diagnosis'], h[:1])
    check('ConsultationNote holds the latest text',
          ConsultationNote.objects.filter(consultation=cons).order_by('-created_at').first().diagnosis == body2['diagnosis'])
    # closed case is locked
    r = dc.patch(url, {**body2, 'status': 'closed'}, content_type=JSON)
    check('closing the case is allowed', r.status_code == 200 and CaseDetail.objects.get(pk=case.pk).case_status == 'closed')
    r = dc.patch(url, {**body2, 'status': 'closed', 'diagnosis': 'tampered'}, content_type=JSON)
    check('editing notes of a closed case -> 409 case_closed', r.status_code == 409 and r.json().get('code') == 'case_closed', r.content[:200])
    check('locked edit did not change the note', ConsultationNote.objects.filter(consultation=cons).order_by('-created_at').first().diagnosis == body2['diagnosis'])
    r = dc.patch(url, {**body2, 'status': 'in_progress', 'diagnosis': 'after reopen'}, content_type=JSON)
    check('reopening and editing in one save is allowed', r.status_code == 200 and r.json()['diagnosis'] == 'after reopen', r.content[:200])
    # not editable before acceptance
    Consultation.objects.filter(pk=cons.pk).update(status='requested')
    r = dc.patch(url, {**body2, 'diagnosis': 'too early'}, content_type=JSON)
    check('consultation not accepted yet -> 409 case_not_editable', r.status_code == 409 and r.json().get('code') == 'case_not_editable', r.content[:200])
    Consultation.objects.filter(pk=cons.pk).update(status='rejected')
    check('rejected consultation -> 409', dc.patch(url, {**body2, 'diagnosis': 'x'}, content_type=JSON).status_code == 409)
    check('anonymous -> 401', Client().patch(url, body, content_type=JSON).status_code == 401)
    check('history rows are never deleted by an edit', len(dc.get(url + 'history/').json()['history']) >= 4)

    print('\n== NF-6: no accidental replacement, validation, patient/role access ==')
    Consultation.objects.filter(pk=cons.pk).update(status='accepted')
    row = dc.get('/api/doctor/cases/').json()['cases']
    mine = next(x for x in row if x['id'] == str(case.id))
    rev = mine['notes_revision']
    check('case row exposes notes_revision (= number of recorded edits)', isinstance(rev, int) and rev >= 4, mine.get('notes_revision'))
    # a partial edit (only one field) leaves every other note untouched
    r = dc.patch(url, {'consultation_id': str(cons.id), 'next_steps': 'Recheck in 5 days', 'base_revision': rev}, content_type=JSON)
    j = r.json()
    check('partial edit -> 200, only next_steps changed (diagnosis/treatment/warnings preserved)',
          r.status_code == 200 and j['next_steps'] == 'Recheck in 5 days' and j['diagnosis'] == 'after reopen' and j['treatment_plan'] == 'Supportive care' and j['warnings'] == 'Isolate', r.content[:300])
    check('revision advanced by one', j['notes_revision'] == rev + 1)
    h0 = dc.get(url + 'history/').json()
    check('history newest entry: author, timestamp, previous and new value, revision number',
          h0['history'][0]['editor'] and h0['history'][0]['created_at'] and h0['history'][0]['changes']['next_steps'] == {'from': 'Recheck in 3 days', 'to': 'Recheck in 5 days'}
          and list(h0['history'][0]['changes']) == ['next_steps'] and h0['history'][0]['revision'] == rev + 1, h0['history'][0])
    # stale editor (opened at `rev`, someone saved since) must not overwrite
    r = dc.patch(url, {'consultation_id': str(cons.id), 'next_steps': 'STALE OVERWRITE', 'base_revision': rev}, content_type=JSON)
    check('stale base_revision -> 409 note_conflict with the current values', r.status_code == 409 and r.json().get('code') == 'note_conflict'
          and r.json()['current']['next_steps'] == 'Recheck in 5 days' and r.json()['notes_revision'] == rev + 1, r.content[:300])
    check('stale edit did not change anything', ConsultationNote.objects.filter(consultation=cons).order_by('-created_at').first().next_steps == 'Recheck in 5 days'
          and len(dc.get(url + 'history/').json()['history']) == rev + 1)
    # clearing recorded diagnosis / treatment is refused; optional notes may be cleared
    for key in ('diagnosis', 'treatment_plan'):
        r = dc.patch(url, {'consultation_id': str(cons.id), key: '   '}, content_type=JSON)
        check(f'blanking the recorded {key} -> 400 note_cannot_be_cleared', r.status_code == 400 and r.json().get('code') == 'note_cannot_be_cleared', r.content[:200])
    r = dc.patch(url, {'consultation_id': str(cons.id), 'warnings': ''}, content_type=JSON)
    check('an optional note (warnings) can be cleared deliberately, recorded in history',
          r.status_code == 200 and r.json()['warnings'] in ('', None) and dc.get(url + 'history/').json()['history'][0]['changes']['warnings']['from'] == 'Isolate')
    # validation
    r = dc.patch(url, {'consultation_id': str(cons.id), 'diagnosis': 'x' * 5001}, content_type=JSON)
    check('over-long note -> 400', r.status_code == 400, r.content[:120])
    r = dc.patch(url, {'consultation_id': str(cons.id), 'base_revision': -1}, content_type=JSON)
    check('negative base_revision -> 400', r.status_code == 400)
    r = dc.patch(url, {'consultation_id': 'not-a-uuid', 'diagnosis': 'y'}, content_type=JSON)
    check('malformed consultation id -> 400', r.status_code == 400)
    check('whitespace around text is trimmed', dc.patch(url, {'consultation_id': str(cons.id), 'diagnosis': '   Trimmed dx   '}, content_type=JSON).json()['diagnosis'] == 'Trimmed dx')
    # roles / patient access
    check('the patient (farmer) cannot read the doctor case list -> 403', fc2.get('/api/doctor/cases/').status_code == 403)
    check('the patient cannot read the history -> 403', fc2.get(url + 'history/').status_code == 403)
    check('another doctor cannot even send a conflicting edit (404)', d2c.patch(url, {'consultation_id': str(cons.id), 'diagnosis': 'hijack'}, content_type=JSON).status_code == 404)
    check('another doctor sending a foreign consultation id is refused (404)',
          d2c.patch(url, {'consultation_id': str(cons.id), 'diagnosis': 'hijack'}, content_type=JSON).status_code == 404 and
          ConsultationNote.objects.filter(consultation=cons).order_by('-created_at').first().diagnosis == 'Trimmed dx')
    check('another doctor does not see the case in their list', all(x['id'] != str(case.id) for x in d2c.get('/api/doctor/cases/').json()['cases']))
    check('anonymous history -> 401', Client().get(url + 'history/').status_code == 401)


    cleanup()
    print(f'\n{PASS} passed, {FAIL} failed')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    try:
        main()
    finally:
        cleanup()
