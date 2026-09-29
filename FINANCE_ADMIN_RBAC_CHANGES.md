# Finance Admin — RBAC Changes

Directly implements the remediation plan in `FINANCE_ADMIN_RBAC_AUDIT.md`
(the prior audit-only pass) plus this task's explicit permission list.
Companion to `FINANCE_ADMIN_DASHBOARD_AND_SUBSCRIPTIONS.md` /
`FINANCE_ADMIN_CASHOUT_WORKFLOW.md`. Nothing in this work was committed.

## 1. Permission map — before / after

Role identifier remains `admin_finance` (this codebase's actual
identifier — see the audit's §2 for the `finance_admin` naming note;
unchanged here, not part of this task's scope).

**Before** (`postgres_backend_extension.sql`, tier 3):
```json
{
  "finance": ["view","edit","refund","export","approve"],
  "subscriptions": ["view","edit","approve","refund","export"],
  "users": ["view"],
  "audit": ["view"],
  "approvals": ["view"]
}
```

**After** (`finance_admin_extension.sql`, applied to the dev DB):
```json
{
  "finance": ["view","edit","refund","export","approve"],
  "subscriptions": ["view","edit","approve","refund","export","manage"],
  "cashouts": ["view","review","approve","reject"],
  "audit": ["view"]
}
```

- **Removed**: `users` (read access to the user list/approval-adjacent
  data) and `approvals` (the generic operational approval queue —
  farmer/doctor/pharmacy/delivery/researcher verification, admin
  suspensions, role changes). Finance Admin has zero access to either
  now, verified live (`GET /users/` → 403, `GET /approval-queue/` → 403).
- **Added**: `cashouts` (new module, `view`/`review`/`approve`/`reject` —
  backs the workflow in `FINANCE_ADMIN_CASHOUT_WORKFLOW.md`) and
  `subscriptions.manage` (plan create/edit/activate/deactivate — backs
  `FINANCE_ADMIN_DASHBOARD_AND_SUBSCRIPTIONS.md` §2A).
- **Unchanged**: `finance` (view/edit/refund/export/approve — already
  matched the required scope) and the existing `subscriptions` actions.

## 2. Mapping the task's 8 required permission strings

This project's RBAC is module:action (`{module: [action, ...]}`), not a
flat list of dotted permission strings — the same shape used by every
other role, unchanged by this task. Each required string maps onto that
existing shape rather than introducing a second, parallel permission
vocabulary:

| Required string | Backend mapping |
|---|---|
| `finance.view` | `finance: view` (unchanged, pre-existing) |
| `finance.export` | `finance: export` (unchanged, pre-existing) |
| `subscriptions.manage` | `subscriptions: manage` (**new** action, gates plan create/edit/activate/deactivate only — reading plans/subscriptions still just needs `view`) |
| `payments.view` | `payments` is aliased to the `finance` module (`MODULE_ALIASES`, pre-existing) → `finance: view` |
| `refunds.create` | the existing `refund` action on `finance`/`subscriptions` (a Finance Admin's own refund, under the approval threshold) |
| `refunds.approve` | the existing threshold escalation (`requires_approval`) — refunds above ৳5000 require Operations/Super Admin via the approval queue; this is a threshold, not a separate grantable permission a role can hold independently of `refund` itself |
| `cashouts.review` | `cashouts: view` (list Pending/Approved) |
| `payouts.approve` | `cashouts: approve` — **scoped to cashout settlement, not delivery-rider payroll**. See §3. |

## 3. Why `payouts.approve` does not restore delivery-rider payout access

The pre-existing, intentional design (confirmed by an existing test:
`scripts/test_admin_panel.py` — `finance BLOCKED from riders (403)`,
`finance lacks delivery perms`) keeps delivery-rider payout/payroll data
(`DeliveryEarning`, module `payouts`→`delivery`) under Delivery/Operations
Admin only. This task's own restrictions list explicitly repeats that
Finance Admin must not touch "Operations workflows unrelated to finance"
and lists delivery-worker *verification* as forbidden. Reading
`payouts.approve` in this task's context (Section 6/7, the cashout
dashboard/workflow section) as "approve a **cashout** payout" — not "gain
delivery-rider payroll access" — keeps both instructions satisfied
simultaneously: Finance Admin gets real payout-approval authority (over
farmer cashouts, which are the actual "payout" data flowing through
Finance's own domain), without reopening the delivery-module boundary the
existing test suite already locks in place. Verified live and by test:
Finance Admin still gets 403 on `/riders/` and `/payouts/` (the delivery
one) after this change.

## 4. Fixed: audit-log cross-department leak (Critical, from the prior audit)

`admin_audit_logs` (`api/admin_extra.py`) used to return **every**
module's activity by default unless the caller happened to pass
`?module=`. Fixed: a tier-3 module admin (Finance, Content, Research, …)
now gets a **default filter** to only the module(s) it's actually
permitted in, unless it explicitly passes `?module=` itself. Super Admin
and Operations Admin (who legitimately oversee everything) are
unaffected. The filter maps canonical permission keys back to every
endpoint *slug* that resolves to them (`MODULE_ALIASES`), since
`ActivityLog.module` stores the slug (e.g. `payments`), not always the
canonical key (`finance`) — without that mapping the fix would have
accidentally hidden Finance Admin's own payment/refund audit history.

## 5. Fixed: refund/cashout approval-threshold amount spoofing (Critical)

`_maybe_enqueue` (`api/admin_views.py`) used to compute the
approval-threshold check as:

```python
context['amount'] = request.data.get('amount') or _lookup_amount(module, record_id)
```

A caller could include a low `amount` in the request body to make a
large refund appear under the ৳5000 threshold and skip the approval
queue entirely — the *actual* refunded amount was always the real
payment amount (never taken from the client), but the **decision of
whether approval was required at all** could be lied to. Fixed: the
threshold check now always uses the server-computed `_lookup_amount(...)`
directly, ignoring any client-supplied `amount`. The new cashout-approval
threshold check (`api/admin_cashouts.py`) was written the same way from
the start — it never reads an `amount` from the request body at all.

## 6. Frontend

- Sidebar (`admin_sidebar.dart`): the existing "Approval Queue" item is
  unaffected in code (still gated on `AdminModule.approvals`) — it now
  simply never renders for Finance Admin, since `canAccess(approvals)` is
  false once the permission key is gone. No UI code had to specifically
  "know about" Finance Admin to hide it; removing the permission was
  sufficient. Verified by widget test (`admin_finance_test.dart`): with no
  session, `Approval Queue`/`Subscriptions`/`Pending Cashout Requests`/
  `Approved Cashout Requests` are all absent (the same mechanism that
  hides them from Finance Admin also hides them from every unauthorized
  viewer).
- New items ("Subscriptions", "Pending Cashout Requests", "Approved
  Cashout Requests") are each gated on their own `canAccess(...)` check —
  none of them piggyback on the "Finance" item's visibility.
- The Dart-side fallback permission matrix
  (`lib/features/admin/data/models/admin_role.dart`, used only if `/me/`
  is unreachable) was updated to match: `AdminRole.financeAdmin` no
  longer includes `AdminModule.approvals`, and now includes
  `cashoutsPending`/`cashoutsApproved`.

## 7. Session revalidation

No JWT claim or cached permission map encodes role permissions long-term
in this project — `AdminSession.refresh()` re-fetches
`GET /api/admin-panel/me/` (which recomputes `effective_permissions(user)`
live from the DB `roles.permissions` column) on every app boot and after
every mutating action's session refresh path already in place. An
existing Finance Admin session therefore picks up this permission change
on its very next `/me/` refresh — no forced logout, token invalidation, or
extra code was needed for "sessions refresh safely."

## 8. What was deliberately left unchanged

- `admin_hourly_rate` (Super-Admin-only rate changes) — untouched; a
  Finance Admin still cannot alter anyone's rate, including its own.
- `admin_roles_view`'s GET (returns every role's permission map, no
  permission check on read) — flagged as a **Medium** finding in the
  prior audit but out of scope for this task's explicit permission list;
  not changed here to avoid scope creep beyond what was asked.
- Operations Admin's and Super Admin's permission maps — completely
  unchanged; this task only touches `admin_finance`.
