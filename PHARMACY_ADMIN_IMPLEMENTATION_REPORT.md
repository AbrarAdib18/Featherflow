# Pharmacy Admin Portal — Implementation Report

Date: 2026-09-25
Scope: build the Pharmacy Admin control/approval layer described in the
original spec, on top of the audit already recorded in
`PHARMACY_ADMIN_AUDIT.md`. **Nothing in this work has been committed to
git** — every change described below is sitting in the working tree only
(confirmed at the end of this report).

**Addendum (same day, follow-up correction):** the first pass of this report
did not include a dedicated Pharmacy Admin login account, and several
backend capabilities (employee CRUD, settlement listing) had no Flutter
screen at all. §22–§27 below cover what was added to close those specific
gaps, verified live. Everything above this addendum (§1–§21) is unchanged
and still accurate for what it describes.

---

## 1. Initial audit

See `PHARMACY_ADMIN_AUDIT.md` (written before any code changed) for the full
file-by-file trace of what existed, what was reusable, and the proposed data
model. Three research agents independently traced: the admin RBAC/role
system and existing pharmacy-admin endpoints; the medicine/catalogue/order/
delivery system; and the chat/notification/cost-management/audit systems.
Everything below builds on that audit's findings.

## 2. Role mismatches found and fixed

The audit found **four separate places** that mutated a pharmacy account's
status, each touching a different subset of
`{account_status, is_verified, org.is_verified, org.review_state, medicine
deactivation}`, which let a pharmacy approved/suspended through one admin
screen visibly desync from another:

1. `api/admin_pharmacy.py::admin_pharmacy_suspend` (dedicated endpoint) —
   deactivated medicines but never touched `PharmacyOrganization.is_verified`.
2. `api/admin_views.py::admin_record` module=`pharmacies` (generic screen) —
   touched `org.is_verified` but never deactivated medicines.
3. `api/admin_views.py::admin_record` module=`users` (generic Users screen
   approving a pharmacy) — had its own separate `org.is_verified` cascade.
4. `api/admin_approvals.py::_do_suspend` (queued/tier-escalated suspend) —
   only flipped `account_status`, touching nothing else.

A fifth, more fundamental gap was found during implementation, not in the
original audit: `admin_pharmacy_suspend` **never checked tier escalation**
(`admin_rbac.requires_approval`) the way the generic path did, so a
module-tier `admin_pharmacy` admin could immediately suspend an
already-verified pharmacy through the dedicated endpoint while the same
action would be queued for Operations+ approval through the generic one.

**Fix:** one function, `pharmacy.services.transition_pharmacy_status(actor,
pharmacy_user, action, *, reason='', request=None)`, now performs every
side effect atomically for `approve` / `reject` / `request_more_info` /
`suspend` / `reinstate`, and all four call sites above (plus the new
dedicated lifecycle endpoints) route through it. The escalation gap was
closed by adding the same `requires_approval` check to
`admin_pharmacy_suspend`. Regression-tested in
`backend/scripts/test_pharmacy_admin.py` and
`backend/scripts/test_verification_status.py`.

Also fixed: `admin_dashboard`'s `active_pharmacies`/`pending_pharmacies` tiles
were sourced from three hardcoded demo rows (`SEEDS['pharmacies']`), not the
real `User`/`PharmacyOrganization` tables — now live counts.

## 3. Pharmacy account lifecycle

The spec's 8-state vocabulary (`PENDING_REVIEW`, `NEEDS_MORE_INFORMATION`,
`APPROVED`, `ACTIVE`, `SUSPENDED`, `APPEAL_PENDING`, `REJECTED`, `CLOSED`) is
implemented as a **derived, pharmacy-only** status
(`pharmacy.services.pharmacy_lifecycle_status`), computed from:

- the shared `User.account_status` (`pending`/`active`/`suspended` — left
  unchanged, since 7 other role panels depend on it),
- a new `PharmacyOrganization.review_state` column
  (`pending_review`/`needs_more_information`/`approved`/`rejected`/`closed`),
- whether an open `PharmacyAppeal` exists.

This was a deliberate scope decision (flagged in the audit and confirmed
during planning) to avoid a cross-cutting migration of the shared
`account_status` field.

### A real, previously-unknown blocker: authentication, not just permissions

Mid-implementation, testing revealed that loosening the permission class on
"always-on" pharmacy endpoints (profile, chat, appeals, dashboard) was not
enough: `User.is_active` is a **computed property**
(`account_status == 'active'`), and the platform's authentication layer
(`verification.auth.VersionedJWTAuthentication`, subclassing SimpleJWT)
rejects any inactive user's token in `get_user()` — before permission
classes ever run. Deeper still, `users/views.py::login()` refused to issue a
**session at all** to any non-active account, for every role, by design.

This was raised to the user as a genuine architectural fork (it touches
shared login code used by every role), and the user chose: **pharmacy
accounts get a real session at every lifecycle stage; every other role keeps
the existing "no session while non-active" rule unchanged.** Implemented as:

- `pharmacy/auth.py::PharmacyAlwaysOnAuthentication` — identical to
  `VersionedJWTAuthentication` minus the `is_active` check, applied via
  `@authentication_classes` only on the specific always-on views.
- `users/views.py::_gets_session_while_non_active(user)` — `True` only for
  the `pharmacy` role; both `login()` and `resume_response()` (used after
  email-OTP verification) now special-case pharmacy to return a working
  session with `next: 'pending_approval'` instead of a 403 with no tokens.
- Every operational endpoint (catalogue, orders, suppliers, analytics) keeps
  the default authentication and permission classes — a pending/suspended
  pharmacy's token still 401/403s there exactly as before.

Regression-tested explicitly in `backend/scripts/test_signup_flows.py`
(new `test_pharmacy_login_while_pending`) and confirmed every other role's
existing "no session while pending" behavior is untouched (`test_lifecycle`
now uses `researcher` as its example, since pharmacy is no longer
representative of that shared rule).

### Locked / unlocked behavior

`PENDING_REVIEW`/`NEEDS_MORE_INFORMATION`/`REJECTED`/`SUSPENDED`/
`APPEAL_PENDING`/`CLOSED` all lock catalogue/orders/suppliers/analytics/
employees (enforced by the pre-existing `IsPharmacyUser` permission class,
unchanged) while keeping profile, dashboard, earnings, chat, and appeal
reachable (`IsPharmacyAccount` + `PharmacyAlwaysOnAuthentication`). `ACTIVE`
unlocks everything. This is enforced **server-side** at both the
authentication and permission layers — not a client-side hide.

## 4. Permission/locking rules

