# Finance Admin RBAC Audit

**Audit-only.** No code, migrations, configuration, seed data, database
records, permissions, routes, UI, or tests were changed. Nothing was
committed. All findings below are backed by direct code inspection and/or
real (read-only) API calls against the live dev database using the
seeded `finance.tanvir@example.com` account.

---

## 1. Executive summary

The codebase has a **real, partially-matching** Finance Admin
implementation — it is not a stub, and several core protections (module
RBAC, immutable audit log, self-approval block on the generic approval
queue, no raw payment-credential exposure) are genuinely enforced and
verified working. However, measured against this task's specification,
compliance is **Partial**, with several **Critical/High** gaps:

- The role identifier is `admin_finance`, not `finance_admin` (naming
  mismatch, not necessarily functional — see §2).
- Permissions are **module-level** (`finance`, `subscriptions`, `users`,
  `audit`, `approvals`), not the granular `finance.view` /
  `refunds.approve` / `cashouts.review` / `payouts.approve` strings the
  spec names. Several of the granular concepts (cashouts, doctor/pharmacy
  payouts) have **no corresponding module at all**.
- **Verified live**: Finance Admin cannot access delivery/rider payouts
  (`403`, and this is an *existing, intentional* test assertion — see
  §7). Doctor payouts (`doctor.PayoutRequest`/`DoctorEarning`) and
  pharmacy payouts/settlements have **no admin endpoint whatsoever**, for
  any role.
- **Verified live**: an unfiltered audit-log request returns entries from
  10 unrelated modules (shifts, auth, doctors, delivery-orders, users,
  consultation-disputes, team, cost_management, escalations) — cross-
  department data is not scoped out by default.
- The refund approval-threshold check trusts a **client-supplied
  `amount`** field before falling back to the server-computed one
  (`api/admin_views.py:171`) — a caller can under-report the amount to
  bypass the approval queue.
- "Approving" a cashout/payout is not a distinct action in the RBAC
  action vocabulary — it is a generic `edit`, so it **never** goes
  through the approval-threshold gate or the self-approval check, no
  matter the amount.
- No dedicated Cashout, Payout, Settlement, Commission, Tax/Accounting
  Report, or Finance Notes feature exists in the backend or the UI —
  these are **missing features**, not hidden-but-present ones.
- `request_id` is a real column on the audit log and request-id
  middleware already exists, but it is **never populated** on any
  `ActivityLog` row anywhere in the codebase.

Payment-credential security is a clean pass: no raw card data, secrets,
or gateway credentials are stored in any model reachable through the
admin panel, and every credential is environment-variable-only.

---

## 2. Finance Admin role/level interpretation

| Spec | Actual | Match |
|---|---|---|
| Role identifier `finance_admin` | `admin_finance` (`postgres_backend_extension.sql:144`, `users/management/commands/seed_platform_demo.py:263`, `api/admin_rbac.py:28`) | **Naming mismatch.** Every seed script, test, and RBAC constant in this codebase uses `admin_finance`. There is no `finance_admin` string anywhere. Functionally equivalent role, different identifier. |
| "Level 3 — Financial control" | `tier_level = 3` (`postgres_backend_extension.sql:144-149`), `TIER_MODULE = 3` (`api/admin_rbac.py:38`) | **Match.** Verified live: `GET /me/` for `finance.tanvir@example.com` returns `"tier": 3`. |
| "not a platform-wide administrator" | Confirmed: `admin_finance`'s permission map has no `*` wildcard, no `team`/`delivery`/`pharmacy`/`doctors`/`settings` write access. `is_super_admin` is `False`. | **Match**, verified live. |

---

## 3. Current implementation inventory

**Role/permission storage:** database-backed (Postgres `roles.permissions`
JSONB column, `managed=False` Django model `users.models.Role`, not
Django migrations — confirmed via `manage.py migrate --check`, 0
pending). Seeded/updated by `postgres_backend_extension.sql:144-149`.

**Enforcement style:** centralized, not scattered role-string checks.
Every generic collection/record endpoint funnels through
`api/admin_views.py:_gate()` (line 110) →
`api.admin_rbac.can_perform_action(user, module, action)`, which reads
the merged `effective_permissions(user)` map (`api/admin_rbac.py:97`).
A handful of *specific* endpoints (`admin_oversight`, `admin_audit_logs`,
payroll/`_require_super`, `admin_hourly_rate`) instead call a direct tier
predicate (`is_super_admin`, `is_operations_admin`) or a single
`can_perform_action('audit', 'view')` check rather than going through
`_gate()` — this is a second, smaller enforcement surface, not a
scattered one, but it does mean "centralized" is centralized-in-two-
places, not one.

**Actual `admin_finance` permission map** (`postgres_backend_extension.sql:144-149`):
```json
{
  "finance": ["view", "edit", "refund", "export", "approve"],
  "subscriptions": ["view", "edit", "approve", "refund", "export"],
  "users": ["view"],
  "audit": ["view"],
  "approvals": ["view"]
}
```
No `delivery`, `pharmacy`, `doctors`, `team`, `settings`, `content`,
`research`, `community`, `escalations`, or `oversight` keys.

**Endpoint module → permission-map key mapping** (`api/admin_rbac.py:48-64`,
`MODULE_ALIASES`): `payments → finance`, `subscription-plans →
subscriptions`, `subscriptions → subscriptions`, `riders → delivery`,
`payouts → delivery`. **There is no `cashouts` key or alias at all.**

