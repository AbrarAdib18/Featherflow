# Pharmacy Admin Portal — Audit Report

Date: 2026-09-25
Scope: audit only (per build instructions, step 1). No code changed in this pass.

This document traces the pharmacy-admin surface **as it exists today**, end to end
(UI → API → DB), before any new code is written for the full Pharmacy Admin
control/approval layer. All file:line references were verified by direct code
reads during this audit.

---

## 1. What already exists (reusable as-is)

### 1.1 Admin role/permission system — reuse, do not reinvent

FeatherFlow already has a mature tiered RBAC system. There is no separate "admin
user" model — admins are `users.User` rows holding a `Role` (table `roles`) via
`UserRole`, with `panel_type='admin'`.

- `backend/api/admin_rbac.py` (243 lines) is the single source of truth:
  - Tiers: `admin_super` (1, wildcard `{"*":["*"]}`) → `admin_operations` (2) →
    per-module admins (3): `admin_finance`, `admin_content`, `admin_research`,
    `admin_delivery`, **`admin_pharmacy`**, `admin_doctor`, `admin_support`,
    `admin_team` → `admin_support` (4, lowest tier, "Support Agent").
  - `MODULE_ROLE['pharmacy'] = 'admin_pharmacy'` already exists.
  - `ACTIONS = {view, create, edit, approve, reject, delete, suspend, assign,
    export, refund, override}`.
  - Current RBAC matrix for module `pharmacy`: `['view','edit','approve',
    'reject','suspend','export']` (`admin_rbac.py:119`) — **missing `create`,
    `delete`, `assign`** (needed for admin medicine add + delivery assignment).
  - `can_perform_action(user, module, action)` — the gate to call in every new
    view. `requires_approval(...)` escalates sensitive actions to
    `AdminApprovalQueue` if the acting admin's tier is too low.
  - DRF permission classes `IsAdminUser` / `ModulePermission` already enforce
    suspended-admin lockout and pending-admin-approval lockout.

**Decision for this build:** every new Pharmacy Admin endpoint uses
`can_perform_action(user, 'pharmacy', <action>)`, after extending the matrix
with `create`/`delete`/`assign`. No new role scheme needed.

### 1.2 Existing pharmacy-admin endpoints (already working)

Mounted under `/api/admin-panel/...` (not `/api/admin_pharmacy` — that's just
the module filename), all gated by `IsAdminUser` + `_deny()` → `can_perform_action`.

`backend/api/admin_pharmacy.py` (234 lines):

| Endpoint | Method | What it does |
|---|---|---|
| `/admin-panel/pharmacy/medicines/` | GET | Cross-pharmacy medicine list, filters incl. `pending=true` |
| `/admin-panel/pharmacy/medicines/<id>/approve/` | PATCH | Approve a prescription medicine |
| `/admin-panel/pharmacy/medicines/<id>/reject/` | PATCH | Reject with required reason |
| `/admin-panel/pharmacy/expiry-alerts/` | GET | Cross-pharmacy expiry monitoring |
| `/admin-panel/pharmacy/orders/` | GET | Cross-pharmacy order/delivery monitor (reads `AdminPanelRecord` JSON bridge) |
| `/admin-panel/pharmacy/<id>/suspend/` | PATCH | Suspend/reactivate a pharmacy account, bulk-deactivates its medicines |
| `/admin-panel/pharmacy/<id>/analytics/` | GET | Per-pharmacy medicine/order/revenue/expiry counts |

`backend/api/admin_views.py` generic module dispatcher also handles module
`pharmacies` (`_pharmacy_json`, `admin_record`) — a **second, divergent**
pharmacy-account suspend/approve path (see §3 role mismatches).

Flutter already has a 4-tab admin screen wired to all of the above:
`lib/features/admin/presentation/screens/admin_pharmacy_screen.dart`
(Pharmacies / Medicine Approvals / Expiry Monitoring / Orders & Delivery), via
`AdminApiService` (`lib/features/admin/data/services/admin_api_service.dart:152-181`).

**Conclusion:** medicine approve/reject, expiry monitoring, order/delivery
monitoring, and basic suspend/reactivate are already built end to end. This
build extends rather than replaces that screen and those endpoints.