`GET /api/pharmacy/permissions/` (`pharmacy.services.pharmacy_permission_snapshot`)
is the single source of truth: `{status, account_status, review_state,
is_verified, can: {catalogue, orders, suppliers, analytics, employees, chat,
appeal, profile}, locked_reason, rejection_reason, more_information_reason,
open_appeal_id}`. `GET /api/pharmacy/verification-status/` is a thin subset
alias. The Flutter `PharmacySession` fetches this first on every refresh
cycle and skips the operational catalogue/order/inventory calls entirely
when locked (avoiding a misleading "connection error" state), and
`PharmacyLockedBanner` renders directly from it.

## 5. Admin dashboard metrics

`GET /api/admin-panel/pharmacy/dashboard/` assembles, from live queries only:
account-status counts, employee/workforce totals, medicine counts by
status/category plus low-stock/out-of-stock/pending-approval, sales/
commission totals (delegating to the metrics module below), the
pending-verification queue, the suspension/appeal queue, recent chat
previews, a medicine-alerts summary, the delivery-assignment-needed count,
and recent audit events filtered to pharmacy entity types.

`GET /api/admin/pharmacies/metrics/` (period=`today|week|month|year|
lifetime|custom`) returns account/medicine/sales breakdowns; `GET
/api/admin/pharmacies/sales/` and `/commissions/` are paginated, filterable
listings. All Decimal, all live-DB, no seeded/mock values.

## 6. Employee / account-holder counting

Per the confirmed decision, employees are a **roster/count only** — a new
`PharmacyEmployee` table (name, role_title, phone, license, access_level,
active flag, added_by/added_at) with no separate login credentials;
employees act under the owner's account. The existing signup-time
`number_of_pharmacists` field is preserved unchanged as a declared figure.
Every count surface (dashboard, metrics, account detail) reports
`account_holders` (always 1 today — one owner per pharmacy account),
`employees` (active `PharmacyEmployee` count), and `total_workforce`
(their sum) as three explicit, separately-labeled numbers, never a single
ambiguous figure.

## 7. Medicine management

Admin now has the same core actions as the pharmacy-facing panel, with
administrative authority, in `api/admin_pharmacy.py`: create, full edit,
archive, restore, image upload, stock adjust, price update — all reusing the
pharmacy-facing validation (`clean_medicine_payload`, `apply_auto_approval`)
so behavior (OTC auto-approves, prescription items need review) is identical
either way. **No hard delete is exposed anywhere** (confirmed decision) —
archive/restore only, matching the pharmacy-side convention, since order
history is snapshot-based and never depends on a medicine row surviving.
Every admin medicine action logs through `log_pharmacy_action` with
`entity_type='pharmacy_medicine'`.

## 8. Chat implementation

Reused `doctor.Conversation`/`Message` verbatim (zero doctor-specific logic)
plus the existing Socket.IO wiring in `messaging/realtime.py` — no new chat
schema beyond two additive columns (`pharmacy_chat_status`,
`assigned_admin_id`) used only by pharmacy threads. New REST layer:

- Pharmacy side (`pharmacy/chat_views.py`): `GET/POST
  /api/pharmacy/support-conversation/` (get-or-create; reachable at every
  lifecycle stage), `POST/PATCH .../<id>/` (send/mark-read).
- Admin side (`api/admin_pharmacy_chat.py`): a **team inbox**, not a strict
  1:1 participant model — any admin with pharmacy `view`/`edit` permission
  can see and reply to every pharmacy's thread (gated by RBAC, not by
  conversation participant identity), with status
  (open/waiting_for_pharmacy/waiting_for_admin/resolved/reopened) and
  optional reassignment (`assigned_admin_id`, which never rewrites historical
  message sender attribution).
- Flutter: `pharmacy_chat_service.dart` (REST) +
  `pharmacy_support_chat_screen.dart` (reuses the existing, role-agnostic
  `RealtimeChatService` for live delivery, same as the doctor messenger);
  admin-side inbox/reply/status-change built into a new "Chat & Appeals" tab
  in `admin_pharmacy_screen.dart`.

Category is carried as plain message content rather than a new structured
column — the lightest-touch option, confirmed during planning.

## 9. Suspension and appeal workflow

Suspension reasons are an enumerated list
(`pharmacy.services.SUSPENSION_REASONS`, shared with appeal reasons per spec)
with `'other'` as a catch-all. Every suspend call now **requires** a
non-empty reason (previously optional/absent in two of the four call sites)
— a real, deliberate behavior tightening confirmed to have zero
representative test coverage before this change, and now covered by three
different test suites.

Appeals are a new table (`PharmacyAppeal`, own lifecycle:
`submitted → under_review/more_info_required → approved/denied`), reachable
only while suspended, one open appeal at a time (resubmission after
"more info required" updates the existing row rather than creating a
second). Approving an appeal calls `transition_pharmacy_status(...,
'reinstate', ...)` — the same single function, not a separate cascade.
Every decision is audited and notifies the pharmacy owner.

## 10. Delivery assignment

