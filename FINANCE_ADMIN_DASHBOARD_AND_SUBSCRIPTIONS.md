# Finance Admin — Dashboard, Subscriptions & Revenue

Companion to `FINANCE_ADMIN_CASHOUT_WORKFLOW.md` and
`FINANCE_ADMIN_RBAC_CHANGES.md`. Builds directly on the gaps identified in
`FINANCE_ADMIN_RBAC_AUDIT.md` (the prior audit-only pass). Nothing in this
work was committed.

## 1. What was inspected first

- **Dashboard/routes/sidebar**: `AdminDashboardScreen` is one shared screen
  for every admin role (`lib/features/admin/presentation/screens/admin_dashboard_screen.dart`),
  branching only on session data — Finance Admin previously saw the same
  Operations-oriented "Active Users"/"Pending Approvals"/"Recent Activity"
  cards as every other role.
- **Subscription plans**: `subscriptions.SubscriptionPlan`/`Subscription`
  (`backend/subscriptions/models.py`) already existed, but the admin-panel
  `subscription-plans` collection endpoint was backed by a **hardcoded
  Python dict** (`api/admin_views.py`'s `SEEDS['subscription-plans']`) —
  4 fake plan rows, never touching the real `SubscriptionPlan` table at
  all. Editing a "plan" through the old generic endpoint would have
  written into `AdminPanelRecord.payload` (a generic JSON blob store), not
  a real plan row.
- **Billing/payment intents**: `billing.PaymentIntent`/`_activate()`
  (`backend/billing/services.py`) is the one authoritative place a
  subscription payment becomes "verified paid" — it already runs inside
  `@transaction.atomic`, row-locks the intent (`select_for_update`), and is
  itself idempotent (`if locked.status == 'succeeded': return locked`).
  There was, however, **no revenue/ledger model of any kind** anywhere in
  the codebase — `finance_summary`'s "MRR"/"lifetime revenue" numbers were
  computed by re-summing `Payment`/`Subscription` rows on every request,
  not from a recognized-revenue-event ledger.
- **Active-user query**: already fixed for the Operations Admin dashboard
  earlier this session (`OPERATIONS_ADMIN_DASHBOARD_AUDIT.md` §4) —
  `User.objects.filter(account_status='active').count()`. Reused verbatim
  for the Finance dashboard rather than redefined.
- **Pending approvals / approvals dashboard**: the generic
  `AdminApprovalQueue` (farmer/doctor/pharmacy/delivery/researcher
  verification, admin suspensions, role changes) — confirmed Finance
  Admin had `"approvals": ["view"]` in its permission map
  (`postgres_backend_extension.sql`), i.e. it could see this queue. See
  `FINANCE_ADMIN_RBAC_CHANGES.md` for the removal.
- **RBAC/permission helpers**: `api/admin_rbac.py`'s module:action
  permission map (unchanged shape, just a different set of grants — see
  the RBAC doc).
- **Reports/export/audit-log**: `admin_module_export` (generic CSV of
  whatever `_collection_rows` returns) and `admin_audit_logs` (found
  unscoped by default in the prior audit — fixed as part of this pass,
  documented in `FINANCE_ADMIN_RBAC_CHANGES.md`).
- **Reference images**: image 1 (a dark-green "Approval Queue" bar with
  a visible green "Pending" chip and three blank/invisible pills) is
  `AdminApprovalsScreen`'s `_StatusTabs` — see §5 below. Image 2 (a
  tabbed Plans/Subscribed-Users/Payments layout) shaped the Subscriptions
  module's 3-tab structure in §2.

## 2. Subscriptions module

New sidebar item **"Subscriptions"** (`lib/features/admin/presentation/widgets/admin_sidebar.dart`),
gated on `session.canAccess(AdminModule.subscriptions)` — visible only when
the caller's permission map actually has a `subscriptions` key (true for
Finance Admin after the RBAC change; false for every other role, so it
can't be reached "merely because the Finance item is visible").
Route: `/admin/subscriptions` → `AdminSubscriptionsScreen`
(`lib/features/admin/presentation/screens/admin_subscriptions_screen.dart`),
a 3-tab screen: **Plans / Subscribed Users / Payments**. No parallel
billing system — all three tabs read the existing `subscriptions`/
`payments` app models.

### A. Plans — now real, not seed data

New dedicated endpoint (`backend/api/admin_subscriptions.py`, registered
ahead of the old generic `<str:module>/` catch-all):

```text
GET   /api/admin-panel/subscription-plans/       list, permission: subscriptions.view
POST  /api/admin-panel/subscription-plans/       create, permission: subscriptions.manage
PATCH /api/admin-panel/subscription-plans/<id>/  edit/activate/deactivate, permission: subscriptions.manage
```

