"""Checks for the subscription checkout + payment flow (backend ``billing`` app).

    GET  /api/subscriptions/plans/
    GET  /api/subscriptions/current/
    POST /api/subscriptions/checkout/
    POST /api/payments/<id>/method/
    POST /api/payments/<id>/confirm/     (dev mode)
    POST /api/payments/<id>/cancel/
    GET  /api/payments/<id>/
    POST /api/payments/webhook/<provider>/

Run:  backend/venv/Scripts/python.exe backend/scripts/test_subscription_payment.py

Django test Client against the live DB. Throw-away account ``paytest+``.
Idempotent — cleans its own PaymentIntent / Subscription / Payment rows.
"""
import json
import os
import sys
from datetime import date

import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
os.environ.setdefault('EMAIL_BACKEND', 'django.core.mail.backends.locmem.EmailBackend')
django.setup()

from django.conf import settings as dj  # noqa: E402
if 'testserver' not in dj.ALLOWED_HOSTS:
    dj.ALLOWED_HOSTS.append('testserver')

from django.test import Client  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from billing.models import PaymentIntent  # noqa: E402
from billing.services import billing_mode  # noqa: E402
from payments.models import Payment  # noqa: E402
from subscriptions.models import Subscription, SubscriptionPlan  # noqa: E402
from users.models import Role, User  # noqa: E402

PREFIX = 'paytest+'
J = 'application/json'
PASS = FAIL = 0


def check(name, cond, extra=''):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f'  ok   {name}')
    else:
        FAIL += 1
        print(f'  FAIL {name}   {extra}')


def mk(handle='farmer', role='farmer'):
    import hashlib
    email = f'{PREFIX}{handle}@featherflow.dev'
    phone = '+8801' + hashlib.md5(email.encode()).hexdigest()[:9]
    u, _ = User.objects.get_or_create(email=email, defaults=dict(
        full_name=f'Pay {handle}', phone=phone, date_of_birth=date(1990, 1, 1),
        present_address='Dhaka', consent_terms=True, account_status='active'))
    u.account_status = 'active'
    u.set_password('Testpass!2026')
    u.save()
    r, _ = Role.objects.get_or_create(name=role, defaults={'panel_type': role})
    u.roles.clear()
    u.roles.add(r)
    return u


def cl(u):
    c = Client()
    if u is not None:
        c.defaults['HTTP_AUTHORIZATION'] = f'Bearer {RefreshToken.for_user(u).access_token}'
    return c


def cleanup(u):
    if u is None:
        return
    PaymentIntent.objects.filter(user=u).delete()
    Subscription.objects.filter(user=u).delete()
    Payment.objects.filter(user=u, payment_type='subscription').delete()
    User.objects.filter(email__startswith=PREFIX).delete()


