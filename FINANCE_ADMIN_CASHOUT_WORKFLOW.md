# Finance Admin — Cashout Workflow

Companion to `FINANCE_ADMIN_DASHBOARD_AND_SUBSCRIPTIONS.md` and
`FINANCE_ADMIN_RBAC_CHANGES.md`. Nothing in this work was committed.

## 1. What already existed

A farmer-facing "cashout" action already existed
(`backend/farmers/cost_views.py:cashout`, route
`farmers/costs/cashout/`) — it creates a `payments.Payment` row with
`payment_type='cashout'`, `status='pending'`, and a payout
method/account-details note. There was **no Finance Admin review
workflow at all** for these rows before this pass: they were only
visible mixed into the generic `/admin-panel/payments/` list (no
cashout-specific filter, no approve/reject action, no idempotency guard,
no self-approval check — all confirmed absent in
`FINANCE_ADMIN_RBAC_AUDIT.md`). Delivery-rider payouts (`DeliveryEarning`,
module `payouts`→`delivery`) are a **separate, pre-existing, unrelated**
mechanism gated to Delivery/Operations Admin — deliberately not touched or
merged with this workflow (see `FINANCE_ADMIN_RBAC_CHANGES.md` for why
`payouts.approve` in the required-permission list is interpreted as
"approve a cashout payout," not "gain access to delivery-rider payroll").

## 2. Design — extend, don't duplicate

Rather than a parallel "cashout request" model duplicating
amount/currency/requester (already on `Payment`), a new table
`cashout_reviews` (`backend/finance_admin_extension.sql`,
model `api.finance_models.CashoutReview`) holds a **one-to-one review
record per cashout-type Payment** (`UNIQUE(payment_id)`), carrying only
the review-specific fields: `status`, `reviewed_by`, `reviewed_at`,
`rejection_reason`, `notes`, `settled_at`.

## 3. State machine

```text
requested / under_review --approve--> approved --settle--> paid
                          --reject--> rejected
```

- **requested**: created by `farmers.cost_views.cashout` at the moment the
  request is made (now also creates the paired `CashoutReview` row —
  previously it did not, meaning cashouts before this change were
  invisible to any review queue at all; fixed in this pass).
- **under_review**: set automatically only when an approval gets queued
  for a higher tier (see §5) — otherwise a request simply stays
  `requested` until reviewed directly.
- **approved**: Finance Admin decided yes. The underlying `Payment.status`
  is *not* changed yet — money hasn't moved.
- **rejected**: Finance Admin decided no (a reason is required). The
  underlying `Payment.status` becomes `failed` (the closest fit within
  this project's `payments_status_check` constraint —
  `pending/completed/failed/refunded` are the only allowed values; there
  is no `cancelled` payment status in this schema). The `CashoutReview`
  row itself, not the payment status string, is the actual source of
  truth for *why*.
- **paid**: a follow-up "settle" action on an already-`approved` request —
  `Payment.status` becomes `completed`, `settled_at` is stamped. This is
  the only way a cashout's underlying payment is ever marked as money
  actually paid out.

**Pending Cashout Requests** = `status IN (requested, under_review)` —
"still needs Finance Admin action." **Approved Cashout Requests** =
`status IN (approved, paid)` — "Finance Admin already made the call";
`paid` is the settled continuation of the same decision, not a second
review. No `rejected`/`cancelled` request ever appears on either page —
confirmed by test (a rejected request is asserted absent from both the
pending and approved queries).

## 4. Endpoints

```text
GET  /api/admin-panel/cashouts/pending/            permission: cashouts.view
GET  /api/admin-panel/cashouts/approved/           permission: cashouts.view
POST /api/admin-panel/cashouts/<review_id>/review/  permission: cashouts.approve / cashouts.reject
     body: {"decision": "approve" | "reject" | "settle", "reason"?, "notes"?}
```

(`backend/api/admin_cashouts.py`). Both list endpoints are
server-paginated (`limit`/`offset`, capped at 200/request) and join
`CashoutReview` → `Payment` → requester name/role — never returning
identity-document, medical, or verification fields (verified by test:
`is_verified`/`license_number` are absent from every cashout row).

### Concurrency / integrity