- Trace: Flutter `_PlansTab` → `AdminApiService.subscriptionPlans()` →
  `subscription_plans_list` → `SubscriptionPlan.objects.all()` +
  `Subscription.objects.values_list('plan_id').annotate(Count)` for
  `subscriber_count` → `subscription_plans` table.
- Fields shown: name, features (`features_unlocked` JSON — reused, no new
  "description" column), billing interval (**derived** from
  `duration_days` via the new `SubscriptionPlan.billing_interval`
  property — 30→`monthly`, 365→`yearly`, none→`one_time`; deliberately
  not a duplicate stored column), price, currency, active/inactive,
  subscriber count, created/updated date (`updated_at` is a genuinely new
  column — see §6 — the row never had one before).
- Validation (server-side, price never trusted from Flutter): name
  required + unique (case-insensitive), price is a non-negative Decimal,
  currency ∈ {BDT, USD}, duration_days is a positive integer or omitted
  (one-time). Duplicate name → 400/409. Negative price → 400.
- **No DELETE route exists** — plans can only be deactivated
  (`is_active=False`), never removed, so a plan with subscription history
  can never be corrupted or orphaned. Deactivating a plan does not touch
  any existing `Subscription` row (verified by test — see below).
- Every create/edit is audit-logged (`ActivityLog`, `module='subscription-plans'`,
  with before/after `old`/`new` values).

### B. Subscribed Users

Reuses the existing `subscriptions` collection endpoint
(`GET /api/admin-panel/subscriptions/`, unchanged) — real `Subscription`
rows only, gated on `subscriptions.view`. Shows user, plan, status,
started/expires dates, price, auto-renew. This page cannot edit user
verification/account status — it has no write action at all, only GET.

### C. Subscription Payments

Reuses the existing `payments` collection endpoint (unchanged), filtered
client-side to exclude `Payout`-typed rows (delivery-rider payouts belong
to Delivery Admin, not here). Shows real `Payment` rows: amount, currency,
status, method, dates. No gateway credentials, tokens, or raw payloads are
in the `Payment` model at all (see `FINANCE_ADMIN_RBAC_AUDIT.md` §9 — this
was already a clean pass before this work).

## 3. Revenue recognition — the actual fix

### Before