### 1.3 Pharmacy catalogue (real tables) — reuse

`backend/pharmacy/models.py`, `managed=False`, keyed by `pharmacy_user_id -> users(id)`:

- **`PharmacyMedicine`** (table `pharmacy_catalogue_medicines`): name, generic_name,
  manufacturer, category (choices), prescription_required, price, previous_price,
  stock_quantity, unit, min_order_quantity, pack_size, description,
  dosage/storage instructions, cold_chain_required, expiry_date, batch_number,
  images (JSON list), **is_active** (archive flag), **is_approved** (admin gate,
  only meaningful for `prescription_required=True` — OTC auto-approves via
  `apply_auto_approval()` in `pharmacy/services.py:244-254`), approval_rejected_reason,
  views_count, orders_count. Derived: `expiry_alert_level`, `is_low_stock`,
  `stock_status`, `is_top_seller`.
- **`PharmacySupplier`** (table `pharmacy_suppliers`).
- **`PharmacyExpiryAlert`** (table `pharmacy_expiry_alerts`, 1:1 with a medicine).

Pharmacy-facing CRUD lives in `backend/pharmacy/catalogue_views.py` (all scoped
`pharmacy_user=request.user`, `IsPharmacyUser`): list/create, detail/update,
**soft-delete only** (`DELETE` sets `is_active=False`, never a hard delete —
order history is snapshot-based so this is always safe), image upload
(magic-byte validated, max 5/medicine), stock adjust, price update, bulk CSV
upload. This UI/service layer (`lib/features/pharmacy/presentation/widgets/add_medicine_dialog.dart`,
`pharmacy_catalogue_screen.dart`) is the template to adapt for an admin-side
medicine editor — **reuse the same request/response shape**, add an
admin-authority wrapper.

**Gap:** there is currently no admin **create/edit/archive** endpoint for
medicines — RBAC matrix has no `create`/`delete` for module `pharmacy`, and no
view in `admin_pharmacy.py` performs them. Admin can only approve/reject
prescription items today.

### 1.4 Orders — JSON bridge only, no relational table

Orders are **not** a real Django model. They live as `AdminPanelRecord`
(`backend/audit/models.py:9-27`, table `backend_admin_records`, generic
`{module, record_id, payload(JSON)}`) with `module='pharmacy-orders'`,
`record_id = order_key(pharmacy_user_id, order_id)` (`pharmacy/services.py:361`).
Payload embeds item **snapshots** (medicine_id, quantity, unit_price at order
time) — not live FKs — so catalogue changes never corrupt order history.
Status vocabulary: pending → processing → shipped → delivered/cancelled/refunded
(`catalogue_views.py:502-506`).

Delivery assignment uses a **real** relational model,
`delivery.models.DeliveryOrder` (table `delivery_orders`), created from a
queue entry (`AdminPanelRecord module='delivery-queue'`) via
`api/admin_views.py::_assign_from_queue` (L649-694): checks
`rider.approved_by_admin_id is not None` and per-rider capacity
(`delivery/services.py::capacity_error`), but **does not check `is_online`/
`current_status`** — an admin can currently assign to an offline rider (soft
gap, not a hard bug). Rider model: `profiles.DeliveryProfile`.

**Gap for commission/settlement:** since orders are JSON, there is no place to
attach an idempotent, queryable "this sale generated X commission" record
today. This audit proposes new real tables (§5) rather than bolting commission
fields onto the JSON payload, because idempotency and Decimal-safe aggregation
need a real unique constraint and indexed columns.

### 1.5 Pharmacy account / verification model — real, but split across two flags

`profiles.PharmacyOrganization` (`profiles/models.py:225-243`, table
`pharmacy_organizations`, 1:1 with `User`): business_name,
authorized_contact_person, business_registration_number (unique),
trade_license_url, tax_vat_tin_number, business_address, warehouse_address,
number_of_pharmacists, responsible_pharmacist_name, **is_verified**,
**approved_by_admin** (FK), created_at/updated_at.