- `transaction.atomic()` + `select_for_update()` on both the
  `CashoutReview` and `Payment` rows before any status change — two
  reviewers racing the same request cannot both succeed (the second sees
  the already-updated `status` once it acquires the lock and gets a clean
  409, not a corrupted double-decision).
  - Note: `select_for_update()` is applied to `Payment` **without**
    `select_related('user')` — Postgres refuses `FOR UPDATE` across an
    outer join, and `Payment.user` is nullable, so joining it in would
    make the lock query fail outright. The requester's name is instead
    read via a plain (unlocked) FK access after the row is already
    locked, which is safe since nothing else can mutate the locked row
    concurrently.
- Re-approving/re-rejecting an already-decided request → `409
  already_decided` (idempotent, verified by test).
- Settling a request that isn't `approved` yet → `409 invalid_transition`.
- Rejecting without a `reason` → `400` (verified by test).
- **Self-approval is blocked explicitly**: `if payment.user_id ==
  request.user.id: return 403` — checked before any status change, for
  every decision (approve/reject/settle), not only the above-threshold
  path. Verified by test.
- **No DELETE route exists anywhere in this workflow** — a cashout
  request can only move through the state machine above; it can never be
  permanently removed.

### Above-threshold escalation

Reuses the **existing** approval-queue infrastructure
(`api/admin_approvals.py`) rather than building a second one. If
`payment.amount > REFUND_APPROVAL_THRESHOLD` (৳5000, the same constant
the refund-approval gate already used —
`api/admin_rbac.py:REFUND_APPROVAL_THRESHOLD`) and the caller's tier
can't self-clear it (`tier > TIER_OPERATIONS`), the review is parked via
`enqueue_approval(action_type='approve', module='cashouts', ...)`,
`CashoutReview.status` is set to `under_review`, and the endpoint returns
`202 approval_required`. When an Operations/Super Admin later decides
that queue entry, `execute_approved()`'s new `_do_approve_cashout`
branch (`api/admin_approvals.py`) finalizes it — same dispatch mechanism
already used for suspend/refund/team-role-change, now also cashouts.
Verified by test: a ৳6000 cashout returns `202` and lands in
`under_review`, not `approved`.

**Note on the threshold check's integrity**: `_lookup_amount()`
(`api/admin_views.py`) previously preferred a **client-supplied**
`amount` over the server-recorded one for the *refund* threshold gate — a
real bypass (documented as Critical in `FINANCE_ADMIN_RBAC_AUDIT.md`).
Fixed as part of this pass (see `FINANCE_ADMIN_RBAC_CHANGES.md` §3); the
new cashout-approval threshold check in `admin_cashouts.py` was written
to always use `payment.amount` directly and never accepts a client-
supplied override at all.

## 5. Audit

Every decision (approve/reject/settle, and the queued-then-later-approved
path) writes an `ActivityLog` row: `module='cashouts'`, actor
(`request.user`/the approver), `action_type` (approve/reject/edit),
`entity_id` (the review id), `old_values`/`new_values` (the status
transition), and `reason` (the rejection reason, when given). A
notification is also sent to the requester on every decision.

## 6. Frontend

`AdminCashoutsScreen` (`lib/features/admin/presentation/screens/admin_cashouts_screen.dart`),
one widget parametrized by `pending: bool` so Pending/Approved share the
card layout without duplicating it. Sidebar entries "Pending Cashout
Requests" / "Approved Cashout Requests" (gated on
`AdminModule.cashoutsPending`/`cashoutsApproved`, i.e. the `cashouts`
permission key — visible to Finance Admin only). Approve/settle use a
confirmation dialog; reject requires a typed reason via
`showAdminTextPrompt` before the request is even sent. Loading/empty/
error/retry states via the shared `AdminLoading`/`AdminEmpty`/`AdminError`
widgets (the same ones the rest of the admin panel already uses).

## 7. Test coverage

`backend/scripts/test_finance_admin.py` (35 checks, all passing) covers:
new cashout appears in Pending; no user-verification fields leak into the
row; approve → moves to Approved; duplicate approve → 409; reject without
a reason → 400; reject with a reason → 200 and excluded from both queues;
self-approval → 403; above-threshold → 202/`under_review`, not
auto-approved.
