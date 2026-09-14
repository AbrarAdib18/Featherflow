"""Provider webhook signature verification.

This is the **production boundary**. Nothing here runs in development mode
(``BILLING_MODE != 'live'``). Each provider needs its real verification wired
in before going live — the stubs below intentionally raise so a mis-configured
live deployment fails loudly instead of trusting an unsigned callback.

Wire-in checklist per provider:
  * Stripe   — ``stripe.Webhook.construct_event(raw, sig_header, settings.STRIPE_WEBHOOK_SECRET)``
  * bKash    — verify the callback against the tokenised checkout, then query
               ``/tokenized/checkout/payment/status`` to confirm the amount.
  * Nagad    — verify the RSA signature on the callback payload with Nagad's
               public key, then call the payment-verify API.

Each verifier must return a dict:
    {'intent_id': <uuid str>, 'provider_ref': <str>,
     'outcome': 'success'|'failure'|'cancel'|'dispute'}

'dispute' maps a chargeback/dispute event on an already-succeeded payment —
see billing.services._flag_dispute. It never auto-refunds; it only flags the
intent for admin review.

Optional keys, used by billing.services / billing.views when present:
  * 'event_id'  — the provider's own delivery/event id (Stripe ``event.id``,
                  bKash/Nagad equivalent). When supplied, the webhook view
                  records it in ``WebhookEvent`` and skips reprocessing a
                  delivery it has already seen (replay / duplicate-delivery
                  protection). Omit only if a provider truly has no such id.
  * 'amount'    — the amount the provider says it charged, in the same units
                  as ``PaymentIntent.amount`` (e.g. Decimal-compatible str).
  * 'currency'  — the currency the provider says it charged, e.g. 'BDT'.
                  When either is supplied and disagrees with the intent's own
                  recorded amount/currency, ``billing.services`` refuses to
                  activate the subscription and fails the intent instead —
                  this is the amount/currency-mismatch guard, and it never
                  trusts amount/currency values supplied only by the client.
"""
from django.conf import settings


def verify_and_parse(provider, raw_body, headers):
    fn = {
        'stripe': _verify_stripe,
        'bkash': _verify_bkash,
        'nagad': _verify_nagad,
    }.get(provider)
    if fn is None:
        raise ValueError(f'Unknown payment provider: {provider}')
    return fn(raw_body, headers)


def _verify_stripe(raw_body, headers):
    secret = getattr(settings, 'STRIPE_WEBHOOK_SECRET', '')
    if not secret:
        raise RuntimeError('STRIPE_WEBHOOK_SECRET is not configured.')
    raise NotImplementedError(
        'Stripe webhook verification is not wired in. Add the `stripe` package '
        'and call stripe.Webhook.construct_event() here.')


def _verify_bkash(raw_body, headers):
    if not getattr(settings, 'BKASH_APP_SECRET', ''):
        raise RuntimeError('BKASH_APP_SECRET is not configured.')
    raise NotImplementedError('bKash callback verification is not wired in.')


def _verify_nagad(raw_body, headers):
    if not getattr(settings, 'NAGAD_PUBLIC_KEY', ''):
        raise RuntimeError('NAGAD_PUBLIC_KEY is not configured.')
    raise NotImplementedError('Nagad callback verification is not wired in.')
