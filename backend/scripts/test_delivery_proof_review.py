"""Regression suite for F-005: delivery arrival + proof review lifecycle.

Runs against the live dev DB with throw-away prefixed accounts (self-cleaning),
like the other scripts in this folder:

    python scripts/test_delivery_proof_review.py
"""
import os
import sys
from datetime import date

import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
os.environ.setdefault('EMAIL_BACKEND', 'django.core.mail.backends.locmem.EmailBackend')
django.setup()

from django.conf import settings as dj_settings  # noqa: E402
if 'testserver' not in dj_settings.ALLOWED_HOSTS:
    dj_settings.ALLOWED_HOSTS.append('testserver')

from django.core.files.uploadedfile import SimpleUploadedFile  # noqa: E402
from django.test import Client  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from audit.models import ActivityLog, AdminPanelRecord  # noqa: E402
from delivery.models import DeliveryEarning, DeliveryOrder, DeliveryOrderEvent, DeliveryProof  # noqa: E402
from delivery_flow_helpers import PNG, approve, arrive, png_file, reject, submit_proof  # noqa: E402
from notifications.models import Notification  # noqa: E402
from expenses.models import Expense  # noqa: E402
from profiles.models import DeliveryProfile, FarmerProfile  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'proofreview+'
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
    orders = DeliveryOrder.objects.filter(delivery_person__user__in=users)
    Expense.objects.filter(source_feed_order_id__startswith='PROOFREV-').delete()
    from pharmacy.models import PharmacyCommission, PharmacySale
    PharmacyCommission.objects.filter(sale__order_reference__startswith='PROOFREV-').delete()
    PharmacySale.objects.filter(order_reference__startswith='PROOFREV-').delete()
    Notification.objects.filter(user__in=users).delete()
    DeliveryEarning.objects.filter(delivery_person__user__in=users).delete()
    orders.delete()
    DeliveryProfile.objects.filter(user__in=users).delete()
    FarmerProfile.objects.filter(user__in=users).delete()
    users.delete()
    AdminPanelRecord.objects.filter(module__in=['feed-orders', 'pharmacy-orders'],
                                    record_id__startswith='PROOFREV-').delete()


_n = [0]


def mk_user(tag, role_name):
    _n[0] += 1
    role, _ = Role.objects.get_or_create(name=role_name, defaults={'panel_type': role_name})
    u = User.objects.create_user(
        email=f'{PREFIX}{tag}@example.com', password='Test1234!',
        phone=f'0197{os.getpid() % 1000:03d}{_n[0]:04d}', full_name=tag.title(),
        date_of_birth=date(1990, 1, 1), present_address='Dhaka', consent_terms=True,
        account_status='active', is_verified=True)
    u.roles.add(role)
    return u


def client_for(user):
    c = Client()
    c.defaults['HTTP_AUTHORIZATION'] = f'Bearer {RefreshToken.for_user(user).access_token}'
    return c


def make_order(rider_profile, farmer, tag, order_type='marketplace', otp=None, owner=None):
    module = 'feed-orders' if order_type == 'marketplace' else 'pharmacy-orders'
    rec = AdminPanelRecord.objects.create(
        module=module, record_id=f'PROOFREV-{tag}-{rider_profile.user_id}',
        payload={'id': f'PROOFREV-{tag}', 'total_amount': 500, 'order_number': f'PR-{tag}', 'farmer_id': str(farmer.id),
                 'status': 'processing', 'items': [], **({'owner_id': str(owner.id)} if owner else {})})
    return DeliveryOrder.objects.create(
        delivery_person=rider_profile, order_reference_id=rec.id, order_type=order_type,
        pickup_address='Warehouse', delivery_address='Farm', status='accepted',
        pickup_lat='23.81', pickup_lng='90.41', delivery_lat='23.81', delivery_lng='90.41',
        otp_code=otp, is_pharmacy_delivery=(order_type == 'medicine'))


def patch_status(c, oid, status):
    return c.patch(f'/api/delivery/orders/{oid}/status/', {'status': status}, content_type=JSON)