**Screens/APIs Finance Admin can currently reach** (verified live, see
§7 endpoint matrix): `/me/`, `/dashboard/`, `/payments/` (+ record PATCH),
`/finance/summary/`, `/subscriptions/` (read; via generic dispatch, no
plan management), `/roles/` (read-only role catalogue, unauthenticated-
to-write), `/audit-logs/` (unscoped by default), `/my-shift/*` (own
shift/earnings — Finance Admin is tier 3, i.e. an hourly admin like any
other module admin), `/admin-panel/<module>/export/` for any module they
can view.

**Financial modules that exist vs. are missing:**

| Responsibility (spec) | Exists in backend? | Reachable by Finance Admin? |
|---|---|---|
| Revenue / MRR / lifetime revenue | Yes (`api/admin_finance.py:finance_summary`) | Yes |
| Subscriptions (view/refund) | Yes (`Subscription` model, `finance_action`'s `sub:` branch) | Yes |
| Subscription **plan management** (create/edit plans) | **No** — `SubscriptionPlan` is only ever `.filter(is_active=True)`-read (`api/admin_finance.py:119`); no admin create/edit endpoint anywhere | N/A — doesn't exist for anyone |
| Transactions / payment records | Yes (`payments.Payment`) | Yes |
| Failed/successful/pending/refunded/cancelled payments | Yes — the `status` field, filterable in the UI's tabs | Yes (view); refund only, no dedicated status-workflow validation |
| Refunds | Yes (`finance_action`'s refund branch, `payments/admin_finance.py:160-170`) | Yes, with a real (if imperfect — see §8) approval-threshold gate |
| **Cashouts** (as a distinct reviewable/approvable workflow) | **No** — cashouts are just `Payment` rows with `payment_type='cashout'` (`farmers/cost_views.py:569`), mixed into the same flat payments list, with no cashout-specific status machine, filter, or approval gate | Only as an undifferentiated payment row |
| Farmer payouts | Same as cashouts — farmer payout *is* the cashout flow above | Same partial visibility |
| Pharmacy payouts/settlements | **No model, no endpoint exists at all** | N/A |
| Doctor payouts/earnings | **Model exists** (`doctor.models.DoctorEarning`, `doctor.models.PayoutRequest`, lines 99-124) **but zero references anywhere in `api/`** — no admin endpoint | **No** — not reachable by any admin role |
| Delivery-worker payouts | Yes (`DeliveryEarning`, `/admin-panel/payouts/`) | **No — verified 403.** Gated under the `delivery` module, which Finance Admin's permission map does not grant. This is an *existing, intentional* project decision — see §6/§7. |
| Financial reports (general) | Only `finance_summary`'s fixed set of numbers + a raw payments CSV export | Yes, in that limited form |
| Settlement reports | **No** — term appears only in an unrelated farmer notification string (`farmers/cost_views.py:575`) and a banking-details field (`users/serializers.py:506`) | N/A |
| Commission reports | **No** — no model, view, or serializer anywhere | N/A |
| Tax/accounting reports | **No** | N/A |
| Financial disputes | **No dedicated model.** `ConsultationDispute` exists but is a doctor/patient dispute, module `doctors`, not reachable by Finance Admin and not financial in nature. | N/A for finance-specific disputes |
| Finance notes on transactions | **No dedicated model or endpoint.** The only "note" mechanism is `Payment.notes`, overwritten as a side effect of processing a refund (`api/admin_finance.py:164`) — not a general append-anytime, audit-tracked note feature | Partial/incidental only |

**Related role sharing excessive Finance Admin access:** none found.
`admin_operations` (tier 2) has its own, separate, slightly *narrower*
finance grant (`["view","export"]` only, `postgres_backend_extension.sql:135`)
— Operations Admin cannot refund/approve finance actions directly, which
is correct (Operations sits *above* Finance in tier but the permission
map itself doesn't grant finance write actions — Operations' power over
finance comes from being the required-tier approver in the approval
queue, not from the finance permission map). No other role's permission
map includes a `finance`/`subscriptions` key with write actions.

---

## 4. Permission matrix

| Required permission | Existing implementation | Backend enforcement | Frontend visibility | Status |
|---|---|---|---|---|
| `finance.view` | `"finance": [...,"view",...]` module permission | `can_perform_action(user,'finance'/'payments','view')` via `_gate()` | `AdminFinanceScreen` shown when `session.can(financeSubscriptions, view)` | **Pass** (as a module permission, not the literal string) |
| `finance.export` | `"finance": [...,"export",...]` | `admin_module_export` checks `can_perform_action(module,'export')` | CSV export button/route exists | **Pass** |
| `subscriptions.manage` | `"subscriptions": ["view","edit","approve","refund","export"]` — covers per-subscription actions | Enforced via `_gate()` for the `subscriptions` module | No plan-management UI exists | **Partial** — per-user subscription actions yes; subscription **plan** management (the more natural reading of "manage") does not exist for anyone |
| `payments.view` | No separate `payments` permission key — `payments` is aliased to `finance` (`api/admin_rbac.py:MODULE_ALIASES`) | Same as `finance.view` | Same screen | **Pass** (folded into `finance`, functionally equivalent) |
| `refunds.create` | No `refunds` key — refund is an *action* (`'refund'`) inside the `finance`/`subscriptions` permission list, not its own permission namespace | `_resolve_action()` classifies `status=Refunded` as `'refund'`; `admin_finance:['refund']` grants it | "Refunds" tab, refund button | **Pass** functionally, **Fail** as a literal separate permission (it's bundled) |
| `refunds.approve` | Same bundling — `'refund'` is a single action, there is no separate create-vs-approve split. A refund a Finance Admin can perform directly *is* both create and approve in one step, when under threshold. | `requires_approval()` escalates only when amount `>` `REFUND_APPROVAL_THRESHOLD` (`api/admin_rbac.py:178`) | No distinct "approve" UI step — it's the same refund button | **Partial** — the *concept* of a separate approval gate exists (see §6, §8) but is not a distinct permission the role is granted/denied; it's a threshold, not a permission |
| `cashouts.review` | **Does not exist.** No `cashouts` module, alias, or permission key anywhere. | N/A | No cashout-specific screen | **Missing** |
| `payouts.approve` | Exists only for **delivery** payouts, under the `delivery` permission key — which `admin_finance` does **not** hold | `can_perform_action(user,'payouts'→'delivery','approve')` → `False` for Finance Admin (verified live, 403) | No payout UI reachable by Finance Admin | **Fail** against the spec (works for Delivery Admin, not Finance Admin) |

---

## 5. Allowed-action audit

| # | Action | Backend result | Evidence |
|---|---|---|---|
| 1 | View financial dashboard data | Pass — `GET /admin-panel/dashboard/` → 200 | Live call, finance.tanvir |
| 2 | View revenue/expenses/commissions/settlement/financial summaries | Partial — revenue (`finance_summary`) yes; **expenses, commissions, settlement have no backend representation at all** | `api/admin_finance.py:finance_summary` (only `mrr`, `lifetime_revenue`, `active_subscriptions`, `pending_payout_liability`, `payouts_paid_this_month`, `total_refunds`, `plans`) |
| 3 | Export finance reports | Pass (as a raw CSV of the payments list) | Existing test: `scripts/test_admin_panel.py:218` "finance exports payments CSV" |
| 4 | Manage subscription plans | **Missing feature — not implemented** for any role | See §3 |
| 5 | Review subscription renewals/expirations | Partial — `Subscription.expires_at`/`auto_renew` are visible fields in the collection row (`api/admin_views.py` subscriptions branch), but there is no renewal/expiry-specific report or filter | `api/admin_views.py` subscriptions branch (`~1119-1130` per `_collection_rows`) |
| 6 | View successful/failed/pending/refunded/cancelled payments | Pass — `status` field is present and the UI has "All Payments"/"Failed"/"Refunds" tabs | `lib/features/admin/presentation/screens/admin_finance_screen.dart:148-150` |
| 7 | Review payment disputes | **Missing feature** — no finance-specific dispute model | See §3 |
| 8 | Create refunds when permitted | Pass | `api/admin_finance.py:160-170`, verified by existing tests |
| 9 | Approve refunds only within configured limit | Partial-pass — the gate exists but the amount can be spoofed by the caller (see §8, Critical) | `api/admin_views.py:171` |
| 10 | Review cashout requests | **Fail/Missing** — no dedicated cashout review capability; only visible as an undifferentiated payment row | See §3 |
| 11 | Approve payouts where allowed | Fail for delivery (403, verified live); Missing entirely for doctor/pharmacy | See §3, §7 |
| 12 | Review farmer/pharmacy/doctor/delivery payout data | Fail/Missing across the board except farmer-cashout-as-a-payment-row | See §3 |
| 13 | View accounting/tax-related reports | **Missing feature** | See §3 |
| 14 | Add internal finance notes | **Missing feature** (only an incidental overwrite of `Payment.notes` during refund) | `api/admin_finance.py:164` |
| 15 | View proper audit history for financial actions | Partial-pass — `audit` view permission is granted and works, **but is not scoped to finance by default** (Critical, see §10) | `api/admin_extra.py:372-400` |

---

## 6. Restricted-action audit

| # | Restriction | Verified backend result | Evidence |
|---|---|---|---|
| 1 | Cannot manage user roles | Pass — `admin_roles_view` POST (permission edit) requires `is_super_admin` | `api/admin_extra.py:330-331` |
| 2 | Cannot create/edit/assign/suspend/restore/delete admin accounts | Pass, verified live and by existing test | `scripts/test_admin_panel.py:199` "finance cannot create admin (403)"; live check `GET /admin-panel/admins/` → 403 |
| 3 | Cannot change platform-wide settings | Pass, verified live | `GET /admin-panel/settings/` → 403 |
| 4 | Cannot change payment gateway credentials | Pass (no such endpoint exists for anyone) | See §9 |
| 5 | Cannot read gateway secrets/API keys/webhook secrets/raw card data | Pass | See §9 |
| 6 | Cannot access unrelated private identity documents | Pass, verified live | `GET /admin-panel/users/` (identity-doc-bearing detail) not tested directly, but the `users` permission is `view`-only and the generic user list (`_user_json`) does not include private document URLs; doctor license documents are under the `doctors` module → 403 verified live |
| 7 | Cannot access unrelated private medical/consultation records | Pass, verified live | `GET /admin-panel/consultations/` → 403; `GET /admin-panel/doctors/` → 403 |
| 8 | Cannot edit prescriptions/clinical notes/treatment content | Pass (no path reaches it — `doctors` module fully blocked) | Same as above |
| 9 | Cannot edit research papers/researcher content/credentials | Pass, verified live | `GET /admin-panel/researchers/` → 403, `GET /admin-panel/articles/` → 403 |
| 10 | Cannot edit community posts/moderation | Pass, verified live | `GET /admin-panel/community-users/` → 403 |
| 11 | Cannot edit pharmacy inventory/prices/stock/suppliers | Pass, verified live | `GET /admin-panel/pharmacies/` → 403, `GET /admin-panel/medicines/` → 403 |
| 12 | Cannot assign delivery riders or mark deliveries complete | Pass, verified live | `GET /admin-panel/riders/` → 403 (assign/complete actions are deeper in the same blocked `delivery` module) |
| 13 | Cannot permanently delete financial records | Pass for the `payments` module specifically | `api/admin_views.py:1298-1299` — `DELETE` on `payments` returns `405 "Financial records cannot be deleted."` explicitly, regardless of role |
| 14 | Cannot delete audit records | Pass, enforced at the DB level | `audit/models.py:88-90` — `ActivityLog.delete()` raises `ValueError`; a DB trigger additionally rejects UPDATE/DELETE per the model's own docstring (`audit/models.py:33-35`) |
| 15 | Cannot approve own refund/payout/settlement/cashout | **Partial.** Enforced for anything that reaches the generic approval queue (`entry.requested_by_id == request.user.id` check, `api/admin_extra.py:506`) — but a refund only reaches that queue when it exceeds the threshold; a cashout/payout "approval" (a generic `edit`) never reaches the queue at all, so this check **never applies** to it. No `payment.user_id == request.user.id` check exists anywhere in `finance_action`. | `api/admin_extra.py:506`; absence confirmed by targeted search of `api/admin_finance.py` and `api/admin_views.py` |
| 16 | Cannot approve above-threshold refunds without **Super Admin** approval | **Partial/Fail as literally specified.** The threshold escalates to `TIER_OPERATIONS` (tier 2), not specifically Super Admin (tier 1) — an Operations Admin, not only a Super Admin, can approve a large refund. | `api/admin_rbac.py:197-198`, `needed = TIER_OPERATIONS` |
| 17 | Cannot bypass approval workflows through direct API calls | **Fail (Critical).** The approval-threshold check reads `request.data.get('amount')` **before** the server-computed lookup — a caller can pass a low `amount` in the PATCH body to make a large refund appear small enough to skip the queue. The actual refund itself still reflects the true payment amount (no partial-amount field is applied), but the **gate that decides whether approval was required can be lied to**. | `api/admin_views.py:171`: `context['amount'] = request.data.get('amount') or _lookup_amount(module, record_id)` |
| 18 | Cannot access another department's data outside the financial context | **Fail (Critical) for the audit log** — see §10. Otherwise pass (every non-finance module tested returns 403). | See row 15/§10 |

---

## 7. Endpoint authorization matrix

All rows verified live against the dev DB using `finance.tanvir@example.com`
(Finance Admin) unless noted "inspected" (code-read only, not called).

| Endpoint | Method | Purpose | Auth required | Required permission | Finance Admin result | Unauthorized-role result | Evidence |
|---|---|---|---|---|---|---|---|
| `/api/admin-panel/dashboard/` | GET | Dashboard stats | Yes | any admin | **200** | 403 (non-admin) | Live call |
| `/api/admin-panel/me/` | GET | Own role/tier/permissions | Yes | any admin | **200**, `tier:3`, `permissions` includes `finance` not `delivery` | N/A | Live call |
| `/api/admin-panel/payments/` | GET/PATCH | Payment list/refund | Yes | `finance:view`/`edit`/`refund` | **200** (GET); refund allowed (existing test) | 403 for `delivery` role (existing test `scripts/test_admin_panel.py:113`) | Live call + test |
| `/api/admin-panel/payments/` | DELETE | Delete a payment | Yes | n/a — blocked for everyone | **405**, "Financial records cannot be deleted." | Same for every role | `api/admin_views.py:1298-1299`, inspected |
| `/api/admin-panel/finance/summary/` | GET | Revenue/MRR/refunds summary | Yes | `finance:view` (implicitly, via `admin_finance_summary`) | **200** | Not tested for other roles | Live call |
| `/api/admin-panel/subscriptions/` | GET | Subscription list | Yes | `subscriptions:view` | **200**, empty result set in this dev DB | Not tested | Live call |
| `/api/admin-panel/payouts/` | GET | Delivery-rider payouts | Yes | `payouts`→`delivery:view` | **403** "cannot view in the delivery module" | 200 for `admin_delivery` (existing test) | Live call + `scripts/test_admin_panel.py:109,112` |
| `/api/admin-panel/riders/` | GET | Delivery riders | Yes | `delivery:view` | **403** | 200 for `admin_delivery` | Live call + existing test |
| `/api/admin-panel/roles/` | GET | Role catalogue + **full permission maps** of every admin role | Yes | **none checked on GET** | **200** — includes every role's complete permission JSON | Same for every authenticated admin role (no gate at all) | `api/admin_extra.py:320-328`, live call |
| `/api/admin-panel/roles/` | PATCH | Edit a role's permissions | Yes | Super Admin only | Not called (would be 403 per code) | — | `api/admin_extra.py:330-331`, inspected |
| `/api/admin-panel/audit-logs/` | GET | Audit trail | Yes | `audit:view` | **200**, returns entries from **10 unrelated modules** with no default finance filter | — | Live call, §10 |
| `/api/admin-panel/admins/` | GET | Admin account list | Yes | `team:view` (Finance Admin has none) | **403** | — | Live call |
| `/api/admin-panel/all-admins/` | GET | Team-wide shift/payroll view | Yes | `is_super_admin` only | **403** | — | Live call |
| `/api/admin-panel/shifts/` | GET | All admins' shift records | Yes | `is_super_admin` only | **403** | — | Live call |
| `/api/admin-panel/my-shift/status/` | GET | Own shift status | Yes | any hourly admin (tier > 1) | **200** — Finance Admin, like every non-Super admin, tracks its own shift/pay | — | Live call |
| `/api/admin-panel/doctors/`, `/consultations/`, `/pharmacies/`, `/medicines/`, `/researchers/`, `/articles/`, `/community-users/`, `/settings/`, `/diseases/` | GET | Respective modules | Yes | respective module `view` | **403 for all** | — | Live call, batch above |
| `doctor.PayoutRequest` / `DoctorEarning` | — | Doctor payouts/earnings | — | — | **No endpoint exists** — not reachable by any role, admin or otherwise, through the admin panel | `doctor/models.py:99-124`, confirmed zero references in `api/` |
| Pharmacy payouts/settlements | — | — | — | — | **No model or endpoint exists at all** | Confirmed by search |
| Payment gateway configuration | — | — | — | — | **No admin-facing config endpoint exists for any role.** Credentials are environment-variables only (`featherflow_backend/settings.py:215-226`). | Inspected |

---

## 8. Financial-data integrity findings

- **Soft deletion / no permanent delete:** `payments` module DELETE is
  hard-blocked (405) for every role (`api/admin_views.py:1298-1299`).
  Not verified for `subscriptions`/`payouts` DELETE specifically — those
  modules aren't special-cased in `admin_record`, so a DELETE would fall
  through to the generic `_records(module)`/seed-store path, which is
  unlikely to apply to real `Subscription`/`DeliveryEarning` rows at all
  (those aren't `AdminPanelRecord` seed rows) — practically inert rather
  than a deletion, but not an explicit, intentional 405 either. **Not a
  live financial-record-deletion risk, but not a clean, explicit
  guarantee either.**
- **Valid status/state transitions:** the refund branch has real
  validation (`if payment.status == 'refunded': return 409`,
  `api/admin_finance.py:161-162` — idempotent, cannot double-refund).
  The **generic non-refund status-edit branch has none** — any string
  can be written to `payment.status` (`api/admin_finance.py:171-175`),
  including for a `payment_type='cashout'` row. This is the same code
  path a Finance Admin would use to "approve" a cashout (e.g.
  `{"status": "completed"}`).
- **Duplicate-action idempotency:** refunds — yes (409 on re-refund).
  Cashout/payout "approval" via the generic branch — **no idempotency
  check at all**; the same PATCH can be replayed with no guard.
- **Approval is transactional:** the approval-queue `decide()` uses
  `transaction.atomic()` + `select_for_update()` (`api/admin_approvals.py:72-73`)
  — real, verified. The refund/cashout action itself
  (`finance_action`) is **not** wrapped in its own `transaction.atomic()`
  block, though it's a single-model `.save()` in the refund case so the
  practical risk is low.
- **Amounts calculated server-side:** the *actual* refunded amount is
  always the payment's own stored `amount` (never taken from the
  request body) — correct. But the **approval-threshold gate's
  amount** is `request.data.get('amount') or _lookup_amount(...)`
  (`api/admin_views.py:171`) — client-suppliable, and used first. This
  is a real integrity gap in the *gate*, not in the money movement
  itself.
- **Currency/amount validation:** no explicit currency-mismatch or
  negative-amount validation was found in the refund path (the amount is
  never taken from the client for the refund itself, so this is lower
  risk than it would otherwise be).
- **Finance notes auditable:** N/A — no dedicated note feature exists
  (see §3/§5).
- **Refund approval limits configuration-driven:** **Partially.**
  `REFUND_APPROVAL_THRESHOLD = 5000` is a single, centrally-defined
  Python module constant (`api/admin_rbac.py:178`) — easy to locate and
  change, but not a DB-backed, admin-editable, or per-role setting.
- **Refunds above threshold require Super Admin approval:** **Partial**
  — escalates to `TIER_OPERATIONS` (tier 2: Operations Admin **or**
  Super Admin), not exclusively Super Admin (§6, row 16).
- **Finance Admin cannot self-approve:** true for the queued-refund path
  (`api/admin_extra.py:506`); **false/not-applicable for cashout/payout
  "approval"**, which never enters the queue (§6, row 15).
- **Every finance action creates an audit record:** refund and generic
  edit both call `_audit()`/`_log()` — true. Payout/cashout-as-generic-
  edit is audited as `'Edit payment'` / `action_type='edit'`, not
  distinguishably as a payout or cashout approval — a reviewer reading
  the audit trail cannot tell a routine payment status correction apart
  from a cashout being approved.
- **Audit entries contain actor/permission/action/target/time/request
  ID/before-after:** actor/action/target/time — yes. **Permission** (which
  permission string authorized this) — not recorded, only the module/
  action strings. **Request ID** — the column exists
  (`audit/models.py:76`) and request-id middleware/contextvar
  infrastructure already exists (`api/request_id.py`), but it is **never
  passed when creating an `ActivityLog` row** anywhere in the codebase
  (confirmed by search) — every audit row has `request_id = NULL`.
  **Before/after** — `api/admin_views.py:_log()` supports `old`/`new`
  and several call sites use it (e.g. pharmacy, users); **`api/admin_finance.py:_audit()`
  (used for every refund) never passes `old`/`new` at all**
  (`api/admin_finance.py:210-216`) — a refund's audit row has no
  before/after snapshot of the payment.
- **Sensitive data never logged:** no evidence of API keys, secrets,
  JWTs, OTPs, or full private documents appearing in `old_values`/
  `new_values` for finance actions — the finance audit payloads are
  narrow (amount, reason) by construction.

---

## 9. Payment-credential security findings — clean pass

- Every gateway credential (`STRIPE_SECRET_KEY`, `STRIPE_PUBLISHABLE_KEY`,
  `STRIPE_WEBHOOK_SECRET`, `BKASH_APP_KEY/SECRET/USERNAME/PASSWORD`,
  `NAGAD_MERCHANT_ID/PRIVATE_KEY/PUBLIC_KEY`) is sourced only from
  environment variables (`featherflow_backend/settings.py:215-226`) —
  never stored in a DB table, never returned by any admin endpoint.
- `SECRET_KEY` (Django) is environment-sourced with a DEBUG-only
  insecure fallback (`featherflow_backend/settings.py:22-28`) — not
  exposed via any API.
- `payments.Payment` model fields (`payments/models.py:5-25`): amount,
  currency, method, type, reference_id/type, status, transaction_id,
  receipt_url, notes — **no card number, expiry, CVC, or raw token**.
- `billing.WebhookEvent` stores only `provider` + `event_id` (an
  idempotency key), never the raw webhook payload
  (`billing/models.py:118-139`).
- No admin-facing "payment gateway configuration" endpoint exists in
  `api/urls.py` for **any** role, so there is nothing to accidentally
  expose to Finance Admin or anyone else.
- **Expected result met:** Finance Admin sees operational status +
  provider reference IDs (`transaction_id`, `receipt_url`) only; no
  secrets, no raw card data, gateway config is (trivially) Super-Admin-
  only because it doesn't exist for anyone.

---

## 10. Audit-log coverage findings

- **Immutability — strong pass.** `ActivityLog.save()` raises on any
  update; `.delete()` raises unconditionally; the docstring states a DB
  trigger backs this too (`audit/models.py:82-90`). Verified by the
  existing test `scripts/test_admin_panel.py` → "audit UPDATE blocked".
- **Scope — Critical fail against the spec's restriction #18.**
  `admin_audit_logs` (`api/admin_extra.py:372-400`) checks only
  `can_perform_action(user, 'audit', 'view')` and otherwise returns
  `ActivityLog.objects.all()` unless the *caller* supplies `?module=`.
  There is no server-side default restricting a Finance Admin's view to
  `module='payments'`/finance-relevant entries. **Verified live**: an
  unfiltered call returned entries tagged `shifts` (44), `auth` (101),
  `payments` (49), `escalations` (14), `delivery-orders` (9), `doctors`
  (24), `users` (10), `cost_management` (10), `team` (1),
  `consultation-disputes` (4) — i.e. other admins' shift clock-ins,
  platform-wide login events, doctor-module edits, delivery assignment
  history, and more, none of which are financial.
- **`request_id` — never populated,** despite the column and the
  request-id contextvar/middleware both existing (see §8). This means
  "which single HTTP request produced this audit row" cannot currently
  be answered from the audit table alone.
- **Permission-string not recorded** — only module + action strings are
  stored, not the exact permission entry that authorized the action.
- **Finance-specific action typing is coarse** — a cashout/payout
  status edit and an ordinary payment status correction are both logged
  identically as `action_type='edit'`, `action='Edit payment'`
  (`api/admin_finance.py:171-176`), making finance-specific audit
  review harder than it needs to be.

---

## 11. UI/navigation findings

- **Module scoping:** the sidebar shows exactly one finance-relevant
  item, "Finance" (→ `AdminModule.financeSubscriptions`,
  `lib/features/admin/presentation/widgets/admin_sidebar.dart:132-139`),
  gated on `session.canAccess(...)`. No separate Subscriptions/Refunds/
  Cashouts/Payouts/Reports/Finance-Audit sidebar entries exist — because
  those features don't exist as separate screens (§3).
- **Direct-route safety:** `AdminFinanceScreen` checks
  `session.can(financeSubscriptions, view)` in `build()` and renders a
  clean "Access Restricted" panel if not
  (`lib/features/admin/presentation/screens/admin_finance_screen.dart:102-126`)
  rather than crashing or silently showing empty data — **pass**.
- **Hides user-role management / platform settings / content / research
  / pharmacy inventory / delivery assignment:** pass by omission — none
  of those items appear anywhere in Finance Admin's sidebar tree (the
  sidebar itself gates every other item on its own module permission,
  which Finance Admin's map doesn't grant).
- **Does not expose payment gateway credentials:** pass — the finance
  screen only ever renders fields from `finance_summary`/`list('payments')`,
  neither of which can contain a secret (§9).
- **Data source:** `AdminFinanceScreen`/`_SummaryBar` fetch real API
  data (`AdminApiService.instance.list('payments')`,
  `.financeSummary()`) — no hardcoded/fake numeric placeholders found.
  One minor gap: `_SummaryBar`'s fetch has `.catchError((_) {})`
  (`lib/features/admin/presentation/screens/admin_finance_screen.dart:203`)
  — a failed summary fetch fails **silently**, showing ৳0.00 tiles with
  no error/retry affordance, which could look like real zero data rather
  than "couldn't load."
- **Missing UI entirely** for: cashout review, doctor/pharmacy payout
  review, settlement/commission/tax reports, and finance notes — because
  the backend has nothing to show.
- **Colors/responsiveness:** not specifically audited in this pass
  (task scope is RBAC/data-access, not visual QA); no obvious
  green-on-green or fixed-width issue spotted in a code read of
  `admin_finance_screen.dart`.

---

## 12. High-risk findings

1. **(Critical)** Refund approval-threshold check trusts a client-
   supplied `amount` before the server-computed one
   (`api/admin_views.py:171`) — the approval gate itself can be
   bypassed by under-reporting the amount in the request body.
2. **(Critical)** Cashout/payout "approval" is not a recognized action
   type in the RBAC action vocabulary — it is generic `edit`, so it
   **never** reaches the approval-threshold gate or the self-approval
   check, regardless of amount.
3. **(Critical)** Audit-log access is not scoped to finance by default —
   a Finance Admin's unfiltered request surfaces cross-department
   activity (verified: 10 unrelated modules, 266 rows).
4. **(High)** Doctor and pharmacy payouts/settlements have no admin
   endpoint at all — not a Finance Admin restriction, a total feature
   gap.
5. **(High)** Delivery-worker payouts are fully blocked to Finance Admin
   (403, by design per an existing test) — directly contradicts the
   spec's required responsibility #10/#11/#12.
6. **(High)** No dedicated Cashout / Settlement / Commission / Tax
   report / Finance Notes feature exists anywhere.
7. **(Medium)** `GET /api/admin-panel/roles/` has no permission check at
   all — any authenticated admin (including Finance Admin) can read
   every role's full permission map.
8. **(Medium)** `_audit()` in `api/admin_finance.py` never records
   `old_values`/`new_values`/`request_id` for refunds — weaker forensic
   trail than the generic `_log()` helper provides elsewhere.
9. **(Medium)** Above-threshold refunds escalate to Operations Admin
   tier, not specifically Super Admin, as the spec requires.
10. **(Low)** `REFUND_APPROVAL_THRESHOLD` is a hardcoded Python constant,
    not a DB-configurable setting.
11. **(Low)** `_SummaryBar`'s failed fetch is silent (no error/retry UI).

---

## 13. Missing features

Confirmed absent for **every** role, not just Finance Admin:

- Subscription **plan** management (create/edit/deactivate a
  `SubscriptionPlan`).
- A distinct Cashout review/approve workflow (cashouts exist only as
  undifferentiated `Payment` rows).
- Doctor payout/earnings admin review (model exists, zero admin wiring).
- Pharmacy payout/settlement (no model, no endpoint).
- Settlement reports.
- Commission reports.
- Tax/accounting reports.
- A financial-disputes model/workflow.
- Finance notes (a standalone, auditable note attached to a
  transaction, independent of a status change).
- Any payment-gateway-configuration admin screen (arguably not a gap
  given credentials are environment-only, but "gateway configuration is
  Super-Admin-only and separately protected" implies the spec expected
  such a screen to exist).

---

## 14. Recommended remediation plan

**Critical**
1. Stop trusting `request.data.get('amount')` in
   `_maybe_enqueue`/`_lookup_amount` for the approval-threshold check —
   always use the server-computed amount for that decision.
2. Introduce a distinct `'approve'` (or `'payout_approve'`) action
   classification for cashout/payout status transitions so they flow
   through `requires_approval()`/the approval queue like refunds do,
   including the existing self-approval block.
3. Default `admin_audit_logs` to the caller's own permitted module(s)
   (e.g. `module__in=['finance','subscriptions']` for Finance Admin)
   unless a Super Admin/explicitly-permitted role requests otherwise.

**High**
4. Decide whether Finance Admin should see delivery/doctor/pharmacy
   payout data (per this task's spec, yes) and, if so, add a `payouts`
   permission key independent of `delivery`, or grant `admin_finance` a
   scoped, read-plus-approve view over `DeliveryEarning`/
   `DoctorEarning`/`PayoutRequest` without granting the rest of the
   `delivery`/`doctors` modules.
5. Build the missing doctor-payout and pharmacy-payout/settlement admin
   endpoints (currently reachable by no one).
6. Build a real Cashout review workflow (status machine + idempotent
   approve/reject + audit) instead of the generic payment-status edit.
7. Add Settlement/Commission/Tax report data and endpoints if these are
   genuinely required deliverables (currently entirely absent).
8. Add a Finance Notes model (append-only, actor + timestamp, linked to
   a transaction) instead of overloading `Payment.notes`.

**Medium**
9. Gate `GET /api/admin-panel/roles/` behind at least `IsAdminUser` +
   a minimal permission check (or explicitly document it as
   intentionally open metadata).
10. Wire `request_id` (already available via `api.request_id.get_request_id()`)
    into every `ActivityLog.objects.create(...)` call site, starting
    with `api/admin_finance.py:_audit()` and `api/admin_views.py:_log()`.
11. Pass `old`/`new` snapshots into `api/admin_finance.py:_audit()` for
    refunds, matching the generic `_log()` helper's capability.
12. Change the refund-threshold escalation target from
    `TIER_OPERATIONS` to `TIER_SUPER` if "Super Admin approval"
    specifically (not "Operations or above") is the intended policy.

**Low**
13. Move `REFUND_APPROVAL_THRESHOLD` into a DB-backed or `.env`-driven
    setting if per-environment tuning without a code change is desired.
14. Show an explicit error/retry state in `_SummaryBar` instead of
    silently swallowing a failed fetch.
15. Rename/alias the role identifier if `finance_admin` (vs.
    `admin_finance`) is required by an external contract; otherwise
    document the existing naming as intentional.

---

## 15. Exact files and line references

- `postgres_backend_extension.sql:144-149` — `admin_finance` permission
  seed.
- `postgres_backend_extension.sql:388` — tier_level=3 role list.
- `api/admin_rbac.py:21-44` — role constants, `MODULE_ROLE`, `ACTIONS`.
- `api/admin_rbac.py:48-64` — `MODULE_ALIASES` (payments→finance,
  payouts/riders→delivery).
- `api/admin_rbac.py:97` — `effective_permissions`.
- `api/admin_rbac.py:178` — `REFUND_APPROVAL_THRESHOLD = 5000`.
- `api/admin_rbac.py:181-202` — `requires_approval`.
- `api/admin_rbac.py:207-226` — `IsAdminUser`.
- `api/admin_views.py:83-107` — `_REQUEST_ACTION`/`_BODY_ACTION_TO_PERMISSION`/`_resolve_action`.
- `api/admin_views.py:110-121` — `_gate`.
- `api/admin_views.py:140-157` — `_lookup_amount`.
- `api/admin_views.py:160-188` — `_maybe_enqueue` (client-suppliable
  amount at line 171).
- `api/admin_views.py:203-222` — `_log` (supports old/new, no
  request_id).
- `api/admin_views.py:1072-1076` — `payouts` module → `DeliveryEarning`.
- `api/admin_views.py:1281-1301` — `admin_record` dispatch, `payments`
  DELETE→405 at 1298-1299.
- `api/admin_finance.py` (whole file) — `finance_rows`, `finance_summary`,
  `finance_action` (124-177), `_audit` (210-216, no old/new/request_id).
- `api/admin_extra.py:320-328` — `admin_roles_view` GET, no permission
  check.
- `api/admin_extra.py:372-400` — `admin_audit_logs`, no default module
  scoping.
- `api/admin_extra.py:494-519` — `admin_approval_decide`, self-approval
  block at line 506.
- `api/admin_extra.py:648-673` — `admin_module_export`.
- `api/admin_approvals.py:69-104` — `decide`, transactional
  (`select_for_update`, line 73).
- `audit/models.py:30-90` — `ActivityLog` (request_id field at line 76,
  immutability at 82-90).
- `payments/models.py:5-25` — `Payment` model (no sensitive fields).
- `billing/models.py:43-116, 118-139` — `PaymentIntent`, `WebhookEvent`.
- `doctor/models.py:99-124` — `DoctorEarning`, `PayoutRequest` (unused
  by any admin endpoint).
- `farmers/cost_views.py:550-576` — farmer `cashout` action, creates a
  `Payment(payment_type='cashout')`.
- `featherflow_backend/settings.py:22-28, 208-226` — secret key +
  gateway credentials (env-only).
- `users/management/commands/seed_platform_demo.py:263` — seeded
  `finance.tanvir@example.com` / `admin_finance`.
- `lib/features/admin/presentation/widgets/admin_sidebar.dart:132-139` —
  Finance sidebar item.
- `lib/features/admin/presentation/screens/admin_finance_screen.dart:99-126`
  — access-restricted guard; `140-152` — 3-tab layout; `195-204` —
  `_SummaryBar` silent-catch.

---

## 16. Tests inspected/run

- `python manage.py check` — **0 issues.**
- `python manage.py migrate --check` — **0 pending** (confirms the
  `managed=False`/hand-written-SQL convention, no Django migration
  drift).
- `backend/scripts/test_admin_panel.py` (existing suite, run as-is, not
  modified) — **62 passed, 1 failed.** The 1 failure
  (`admin login 200`) is a pre-existing, unrelated email-verification
  issue (confirmed in an earlier session via `git stash` — same result
  with/without unrelated in-flight changes). Finance-relevant
  assertions in this run, all **passed**: `finance me 200`, `finance
  tier == 3`, `finance has finance perms`, `finance lacks delivery
  perms`, `finance can read payments`, `finance BLOCKED from riders
  (403)`, `finance cannot create admin (403)`, `finance admin BLOCKED
  from assigning (403)`, `finance exports payments CSV`, `requester
  cannot self-approve (400/403)`, `audit UPDATE blocked`.
- `flutter analyze lib/features/admin` — **No issues found.**
- Additional **read-only** live verification performed for this audit
  (Django test `Client`, JWT auth as `finance.tanvir@example.com`,
  no writes): `GET /me/`, `/dashboard/`, `/payments/`,
  `/subscriptions/`, `/finance/summary/`, `/payouts/`, `/riders/`,
  `/admins/`, `/roles/`, `/audit-logs/?limit=500`, `/doctors/`,
  `/consultations/`, `/pharmacies/`, `/medicines/`, `/researchers/`,
  `/articles/`, `/community-users/`, `/all-admins/`, `/shifts/`,
  `/my-shift/status/`, `/settings/`, `/diseases/`. No PATCH/POST/DELETE
  request was made against any endpoint during this audit.

---

## 17. Confirmation — no implementation changes

No source file, migration, seed script, configuration file, database
row, permission, route, UI component, or test was created, edited, or
deleted as part of this audit. `FINANCE_ADMIN_RBAC_AUDIT.md` is the only
new file. All verification was performed via `manage.py check`,
`manage.py migrate --check`, running the pre-existing
`scripts/test_admin_panel.py` unmodified, `flutter analyze`, and
read-only (`GET`) API calls made through Django's test `Client`.

## 18. Confirmation — nothing committed

No `git add`/`git commit` was run. The working tree's only change from
this task is the addition of `FINANCE_ADMIN_RBAC_AUDIT.md` itself.
