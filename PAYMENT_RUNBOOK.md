# FeatherFlow — Production Payment Runbook

**Date:** 2026-09-14
**Scope:** `billing/` app — subscription checkout, provider webhooks, refunds, disputes, reconciliation.
**Companion documents:** `PRODUCTION_READINESS_REPORT.md` §7, `OPERATIONS_RUNBOOK.md`, `SECURITY_HARDENING_REPORT.md`.

**Status: sandbox-only. Real-money payments are not enabled and must not be enabled from this runbook alone** — see §1. This document tells you exactly what to do *once* real provider credentials exist; it does not itself grant readiness to flip `BILLING_MODE=live`.

---

## 1. The one hard blocker, stated plainly

`billing/webhooks.py` verifies **nothing** for Stripe, bKash, or Nagad today — `_verify_stripe`/`_verify_bkash`/`_verify_nagad` each raise `RuntimeError` (if the relevant secret setting is unset) or `NotImplementedError` (if it is set) unconditionally. No HTTP call to any provider exists anywhere in this codebase. This is intentional: implementing real signature verification without a real sandbox account to test it against would mean shipping unverified crypto/HTTP code that *claims* to check a signature but has never actually been exercised against a real payload — worse than an honest stub.

**Do not**:
- Set `STRIPE_SECRET_KEY`, `BKASH_APP_SECRET`, or `NAGAD_MERCHANT_PRIVATE_KEY` in any deployed environment. `featherflow_backend/settings.py` auto-flips `BILLING_MODE` to `'live'` the instant any one of these is present — there is no separate opt-in switch. Today that would not overcharge anyone (nothing calls a provider), but it **breaks checkout outright** for every user, because `select_method` returns `redirect_url: None` in live mode with no real provider integration behind it.
- Claim payment integration is production-ready. It is not, until §2's checklist is run for real against a provider's sandbox and passes.

Everything else in this document is preparation so that, once real credentials exist, wiring in the three verifiers is the *only* remaining step — not a redesign.

---

## 2. Checklist to run before flipping `BILLING_MODE=live` for the first time (any provider)

Do this once per provider, in a **provider sandbox account**, before ever pointing at production credentials:

1. Obtain sandbox API keys/app secrets and a sandbox webhook signing secret (§3) — separate literal values from production, never the same credential reused.
2. Implement that provider's verifier in `billing/webhooks.py` (§5) and its checkout-session/payment-creation call (not yet built anywhere — `select_method` in `billing/views.py` only returns `redirect_url: None` today).
3. Point the provider's sandbox dashboard at this deployment's webhook URL (§4).
4. Fire a real webhook from the provider's sandbox (their dashboard has a "send test event" button, or trigger it via a real sandbox checkout) and confirm in your logs that `billing.webhooks.verify_and_parse` returns successfully — not that it *would*, that it *did*, against a byte-for-byte real payload with a real signature header.
5. Run the full `scripts/test_subscription_payment.py` suite (§8) plus a manual sandbox checkout end-to-end: create a subscription, confirm the webhook lands, confirm the subscription activates, confirm a refund flows back correctly, confirm a forced signature-tamper is rejected.
6. Only then, in a **staging** environment first, set the sandbox credentials and confirm `GET /api/subscriptions/plans/` reports `"mode": "live"` with sandbox charges succeeding end-to-end.
7. Repeat with production credentials in production, with the sandbox ones removed — never both configured in the same environment (see §3's naming convention, which makes this a copy-paste error to avoid rather than a structural safeguard the code enforces).

**Until step 4 has actually happened for a given provider, that provider is not production-ready — regardless of how much of steps 1-3 is done.**

---

## 3. Required credentials & environment variables

None of these exist in this environment today (verified: `backend/.env`, `backend/.env.example`, and the shell environment contain no `STRIPE_*`/`BKASH_*`/`NAGAD_*` values as of this pass). When they do, keep sandbox and production **in separate env files / separate secret-manager entries**, never the same variable holding different values per deploy target — that invites exactly the mix-up this runbook exists to prevent.

All of these are already declared in `featherflow_backend/settings.py` (read from the environment, default `''` unless noted) — nothing new needs adding to settings.py itself when real values arrive, only the verifier/checkout code in `billing/webhooks.py` and `billing/views.py` that consumes them.

| Provider | Env var | Sandbox source | Production source | Notes |
|---|---|---|---|---|
| Stripe | `STRIPE_SECRET_KEY` | Stripe Dashboard → Developers → API keys → **Test mode**, `sk_test_...` | Same page, **Live mode**, `sk_live_...` | Never log this value. Test/live keys are visually distinguishable by prefix — a real safeguard, unlike our env-var naming which needs discipline. Presence of this key is one of the three that auto-flips `BILLING_MODE` to `'live'` (see below). |
| Stripe | `STRIPE_PUBLISHABLE_KEY` | Same page, `pk_test_...` | `pk_live_...` | Safe to expose client-side; not a secret. |
| Stripe | `STRIPE_WEBHOOK_SECRET` | Stripe Dashboard → Developers → Webhooks → your sandbox endpoint → Signing secret, `whsec_...` | Same, on the **live** endpoint (Stripe issues a *different* signing secret per endpoint, even for the same account) | Required for `_verify_stripe` to even attempt verification — currently unset here, which is why the stub raises `RuntimeError` before it would ever reach the `NotImplementedError`. |
| bKash | `BKASH_APP_KEY`, `BKASH_APP_SECRET`, `BKASH_USERNAME`, `BKASH_PASSWORD` | bKash Merchant/PGW sandbox portal | bKash production onboarding (separate merchant agreement) | bKash's tokenized checkout requires exchanging these for a short-lived grant token before each checkout call — not implemented yet. `BKASH_APP_SECRET` presence is the auto-flip trigger. |
| bKash | `BKASH_BASE_URL` | Already defaults to `https://tokenized.sandbox.bka.sh` | Set explicitly to bKash's production base URL | **This default is sandbox** — do not assume unsetting it means "production"; it means "sandbox by default," so a forgotten override in a prod deploy fails safe (hits bKash's sandbox, not production) rather than fails dangerous. |
| Nagad | `NAGAD_MERCHANT_ID`, `NAGAD_MERCHANT_PRIVATE_KEY` (our own key, for signing outbound requests) | Nagad sandbox/UAT credentials from their merchant onboarding | Nagad production merchant credentials | `NAGAD_MERCHANT_PRIVATE_KEY` presence is the auto-flip trigger. |
| Nagad | `NAGAD_PUBLIC_KEY` (Nagad's key, to verify *their* signature on callbacks) | Nagad sandbox onboarding packet | Nagad production onboarding packet | Do not confuse with `NAGAD_MERCHANT_PRIVATE_KEY` above — one verifies inbound, the other signs outbound. |
| Nagad | `NAGAD_BASE_URL` | Already defaults to `https://api.mynagad.com/api/dfs` — **verify this is actually Nagad's sandbox/UAT host before relying on it**, unlike `BKASH_BASE_URL` whose default is clearly named `.sandbox.` | Confirm the production host against Nagad's own onboarding docs | Do not assume this default is sandbox just because bKash's is — Nagad's onboarding material is the source of truth here, this codebase has not verified it against a real Nagad account. |

**Never store**: card numbers, CVC, or any other cardholder data in this codebase. Every provider above hosts its own card-entry UI/SDK (Stripe Elements/Checkout, bKash's tokenized flow, Nagad's redirect flow) — this backend only ever sees a provider-issued reference token. `billing.models.PaymentIntent` has no field capable of holding raw card data, by design (see `PRODUCTION_READINESS_REPORT.md` §7).

---

## 4. Webhook URLs

Already routed and live (returns `404` while `BILLING_MODE != 'live'`, by design — see `billing/views.py:webhook`):

```
POST https://<your-domain>/api/payments/webhook/stripe/
POST https://<your-domain>/api/payments/webhook/bkash/
POST https://<your-domain>/api/payments/webhook/nagad/
```

Register the exact URL for each provider in that provider's sandbox dashboard first, production dashboard later — using the provider's own retry/delivery-confirmation semantics (a `2xx` response tells the provider delivery succeeded; this endpoint returns `200` for both a freshly-processed event and a detected duplicate, so a provider's automatic retry-on-non-2xx behavior won't cause reprocessing — see §6).

No IP allowlisting exists on this endpoint today — it authenticates purely via signature verification (once implemented), matching how Stripe/bKash/Nagad's own docs describe securing a webhook receiver. If your infrastructure sits behind a WAF/reverse proxy, make sure it does not block or rewrite the raw request body before it reaches Django — signature verification needs the **exact bytes** the provider signed, not a re-serialized copy.

---

## 5. What's already built vs. what still needs real-provider work

**Built, tested, provider-agnostic (this pass added the items marked \*):**

| Piece | File | Notes |
|---|---|---|
| Server-side amount computation | `billing/services.py:create_checkout` | Amount always comes from the DB plan row, never the request body. |
| Idempotent checkout | `billing/services.py:create_checkout` | DB-level `UniqueConstraint` on `(user, idempotency_key)`. |
| State machine | `billing/models.py` (`STATUS_CHOICES`, `TERMINAL_STATUSES`) | `created → pending → {succeeded, failed, cancelled, refunded, disputed}`. `disputed`\* is new this pass. |
| Activation only after verified success | `billing/services.py:_apply_outcome` → `_activate` | Only reachable via `confirm_dev` (dev-only, refused in live mode) or `confirm_provider` (only ever called after `verify_and_parse` succeeds). |
| Duplicate/replay webhook protection\* | `billing/models.py:WebhookEvent`, `billing/services.py:record_webhook_event` | A `(provider, event_id)` unique constraint — the second delivery of the same event is a DB-level no-op, answered `200` without reprocessing. Requires the verifier to return an `event_id` (§6). |
| Amount/currency mismatch guard\* | `billing/services.py:_amount_mismatch`, wired into `_apply_outcome` | If a verified webhook's reported amount/currency disagree with what the intent was created for, the intent is failed instead of activated — never trusts a client-supplied amount, and never activates on a provider-reported amount it can't reconcile with our own record. |
| Refund sync | `billing/services.py:mark_intents_refunded`, called from `api/admin_finance.py` | An admin refund of the legacy `payments`/`subscriptions` rows also marks the originating `PaymentIntent` `refunded`. |
| Dispute/chargeback handling\* | `billing/services.py:_flag_dispute` | A `'dispute'` outcome on an already-`succeeded` intent moves it to `disputed` and raises an `AdminEscalation` (`audit.models`) — **never auto-refunds**; a human decides. Idempotent against replay. |
| Reconciliation for missed/delayed webhooks\* | `billing/management/commands/reconcile_pending_payments.py` | Flags intents stuck in `created`/`pending` past `--stale-minutes` (default 30); times out ones stuck past `--timeout-hours` (default 24) by marking them `failed` — the same terminal state a real provider failure webhook would produce. `--dry-run` reports without mutating anything. Does **not** call any provider status API (none exists generically across the three providers) — this is a same-side safety net, not a provider integration. |
| Audit logging without secrets\* | `billing/services.py:record_audit_event` | Every state transition (success, failure, cancel, mismatch-reject, dispute) writes an `ActivityLog` row with intent id, status, amount, currency, provider — never a secret, token, or card fragment. |
| Sandbox/live separation | `featherflow_backend/settings.py`, `.env.example` | `BILLING_MODE` auto-upgrades to `'live'` only when a provider secret is set — see §1 for why this is also a footgun, not just a safeguard. |

**Not built — needs real credentials, per this pass's explicit instruction not to invent provider behavior:**

| Piece | Why it's blocked |
|---|---|
| `_verify_stripe` / `_verify_bkash` / `_verify_nagad` real implementations | Each needs to be written *and tested* against a real signed payload from that provider's sandbox — writing crypto/signature-checking code with nothing to verify it against is worse than the current explicit stub. |
| Provider checkout-session / payment-creation calls | `select_method` (`billing/views.py`) returns `redirect_url: None` in live mode today — no HTTP call to any provider to create a hosted checkout / tokenized payment exists yet. |
| bKash grant-token exchange | bKash's tokenized checkout requires fetching a short-lived grant token before each checkout call — not implemented, needs the sandbox app credentials to build against. |
| Real provider status/reconciliation lookups | §5's reconciliation command times out stuck intents using only our own clock; a real integration should also *ask the provider* for the intent's actual status before giving up, for the (small) fraction of cases where the provider did succeed but our webhook delivery failed. That's a provider-specific API call per provider — add it inside `reconcile_pending_payments.py`'s `_time_out` once each verifier exists, rather than failing blind. |

---

## 6. How the new hardening pieces plug in (for whoever implements a real verifier)

Each `_verify_stripe`/`_verify_bkash`/`_verify_nagad` must return a dict shaped exactly as documented in `billing/webhooks.py`'s module docstring:

```python
{
    'intent_id': '<uuid str>',        # billing.PaymentIntent.id this event is about
    'provider_ref': '<str>',          # the provider's own transaction/payment id
    'outcome': 'success' | 'failure' | 'cancel' | 'dispute',
    # optional, used when present:
    'event_id': '<str>',              # the provider's own delivery/event id — enables replay/duplicate protection
    'amount': '<str/Decimal-able>',   # what the provider says it charged
    'currency': '<str>',              # what the provider says the currency was
}
```

`billing/views.py:webhook` already does the rest: looks up the intent, calls `services.record_webhook_event(provider, event.get('event_id'), intent=intent)` (skips reprocessing if `False`), then `services.confirm_provider(intent, event['outcome'], event.get('provider_ref', ''), via=f'{provider}-webhook', event_amount=event.get('amount'), event_currency=event.get('currency'))`. **A real verifier only needs to parse and authenticate the payload — it should not reimplement any of the state-machine, dedupe, or mismatch logic**, all of which already exists and is tested against synthetic (but shape-correct) events in `scripts/test_subscription_payment.py`.

If a provider has no natural `event_id` (check their docs before assuming — Stripe's `event.id`, and bKash/Nagad's callback likely has an equivalent transaction/reference id), omit the key; `record_webhook_event` treats a missing id as "can't dedupe on delivery id" and always processes — replay protection then falls back to the intent's own idempotent state machine (a webhook confirming an already-`succeeded` intent is still a safe no-op, just without the "this exact delivery was a duplicate" distinction in the logs).

---

## 7. Incident playbook

| Symptom | Likely cause | Action |
|---|---|---|
| Webhook endpoint returning `404` in production | `BILLING_MODE` isn't `'live'` — check whether the expected secret env var is actually set in that environment | Confirm `GET /api/subscriptions/plans/` reports `"mode"` — if `"dev"` in an environment that should be live, the secret env var is missing/misnamed, not a code bug. |
| Webhook endpoint returning `400` for every real delivery | Verifier is rejecting a genuinely valid signature — check the signing secret matches the **specific endpoint** the provider is calling (Stripe issues a distinct `whsec_` per endpoint) and that no reverse proxy is altering the raw request body before Django sees it (§4) | Check `billing` logger for `webhook rejected (<provider>): <reason>` — the reason string here is deliberately specific, not just "invalid". |
| A batch of intents stuck in `pending` with no webhook | Provider outage, misconfigured webhook URL, or our endpoint was down when the provider tried delivery | Run `python manage.py reconcile_pending_payments --dry-run` first to see the size of the backlog, then without `--dry-run` once you've confirmed these really are dead (not just slow) — see §5 for what this does and does not do. |
| `Payment amount/currency mismatch` warnings in logs | Either a real provider-side pricing discrepancy (investigate immediately — do not silently increase the timeout/retry to make the warning go away) or a plan-price change that raced an in-flight checkout | Check `intent.failure_reason` and the log line's `expected X, provider reported Y` — cross-reference against the plan's current price and the intent's `created_at` vs. any pricing change. |
| A dispute (`AdminEscalation` with `module='billing'`) appears | A cardholder/provider chargeback on a completed payment | Review in the admin escalations queue — the intent is already `disputed`, the subscription is **not** auto-cancelled, no refund has been auto-issued. A human decides the outcome (uphold the charge and clear the dispute, or refund via the existing admin refund flow, which also correctly syncs the `PaymentIntent`). |
| Suspected replayed/forged webhook flood | Someone captured a real webhook payload and is resending it | Once a verifier is real, a captured-and-replayed payload still needs a *valid* signature to pass `verify_and_parse` at all (replay protection here guards duplicate delivery of legitimately-signed events, not forged ones — signature verification is the actual defense against forgery). If signatures are failing as expected, this is contained; if they're passing, rotate the webhook signing secret immediately. |

---

## 8. Test coverage map

`scripts/test_subscription_payment.py` (run: `backend/venv/Scripts/python.exe backend/scripts/test_subscription_payment.py`) covers, **without any real provider credentials**:

| Scenario (from the task's own list) | How it's tested | Real-provider-dependent? |
|---|---|---|
| Valid webhook | `billing.webhooks._verify_stripe` monkeypatched (test-scope only, restored after) to return a synthetic already-verified event; exercises the real `webhook()` view + `confirm_provider` + `_activate` | Verification itself: yes, not covered. Everything downstream of verification: no, fully covered. |
| Invalid signature | Real, unpatched `_verify_stripe` in live mode with no `STRIPE_WEBHOOK_SECRET` configured — genuinely exercises today's rejection path | No — this is real code, not simulated. |
| Replay webhook | Same intent confirmed twice via two different synthetic `event_id`s — asserts idempotent (no double activation) | No |
| Duplicate webhook | Same synthetic `event_id` delivered twice — asserts the second is deduped via `WebhookEvent` and returns `duplicate: true` without reprocessing | No |
| Successful / failed / cancelled payment | Direct dev-mode confirm (`/confirm/`) and synthetic-webhook paths, both | No |
| Refund | Real admin refund endpoint, asserts sync to `PaymentIntent` (pre-existing test, still passing) | No |
| Subscription activation (only after verified success) | Asserted throughout — a mismatch or failure never creates a `Subscription` row | No |
| Provider timeout | Modeled as "no webhook ever arrives" — a backdated stuck intent processed by `reconcile_pending_payments`, asserting it times out to `failed` | Network-level timeout behavior against a real provider: not covered (there is no real HTTP call to time out yet). The functional consequence — a payment that never confirms must not silently stay pending forever or silently activate — is covered. |
| Mismatched amount/currency | Synthetic webhook event with a deliberately wrong amount/currency — asserts rejection, not activation | No |
| Dispute/chargeback | Synthetic `'dispute'` outcome on a succeeded intent — asserts `disputed` status, `AdminEscalation` raised, no auto-refund, idempotent against replay | No |

**What remains genuinely untested and will stay that way until real sandbox credentials exist**: whether `_verify_stripe`/`_verify_bkash`/`_verify_nagad`, once written, correctly validate a *real* provider signature (not just our own synthetic stand-in), and whether the not-yet-built checkout-creation HTTP calls actually work end-to-end against a provider sandbox. §2 is the checklist for closing that gap when the credentials arrive.

Run the full regression suite (`OPERATIONS_RUNBOOK.md` §8) after any change to `billing/` — this pass's changes bring `test_subscription_payment.py` to **65/65** (was 41/41).

---

## 9. Kill switch

If live mode is ever accidentally enabled in a deployed environment: set `BILLING_MODE=dev` explicitly (fastest — it overrides the auto-detection outright), or remove/unset the `STRIPE_SECRET_KEY`/`BKASH_APP_SECRET`/`NAGAD_MERCHANT_PRIVATE_KEY` env var that triggered the auto-upgrade, then restart the app process (`featherflow_backend/settings.py`: `BILLING_MODE = os.environ.get('BILLING_MODE', 'live' if any provider secret is set else 'dev')` — an explicit `BILLING_MODE` env var always wins over the auto-detection). Any `PaymentIntent` left `pending` from the moment live mode was mistakenly on is safe — no provider call was made (none exists yet) — run `reconcile_pending_payments --dry-run` afterward to see if any accumulated.