`User.account_status` (`users/models.py:78`) is a plain `CharField`, **no
`choices=` constraint**, default `'pending'`. Observed values in the entire
codebase: `pending`, `active`, `suspended` only — there is no persisted
"rejected" or "needs more information" state; both collapse into `suspended`
today (`verification/status.py:41-46` documents this explicitly).
`IMMEDIATE_ACTIVE_ROLES = {'farmer','doctor'}` — pharmacy is **not** in it, so
pharmacy signups already start `account_status='pending'`, matching the spec's
`PENDING_REVIEW` requirement, just under a different literal string.

Signup fields captured today (`users/serializers.py`
`REQUIRED_ROLE_FIELDS['pharmacy']` + `KNOWN_ROLE_DATA_FIELDS['pharmacy']`):
business_name, contact_person, business_reg_number, tax_number,
business_address (required); warehouse_address, number_of_pharmacists,
responsible_pharmacist, trade_license, plus two cert uploads that are claimed
as `signup_documents` but have **no dedicated column** on
`PharmacyOrganization` (`business_registration_cert_url`,
`responsible_pharmacist_cert_url` — accepted, stored only in the generic
documents table, not surfaced back on the profile row).

**Gap:** "number_of_pharmacists" is the closest existing field to the spec's
"declared employee count," but it's specifically framed as pharmacist count,
not general staff headcount, and there's no separate employee roster table at
all (spec §3 wants owner vs. employee counted separately with audit trail on
updates).

### 1.6 Chat — reuse `doctor.Conversation`/`Message`, not build new

`backend/doctor/models.py`:
```python
class Conversation:  # table 'conversations'
    participant_one, participant_two -> User (generic FKs, no role baked in)
    consultation -> Consultation, NULLABLE
    last_message_at, created_at
class Message:  # table 'messages'
    conversation -> Conversation (related_name='messages')
    sender -> User; content; message_type (text/image/file); file_url
    is_read; sent_at
```
`consultation` being nullable and the participant pair having no role
assumption means **this model needs zero schema changes** to host a
pharmacy↔admin support thread (`participant_one`=pharmacy user,
`participant_two`=an admin/support agent, `consultation=None`).

Real-time transport: `backend/messaging/realtime.py` (Socket.IO,
`AsyncServer`, wired into `backend/featherflow_backend/asgi.py`) is already
generic — `join_conversation`/`send_message`/`mark_read` events operate on any
`Conversation` id, with a `persist_message()` that also creates a
`Notification` for the other participant. Flutter already has a
conversation-agnostic client: `lib/core/network/realtime_chat_service.dart`.
REST fallback pattern to mirror: `backend/doctor/views.py`
`conversations`/`conversation_detail` (`doctor/urls.py:12-13`).

**Alternative/complementary precedent:** `audit.models.SupportTicket` +
`SupportTicketReply` (real tables, already generic across all roles,
`backend/api/admin_support.py` full CRUD, user-facing `POST/GET
/api/support/tickets/` already open to any authenticated user including
pharmacy). This is async/threaded, not live 2-way chat. **Decision:** use
`doctor.Conversation`/`Message` + Socket.IO for the live "Contact Pharmacy
Admin" chat (spec §8 wants read/unread, timestamps, retry — chat fits better
than a ticket), and reuse `SupportTicket` category/priority conventions for
categorizing the conversation subject if useful, rather than building a third
system.

**Gap:** no pharmacy-scoped REST create/list endpoint yet (need one mirroring
`doctor/views.py`), and no admin-side inbox aggregating pharmacy conversations
(list conversations where `participant_one` or `participant_two` has role
`pharmacy` / `admin_pharmacy`).

### 1.7 Notifications — reuse as-is

`notifications.Notification` (`backend/notifications/models.py`): user, title,
body, `notification_type` (choices — no pharmacy-specific value yet, but
`reference_type` free-text already carries `'pharmacy_order'` etc.),
reference_id/type, is_read, created_at. `pharmacy/services.py:37` already has
its own `notify()` helper. Polling: `GET /api/pharmacy/updates/` **already
exists** (`admin_extra.py::module_updates`, registered in `api/urls.py:41-44`)
and Flutter's `lib/core/network/user_updates_service.dart` already polls it
every 10s and auto-logs-out on `access_revoked` (suspended). No new
infrastructure needed for pharmacy-owner notifications — just more call sites.

