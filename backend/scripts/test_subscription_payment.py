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
from datetime import date, timedelta
from io import StringIO
from unittest import mock

import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
os.environ.setdefault('EMAIL_BACKEND', 'django.core.mail.backends.locmem.EmailBackend')
django.setup()

from django.conf import settings as dj  # noqa: E402
if 'testserver' not in dj.ALLOWED_HOSTS:
    dj.ALLOWED_HOSTS.append('testserver')

from django.core.management import call_command  # noqa: E402
from django.test import Client  # noqa: E402
from django.utils import timezone  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

import billing.webhooks as webhooks_mod  # noqa: E402
from audit.models import AdminEscalation  # noqa: E402
from billing.models import PaymentIntent, WebhookEvent  # noqa: E402
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

        # ── admin refund syncs the PaymentIntent, not just the legacy row ──
        # (production readiness follow-up: an admin refund used to update
        # `payments`/`subscriptions` directly and leave the originating
        # PaymentIntent stuck showing status='succeeded' forever.) Uses its
        # own dedicated user/checkout — a second checkout for `u` would
        # retire `u`'s existing active subscription (by design — one active
        # subscription per user), which would break the checks below.
        ru = mk('refund')
        rc = cl(ru)
        r = rc.post('/api/subscriptions/checkout/',
                    json.dumps({'plan_id': pro['id'], 'idempotency_key': 'k-refund'}), content_type=J)
        rid = r.json()['id']
        rc.post(f'/api/payments/{rid}/method/', json.dumps({'payment_method': 'card'}), content_type=J)
        rc.post(f'/api/payments/{rid}/confirm/', json.dumps({'outcome': 'success'}), content_type=J)
        refund_intent = PaymentIntent.objects.get(pk=rid)
        admin = mk('admin', 'admin_super')
        ac = cl(admin)
        r = ac.patch(f'/api/admin-panel/payments/sub:{refund_intent.subscription_id}/',
                      json.dumps({'action': 'refund', 'reason': 'test refund'}), content_type=J)
        check('admin subscription refund -> 200', r.status_code == 200, r.content[:200])
        intent_after = PaymentIntent.objects.get(pk=rid)
        check('refunding the subscription also marks its PaymentIntent refunded',
              intent_after.status == 'refunded', intent_after.status)
        check('refunded subscription is cancelled',
              Subscription.objects.filter(pk=refund_intent.subscription_id).first().status == 'cancelled')
        # NOTE: cleanup(u) deletes *every* PREFIX-tagged user, not just its
        # argument — must not call it mid-test (it would delete `u` too,
        # breaking every check below that still relies on `u`/`c`). Delete
        # just these two throwaway accounts' own rows instead.
        PaymentIntent.objects.filter(user=ru).delete()
        Subscription.objects.filter(user=ru).delete()
        Payment.objects.filter(user=ru, payment_type='subscription').delete()
        User.objects.filter(email=f'{PREFIX}refund@featherflow.dev').delete()
        PaymentIntent.objects.filter(user=admin).delete()
        Subscription.objects.filter(user=admin).delete()
        User.objects.filter(email=f'{PREFIX}admin@featherflow.dev').delete()

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

        # ── live-mode webhook pipeline ──────────────────────────────────
        # billing/webhooks.py deliberately leaves real Stripe/bKash/Nagad
        # signature verification as NotImplementedError — no sandbox
        # credentials exist in this environment (see PAYMENT_RUNBOOK.md), and
        # wiring in unverified crypto/HTTP calls would be worse than an
        # explicit stub. Two kinds of checks below:
        #  (a) the *real* rejection path, unpatched — no provider secret is
        #      configured, so the webhook must still be refused with 400.
        #  (b) billing.webhooks._verify_stripe is monkeypatched, only inside
        #      this block, to return a synthetic *already-verified* event —
        #      this tests OUR OWN code downstream of verification (dedupe,
        #      idempotency, amount/currency guard, state machine, disputes),
        #      never real provider signature-checking behaviour.
        _test_event_ids = ('evt_test_1', 'evt_test_2', 'evt_mismatch', 'evt_dispute_1')
        # WebhookEvent.intent uses on_delete=SET_NULL — a leftover row from a
        # prior (possibly interrupted) run would otherwise permanently block
        # reusing these event ids, since the dedupe check is keyed on
        # (provider, event_id) alone, independent of which intent it pointed to.
        WebhookEvent.objects.filter(provider='stripe', event_id__in=_test_event_ids).delete()

        prev_mode = getattr(dj, 'BILLING_MODE', 'dev')
        dj.BILLING_MODE = 'live'
        try:
            check('billing_mode() reflects the live-mode override', billing_mode() == 'live')

            # -- invalid signature: real code path, no secret configured --
            r = c.post('/api/payments/webhook/stripe/', '{"fake": "payload"}', content_type=J)
            check('webhook with no provider secret configured -> 400 (real rejection path)',
                  r.status_code == 400, r.content[:160])
            r = c.post('/api/payments/webhook/unknown-provider/', '{}', content_type=J)
            check('webhook for unknown provider -> 400', r.status_code == 400, r.content[:160])

            # -- valid webhook (synthetic verified event) -> activates --
            wu = mk('webhook')
            wc = cl(wu)
            r = wc.post('/api/subscriptions/checkout/',
                        json.dumps({'plan_id': pro['id'], 'idempotency_key': 'k-webhook'}), content_type=J)
            wid = r.json()['id']
            wc.post(f'/api/payments/{wid}/method/', json.dumps({'payment_method': 'card'}), content_type=J)
            w_intent = PaymentIntent.objects.get(pk=wid)

            good_event = {'intent_id': wid, 'provider_ref': 'pi_test_123', 'outcome': 'success',
                         'event_id': 'evt_test_1', 'amount': str(w_intent.amount),
                         'currency': w_intent.currency}
            with mock.patch.object(webhooks_mod, '_verify_stripe', return_value=good_event):
                r = c.post('/api/payments/webhook/stripe/', json.dumps({'ok': True}), content_type=J)
            check('valid (verified) webhook -> 200 ok',
                  r.status_code == 200 and r.json().get('ok') is True, r.content[:160])
            w_intent.refresh_from_db()
            check('valid webhook activates the subscription', w_intent.status == 'succeeded')
            check('WebhookEvent recorded for replay protection',
                  WebhookEvent.objects.filter(provider='stripe', event_id='evt_test_1').exists())

            n_subs = Subscription.objects.filter(user=wu, status='active').count()
            n_pays = Payment.objects.filter(user=wu, payment_type='subscription').count()

            # -- duplicate delivery of the same event -> deduped no-op --
            with mock.patch.object(webhooks_mod, '_verify_stripe', return_value=good_event):
                r = c.post('/api/payments/webhook/stripe/', json.dumps({'ok': True}), content_type=J)
            check('duplicate webhook delivery -> 200, flagged duplicate',
                  r.status_code == 200 and r.json().get('duplicate') is True, r.content[:200])
            check('duplicate delivery created no extra subscription/payment',
                  Subscription.objects.filter(user=wu, status='active').count() == n_subs and
                  Payment.objects.filter(user=wu, payment_type='subscription').count() == n_pays)

            # -- replay under a *different* delivery id, same outcome -> still
            # idempotent via intent.status (not just event-id dedupe) --
            replay_event = {**good_event, 'event_id': 'evt_test_2'}
            with mock.patch.object(webhooks_mod, '_verify_stripe', return_value=replay_event):
                r = c.post('/api/payments/webhook/stripe/', json.dumps({'ok': True}), content_type=J)
            check('replayed success under a new delivery id is idempotent',
                  r.status_code == 200 and r.json().get('ok') is True)
            check('replay created no extra subscription/payment',
                  Subscription.objects.filter(user=wu, status='active').count() == n_subs and
                  Payment.objects.filter(user=wu, payment_type='subscription').count() == n_pays)

            # -- mismatched amount/currency -> rejected, never activated --
            mu = mk('mismatch')
            mcl = cl(mu)
            r = mcl.post('/api/subscriptions/checkout/',
                         json.dumps({'plan_id': pro['id'], 'idempotency_key': 'k-mismatch'}), content_type=J)
            mid = r.json()['id']
            mcl.post(f'/api/payments/{mid}/method/', json.dumps({'payment_method': 'card'}), content_type=J)
            bad_event = {'intent_id': mid, 'provider_ref': 'pi_bad', 'outcome': 'success',
                        'event_id': 'evt_mismatch', 'amount': '1.00', 'currency': 'USD'}
            with mock.patch.object(webhooks_mod, '_verify_stripe', return_value=bad_event):
                r = c.post('/api/payments/webhook/stripe/', json.dumps({'ok': True}), content_type=J)
            check('mismatched-amount webhook -> 200 (accepted + safely rejected)', r.status_code == 200)
            m_intent = PaymentIntent.objects.get(pk=mid)
            check('mismatched amount/currency intent is failed, not activated',
                  m_intent.status == 'failed', m_intent.status)
            check('mismatch failure reason is descriptive',
                  'match' in m_intent.failure_reason.lower())
            check('no subscription activated for the mismatched payment',
                  Subscription.objects.filter(user=mu, status='active').count() == 0)

            # -- disputed payment (chargeback) on an already-succeeded intent --
            dispute_event = {**good_event, 'event_id': 'evt_dispute_1', 'outcome': 'dispute'}
            with mock.patch.object(webhooks_mod, '_verify_stripe', return_value=dispute_event):
                r = c.post('/api/payments/webhook/stripe/', json.dumps({'ok': True}), content_type=J)
            check('dispute webhook -> 200', r.status_code == 200, r.content[:160])
            w_intent.refresh_from_db()
            check('disputed intent moves to disputed status (never auto-refunded)',
                  w_intent.status == 'disputed', w_intent.status)
            check('dispute raises an admin escalation for manual review',
                  AdminEscalation.objects.filter(module='billing', target_id=w_intent.id).exists())
            check('disputed subscription is left untouched pending admin review',
                  Subscription.objects.filter(user=wu, status='active').count() == n_subs)

            n_escalations = AdminEscalation.objects.filter(module='billing', target_id=w_intent.id).count()
            with mock.patch.object(webhooks_mod, '_verify_stripe', return_value=dispute_event):
                r = c.post('/api/payments/webhook/stripe/', json.dumps({'ok': True}), content_type=J)
            check('replayed dispute delivery is deduped (no reprocessing)',
                  r.status_code == 200 and r.json().get('duplicate') is True)
            check('no second escalation from a replayed dispute',
                  AdminEscalation.objects.filter(module='billing', target_id=w_intent.id).count()
                  == n_escalations)

            # -- provider timeout (webhook never arrives) via reconciliation --
            tu = mk('timeout')
            tcl = cl(tu)
            r = tcl.post('/api/subscriptions/checkout/',
                         json.dumps({'plan_id': pro['id'], 'idempotency_key': 'k-timeout'}), content_type=J)
            tid = r.json()['id']
            tcl.post(f'/api/payments/{tid}/method/', json.dumps({'payment_method': 'bkash'}), content_type=J)
            PaymentIntent.objects.filter(pk=tid).update(
                created_at=timezone.now() - timedelta(hours=48))
            call_command('reconcile_pending_payments', '--timeout-hours=24', '--stale-minutes=1',
                        stdout=StringIO())
            t_intent = PaymentIntent.objects.get(pk=tid)
            check('reconciliation times out a stuck intent (simulated provider timeout)',
                  t_intent.status == 'failed', t_intent.status)
            check('timeout failure reason names the cause',
                  'timed out' in t_intent.failure_reason.lower())

            # --dry-run reports without mutating anything
            dru = mk('dryrun')
            drc = cl(dru)
            r = drc.post('/api/subscriptions/checkout/',
                         json.dumps({'plan_id': pro['id'], 'idempotency_key': 'k-dryrun'}), content_type=J)
            drid = r.json()['id']
            drc.post(f'/api/payments/{drid}/method/', json.dumps({'payment_method': 'bkash'}), content_type=J)
            PaymentIntent.objects.filter(pk=drid).update(
                created_at=timezone.now() - timedelta(hours=48))
            call_command('reconcile_pending_payments', '--timeout-hours=24', '--stale-minutes=1',
                        '--dry-run', stdout=StringIO())
            check('reconciliation --dry-run leaves a stuck intent untouched',
                  PaymentIntent.objects.get(pk=drid).status == 'pending')

            WebhookEvent.objects.filter(provider='stripe', event_id__in=_test_event_ids).delete()
            for tmp_user in (wu, mu, tu, dru):
                PaymentIntent.objects.filter(user=tmp_user).delete()
                Subscription.objects.filter(user=tmp_user).delete()
                Payment.objects.filter(user=tmp_user, payment_type='subscription').delete()
            User.objects.filter(email__in=[
                f'{PREFIX}webhook@featherflow.dev', f'{PREFIX}mismatch@featherflow.dev',
                f'{PREFIX}timeout@featherflow.dev', f'{PREFIX}dryrun@featherflow.dev']).delete()
        finally:
            dj.BILLING_MODE = prev_mode
            check('billing_mode() restored to dev after the live-mode block',
                  billing_mode() == 'dev')

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