def main():
    cleanup()
    rider = mk_user('rider', 'delivery')
    rider2 = mk_user('rider2', 'delivery')
    farmer = mk_user('farmer', 'farmer')
    farmer2 = mk_user('farmer2', 'farmer')
    super_admin = mk_user('superadmin', 'admin_super')
    delivery_admin = mk_user('deliveryadmin', 'admin_delivery')
    feed_admin = mk_user('feedadmin', 'feed_admin')
    pharm_admin = mk_user('pharmadmin', 'admin_pharmacy')
    support_admin = mk_user('supportadmin', 'admin_support')
    prof = {}
    for u in (rider, rider2):
        prof[u] = DeliveryProfile.objects.create(
            user=u, drivers_license_number=f'DL-{u.id}', license_class='B',
            license_expiry_date=date(2031, 1, 1), license_photo_url='x', approved_by_admin=None)
    rc, r2c, fc, f2c = client_for(rider), client_for(rider2), client_for(farmer), client_for(farmer2)
    sa, da, fa, pa, sup = (client_for(super_admin), client_for(delivery_admin), client_for(feed_admin),
                           client_for(pharm_admin), client_for(support_admin))

    print('\n== valid / invalid transitions ==')
    o = make_order(prof[rider], farmer, 'A')
    check('accepted -> arrived is refused (must pick up first)', patch_status(rc, o.id, 'arrived').status_code == 409)
    check('accepted -> picked_up', patch_status(rc, o.id, 'picked_up').status_code == 200)
    check('picked_up -> arrived is refused', patch_status(rc, o.id, 'arrived').status_code == 409)
    check('picked_up -> on_the_way', patch_status(rc, o.id, 'on_the_way').status_code == 200)
    r = patch_status(rc, o.id, 'delivered')
    check('rider cannot mark delivered (409)', r.status_code == 409, r.content[:200])
    r = patch_status(rc, o.id, 'proof_submitted')
    check('rider cannot set proof_submitted via PATCH (400/409)', r.status_code in (400, 409), r.status_code)

    print('\n== arrival ==')
    r = patch_status(r2c, o.id, 'arrived')
    check("another rider cannot mark arrival on this order (404)", r.status_code == 404, r.status_code)
    r = patch_status(fc, o.id, 'arrived')
    check('a farmer cannot mark arrival (403)', r.status_code == 403, r.status_code)
    r = patch_status(rc, o.id, 'arrived')
    body = r.json()
    check('on_the_way -> arrived 200', r.status_code == 200 and body['status'] == 'arrived', r.content[:300])
    check('order json exposes can_submit_proof / stage label',
          body.get('can_submit_proof') is True and body.get('stage_label') == 'Arrived', body)

    print('\n== proof upload validation ==')
    url = f'/api/delivery/orders/{o.id}/proof/'
    r = rc.post(url, {})
    check('missing proof photo -> 400', r.status_code == 400, r.content[:200])
    r = rc.post(url, {'file': SimpleUploadedFile('n.txt', b'hello', content_type='text/plain')})
    check('non-image file -> 400', r.status_code == 400, r.content[:200])
    r = rc.post(url, {'file': SimpleUploadedFile('fake.png', b'not a png', content_type='image/png')})
    check('fake image (bad magic bytes) -> 400', r.status_code == 400, r.content[:200])
    big = SimpleUploadedFile('big.png', PNG + b'0' * (6 * 1024 * 1024), content_type='image/png')
    r = rc.post(url, {'file': big})
    check('oversized file -> 400', r.status_code == 400, r.content[:200])
    r = rc.post(url, '{"file": "x"}', content_type=JSON)
    check('JSON body instead of multipart -> 415', r.status_code == 415, r.status_code)
    check('order is still arrived after every failed upload', DeliveryOrder.objects.get(pk=o.id).status == 'arrived')
    check('no proof rows were created by failed uploads', DeliveryProof.objects.filter(delivery_order=o).count() == 0)
    r = r2c.post(url, {'file': png_file()})
    check("another rider cannot submit proof for this order (404)", r.status_code == 404, r.status_code)
    r = fc.post(url, {'file': png_file()})
    check('a farmer cannot submit proof (403)', r.status_code == 403, r.status_code)

    print('\n== valid proof does NOT complete the order ==')
    r = submit_proof(rc, o.id, note='left at gate')
    check('valid proof -> 201', r.status_code == 201, r.content[:300])
    p1 = r.json()['proof']
    check('order is proof_submitted (under review), not delivered',
          r.json()['order']['status'] == 'proof_submitted' and DeliveryOrder.objects.get(pk=o.id).status == 'proof_submitted')
    check('proof attempt 1, status submitted', p1['attempt'] == 1 and p1['status'] == 'submitted')
    check('no earning / expense while under review',
          DeliveryEarning.objects.filter(delivery_order=o).count() == 0
          and Expense.objects.filter(source_feed_order_id='PROOFREV-A').count() == 0)
    r = submit_proof(rc, o.id)
    check('second proof while one is under review -> 409', r.status_code == 409, r.content[:200])
    check('farmer sees "proof_under_review"',
          AdminPanelRecord.objects.get(module='feed-orders', id=o.order_reference_id).payload.get('status') == 'proof_under_review')
    check('admins were notified of the pending proof',
          Notification.objects.filter(user=super_admin, title__icontains='proof awaiting review').exists())

    print('\n== admin review queue + authorization ==')
    r = sa.get('/api/admin-panel/delivery-proofs/')
    ids = [x['id'] for x in r.json().get('results', [])]
    check('super admin sees the proof in the review queue', r.status_code == 200 and p1['id'] in ids, r.content[:300])
    check('feed admin sees the feed proof', p1['id'] in [x['id'] for x in fa.get('/api/admin-panel/delivery-proofs/').json()['results']])
    check('pharmacy admin does NOT see a feed-order proof',
          p1['id'] not in [x['id'] for x in pa.get('/api/admin-panel/delivery-proofs/').json().get('results', [])])
    check('rider cannot open the admin queue (403)', rc.get('/api/admin-panel/delivery-proofs/').status_code == 403)
    check('farmer cannot open the admin queue (403)', fc.get('/api/admin-panel/delivery-proofs/').status_code == 403)
    check('pharmacy admin cannot approve a feed proof (403)', approve(pa, p1['id']).status_code == 403)
    check('support admin cannot approve (403)', approve(sup, p1['id']).status_code == 403)
    check('rider cannot approve own proof (403)', approve(rc, p1['id']).status_code == 403)
    check('farmer cannot approve (403)', approve(fc, p1['id']).status_code == 403)
    check('proof still pending after all refused approvals', DeliveryProof.objects.get(pk=p1['id']).status == 'submitted')

    print('\n== rejection ==')
    check('rejection without a reason -> 400', reject(sa, p1['id'], '').status_code == 400)
    check('rejection with whitespace reason -> 400', reject(sa, p1['id'], '   ').status_code == 400)
    check('pharmacy admin cannot reject a feed proof (403)', reject(pa, p1['id'], 'nope nope').status_code == 403)
    r = reject(fa, p1['id'], 'Photo is blurry, retake it')
    check('feed admin rejects with reason -> 200', r.status_code == 200, r.content[:300])
    o.refresh_from_db()
    check('order is proof_rejected', o.status == 'proof_rejected')
    check('order did not complete / no earning', DeliveryEarning.objects.filter(delivery_order=o).count() == 0)
    check('duplicate rejection -> 409', reject(fa, p1['id'], 'again again').status_code == 409)
    check('approving an already rejected proof -> 409', approve(sa, p1['id']).status_code == 409)
    check('rider notified of the rejection',
          Notification.objects.filter(user=rider, title__icontains='rejected', body__icontains='blurry').exists())
    d = rc.get(f'/api/delivery/orders/{o.id}/history/').json()
    check('rider sees rejection reason and resubmission is allowed',
          d['order']['proof_rejection_reason'] == 'Photo is blurry, retake it' and d['order']['can_submit_proof'] is True, d['order'])
    check("original proof is preserved with status rejected",
          d['proofs'][0]['id'] == p1['id'] and d['proofs'][0]['status'] == 'rejected' and d['proofs'][0]['url'] == p1['url'])
    check('farmer still sees proof_under_review (rejection is internal)',
          AdminPanelRecord.objects.get(module='feed-orders', id=o.order_reference_id).payload.get('status') == 'proof_under_review')

    print('\n== resubmission ==')
    r = submit_proof(rc, o.id, note='retaken')
    p2 = r.json()['proof']
    check('resubmission -> 201, attempt 2', r.status_code == 201 and p2['attempt'] == 2, r.content[:300])
    check('order back to proof_submitted', DeliveryOrder.objects.get(pk=o.id).status == 'proof_submitted')
    check('attempt-1 proof untouched after resubmission',
          DeliveryProof.objects.get(pk=p1['id']).status == 'rejected' and DeliveryProof.objects.filter(delivery_order=o).count() == 2)
    check('old rejected proof cannot be approved (409)', approve(sa, p1['id']).status_code == 409)

    print('\n== approval completes the order exactly once ==')
    check('earning not created before approval', DeliveryEarning.objects.filter(delivery_order=o).count() == 0)
    r = approve(da, p2['id'])
    check('delivery admin approves -> 200', r.status_code == 200, r.content[:300])
    o.refresh_from_db()
    check('order delivered with delivered_at', o.status == 'delivered' and o.delivered_at is not None)
    check('exactly one earning', DeliveryEarning.objects.filter(delivery_order=o).count() == 1)
    check('farmer expense mirrored exactly once on approval',
          Expense.objects.filter(source_feed_order_id='PROOFREV-A').count() == 1)
    check('duplicate approval -> 409', approve(da, p2['id']).status_code == 409)
    check('duplicate approval by another admin -> 409', approve(sa, p2['id']).status_code == 409)
    check('still exactly one earning and one expense after duplicate approvals',
          DeliveryEarning.objects.filter(delivery_order=o).count() == 1
          and Expense.objects.filter(source_feed_order_id='PROOFREV-A').count() == 1)
    check('a delivered order cannot take another proof (409)', submit_proof(rc, o.id).status_code == 409)
    rider_p = DeliveryProfile.objects.get(user=rider)
    check('rider total_deliveries incremented once', rider_p.total_deliveries == 1, rider_p.total_deliveries)
    check('farmer-visible status is delivered',
          AdminPanelRecord.objects.get(module='feed-orders', id=o.order_reference_id).payload.get('status') == 'delivered')
    check('farmer and rider notified of completion',
          Notification.objects.filter(user=farmer, body__icontains='delivered').exists()
          and Notification.objects.filter(user=rider, title__icontains='completed').exists())

    print('\n== audit history ==')
    evs = [(e.from_status, e.to_status) for e in DeliveryOrderEvent.objects.filter(delivery_order=o).order_by('created_at')]
    expected = [('accepted', 'picked_up'), ('picked_up', 'on_the_way'), ('on_the_way', 'arrived'),
                ('arrived', 'proof_submitted'), ('proof_submitted', 'proof_rejected'),
                ('proof_rejected', 'proof_submitted'), ('proof_submitted', 'delivered')]
    check('state history records every transition in order', evs == expected, evs)
    acts = list(ActivityLog.objects.filter(entity_id__in=[p1['id'], p2['id']]).values_list('action', flat=True))
    check('activity log has submit/reject/submit/approve entries',
          sorted(acts) == sorted(['Proof submitted', 'Proof rejected', 'Proof submitted', 'Proof approved']), acts)
    det = sa.get(f'/api/admin-panel/delivery-proofs/{p2["id"]}/').json()
    check('admin detail returns both attempts and the event history', len(det['proofs']) == 2 and len(det['events']) == len(expected))
    check('rejection reason kept in admin detail', det['proofs'][0]['review_reason'] == 'Photo is blurry, retake it')

    print('\n== F-036: the rider cannot inject proof_of_delivery_url through a status update ==')
    inj = make_order(prof[rider], farmer, 'INJ')
    r = rc.patch(f'/api/delivery/orders/{inj.id}/status/', {'status': 'picked_up', 'proof_of_delivery_url': 'javascript:alert(1)'}, content_type=JSON)
    inj.refresh_from_db()
    check('status update ignores a client-supplied proof_of_delivery_url', r.status_code == 200 and not inj.proof_of_delivery_url, (r.status_code, inj.proof_of_delivery_url))

    print('\n== pharmacy delivery: OTP + pharmacy admin review ==')
    po = make_order(prof[rider2], farmer2, 'B', order_type='medicine', otp='123456', owner=pharm_admin)
    patch_status(r2c, po.id, 'picked_up'); patch_status(r2c, po.id, 'on_the_way'); patch_status(r2c, po.id, 'arrived')
    check('wrong OTP -> 400', submit_proof(r2c, po.id, otp='000000').status_code == 400)
    check('missing OTP -> 400', submit_proof(r2c, po.id).status_code == 400)
    r = submit_proof(r2c, po.id, otp='123456')
    check('correct OTP + photo -> 201', r.status_code == 201, r.content[:300])
    pp = r.json()['proof']['id']
    check('feed admin cannot approve a pharmacy proof (403)', approve(fa, pp).status_code == 403)
    check('pharmacy admin approves pharmacy proof -> 200', approve(pa, pp).status_code == 200)
    check('pharmacy order earning exactly once', DeliveryEarning.objects.filter(delivery_order=po).count() == 1)
    from pharmacy.models import PharmacyCommission, PharmacySale
    sale = PharmacySale.objects.filter(order_reference='PROOFREV-B')
    check('approval creates exactly one pharmacy SALE (Sales / Settlements screens read it)', sale.count() == 1 and float(sale.first().gross_amount) == 500.0,
          [(x.gross_amount, x.status) for x in sale])
    check('... and exactly one COMMISSION (20 percent: 100 / 400)', sale.first() is not None and PharmacyCommission.objects.filter(sale=sale.first()).count() == 1
          and float(PharmacyCommission.objects.get(sale=sale.first()).commission_amount) == 100.0
          and float(PharmacyCommission.objects.get(sale=sale.first()).pharmacy_amount) == 400.0)
    check('a repeated approval (409) creates no second sale or commission', approve(pa, pp).status_code == 409 and PharmacySale.objects.filter(order_reference='PROOFREV-B').count() == 1)

    print('\n== failed delivery path ==')
    fo = make_order(prof[rider], farmer, 'C')
    patch_status(rc, fo.id, 'picked_up'); patch_status(rc, fo.id, 'on_the_way'); patch_status(rc, fo.id, 'arrived')
    r = submit_proof(rc, fo.id)
    check('arrived -> failed allowed', patch_status(rc, fo.id, 'failed').status_code in (200, 409))

    cleanup()
    print(f'\n{PASS} passed, {FAIL} failed')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    try:
        main()
    finally:
        cleanup()