**Gap:** no admin-facing pharmacy notifications exist yet (new signup, new
appeal, new support message, medicine needing review) — the only existing
precedent for "notify platform admins" is the support-ticket escalation flow
in `admin_support.py`.

### 1.8 Audit logging — reuse `audit.ActivityLog`

`audit.models.ActivityLog` (table `activity_logs`) is append-only (`save()`
raises on update, `delete()` always raises — DB trigger backs this too):
user, module, action, action_type (create/edit/delete/approve/reject/suspend/
assign/export/refund/override/...), entity_type/entity_id, old_values/
new_values (JSON), reason, ip_address, user_agent, request_id, created_at.
Already queryable via `GET /api/admin-panel/audit-logs/`.

**Gap / inconsistency to fix, not replicate:** there are currently **three**
near-duplicate writer helpers (`admin_pharmacy.py::_audit`,
`admin_views.py::_log`, `admin_extra.py::_audit`) with slightly different
signatures, and `admin_pharmacy.py`'s `_audit()` **hardcodes
`entity_type='pharmacy_medicine'`** even when logging a pharmacy-suspend
action (whose entity is a pharmacy user, not a medicine) — a real bug that
will corrupt audit-log filtering for suspend/appeal actions unless fixed as
part of this build. Plan: extract one shared `log_pharmacy_action()` helper in
`pharmacy/services.py` (which already has `log_action()` at line 47) and route
every new endpoint through it with a correct `entity_type`.

### 1.9 Money / revenue precedent — reuse `payments.Payment` pattern or clone `DoctorEarning`

`payments.Payment` already has `platform_charge` and `net_amount` fields
built in (used today for `payment_type='cashout'` in farmer Cost Management).
`doctor.DoctorEarning` (gross_amount/platform_fee/net_amount/payout_status/
payout_date, 1:1 with a Consultation) and `delivery.DeliveryEarning` are the
two existing "gross → platform fee → net, with payout status" precedents.
**No pharmacy commission/settlement model exists at all** — pharmacy "revenue"
today is just `sum(total_amount)` over delivered JSON orders
(`catalogue_views.py::analytics_revenue`,
`admin_pharmacy.py::admin_pharmacy_analytics`), with zero commission deducted
or tracked. All money fields across the codebase are `Decimal`, never float,
at the model layer (float only appears at JSON-serialization boundaries) —
new tables must follow the same rule.

---

## 2. Role mismatches found (must reconcile, not carry forward)

1. **Two divergent pharmacy-suspend code paths**:
   `admin_pharmacy.py::admin_pharmacy_suspend` (sets `account_status`,
   `is_verified`, bulk-deactivates medicines, but does **not** touch
   `PharmacyOrganization.is_verified`) vs.
   `admin_views.py::admin_record` module=`pharmacies` (sets `account_status`,
   **and** cascades to `PharmacyOrganization.is_verified` +
   `approved_by_admin`, but does **not** deactivate medicines). The current
   Flutter `admin_pharmacy_screen.dart` suspend action calls the **generic**
   path (`_api.update('pharmacies', ...)`), meaning the more complete
   `admin_pharmacy.py` endpoint is presently unused by the client.
   **Decision:** consolidate into one canonical suspend/reactivate service
   function used by both the dedicated and generic routes, so every side
   effect (account_status, is_verified, org.is_verified, medicine
   deactivation, audit log, notification) always happens together.
2. **A third cascade site**: the generic `users` module PATCH also flips
   `PharmacyOrganization.is_verified` when a pharmacy account is approved
   through the Users screen — a comment in that code already flags this as a
   past desync bug. Same consolidation fixes this.
3. **`admin_dashboard`'s pharmacy stat tiles are not live** — `active_pharmacies`/
   `pending_pharmacies` are sourced from hardcoded `SEEDS['pharmacies']` demo
   data (`admin_views.py` lines 49-53), not real `User`/`PharmacyOrganization`
   counts. Must be replaced with live queries for the new dashboard metrics.
