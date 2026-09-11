# Subscription payments

## What was wrong

`subscription_screen.dart::_subscribe()` looked up a plan by **display name**
(`Pro` / `Research` / `Free`) in the `GET /api/subscriptions/` response, but the
DB plans are named `free`, `monthly_basic`, `monthly_premium`, `yearly`,
`one_time_scan`. `plans.firstWhere(...)` therefore threw
`StateError: Bad state: No element`, surfaced as the generic "bad request".

There was also **no payment step**: the old `POST /api/subscriptions/` just
created a `Subscription` row with `status='pending'` that never activated, and
nothing asked for a payment method.

## The flow now

```
Disease Detection "View Plans"  /  Profile → Subscription
  → /subscription            plans list (server-driven), "current plan" if any
  → /subscription/review     plan review + order summary  → creates a PaymentIntent
  → /subscription/pay        payment-method选: Card (Visa·Mastercard) / bKash / Nagad
  → /subscription/checkout   DEV: simulated provider screen  |  LIVE: provider handoff
  → /subscription/result     success / failed / cancelled
```

Every screen has a back button, loading / error / retry states, disables
duplicate taps, and never shows an infinite spinner. A hard refresh mid-flow
(the `extra` object is lost on web) bounces safely to `/subscription`.

## Development vs production

`BILLING_MODE` (settings.py) — `dev` (default) or `live`. It **auto-upgrades to
`live`** only when a provider secret is actually set
(`STRIPE_SECRET_KEY` / `BKASH_APP_SECRET` / `NAGAD_MERCHANT_PRIVATE_KEY`).

### Development mode (`BILLING_MODE=dev`)

* **No real money moves.** Every screen carries a "Development payment mode"
  banner and the checkout is a labelled simulation.
* `POST /api/payments/<id>/confirm/` accepts `{"outcome": "success"|"failure"|"cancel"}`
  from the client — this is the *only* place a client can influence a payment,
  and it exists **only** in dev mode.
* On a simulated `success` the subscription activates; on `failure`/`cancel` it
  does not.
* No card / wallet fields are shown or collected. "Card" is just a label.

### Production mode (`BILLING_MODE=live`)

* `confirm` from the client is **refused** (409). Activation happens only from a
  **verified provider webhook** → `POST /api/payments/webhook/<provider>/`
  → `billing/webhooks.py::verify_and_parse`.
* `billing/webhooks.py` currently raises `NotImplementedError` for every
  provider — a mis-configured live deploy fails loudly instead of trusting an
  unsigned callback. Wire-in checklist is in that file's docstring:
  * **Stripe** — Checkout (hosted) or PaymentIntents; verify with
    `stripe.Webhook.construct_event(raw, sig, STRIPE_WEBHOOK_SECRET)`. The
    backend only ever sees a PaymentIntent id — never a PAN.
  * **bKash** — tokenized checkout; verify the callback then query
    `/tokenized/checkout/payment/status` and check the amount.
  * **Nagad** — verify the RSA signature on the callback with Nagad's public
    key, then call the payment-verify API.
  Each verifier returns `{'intent_id', 'provider_ref', 'outcome'}`.
* `CheckoutScreen` in live mode shows a "provider checkout not wired in" notice
  until an integration is added — replace that branch with the provider's
  hosted-page redirect / SDK.

**Never** send raw card number / expiry / CVC to the Featherflow backend. Use
the provider's hosted page or client-side tokenization; the backend receives a
token / intent id only. Nothing in this codebase has a PAN field.

## Backend

### Tables

* `subscription_plans`, `subscriptions`, `payments` — unmanaged, unchanged
  (schema-owned). `subscriptions` / `payments` remain the source of truth for
  active plans and completed money.
* **`billing_payment_intents`** — new, managed (`billing` app,
  `billing/migrations/0001_initial.py`). The short-lived order object:
  `user`, plan snapshot (`plan_id/code/name/interval`), **frozen `amount` +
  `currency`**, `payment_method`, `provider`, `status`
  (created/pending/succeeded/failed/cancelled/refunded), `provider_ref`,
  `idempotency_key` (unique per user), `failure_reason`, `payment_id` /
  `subscription_id` cross-refs, `metadata`, timestamps.