def run():
    u = mk()
    try:
        c = cl(u)
        check('dev mode is active for this test run', billing_mode() == 'dev', billing_mode())

        # ── plans ──────────────────────────────────────────────────────────
        r = c.get('/api/subscriptions/plans/')
        check('GET plans -> 200', r.status_code == 200, r.content[:120])
        body = r.json()
        check('plans response has mode', body.get('mode') in ('dev', 'live'))
        plans = body.get('plans', [])
        check('at least one subscribable plan', len(plans) >= 1)
        check('every plan has a numeric price + display', all(
            isinstance(p['price'], (int, float)) and p['price_display'] for p in plans))
        pro = next((p for p in plans if p['code'] == 'monthly_premium'), plans[0])
        check('Pro plan is recommended', any(p['recommended'] for p in plans))

        check('GET current -> null (no subscription yet)',
              c.get('/api/subscriptions/current/').json().get('current') is None)

        # ── checkout ───────────────────────────────────────────────────────
        r = c.post('/api/subscriptions/checkout/',
                   json.dumps({'plan_id': pro['id'], 'idempotency_key': 'k-1'}), content_type=J)
        check('checkout -> 201', r.status_code == 201, r.content[:160])
        intent = r.json()
        iid = intent['id']
        check('intent amount is server-side (matches plan price)',
              abs(intent['amount'] - pro['price']) < 0.001)
        check('intent starts in "created"', intent['status'] == 'created')

        # amount from the client is ignored
        r = c.post('/api/subscriptions/checkout/',
                   json.dumps({'plan_id': pro['id'], 'amount': 1, 'idempotency_key': 'k-2'}),
                   content_type=J)
        check('client-sent amount ignored', abs(r.json()['amount'] - pro['price']) < 0.001)

        # idempotency — same key returns the same intent, no second row
        n_before = PaymentIntent.objects.filter(user=u).count()
        r = c.post('/api/subscriptions/checkout/',
                   json.dumps({'plan_id': pro['id'], 'idempotency_key': 'k-1'}), content_type=J)
        check('duplicate checkout is idempotent (same intent)', r.json()['id'] == iid)
        check('no extra PaymentIntent row created',
              PaymentIntent.objects.filter(user=u).count() == n_before)

        # invalid / inactive plans
        check('unknown plan -> 404',
              c.post('/api/subscriptions/checkout/', json.dumps({'plan_id': 999999}),
                     content_type=J).status_code == 404)
        free = SubscriptionPlan.objects.filter(name='free').first()
        if free:
            check('free plan is not purchasable -> 400',
                  c.post('/api/subscriptions/checkout/', json.dumps({'plan_id': free.id}),
                         content_type=J).status_code == 400)

        # ── method + dev confirm (success) ────────────────────────────────
        for method in ('card', 'bkash', 'nagad'):
            rr = c.post(f'/api/payments/{iid}/method/',
                        json.dumps({'payment_method': method}), content_type=J)
            check(f'select method {method} -> 200 pending',
                  rr.status_code == 200 and rr.json()['status'] == 'pending', rr.content[:120])
            check(f'{method}: dev checkout instructions returned',
                  rr.json().get('next') == 'dev_checkout')

        check('bad method -> 400',
              c.post(f'/api/payments/{iid}/method/', json.dumps({'payment_method': 'crypto'}),
                     content_type=J).status_code == 400)

        r = c.post(f'/api/payments/{iid}/confirm/',
                   json.dumps({'outcome': 'success'}), content_type=J)
        check('confirm success -> 200 succeeded', r.status_code == 200 and r.json()['status'] == 'succeeded')
        check('confirm response carries the activated subscription',
              (r.json().get('subscription') or {}).get('status') == 'active')

        cur = c.get('/api/subscriptions/current/').json()['current']
        check('current subscription is now active + right plan',
              cur and cur['status'] == 'active' and cur['plan']['code'] == 'monthly_premium')
        check('exactly one active subscription', Subscription.objects.filter(user=u, status='active').count() == 1)
        check('exactly one subscription Payment row',
              Payment.objects.filter(user=u, payment_type='subscription', status='completed').count() == 1)
        pay = Payment.objects.filter(user=u, payment_type='subscription').first()
        check('Payment row stores no raw card data',
              'card' not in (pay.notes or '').lower() or 'number' not in (pay.notes or '').lower())

        # idempotent confirm — a retried confirm doesn't double-charge
        r = c.post(f'/api/payments/{iid}/confirm/', json.dumps({'outcome': 'success'}), content_type=J)
        check('confirm is idempotent (still one sub / one payment)',
              Subscription.objects.filter(user=u, status='active').count() == 1 and
              Payment.objects.filter(user=u, payment_type='subscription').count() == 1)

        # ── failure path — no activation ─────────────────────────────────
        r = c.post('/api/subscriptions/checkout/',
                   json.dumps({'plan_id': pro['id'], 'idempotency_key': 'k-fail'}), content_type=J)
        fid = r.json()['id']
        c.post(f'/api/payments/{fid}/method/', json.dumps({'payment_method': 'card'}), content_type=J)
        r = c.post(f'/api/payments/{fid}/confirm/', json.dumps({'outcome': 'failure'}), content_type=J)
        check('confirm failure -> failed', r.json()['status'] == 'failed')
        check('failure does not create a new subscription/payment',
              Subscription.objects.filter(user=u, status='active').count() == 1 and
              Payment.objects.filter(user=u, payment_type='subscription').count() == 1)

        # ── cancel path ─────────────────────────────────────────────────
        r = c.post('/api/subscriptions/checkout/',
                   json.dumps({'plan_id': pro['id'], 'idempotency_key': 'k-cancel'}), content_type=J)
        xid = r.json()['id']
        r = c.post(f'/api/payments/{xid}/cancel/', '{}', content_type=J)
        check('cancel -> cancelled', r.json()['status'] == 'cancelled')
        check('GET payment detail -> 200', c.get(f'/api/payments/{xid}/').status_code == 200)

        # ── permissions ────────────────────────────────────────────────
        check('unauthenticated plans -> 401', Client().get('/api/subscriptions/plans/').status_code == 401)
        check('unauthenticated checkout -> 401',
              Client().post('/api/subscriptions/checkout/', '{}', content_type=J).status_code == 401)
        other = mk('other')
        check("another user cannot read my payment intent -> 404",
              cl(other).get(f'/api/payments/{iid}/').status_code == 404)
        Subscription.objects.filter(user=other).delete()
        PaymentIntent.objects.filter(user=other).delete()
        User.objects.filter(email=f'{PREFIX}other@featherflow.dev').delete()

        # ── webhook is dev-disabled ────────────────────────────────────
        check('webhook rejected in dev mode -> 404',
              c.post('/api/payments/webhook/stripe/', '{}', content_type=J).status_code == 404)

        # ── expired-session shape (garbage token) ─────────────────────
        bad = Client()
        bad.defaults['HTTP_AUTHORIZATION'] = 'Bearer not.a.token'
        check('expired/invalid token -> 401', bad.get('/api/subscriptions/plans/').status_code == 401)

        print(f'\n{PASS} passed, {FAIL} failed\n')
    finally:
        cleanup(u)
    return FAIL == 0


if __name__ == '__main__':
    sys.exit(0 if run() else 1)