4. **Marketplace visibility does not check license verification** — farmer-facing
   catalogue queries (`farmer_views.py`) gate on `account_status='active'`
   only, never on `PharmacyOrganization.is_verified`. Practically this hasn't
   caused harm because `account_status` can't reach `active` without an admin
   approval today, but the two flags can drift (per §2.1/2.2), so the
   marketplace gate should check both, or a single derived "is pharmacy
   operational" property should be introduced and used everywhere.
5. **`admin_pharmacy.py`'s internal audit helper mislabels the entity type**
   for non-medicine actions (see §1.8) — must be fixed, not copied.

---

## 3. API gaps (new endpoints/fields needed)

- RBAC matrix for module `pharmacy`: add `create`, `delete`, `assign` actions.
- Admin medicine create/edit/archive/restore endpoints (mirror the pharmacy-
  facing ones in `catalogue_views.py`, with admin authority + audit).
- Pharmacy account detail endpoint with full profile + documents + counts +
  chat/audit history in one payload (spec §5) — today's `_pharmacy_json` is a
  thin list-row shape only.
- Dedicated status-transition endpoints beyond suspend: approve,
  request-more-information, reject, reinstate — each as its own action with
  reason + audit, rather than overloading `status` strings.
- `GET /api/pharmacy/permissions/` and `/api/pharmacy/verification-status/` —
  a single source of truth the Flutter pharmacy panel polls to decide what's
  locked (spec §7). Today permission is implied client-side from
  `account_status` alone (`user_updates_service.dart`), with no explicit
  permission map coming from the backend.
- Pharmacy-admin chat: `POST /api/pharmacy/support-conversation/` (get-or-create,
  usable even while `PENDING_REVIEW`), admin inbox
  `GET /api/admin-panel/pharmacy-chats/`, reply endpoint, status
  (open/waiting/resolved) field — none of this exists; needs new thin views
  over the reused `Conversation`/`Message` models.
- Appeals: fully new — `POST/GET /api/pharmacy/appeals/`, admin review
  endpoints. No model exists (see §5).
- Commission/settlement: fully new (see §5) — metrics endpoints
  `/api/admin/pharmacies/metrics/`, `/sales/`, `/commissions/`.
- Delivery assignment from the Pharmacy Admin surface: the existing
  `_assign_from_queue` mechanics can be reused, but needs pharmacy-admin-scoped
  list/filter endpoints and an explicit "no assignment to offline rider"
  guard if the spec's stricter eligibility rule is wanted (currently
  optional/soft).

---

## 4. Proposed new data model (additive, no destructive migration)

All new tables `managed=False` with a matching SQL extension file (following
the project's established pattern of `postgres_backend_extension.sql` /
`farmers_panel_extension.sql`), Decimal money fields throughout, plus Django
migrations for any Django-managed pieces (state-only, per project convention).

- **`PharmacyEmployee`** (new) — pharmacy_user FK, name, role_title, phone,
  email, license_number (nullable), is_active, added_at, added_by FK,
  access_level. Lets §3's "account holders / employees / total workforce"
  distinction be a real count instead of a single `number_of_pharmacists` int.
  `PharmacyOrganization.number_of_pharmacists` becomes the *declared* count
  captured at signup; actual employee records are managed post-approval.
- **`PharmacySale`** (new) — order_reference (the `AdminPanelRecord` order
  `record_id`, unique), pharmacy_user FK, gross_amount (Decimal), status,
  completed_at, unique source reference — the durable "this order became a
  completed sale" fact, created exactly once on the `delivered` transition
  (mirrors the existing `mirror_pharmacy_expense()` idempotency pattern in
  `pharmacy/services.py:418-483`, which already proves exactly-once mirroring
  from this same transition is a solved problem in this codebase).