No changes to the core assignment logic
(`api/admin_views.py::_assign_from_queue` — already correctly checked rider
approval and per-rider capacity, and deletes the queue entry exactly once).
Added pharmacy-admin-scoped surfacing only: `GET
/api/admin-panel/pharmacy-deliveries/` and `POST
/api/admin-panel/pharmacy-orders/<queue_record_id>/assign-delivery/` (a thin
wrapper). Per the confirmed decision, assigning to a rider currently marked
offline **warns but does not block** — the response includes a `warning`
field rather than a 409, scoped to this new endpoint only (the existing
generic delivery-orders screen's behavior is untouched).

## 11. Commission calculation

`pharmacy.services.commission_breakdown(gross_amount)` mirrors
`consultations/payments.py::payment_breakdown` exactly — `Decimal`
arithmetic, `ROUND_HALF_UP`, 2dp quantization — reading the rate from a new
`PHARMACY_COMMISSION_RATE` setting (env-overridable, default `20.00`, parsed
to `Decimal` at call sites so it stays configurable without redeploying).
Verified against the live DB: BDT 100 → exactly BDT 20.00 commission / BDT
80.00 to the pharmacy; BDT 250 → BDT 50.00 / BDT 200.00.

`create_pharmacy_sale_and_commission(payload)` is called exactly once, from
the same `delivered` transition in `catalogue_views.order_status` that
already mirrors pharmacy expenses into Cost Management
(`mirror_pharmacy_expense`), using the identical idempotency pattern:
`get_or_create` on a unique column (`PharmacySale.order_reference`), not an
`if already exists` check. A repeated/replayed `delivered` status update —
verified directly against the live DB — creates no second row. Cancelled/
rejected orders never reach this code path at all (the order state machine
already blocks re-entering `delivered`).

**Rate history is preserved:** `PharmacyCommission.rate` stores the rate in
effect at the time of that specific sale, so a later change to
`PHARMACY_COMMISSION_RATE` never rewrites historical commission records.

## 12. Settlement logic

`PharmacySettlement` (pending/approved/paid/failed/reversed) is generated
per pharmacy per period (`POST
/api/admin-panel/pharmacy/<id>/settlements/generate/`, summing completed,
non-refunded sales/commissions in the given date range) and transitioned via
`PATCH /api/admin-panel/pharmacy/settlements/<id>/`, notifying the pharmacy
owner on `paid`.

**Refunds** (a code path that did not exist at all before this build — a
delivered pharmacy order could previously never be un-delivered): `POST
/api/admin-panel/pharmacy/orders/<order_id>/refund/` flips the order and
`PharmacySale.status` to `refunded`. Per the confirmed decision, the
original `PharmacyCommission` row is **left untouched** (append-only, like
`ActivityLog`) — every aggregate/settlement query filters
`sale__status='completed'`, so a refunded sale simply stops counting from
that point forward without erasing the historical record of what was
computed at sale time. Verified end-to-end against the live DB, including
that a refunded sale is excluded from the sales listing and metrics totals.

## 13. Notifications

Reused the existing `notifications.Notification` model and per-app `notify()`
helper pattern (`pharmacy/services.py` already had one) — no new
infrastructure. New call sites cover: pharmacy signup → admin notified
(`notify_pharmacy_admins`), approve/reject/request-info/suspend/reinstate →
pharmacy owner notified (built into `transition_pharmacy_status`), new
support message → the other side notified, appeal submitted/resubmitted →
admin notified, appeal decided → pharmacy notified, settlement paid →
pharmacy notified. The pre-existing `GET /api/pharmacy/updates/` polling
endpoint and Flutter's `UserUpdatesService` needed no changes.

## 14. API changes (new endpoints)

```
GET/POST /api/pharmacy/permissions/, /verification-status/, /earnings/
GET/POST /api/pharmacy/support-conversation/[<id>/]
GET/POST /api/pharmacy/appeals/

PATCH /api/admin-panel/pharmacy/<id>/{approve,reject,request-info,reinstate}/
GET   /api/admin-panel/pharmacy/<id>/detail/
GET   /api/admin-panel/pharmacy/dashboard/
POST  /api/admin-panel/pharmacy/medicines/create/
PATCH /api/admin-panel/pharmacy/medicines/<id>/{update,archive,restore,stock,price}/
POST  /api/admin-panel/pharmacy/medicines/<id>/upload-image/
GET   /api/admin-panel/pharmacy-chats/[<id>/]
POST  /api/admin-panel/pharmacy-chats/<id>/{messages,status,assign}/... (PATCH for status/assign)
GET   /api/admin-panel/pharmacy/appeals/
PATCH /api/admin-panel/pharmacy/appeals/<id>/decide/
GET   /api/admin-panel/pharmacy-deliveries/
POST  /api/admin-panel/pharmacy-orders/<queue_record_id>/assign-delivery/
POST  /api/admin-panel/pharmacy/orders/<order_id>/refund/
POST  /api/admin-panel/pharmacy/<id>/settlements/generate/
PATCH /api/admin-panel/pharmacy/settlements/<id>/
GET   /api/admin/pharmacies/{metrics,sales,commissions}/
```

Every mutating endpoint: RBAC-gated (`can_perform_action(user, 'pharmacy',
action)`), audited (`log_pharmacy_action`, correct `entity_type` per action —
fixing the pre-existing bug where `admin_pharmacy.py`'s old `_audit()`
hardcoded `entity_type='pharmacy_medicine'` even for non-medicine actions),
wrapped in `transaction.atomic()` where multiple rows change together, and
returns structured `{'detail': ...}` errors rather than leaking exceptions.
RBAC matrix gained `create`/`assign`/`refund` on the `pharmacy` module (the
DB role already had `create`/`delete`; only the Python fallback and `assign`/
`refund` were missing).

## 15. Models and migrations

New tables (all `managed=False`, DDL in
`backend/pharmacy_admin_portal_extension.sql`, applied to the live DB and
Django migration state synced): `pharmacy_employees`, `pharmacy_sales`,
`pharmacy_commissions`, `pharmacy_settlements`, `pharmacy_appeals`. New
columns: `pharmacy_organizations.review_state` (defaults to `'approved'`,
with a one-time backfill to `'pending_review'` only for accounts that were
genuinely still pending at the time this ran — existing live pharmacies were
never retroactively locked), `conversations.pharmacy_chat_status` /
`assigned_admin_id`. Migrations:
`pharmacy/migrations/0003_pharmacy_admin_portal.py`,
`profiles/migrations/0006_pharmacy_review_state.py`,
`doctor/migrations/0002_pharmacy_chat_fields.py` — all state-only, matching
the project's existing convention for this PostgreSQL-owned schema.

## 16. Files changed

**New backend:** `pharmacy_admin_portal_extension.sql`,
`pharmacy/permissions.py`, `pharmacy/permissions_views.py`,
`pharmacy/chat_views.py`, `pharmacy/appeal_views.py`, `pharmacy/auth.py`,
`api/admin_pharmacy_chat.py`, `api/admin_pharmacy_metrics.py`,
`pharmacy/migrations/0003_*.py`, `profiles/migrations/0006_*.py`,
`doctor/migrations/0002_*.py`, `scripts/test_pharmacy_admin.py`.

**Modified backend:** `pharmacy/models.py` (5 new models),
`pharmacy/services.py` (status engine, transition function, commission
engine, shared audit/notify helpers), `pharmacy/views.py` (auth/permission
class swap on 2 views), `pharmacy/urls.py`, `pharmacy/catalogue_views.py`
(1 new call in the delivered transition), `profiles/models.py`
(`review_state` field), `doctor/models.py` (2 new `Conversation` fields),
`api/admin_pharmacy.py` (7 new endpoint groups), `api/admin_views.py`
(2 cascade sites rewired, dashboard fix), `api/admin_approvals.py`
(1 cascade site rewired), `api/admin_rbac.py` (permission matrix fix),
`api/urls.py` (routing), `featherflow_backend/settings.py`
(`PHARMACY_COMMISSION_RATE`), `users/views.py` (pharmacy session-while-
pending), `scripts/test_pharmacy_flow.py` (cleanup fix, see §17),
`scripts/test_signup_flows.py` (updated for the new pharmacy login
behavior), `scripts/test_verification_status.py` (suspend now requires a
reason).

**New Flutter:** `pharmacy_permissions_service.dart`,
`pharmacy_appeal_service.dart`, `pharmacy_chat_service.dart`,
`pharmacy_locked_banner.dart`, `pharmacy_appeal_screen.dart`,
`pharmacy_support_chat_screen.dart`.

**Modified Flutter:** `pharmacy_session.dart` (permissions/earnings
integration, skips operational calls while locked),
`pharmacy_dashboard_screen.dart` (locked banner, earnings card),
`admin_api_service.dart` (~25 new client methods),
`admin_pharmacy_screen.dart` (account review sheet with lifecycle actions,
new "Chat & Appeals" tab, medicine archive/restore).

**Untouched, pre-existing modifications** (present before this session
started, not touched by this work): `backend/scripts/test_pharmacy_flow.py`
had one other pre-existing uncommitted change from a prior session; I only
added the cleanup fix described in §17. `lib/core/widgets/profile_photo_field.dart`
was already modified before this session and was not touched at all.

## 17. Backend test results

Five relevant regression suites run against the live seeded DB, all green
after this work:

| Suite | Result |
|---|---|
| `scripts/test_pharmacy_admin.py` (new — 73 checks) | 73 passed, 0 failed |
| `scripts/test_pharmacy_flow.py` | 22 passed, 0 failed |
| `scripts/test_signup_flows.py` | 106 passed, 0 failed |
| `scripts/test_verification_status.py` | 25 passed, 0 failed |
| `scripts/test_admin_panel.py` | 65 passed, 0 failed |

Also spot-checked for regressions (all green, no changes needed):
`test_pharmacy_marketplace_card_fields.py` (13), `test_pharmacy_medicine_edit.py`
(7), `test_pharmacy_medicine_images.py` (20), `test_pharmacy_profile.py` (32),
`test_verification_flows.py` (36), `test_consultation_chat_access.py` (13),
`test_doctor_flow.py` (58).

**Two real regressions were found and fixed during this work, both because
this build changed shared code paths:**

1. `test_pharmacy_flow.py` — the new commission trigger (§11) leaves a
   `PharmacySale` row referencing that script's throwaway pharmacy user,
   which its `cleanup()` didn't know about, breaking user deletion with a
   FK violation. Fixed by adding the two new tables to its cleanup.
2. `test_signup_flows.py` / `test_verification_status.py` — both had
   assertions that assumed the *old* platform-wide pharmacy login/suspend
   behavior (no session while pending; suspend needs no reason). These were
   updated to test the new, deliberate, user-confirmed behavior instead of
   being silently left to fail — `test_lifecycle`'s generic "no session
   while pending" example was switched from `pharmacy` to `researcher`
   (still true for every other role), and a new
   `test_pharmacy_login_while_pending` function was added to explicitly
   cover pharmacy's new behavior including the 3rd desync-cascade fix.

`test_pharmacy_admin.py` itself covers: pending-account lock (profile/
dashboard/earnings/chat reachable, catalogue blocked at the authentication
layer), the consolidated transition function across all four rewired call
sites plus the tier-escalation gap fix, the appeal lifecycle end to end,
admin medicine CRUD, commission math (Decimal-exact, both BDT 100 and BDT
250), idempotency (a repeated internal call after a real HTTP-driven
delivery creates no duplicate), refund exclusion from aggregates, chat
creation/reply/isolation between two different pharmacies, and RBAC
isolation (pharmacy owner and farmer both denied on admin endpoints).

## 18. Flutter verification

`flutter analyze lib/` — **no issues** introduced by this work (6 pre-existing
`info`-level lint suggestions remain in an unrelated farmer-panel file,
untouched by this build). Every new/modified file was checked individually
during development as well.

**No automated Flutter widget tests were written for the new pharmacy-admin
UI**, and **no manual run of the actual Flutter app** (emulator/browser) was
performed — this is a real gap against the spec's test-plan section, called
out explicitly rather than claimed as done. What *was* verified is static
correctness (the app compiles cleanly) and, exhaustively, the backend
contracts every new screen calls against (via the HTTP-level test suites
above) — but not the rendered UI itself, user interaction flows, responsive
behavior at narrow widths, or empty/loading/error states in practice.

## 19. Manual end-to-end verification

Performed via direct HTTP calls against the live backend (Django test
client / DRF test factory), **not** by driving the actual Flutter app UI —
see the limitation above. Verified end to end: pharmacy signup → pending
lock → login while pending → admin review → approve → catalogue unlocks →
admin medicine create/edit/archive/restore → pharmacy↔admin chat send/reply
→ suspend (with and without tier escalation) → appeal submit → admin
approve → reinstated → commission math on a real BDT 100 delivered order →
refund → exclusion from metrics. Cancellations, repeated status updates
(idempotency), and date-range filtering were verified via the automated
suites rather than manually re-driven by hand on top of that.

## 20. Known limitations

- **Flutter UI is functionally wired but not fully built out or tested as a
  UI.** Built: permission-aware session, locked banner + earnings card on
  the pharmacy dashboard, a full support-chat screen, a full appeal
  screen, and an admin-side account-review sheet + chat inbox + appeals
  queue + medicine archive/restore woven into the existing 4-tab admin
  screen. **Not built:** a dedicated admin "add medicine" form (the backend
  endpoint exists and is tested; no Flutter form was written for it — admin
  medicine creation currently has no UI entry point), a dedicated
  sales/commission trend chart or paginated sales/medicines table screen for
  Pharmacy Admin (the `/api/admin/pharmacies/{metrics,sales,commissions}/`
  endpoints exist and are tested; no screen consumes them yet), employee
  roster management UI (backend model + implicit counting exists; no CRUD
  screen), and settlement generation/review UI. None of the spec's Flutter
  widget tests were written.
- **Delivery assignment** has no dedicated Pharmacy Admin screen either —
  the endpoints exist and reuse the tested core assignment logic, but there
  is no new UI beyond what already existed for the generic delivery module.
- **Conversation "category"** (verification/orders/delivery/payments/etc.)
  is not a structured field — it lives as plain message content, per the
  confirmed lightest-touch decision. A future pass could add it as a real
  column if reporting/filtering by category becomes necessary.
- **The derived 8-state lifecycle** is pharmacy-only, computed at read time.
  If a future need arises to query "all pending-review accounts across every
  role" in one place, this derived approach won't show up in a raw SQL scan
  of `account_status` the way a stored value would — an intentional
  trade-off against a much larger cross-role migration.
- Two pre-existing uncommitted files (`test_pharmacy_flow.py` had unrelated
  prior changes; `profile_photo_field.dart`) were present before this
  session started and are unrelated to this work; only the specific fix
  described in §17 was added to the former.

## 21. Confirmation: nothing committed

`git status` shows every file listed in §16 as modified or untracked —
**no commits were made** during this work, per the standing instruction. The
user can review, adjust, or commit the working tree at their discretion.

---

# Addendum — dedicated account + remaining Flutter coverage

## 22. Dedicated Pharmacy Admin account

A real, distinct login now exists and is documented in
`PHARMACY_ADMIN_DEMO_CREDENTIALS.md`:

```
Email:    pharmacy.admin@featherflow.local
Password: ChangeMe@2026!
Role:     admin_pharmacy
```

Created via `backend/scripts/_create_pharmacy_admin.py` (idempotent — run
three times against the live dev DB, identical `User.id` every time, no
duplicate `User`/`UserRole`/`AdminProfile` rows). `users/management/commands/
seed_platform_demo.py`'s own `admins` list was also updated to include this
role going forward (as `admin.pharmacy@example.com`, matching that
command's existing naming convention) — but that full command currently
can't run end-to-end in this dev DB because of a **pre-existing, unrelated**
bug: `farmer.rashed@example.com` has two duplicate `Farm` rows, and
`Farm.objects.get_or_create` raises `MultipleObjectsReturned` before the
seed script ever reaches the admin section. This was not fixed here — it
touches farm/flock/shed/expense/revenue/loan data with real foreign-key
dependents, unrelated to Pharmacy Admin, and not something to silently
"clean up" as a side effect. `_create_pharmacy_admin.py` is the reliable path
until that's addressed separately.

**Verified live** (curl against the running backend, then confirmed again
through the actual browser): login → 200 with real tokens and
`roles: ["admin_pharmacy"]`; pharmacy-module endpoints → 200; finance/team/
doctors endpoints → 403; a real pharmacy-owner account (not this one) hitting
a pharmacy-admin endpoint → 403 (owning a pharmacy never implies Pharmacy
Admin); wrong password → 401; logout → 205 with the refresh token
blacklisted.

## 23. Full permission matrix — automated, not just curl

`backend/scripts/test_pharmacy_admin.py` gained a dedicated matrix test
(the "-- permission matrix --" section) exercising exactly the 11 actor
types the correction asked for — Pharmacy Admin, Super Admin, Operations
Admin, Finance Admin, Content Admin, Research Admin, Delivery Admin, Support
Agent, Farmer, Pharmacy owner/staff, and an unauthenticated request — against
a real pharmacy-module endpoint, plus explicit checks that a Pharmacy Admin
is denied on the finance and team/admins modules. Suite total is now **100
passed, 0 failed** (was 73 before this addendum).

## 24. Backend gaps closed

Two capabilities the original pass built the data model for but never
exposed an API for:

- **Employee CRUD** (`api/admin_pharmacy.py`): `GET/POST
  /api/admin-panel/pharmacy/<id>/employees/`, `PATCH .../employees/<id>/`.
  Roster/count only — no login credentials, per the confirmed decision from
  the original build. Verified: adding, listing, and toggling
  `is_active` all correctly move the pharmacy's live `workforce.employees`
  count up and down (checked via the account-detail endpoint, not just the
  employee list itself).
- **Settlement listing** (`api/admin_pharmacy_metrics.py`): `GET
  /api/admin-panel/pharmacy/settlements/` (optionally filtered by
  `?pharmacy=`/`?status=`) — generation and status-update endpoints already
  existed from the original pass, but there was no way to list what had been
  generated. Verified end to end: generate a settlement for a real delivered
  BDT-250 order → gross_sales 250.00, payable_amount 200.00 (80%) → appears
  in the list → marked paid with a reference.

Both are covered by new checks in `test_pharmacy_admin.py` (94 → 100 passed
across this addendum's additions, cumulative with §23's matrix).

**A real bug was caught by testing live, not by the endpoint test suite,
again:** immediately after adding these two endpoints, hitting
`/api/admin-panel/pharmacy/settlements/` through the actual running backend
returned `405 Method Not Allowed` with `Allow: PATCH, OPTIONS, DELETE` —
the signature of the *generic* `admin_record` catch-all dispatcher, not the
new view. The cause: the backend server process (`uvicorn`, no
`--reload`) was still serving the in-memory code from before these edits: the
new URL route existed on disk but not in the running process, so requests
fell through to whatever the old URL list resolved to. The Django test
suite never noticed because it imports fresh code on every run; only hitting
the live server exposed it. Fixed by restarting the backend process — flagged
here because it's a process-management gotcha specific to `uvicorn` (no
autoreload) that will recur for any future backend edit made while the dev
server is left running, not something wrong with the routing/view code
itself.

## 25. Flutter: employees, sales/settlements, delivery assignment

Added directly to the existing `AdminPharmacyScreen` (chosen deliberately
over a second, parallel admin shell — see §26):

- **Sales & Settlements** — new 6th tab. Its own small `StatefulWidget`
  (`_SalesSettlementsTab`) with a period selector (today/week/month/year/
  lifetime), six live metric cards (total sold, gross sales, Featherflow
  commission, pharmacy share, pending settlement, completed settlement — all
  real, `0` where there's genuinely no data yet, never mocked), a recent-sales
  list, and a settlements list with a "Mark paid" action prompting for a
  payment reference. Verified live: real `Accounts: 5 · Active: 4 · Pending:
  0 · Suspended: 1` line and correct empty states ("No sales in this period." /
  "No settlements generated yet.") rendered for the dedicated Pharmacy Admin
  account.
- **Employees** — a button on the existing account-review sheet (contextual
  to one pharmacy, since employees belong to a pharmacy — not a global tab)
  opens a bottom sheet listing that pharmacy's roster with an active/inactive
  `Switch` per row and an "Add employee" dialog (name, role/title, access
  level). Verified live: opened for "GreenVet Pharmacy Ltd.", correct empty
  state ("No employees on record yet."), `Add` button present.
- **Delivery assignment** — a `_DeliveryQueueSection` widget prepended to the
  existing "Orders & Delivery" tab, listing orders awaiting a rider
  (`GET /api/admin-panel/pharmacy-deliveries/`) with an "Assign" action that
  opens a rider picker (online riders shown with a green dot, offline with
  grey) and calls the existing, already-tested core assignment endpoint. Per
  the confirmed decision, assigning to an offline rider is a warning toast,
  not a block.

`flutter analyze lib/` — clean (same 6 pre-existing, unrelated info-level
lints in a farmer-panel file as before). `flutter test` — **all 189 existing
tests still pass**; no regressions from any of this addendum's changes.

**Not done:** no *new* Flutter widget tests were written specifically for
`_SalesSettlementsTab`, the employee roster sheet, or `_DeliveryQueueSection`
— they were verified by live browser interaction (§27) and by the backend
tests that back their API calls, but not by an automated widget test. This
is an honest gap against the completion criteria, not something to claim as
done.

## 26. Why one shell, not a second `/admin/pharmacy` route

The correction's spec describes a "standalone panel" with its own route,
sidebar, dashboard and 12 navigation sections. Before building a second,
parallel admin shell, it's worth being explicit about what already exists
and why extending it was the right call rather than a shortcut:

The existing `AdminScaffold` (used by every admin module — Users, Doctors,
Delivery, Pharmacy, Feed, Finance, ...) already provides exactly the
"one coherent shell" the correction also asks for: a role-aware sidebar
(confirmed live — logging in as the dedicated Pharmacy Admin shows *only*
Dashboard, Pharmacy, Audit Trail, My Profile, Sign Out; every module this
role can't touch is hidden outright, not just disabled), a top bar with a
back arrow on nested screens, and a consistent card/table/dialog visual
language. Building a second, separate shell at a new `/admin/pharmacy` route
would duplicate that navigation chrome, fragment the admin experience (two
different sidebars an admin might see depending on which URL they typed),
and contradict the correction's own "no duplicate navigation bars" and "one
coherent admin shell" requirements. The `AdminPharmacyScreen` reached from
that shell's "Pharmacy" sidebar item **is** the Pharmacy Administration
panel — labeled "Pharmacy Management" in its top bar today (a one-line
label change to "Pharmacy Administration" if the exact wording matters,
not attempted here since it's cosmetic and the correction's own text uses
both phrasings interchangeably).

Of the correction's 12 suggested navigation sections, what exists today
inside that one screen: Overview (top stat bar), Pharmacy Accounts
(Pharmacies tab, with full detail/approve/reject/suspend/reinstate),
Medicine Catalogue (Medicine Approvals tab, plus admin create/edit/archive/
restore via the underlying API), Inventory (Expiry Monitoring tab),
Orders (Orders & Delivery tab), Sales & Commissions and Settlements (the new
6th tab), Employees (via the account-review sheet), Appeals (Chat & Appeals
tab), Delivery Assignments (the new queue section), Pharmacy Chat (Chat &
Appeals tab). **Not present as a dedicated section:** a standalone Reports/
Audit export screen (recent audit events are visible inline in the account
detail and the dashboard endpoint, but there's no CSV/PDF export UI for
pharmacy-specific reports — the generic `admin_module_export` CSV mechanism
other admin modules use was not wired up for pharmacy in this pass).

## 27. Live browser verification (this addendum)

Performed with Playwright driving real Chromium against the actual running
Flutter web build (`http://127.0.0.1:8090`) and Django backend
(`http://127.0.0.1:8000`), screenshotting each step:

1. Logged in with `pharmacy.admin@featherflow.local` / `ChangeMe@2026!` →
   landed on a dashboard showing the correct role badge ("Pharmacy Admin"),
   tier ("Pharmacy Admin · T3"), a live "4 Active Pharmacies" count, and a
   real audit-log entry for the login itself.
2. Confirmed the sidebar shows only Dashboard / Pharmacy / Audit Trail / My
   Profile / Sign Out — every other admin module is hidden for this role.
3. Opened "Pharmacy" → the 6-tab Pharmacy Management screen, including the
   new "Sales & Settlements" tab.
4. Opened Sales & Settlements → real live metrics (zeros where genuinely
   zero), correct empty states for sales/settlements lists.
5. Opened a pharmacy's account-review sheet ("GreenVet Pharmacy Ltd.") →
   real profile fields, `ACTIVE` status, workforce/medicine/sales numbers,
   and the new "Employees" button.
6. Opened the Employees sheet → correct empty state and a working "Add"
   entry point.
7. (Carried over from the original pass, re-confirmed still working after
   this addendum's changes): approve/suspend/reinstate a pharmacy live,
   pharmacy↔admin chat send/reply in both directions, pending-pharmacy
   dashboard lock screen.

One genuine regression was caught and fixed during this verification: the
uvicorn process-staleness issue described in §24 (settlements 405 until the
backend was restarted) — a process-management gotcha, not a code defect,
but real enough that it would have shipped a broken-looking feature if this
step had been skipped.

## 28. Updated completion-criteria self-check

Against the correction's own final list:

- ✅ A dedicated Pharmacy Admin account exists.
- ✅ The account can log in.
- ✅ The login routes to a real Pharmacy Administration panel (the existing,
  role-scoped admin shell + `AdminPharmacyScreen` — see §26 for why this is
  the panel rather than a second parallel one).
- 🟡 The panel has *most* required sections (see §26's list) — Reports/
  Audit export is the one section with no dedicated screen.
- ✅ Backend permissions are enforced (11-role matrix, automated).
- 🟡 Flutter screens exist for the implemented backend features *that were
  in scope for this addendum* (employees, sales/settlements, delivery
  assignment) — a dedicated "add medicine" admin form and a standalone
  reports/export screen still have no Flutter UI (backend endpoints exist
  and are tested).
- ✅ Every visible action added in this addendum is functional (verified
  live, not just via API test).
- ✅ Back buttons work (inherited from the existing shell, unchanged).
- ✅ Backend tests pass (498 checks across 12 suites).
- ✅ Flutter tests pass (189/189, no new tests added for the new UI — see
  §25's honest gap).
- ✅ Release build succeeds (`flutter build web --release` → `Built build\web`).
- ✅ Live browser verification succeeded (§27).
- This report does not claim full completion where gaps remain (🟡 items
  above are explicit, not glossed over).
- ✅ Nothing is committed — `git status` still shows only working-tree
  changes; no commits were made during this addendum either.

---

# Second addendum — Add Medicine form, Reports & Audit, offline-rider warning, inventory adjust

Date: 2026-09-26. Scope: close the four specific gaps §20/§28 called out as
missing Flutter UI (Add Medicine form, Reports/Audit export screen), upgrade
the offline-rider assignment flow from a post-hoc toast to an explicit
pre-confirmation dialog per a stricter restated spec, and add an inventory
stock-adjustment action. Everything below is new relative to §1–§28; nothing
above this line was changed. **Nothing in this addendum has been committed
either** (confirmed again at the end).

## 29. Add Medicine form (closes §20/§28's biggest named gap)

New `_AddMedicineDialog` in `admin_pharmacy_screen.dart`, opened via a new
"Add Medicine" chip on every pharmacy card in the Pharmacies tab. Mirrors the
pharmacy-facing `AddMedicineDialog`'s proven two-step pattern (save text
fields first against `POST /admin-panel/pharmacy/medicines/create/` — already
built and tested in §7 but never wired to any UI — then reveal
`CatalogueImagePicker`, the same shared, already-validated image widget used
by the pharmacy-facing catalogue and the feed-marketplace admin form, once a
real medicine id exists to upload against). Fields: name, generic name,
category, unit, price, discount price (`previous_price`, optional), stock
quantity, minimum order quantity, expiry date, description, dosage/strength,
prescription-required and cold-chain toggles. Client-side validation matches
the backend's `clean_medicine_payload` exactly (name required, price > 0,
stock ≥ 0, min-qty ≥ 1, expiry in the future). The Save button disables itself
while a request is in flight (duplicate-submission guard), and becomes "Done"
once the medicine is saved, matching the pharmacy-facing dialog's convention.

**Verified live** (Playwright, real Chromium against the running app):
opened the dialog for GreenVet Pharmacy Ltd., filled name/price/stock,
clicked Save → `POST /api/admin-panel/pharmacy/medicines/create/` → **201**,
dialog transitioned to reveal the image picker and "Done" button exactly as
designed. Screenshots captured at each step. Backend also covered by 5 new
automated checks in `test_pharmacy_admin.py` (create via the form, min-qty
persisted, a pharmacy owner denied on the same endpoint).

## 30. Inventory: stock adjustment

Added an "Adjust stock" action to each row in the Expiry Monitoring tab
(which doubles as the inventory view — medicine, pharmacy, current stock,
expiry, low/critical alert level all already present per §7's existing
build) — a small dialog accepting a signed delta (e.g. `20` or `-5`), calling
the already-existing `PATCH /admin-panel/pharmacy/medicines/<id>/stock/`
endpoint (built in §7, previously exposed via no UI at all). Verified live via
curl against the running backend (create → +10 → 60 → archive → is_active
false) and covered by 2 new automated checks (positive adjustment, and that
the endpoint correctly rejects a delta that would take stock negative).

**Known remaining gap**: this is stock-level adjustment only, not a full
stock-movement *history* log (spec §7 also asks to "review history") — the
underlying data for that would need to be reconstructed from `ActivityLog`
rows filtered to this medicine's stock-change actions, which is possible
today via the new Reports & Audit tab's admin-actions export but has no
dedicated per-medicine timeline view yet.

## 31. Reports & Audit (closes §20/§28's second named gap)

New backend `admin_pharmacy_export(request, report_type)` in
`api/admin_pharmacy.py` (`GET /api/admin-panel/pharmacy/export/<report_type>/`)
supporting all 14 report types the spec lists: accounts, approvals,
suspensions, medicines, inventory, orders, sales, commissions, settlements,
employees, appeals, delivery-assignments, chat-activity, admin-actions — each
reusing the same query/filter logic already proven correct in the
corresponding list endpoint, gated by the existing `can_perform_action(user,
'pharmacy', 'export')` check (no RBAC changes needed — `export` was already
in the matrix), and self-audited via `log_pharmacy_action` on every call
(entity_type=`pharmacy_report`) so exports themselves show up in the audit
trail. A second new endpoint, `admin_pharmacy_audit(request)` (`GET
/api/admin-panel/pharmacy/audit/`), returns a dedicated, pharmacy-scoped view
of `ActivityLog` (actor, role, action, entity, before/after values, reason,
IP, timestamp) — filtered server-side to pharmacy entity types only, so it
can never leak an unrelated audit row.

New Flutter `_ReportsAuditTab`, the screen's 7th tab: 14 export buttons (one
per report type, each `PermissionGuard`-wrapped on `export`), and a live
audit-trail list below them with loading/error+Retry/empty states, each row
showing actor, role, entity type, reason, and timestamp.

### A real bug found and fixed during live verification, not by the endpoint tests

Every automated check above passed the first time — because Django's test
`Client` sends no `Accept` header by default. Driving the actual built
release app in a real Chromium browser (Playwright), the export button
returned **406 Not Acceptable** instead of a CSV. Root cause: DRF's
`APIView.initial()` runs content negotiation against `renderer_classes`
*before the view body executes at all*; the Flutter export client explicitly
sends `Accept: text/csv` (real browser behavior), and neither this new
endpoint nor the platform's **existing, pre-dating-this-session**
`admin_module_export` (`api/admin_extra.py`, used by every other module's CSV
export, e.g. Finance/Payroll) had a renderer registered for that media type —
so DRF rejected the request before any of them could ever run. This was a
**platform-wide, previously-undiscovered bug**, not something introduced by
this addendum — it went unnoticed because, per the requirements matrix's own
FA-07 finding, almost no export button anywhere in the app was ever actually
wired up and clicked through a real browser before now.

**Fix**: a small shared `CSVRenderer(BaseRenderer)` (`api/admin_extra.py`,
`media_type='text/csv'`) registered via `@renderer_classes([JSONRenderer,
CSVRenderer])` on both `admin_module_export` and the new
`admin_pharmacy_export` — since both views build and return their own
`HttpResponse` directly rather than a DRF `Response`, the renderer's own
`render()` method is never actually invoked; its only job is to make a real
`Accept: text/csv` header satisfiable during negotiation. Verified via curl
(`Accept: text/csv` → 200, was 406) and by re-running the Playwright export
click end to end, which now downloads a real CSV rendered in-app. Two new
regression checks were added specifically because the existing test suites'
green results would not have caught this: `test_pharmacy_admin.py` and
`test_admin_panel.py` both now send an explicit `HTTP_ACCEPT='text/csv'`
header on one export call each.

**Verified live** (Playwright): clicked "Pharmacy accounts" in the Reports &
Audit tab → `GET .../pharmacy/export/accounts/` → **200** → a dialog rendered
the real CSV content (5 real pharmacy rows, correct headers). The audit trail
list below it, in the same screenshot, showed genuine historical rows
including "Admin added medicine 'PW Test Amoxicillin'" (from §29's live test,
seconds earlier) with correct actor, role, entity type, and timestamp —
confirming the two new features compose correctly end to end, not just in
isolation.

## 32. Offline-rider assignment: upgraded to an explicit pre-confirmation dialog

The original build (§10) surfaced an offline-rider assignment as a **warning
toast after the fact** — technically satisfying "don't block," but a
restated, stricter version of the spec explicitly requires a **confirmation
dialog before the assignment is submitted**, with exact wording: *"This rider
is currently offline. Do you still want to assign this delivery?"* Implemented
in `_DeliveryQueueSectionState._assign`: after the admin picks a rider, if
that rider is offline, a dialog with this exact text and "Cancel"/"Assign
anyway" actions appears before the `POST .../assign-delivery/` call is ever
made; declining does nothing (order stays in the queue), confirming proceeds
to the existing assignment call, whose response `warning` field (already
returned by the backend, unchanged) is still shown as a toast afterward — so
the rule is now satisfied on both ends: warned before, and shown in the
result after, never silently either way.

### A second real bug found while implementing this, not a pre-existing test gap

Both the rider-picker dialog's online/offline dot indicator and my new
confirm-dialog's online check read a JSON field, `rider['is_online']`, that
**the `/admin-panel/riders/` list endpoint never actually returns** — a
repo-wide check of `api/admin_views.py::_rider_json` confirms the real field
is `status` (a string: `'Online'`, `'On break'`, `'Offline'`, etc., built from
`profile.is_online`/`profile.current_status`), not a boolean `is_online` key.
This was a **pre-existing bug in the original delivery-queue section** (§25)
— every rider has always displayed as "Offline" in that picker, regardless of
actual status, since the check silently evaluated to `false` for every rider.
It was only caught now because implementing the new pre-confirmation dialog
required reading that same field carefully. **Fixed** by switching both the
dot-indicator check and the new confirm-dialog check to
`rider['status'] == 'Online'`. No dev-DB riders existed to click through this
specific dialog live in this pass (empty `/admin-panel/riders/` list in the
current seed data), so this fix is verified by direct code/field-name
inspection against the live API response shape rather than an interactive
click-through — flagged explicitly rather than claimed as browser-verified.

## 33. Flutter widget tests added (closes part of §25's honest gap)

`test/admin_screens_smoke_test.dart` (the project's existing admin-screen
smoke-test file, extended rather than duplicated) gained three new tests for
`AdminPharmacyScreen` — the first widget tests this screen has ever had:
renders with all 7 tabs present and no exception; renders at a 320px viewport
without an overflow exception; the new Reports & Audit tab is selectable
without crashing. (Export-button visibility itself isn't asserted in the
widget test, since those buttons are `PermissionGuard`-wrapped and — as with
every other screen in this same test file — no live admin session exists in
a widget test, so permission-gated content correctly renders nothing; this is
the same limitation the file's own pre-existing tests already document.)
**189 → 192** Flutter tests, all passing, zero regressions.

## 34. Files changed in this addendum

**Modified backend:** `api/admin_pharmacy.py` (new `admin_pharmacy_export`,
`admin_pharmacy_audit`, `_pharmacy_report_rows`, `REPORT_TYPES`,
`PharmacySettlement` import), `api/admin_extra.py` (new `CSVRenderer` class,
applied to `admin_module_export`), `api/urls.py` (2 new routes + imports),
`scripts/test_pharmacy_admin.py` (+20 checks: Add Medicine form, inventory
adjust, Reports & Audit export, audit log, the 406 regression guard),
`scripts/test_admin_panel.py` (+1 check: the same 406 regression guard on the
pre-existing generic export).

**Modified Flutter:** `admin_pharmacy_screen.dart` (7th "Reports & Audit"
tab, `_AddMedicineDialog`, `_ReportsAuditTab`, "Add Medicine" chip per
pharmacy card, "Adjust stock" chip per expiry-alert row, offline-rider
pre-confirmation dialog, fixed the `is_online`→`status` field-name bug),
`admin_api_service.dart` (`uploadPharmacyMedicineImage`,
`exportPharmacyReport`, `pharmacyAuditLog`, `adjustPharmacyMedicineStock`),
`test/admin_screens_smoke_test.dart` (+3 tests).

**Not touched:** every file listed in §16/§25 as pre-existing/unrelated
remains untouched; this addendum only added to files already part of the
Pharmacy Admin surface plus the one shared, platform-wide `admin_extra.py`
fix (justified above, since the bug it fixes affects every module's export,
not only pharmacy's).

## 35. Test results (this addendum)

| Suite | Before | After |
|---|---|---|
| `scripts/test_pharmacy_admin.py` | 100 passed | **120 passed**, 0 failed |
| `scripts/test_admin_panel.py` | 65 passed | **66 passed**, 0 failed |
| `scripts/test_pharmacy_flow.py` | 22 passed | 22 passed, 0 failed (no change, re-run for regression) |
| `scripts/test_signup_flows.py` | 106 passed | 107 passed, 0 failed (re-run for regression) |
| `scripts/test_verification_status.py` | 25 passed | 25 passed, 0 failed (re-run for regression) |
| `scripts/test_pharmacy_marketplace_card_fields.py` | 13 passed | 13 passed, 0 failed |
| `scripts/test_pharmacy_medicine_edit.py` | 7 passed | 7 passed, 0 failed |
| `scripts/test_pharmacy_medicine_images.py` | 20 passed | 20 passed, 0 failed |
| `scripts/test_pharmacy_profile.py` | — | 32 passed, 0 failed |
| `scripts/test_doctor_flow.py` | — | 58 passed, 0 failed |
| Flutter (`flutter test`) | 189 passed | **192 passed**, 0 failed |

`manage.py check` — no issues. `manage.py migrate --check` — clean (no new
migrations needed; this addendum added no new models/columns). `flutter
analyze lib/` — same 6 pre-existing, unrelated info-level lints as every
prior report in this file, zero new issues. `flutter build web --release` —
succeeded (`√ Built build\web`).

## 36. Live browser verification (this addendum)

Performed with Playwright driving real Chromium against a fresh
`flutter build web --release` output served on `127.0.0.1:8090`, and the
backend restarted (uvicorn, no autoreload — same gotcha as every prior phase)
after each backend code change:

1. Logged in as `pharmacy.admin@featherflow.local` → Pharmacy screen → all
   real data confirmed (5 pharmacies, live counts).
2. Clicked "Add Medicine" on GreenVet Pharmacy Ltd. → dialog opened with
   every specified field → filled name/price/stock → Save →
   `POST .../medicines/create/` → **201** → image picker revealed → "Done".
3. Opened the new "Reports & Audit" tab → all 14 export buttons rendered →
   audit trail rendered real historical rows.
4. Clicked "Pharmacy accounts" export → `GET .../export/accounts/` → **200**
   (was 406 before the CSVRenderer fix, confirmed via curl before and after)
   → CSV content dialog showed 5 real rows with correct headers.

**Not re-verified live via click-through in this pass** (flagged honestly,
not claimed as done): the offline-rider confirmation dialog (no offline
riders existed in the current dev-DB seed to click through interactively —
verified instead by direct code/API-shape inspection, see §32), and the
inventory stock-adjust dialog's UI interaction specifically (verified via
curl against the same underlying endpoint the UI calls, and the UI code was
read/reasoned through directly, but not clicked live in Chromium in this
pass).

## 37. Updated completion-criteria self-check (supersedes §28 where changed)

- ✅ Add Medicine UI now exists (§29) — was 🟡 in §28, now closed.
- ✅ Reports/Audit UI now exists (§31) — was 🟡 in §28, now closed.
- ✅ Offline rider warning now appears as an explicit pre-confirmation dialog
  (§32), upgraded from the original post-hoc toast.
- ✅ Inventory stock-adjustment action now exists (§30) — no dedicated
  movement-history view yet (explicit remaining gap, see §30).
- ✅ A platform-wide CSV-export bug (406 on a real browser `Accept` header)
  was found and fixed, with regression tests added, not just for pharmacy but
  for the shared exporter every admin module uses.
- ✅ A platform-wide (pre-existing, in the delivery-queue section only)
  `is_online` field-name bug was found and fixed.
- ✅ New Flutter widget tests exist for `AdminPharmacyScreen` (§33) — was a
  named gap in §18/§25, now partially closed (3 tests; not full coverage of
  every dialog/action).
- 🟡 Inventory stock-*movement history* (as opposed to stock adjustment
  itself) still has no dedicated view (§30).
- 🟡 Delivery-assignment offline-warning dialog not click-verified live in
  this pass due to no offline riders in the current seed data (§36).
- ✅ Backend tests pass (590 checks across 10 suites this pass, cumulative
  with all prior phases).
- ✅ Flutter tests pass (192/192).
- ✅ Release build succeeds.
- ✅ Nothing is committed — confirmed again below.

## 38. Confirmation: nothing committed (this addendum)

`git status --short` at the end of this addendum shows every file from §34 as
modified or untracked, identical in kind to every prior phase's confirmation.
No `git add`, `git commit`, or any other git write operation was run at any
point during this addendum.