`finance_summary` computed "MRR"/"lifetime revenue" by re-aggregating
`Payment`/`Subscription` rows live on every request — not wrong per se,
but there was no durable, auditable record of *when* revenue was
recognized, no way to show a refund as a separate visible adjustment
(refunding just flipped `Payment.status`, with nothing to distinguish "this
revenue was reversed" from "this revenue never existed"), and no idempotency
guarantee beyond `_activate()`'s own row lock.

### After

New table `revenue_entries` / model `api.finance_models.RevenueEntry`
(`backend/finance_admin_extension.sql`, applied to the dev DB). One row
per recognized revenue *event* — not per payment — with a
`UNIQUE(source_payment_id, category)` index so:

- The original `'subscription'` recognition can never be duplicated for
  the same payment (a retried webhook, a second confirmation racing the
  first, both hit `IntegrityError` and are treated as "already
  recognized" — see `recognize_revenue()` in `billing/services.py`).
- A refund's `'refund_adjustment'` reversal is a **separate row**, also
  idempotent, storing the **negative** of the original amount — so
  `Sum(amount)` over the whole table (or over a month window) nets out
  correctly with a single aggregate query, and the original recognition
  row is never edited or deleted (`reverse_revenue()` only ever inserts).

Trace: `billing.services._activate()` (inside its existing
`@transaction.atomic`, right after creating the `Payment` + `Subscription`
rows) → `recognize_revenue(payment, subscription=sub, plan=plan)` →
`RevenueEntry.objects.create(...)`. On refund
(`api/admin_finance.py:finance_action`, both the `sub:` and generic
`Payment` branches) → `reverse_revenue(payment)`.

```text
paid subscription payment
  -> Payment.objects.create(status='completed')      [billing/services.py:_activate]
  -> Subscription.objects.create(status='active')    [same atomic block]
  -> recognize_revenue(payment, subscription, plan)   [same atomic block, idempotent insert]
  -> included in finance/dashboard's monthly_revenue / total_revenue aggregates
```

Pending/failed/cancelled payments never call `recognize_revenue` at all —
verified by test (a `status='pending'` payment has zero revenue entries).

### Monthly Revenue — timezone/window rule

`Sum(revenue_entries.amount)` where `recognized_at` falls in
`[1st of this month 00:00, 1st of next month 00:00)`, computed in
**Asia/Dhaka** local time (`api/admin_finance.py:_month_bounds`, the same
convention `api/admin_shifts.py` already established for shift/earnings
windows). Total Revenue is the unbounded `Sum(amount)` over the whole
table. Both are single-aggregate queries (`django.db.models.Sum`), not a
Python loop over every row.

### Sandbox disclosure

This project's checkout flow is dev-mode/sandbox unless a real provider
secret is configured (`BILLING_MODE`, `featherflow_backend/settings.py`) —
unchanged by this work. No real Stripe/bKash/Nagad integration exists in
this environment; the "Verified paid" trigger above fires identically
whether the confirmation came from the dev-mode simulated checkout or a
real provider webhook (`billing/webhooks.py`), since both funnel through
the same `_apply_outcome`/`_activate` path.

## 4. Dashboard metrics — widget → field → query → table → rule

New endpoint `GET /api/admin-panel/finance/dashboard/`
(`admin_finance_dashboard`, `api/admin_finance.py`), permission
`finance.view`. `AdminDashboardScreen` renders `_FinanceDashboardBody`
instead of the generic Operations body when `session.role ==
AdminRole.financeAdmin` — the Operations/Super Admin dashboard body is
completely untouched (a separate widget, a separate branch), preserving
the existing hierarchy exactly as instructed.

| UI label | API field | Query | Table | Inclusion/exclusion | Refresh |
|---|---|---|---|---|---|
| Monthly Revenue | `monthly_revenue` | `Sum(amount)` where `recognized_at` in this Asia/Dhaka calendar month | `revenue_entries` | Both `subscription` and `refund_adjustment` categories (refunds net out automatically since reversals are negative) | On dashboard open, pull-to-refresh |
| Total Revenue | `total_revenue` | `Sum(amount)`, unbounded | `revenue_entries` | Same as above, all-time | Same |
| Active Subscriptions | `active_subscriptions` | `count()` where `status='active'` | `subscriptions` | Only the `active` status string | Same |
| Expiring subscriptions | `expiring_subscriptions_7d` | `count()` where `status='active' AND expires_at` in `[now, now+7d)` | `subscriptions` | Active only, next 7 days | Same |
| Active Users | `active_users` | `count()` where `account_status='active'` | `users` | Excludes pending/suspended/banned — same definition as the Operations dashboard fix | Same |
| Failed payments | `failed_payments_30d` | `count()` where `status='failed' AND created_at >= now-30d` | `payments` | Rolling 30-day window | Same |
| Pending Cashout Requests | `pending_cashout_requests` | `count()` where `status IN (requested, under_review)` | `cashout_reviews` | See `FINANCE_ADMIN_CASHOUT_WORKFLOW.md` | Same |
| Approved Cashout Requests | `approved_cashout_requests` | `count()` where `status IN (approved, paid)` | `cashout_reviews` | Same doc | Same |
| Recent Payments | `recent_payments` | `.order_by('-created_at')[:10]` | `payments` | Newest 10 payment rows of any type, newest-`created_at`-first | Same |

**Metrics named in the task but not implemented** (documented honestly,
not fabricated): Pending Payouts / Settled Payouts (delivery-rider payout
totals — that data belongs to the Delivery module, which Finance Admin
does not have access to; see `FINANCE_ADMIN_RBAC_CHANGES.md` for why this
stays separate), Platform Commissions, Outstanding Liabilities — no
commission/liability ledger exists anywhere in this codebase; inventing
one was out of scope for this pass.

## 5. Recent Activity → Recent Payments

The generic `_activity` feed (`_stats`/`_tasks`/`_activity` from the
shared `admin_dashboard()` endpoint) is entirely gone from Finance
Admin's view — `_FinanceDashboardBody` never calls
`AdminApiService.dashboard()` at all, only `financeDashboard()`. "Recent
Payments" replaces it: the same `recent_payments` list documented above,
capped at 10, each row showing user, plan/type, amount+currency, status,
method, and linking to the Subscriptions module ("View all payments"
button → `/admin/subscriptions`). No mock activity item exists anywhere
in this path — every row is a real `Payment.objects.order_by('-created_at')`
result.

## 6. Migrations / schema

No Django migrations — this project's established convention is
hand-written SQL extension files applied directly (confirmed via
`manage.py migrate --check`, 0 pending, both before and after this work).
New: `backend/finance_admin_extension.sql` — `revenue_entries`,
`cashout_reviews` (see the cashout doc), and one added column
(`subscription_plans.updated_at`). Applied to the dev DB directly via a
one-off `connection.cursor().execute(sql)` (same method used earlier this
session for prior extension files) — not a migration, matching this
codebase's `managed=False` convention throughout.

## 7. Known limitation

Total Revenue nets refunds correctly (negative reversal rows), but if a
subscription's rate/price *itself* changes after being recognized (this
project has no such concept for subscription plans today — prices are
fixed per plan, not per-admin like the Operations Admin hourly rate),
there would be no re-recognition path. Not applicable today; flagged for
completeness.