- **`PharmacyCommission`** (new) — sale FK (unique, 1:1), rate (Decimal,
  stored at time of sale so historical rate changes don't rewrite history),
  gross_amount, commission_amount, pharmacy_amount, created_at. Computed as
  `commission_amount = gross_amount * rate`, `pharmacy_amount = gross_amount -
  commission_amount`, using `Decimal` arithmetic and `ROUND_HALF_UP` (or the
  project's existing rounding convention if one is found during
  implementation) — never float.
- **`PharmacySettlement`** (new) — pharmacy_user FK, period_start/end,
  gross_sales, commission, payable_amount, status (pending/approved/paid/
  failed/reversed), paid_at, payment_reference. Alternative considered: extend
  `payments.Payment` with `payment_type='pharmacy_settlement'` instead of a
  new table — rejected because `Payment` has no period/gross/commission
  breakdown columns and overloading it would mean parsing `notes` for
  structured data, which the spec explicitly wants avoided ("no
  disconnected mock flows").
- **`PharmacyAppeal`** (new) — pharmacy_user FK, suspension reference (the
  audit-log entry id of the suspension being appealed), reason, explanation,
  attachments (JSON list of document URLs, reusing `verification.documents`),
  status (submitted/under_review/more_info_required/approved/denied),
  admin_response, resolved_at, resolved_by FK. Deliberately its own table
  rather than overloading `AdminEscalation`/`SupportTicket`, because appeals
  need a strict lifecycle tied to a specific suspension event, which those
  generic models don't model today.
- Reuse unchanged: `doctor.Conversation`/`Message` (pharmacy support chat),
  `notifications.Notification`, `audit.ActivityLog`, `PharmacyMedicine`/
  `PharmacySupplier`/`PharmacyExpiryAlert`, `delivery.DeliveryOrder`/
  `DeliveryProfile`.
- `User.account_status` keeps its current 3 literal values (`pending`,
  `active`, `suspended`) at the DB layer (changing this is a wider blast
  radius affecting every role, out of scope for a pharmacy-only build per the
  instructions) — the spec's richer lifecycle
  (`PENDING_REVIEW`/`NEEDS_MORE_INFORMATION`/`APPROVED`/`ACTIVE`/`SUSPENDED`/
  `APPEAL_PENDING`/`REJECTED`/`CLOSED`) is implemented as a **derived,
  pharmacy-specific status** computed from `account_status` +
  `PharmacyOrganization.is_verified` + an added
  `PharmacyOrganization.review_state` field (new small CharField:
  `pending_review`/`needs_more_information`/`approved`/`rejected`/`closed` —
  additive column, does not touch the shared `User` table) + open
  `PharmacyAppeal` existence. This avoids a cross-cutting `account_status`
  enum migration while still giving the spec's full state machine.

---

## 5. Test plan (backend + Flutter, mirrors spec §15)

Follow the existing project convention: standalone `backend/scripts/test_*.py`
scripts run against a live seeded DB (see `test_pharmacy_flow.py`,
`test_signup_flows.py`) rather than Django's test runner — this build adds
`backend/scripts/test_pharmacy_admin.py` covering, at minimum:

- Signup → `PENDING_REVIEW` derived status; locked operational endpoints
  return 403 with an explanatory reason; earnings/profile/chat/appeal remain
  reachable.
- Approve → unlocks operations, notification sent, audit row correct,
  `PharmacyOrganization.is_verified` and `account_status` both flip together
  (regression test for the §2 desync bug).
- Reject / request-more-information → reason surfaced, resubmission allowed,
  operations stay locked.
- Suspend → operations lock again, existing order/settlement history
  untouched, appeal becomes submittable.
- Appeal lifecycle: submit → under_review → approve/deny → correct resulting
  state; all transitions audited.
- Medicine admin CRUD: create/edit/archive/restore, cannot hard-delete a
  medicine referenced by a completed `PharmacySale`, image upload validation.
- Commission math: BDT 100 → commission 20 / pharmacy 80 exactly, using
  Decimal comparison (not float `==`); BDT 250 and multi-item orders;
  cancelled/refunded produce no completed commission; repeated status-update
  webhooks do not duplicate `PharmacySale`/`PharmacyCommission` rows
  (idempotency key = order_reference); rate stored at sale time survives a
  later rate change.
- RBAC isolation: pharmacy owner cannot hit `/admin-panel/...`; one pharmacy
  cannot read another's chat/appeal/sale rows; `admin_support` tier cannot
  perform `admin_pharmacy`-only actions.
- Chat: pharmacy can create/access only its own conversation with admin;
  messages persist; unread counts correct; a pending (unapproved) pharmacy can
  still open the chat.
- Delivery assignment: cannot assign to an already-assigned or
  cancelled/completed order; duplicate assignment prevented; audited.

Flutter: widget tests for the locked/unlocked pharmacy dashboard banner,
appeal form, admin pharmacy detail screen, chat inbox/detail, commission
cards — added under `test/` following the existing `pharmacy_*_test.dart`
naming convention once the corresponding screens exist.

---

## 6. Assumptions

1. "Pending" pharmacy accounts already exist in the current schema
   (`account_status` default is `'pending'` and pharmacy is excluded from
   `IMMEDIATE_ACTIVE_ROLES`) — so no data backfill is needed for existing
   pharmacies to have a defined starting state; only *new* review-state fields
   need a default backfill (`review_state='approved'` for any pharmacy already
   `account_status='active'`, to avoid retroactively locking live pharmacies).
2. The spec's literal status names (`PENDING_REVIEW`, `NEEDS_MORE_INFORMATION`,
   etc.) are implemented as a **derived/display** enum, not a literal
   `account_status` value, per §4 above — this is called out explicitly to the
   user as a deliberate scope decision (avoids touching the shared `User`
   table used by 6 other roles).
3. Commission rate (20%/80%) is treated as a configurable setting with a
   hardcoded current value (not a hardcoded literal in every calculation site)
   so it can change later without a code deploy, while still storing the
   rate-at-time-of-sale on every `PharmacyCommission` row per the spec's
   explicit requirement.
4. "Employees" (spec §3) is new ground — the existing `number_of_pharmacists`
   field is preserved as the signup-time declared count; a real
   `PharmacyEmployee` roster is added as described in §4, not a repurposing of
   `number_of_pharmacists`.
5. Live chat (Socket.IO) is used for pharmacy↔admin support rather than the
   ticket-based `SupportTicket` model, matching the spec's emphasis on
   read/unread state, timestamps, and retry — this is a judgment call the
   audit flags rather than something dictated by existing code.
6. Nothing in this repo is committed as part of this work, per the standing
   instruction — all changes stay in the working tree until the user asks
   otherwise.

---

## 7. Summary — what Section 2 onward will build on

Reusable untouched: RBAC engine, `PharmacyMedicine`/`Supplier`/`ExpiryAlert`,
pharmacy-facing catalogue CRUD, `AdminPanelRecord` order bridge + delivery
queue/assignment mechanics, `doctor.Conversation`/`Message` + Socket.IO,
`notifications.Notification` + `/pharmacy/updates/` polling, `audit.ActivityLog`.

Net new: `PharmacyEmployee`, `PharmacySale`, `PharmacyCommission`,
`PharmacySettlement`, `PharmacyAppeal`, a `PharmacyOrganization.review_state`
column, admin medicine create/edit/archive endpoints, a centralized
permission/status guard (`/api/pharmacy/permissions/`), pharmacy↔admin chat
REST wrapper + admin inbox, a consolidated suspend/approve service function
(fixing the 3 divergent cascades in §2), and a live pharmacy-admin dashboard
replacing the hardcoded `SEEDS` stat tiles.

## 8. Post-implementation update (2026-09-26)

This audit predates the build; see `PHARMACY_ADMIN_IMPLEMENTATION_REPORT.md`
for what was actually built, including a second addendum (§29–§38) that
closed the two gaps this audit's own conclusion (§7 above) didn't originally
anticipate needing dedicated Flutter screens for: an Add Medicine form (the
admin create/edit/archive endpoints this audit called out in §1.3/§3 as
missing now have one) and a Reports & Audit export screen (§3's metrics
endpoints now have a consuming UI). That same pass also found and fixed two
real, previously-undiscovered bugs: a platform-wide CSV-export 406 (DRF
content negotiation rejecting a real browser's `Accept: text/csv` header
before any export view could run — affecting every admin module's export,
not just pharmacy's) and a dead `is_online` field-name check in the
delivery-queue rider picker (the real API field is `status`). Both are
detailed with root cause and fix in the implementation report.