### Endpoints (all `IsAuthenticated`, `PaymentWriteRateThrottle` on writes)

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/subscriptions/plans/` | subscribable plans + `free_plan` + `current` + `mode` |
| GET | `/api/subscriptions/current/` | the caller's active subscription |
| POST | `/api/subscriptions/checkout/` | `{plan_id, idempotency_key?}` → `PaymentIntent` (201/200) |
| GET | `/api/payments/<id>/` | intent detail (owner only → 404 otherwise) |
| POST | `/api/payments/<id>/method/` | `{payment_method: card\|bkash\|nagad}` → `pending` |
| POST | `/api/payments/<id>/confirm/` | **dev only** `{outcome}` → activates on success |
| POST | `/api/payments/<id>/cancel/` | mark cancelled |
| POST | `/api/payments/webhook/<provider>/` | live-mode provider callback (signature-verified) |

The legacy `GET/POST /api/subscriptions/` still resolves (backward compat) but
the app no longer uses it.

### Guarantees

* **Amount is computed server-side** from the plan row — `amount` in the
  request body is ignored (test asserts `amount:1` → charged `599`).
* **Inactive / unknown / non-subscribable (`free`) plans** → 404 / 400.
* **Idempotency** — `checkout` with a repeated `idempotency_key` returns the
  same intent, no second row. Without a key, an open intent for the same plan
  is reused.
* **Activation is atomic + idempotent** — `_activate` locks the intent
  `SELECT … FOR UPDATE`; a retried confirm or a duplicate webhook cannot create
  a second `Subscription` / `Payment` (tests assert exactly one each).
* One active subscription per user — the previous one is retired to `replaced`.
* Failure / cancel are terminal and never activate anything.

## Payment-method branding / logos

The method screen uses **clean built-in placeholders**, not shipped brand art:

* **Card** — `Icons.credit_card` + small `VISA` / `Mastercard` text badges.
* **bKash** — pink (`#E2136E`) "bKash" chip.
* **Nagad** — orange (`#EE7000`) "Nagad" chip.

No unlicensed assets are bundled. To use official logos: obtain the brand
assets under each provider's brand guidelines, drop them in
`assets/payment/{visa,mastercard,bkash,nagad}.png`, add an `assets:` section to
`pubspec.yaml`, and swap the `_brandChip(...)` / `Icon` calls in
`lib/features/farmer/presentation/screens/subscription_flow_screens.dart`
(`_MethodTile.leading` / `badges`) for `Image.asset(...)`.

## Environment variables

| Var | Purpose |
|---|---|
| `BILLING_MODE` | `dev` (default) / `live`. Auto-`live` if any provider secret is set. |
| `STRIPE_SECRET_KEY`, `STRIPE_PUBLISHABLE_KEY`, `STRIPE_WEBHOOK_SECRET` | Stripe |
| `BKASH_APP_KEY`, `BKASH_APP_SECRET`, `BKASH_USERNAME`, `BKASH_PASSWORD`, `BKASH_BASE_URL` | bKash tokenized checkout |
| `NAGAD_MERCHANT_ID`, `NAGAD_MERCHANT_PRIVATE_KEY`, `NAGAD_PUBLIC_KEY`, `NAGAD_BASE_URL` | Nagad |
| `THROTTLE_PAYMENT_WRITE` | default `60/hour` |

## Root causes fixed

1. **"bad request" on Continue** — `subscription_screen.dart::_subscribe()`
   matched plans by display name (`Pro`/`Research`) not present in the DB
   (`monthly_premium`/`yearly`) → `plans.firstWhere(...)` threw
   `StateError: No element`. The screen is rewritten to render plans from
   `GET /api/subscriptions/plans/` and navigate by plan **id**.
2. **No payment step** — the old `POST /api/subscriptions/` created a
   `status='pending'` row that never activated. Replaced by the checkout flow +
   `billing` app.
3. **`RangeError: max must be in range 0 < max ≤ 2^32, was 0`** on the review
   screen — `Random().nextInt(1 << 32)` for the idempotency key: `1 << 32`
   overflows to `0` in dart2js (JS bitwise is 32-bit). Fixed to `nextInt(0x7fffffff)`.
   (Only reproduces in the web/release build, not the Dart-VM widget test —
   found by driving the real app.)

## Verified end-to-end (real Flutter web app)

Coordinate-driven Playwright walkthrough as `farmer.nasima@example.com`:
plans → "Review your plan" → "Choose payment method" (Card w/ VISA·Mastercard
badges, bKash, Nagad) → simulated Nagad checkout → "Approve payment" →
`/subscription/result`. DB after: `PaymentIntent(status=succeeded)`,
`Subscription(monthly_basic, active, expires +30d)`, one `Payment` row
(`notes: "…via dev-simulation (dev mode)"`, no card data). Re-opening
`/subscription` shows the "Current plan · Basic · ACTIVE" banner. **0 console
errors.**

## Tests

`backend/scripts/test_subscription_payment.py` — **38 checks**: plans shape &
server-side price, current subscription, checkout + idempotency, client amount
ignored, unknown/free plan rejected, all three methods, dev confirm
success/failure/cancel, activation exactly-once, idempotent confirm, no raw
card data in the `Payment` row, cross-user intent isolation (404),
webhook 404 in dev, unauthenticated 401, invalid token 401.

`test/subscription_flow_test.dart` — model parsing + widget smoke for
`SubscriptionScreen`, `PlanReviewScreen`, `PaymentMethodScreen` (Card/bKash/
Nagad shown, pay disabled until a method is chosen), `PaymentResultScreen`
(success / failed / cancelled).

## What is NOT implemented for real payments

* No Stripe / bKash / Nagad SDK or API call is made. `billing/webhooks.py` is
  stubs that raise.
* No refund endpoint (the `refunded` status exists in the model for a future
  admin/support action).
* No recurring-billing / renewal charge — `expires_at` is set from
  `plan.duration_days` and `auto_renew` is stored, but nothing charges again.
* No receipt PDF/email for subscription payments (the `Payment` row is created;
  wire it into the existing notification/receipt flow if needed).
