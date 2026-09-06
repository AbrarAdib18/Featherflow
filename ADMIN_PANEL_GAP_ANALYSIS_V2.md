# Admin Panel — Gap Analysis v2 (Bug fixes + Shift/Payment system)

**Status:** Bugs fixed & tested. Gap analysis below is for your review before I
build the Shift Timer / Hourly Payment system. **Nothing new has been built yet.**

---

## Part A — Critical bugs (DONE + tested)

### Bug 1: Delivery Admin could not assign riders — **FIXED**

**Root cause:** the assignment endpoints
(`PATCH /api/admin-panel/delivery-orders/<id>/` → `_assign_from_queue` /
`_reassign_order`) were gated by a helper `_is_delivery_ops_admin(user)` that
checked a **hard-coded list of role names** (`admin_super`, `admin_operations`,
`admin_delivery`). Before the RBAC unification, self-registered admins received
the generic `admin` role, which is not in that list → every assignment returned
`403 "You are not authorized to manage delivery assignments."` The `_gate()`
RBAC check added earlier already permits it, but the stale secondary helper still
blocked it.

**Fix:** `_is_delivery_ops_admin` and `_is_research_content_admin` now delegate
to `can_perform_action(user, module, action)` — no hard-coded role names, one
source of truth (the `roles.permissions` matrix). `admin_delivery` /
`admin_operations` / `admin_super` have `delivery: [...,"assign",...]` and now
pass; `admin_finance` / `admin_pharmacy` / etc. correctly still get 403.

**Verified end-to-end** (`test_admin_panel.py`, 6 new assertions):
- delivery admin assigns a queued order → **201**, a real `delivery_orders` row
  is created, the queue row is consumed, the rider gets a "New delivery
  assignment" notification.
- finance admin attempting the same → **403**.
- reassign of an active order by delivery admin → **200**.

### Bug 2: Admin approvals not reflecting in real-time — **FIXED**

**What was already there:** `ResearchSession`, `PharmacySession`,
`DeliverySession` each already run their own `Timer.periodic` (4–6 s) calling
`refresh(silent:true)`, so admin approvals for those roles *did* reflect. The
gaps were:
1. **Doctor** had no polling and no backend hook.
2. **No user-facing toast** ("Your account has been verified by admin").
3. `UserUpdatesService` (added earlier) polled `/api/me/updates/` but only drove
   the suspend→redirect, nothing else.

**Fix:**
- `UserUpdatesService` reworked: 10 s interval, tracks `verified` /
  `accountStatus` / `profile` from the live backend, dedupes notifications,
  exposes `consumeToast()` and `addRefreshHook()`.
- `RealtimeToastHost` wraps every screen (via `MaterialApp.router`'s `builder`)
  and shows a `SnackBar` for every admin-action notification.
- `ResearchSession` / `PharmacySession` / `DeliverySession` register a refresh
  hook, so an admin action detected by the shared poll pokes them immediately
  (belt-and-suspenders with their own timers).
- `DoctorSession` now listens to `UserUpdatesService` and exposes
  `isPlatformVerified` / `accessRevoked` from the live `/api/me/updates/` payload
  (the doctor module is still on demo data for its lists — see §D).

**Verified live** (Django running, timed simulation):
| Flow | Result | Lag (API) |
|---|---|---|
| Admin verifies researcher → researcher poll shows `is_verified=true` + "You are verified" toast | ✅ | 0.09 s (≤10 s in app) |
| Research admin suspends **verified** researcher → 202 queued → Operations approves → researcher's next call → **401** → router redirects to `/login?revoked=1` | ✅ | — |
| Delivery admin assigns order → rider's poll returns "New delivery assignment" notification | ✅ | 0.22 s |

**Notification event types now emitted** by admin actions:
`approval` (verify/reject/publish/suspend decisions), `alert` (new assignment,
escalation), `system` (payout, cancellation). The `shift_started` /
`shift_ended` / `admin_modified` types in your spec do **not exist yet** — they
come with the shift system (§C).

---

## Part B — What already exists (after the earlier passes)

| Area | State |
|---|---|
| RBAC (10 tiered roles, `roles.permissions` matrix, `can_perform_action` on every endpoint) | ✅ done |
| `AdminProfile` (rich: role FK, lifecycle, approval_status, suspend fields) | ✅ done — **no shift/pay fields yet** |
| `AdminRole` concept = `roles` row w/ `permissions` + `tier_level` + `is_system` | ✅ done — **no `hourly_rate_range_*`** |
| `AdminApprovalQueue` table + endpoints + UI | ✅ done |
| `AdminEscalation` table + endpoints + UI | ✅ done |
| Immutable `activity_logs` (trigger + model guard, `reason`/`user_agent`/`action_type`) | ✅ done — **no `shift_start`/`shift_end`/`payment_made` action types yet** |
| Admin Management screen (create/edit/suspend/recover/approve) | ✅ done — **no hourly-rate editor, no all-admins hours table** |
| Audit Trail viewer + per-module activity sheets | ✅ done |
| Oversight + Escalations screens | ✅ done |
| Support desk (real `support_tickets` tables) | ✅ done |
| Finance module (real `payments`/`subscriptions`/`delivery_earnings`) | ✅ done |
| Security monitor (brute-force / impossible-travel / spikes from real data) | ✅ done |
| Polling: `/api/me/updates/` + `/api/{research,delivery,pharmacy,doctors}/updates/` | ✅ done |
| CSV export for every module | ✅ done |
| Scoped rate-limiting on admin endpoints | ✅ done |
| Frontend screens: Dashboard, Users, Doctors, Delivery, Pharmacy, Content, Community, Finance, Team, Support, Profile, **Admin Management, Approval Queue, Audit Trail, Oversight** | ✅ done |

---

## Part C — What's MISSING (the Shift Timer & Hourly Payment system)

Nothing of this exists. Everything below is net-new.

### C1. Database (net-new)

| Object | Notes |
|---|---|
| `admin_shifts` table (`AdminShift`) | shift_date, start_time, end_time, break_start, break_end, break_duration_minutes, total_hours, is_active, ip_address, timestamps. Mirror the existing `delivery_attendance` table pattern (check_in/check_out timestamps). |
| `admin_payments` table (`AdminPayment`) | period_start, period_end, total_hours, hourly_rate (snapshot), total_payment, payment_status(pending/paid/failed), payment_date, payment_method(cash/bank_transfer/mobile_wallet), payment_reference, notes, timestamps. Mirror `worker_payments` which already exists. |
| `admin_profiles` **+4 cols** | `hourly_rate DECIMAL(10,2) DEFAULT 0`, `max_hours_per_week INT NULL`, `last_shift_start TIMESTAMP NULL`. (`is_on_shift` computed from `admin_shifts` — no column, or a cached bool.) |
| `roles` **+2 cols** | `hourly_rate_range_min DECIMAL(10,2)`, `hourly_rate_range_max DECIMAL(10,2)`. |
| Indexes | `admin_shifts(admin_id, shift_date)`, `admin_shifts(is_active)`, `admin_shifts(start_time)`, `admin_payments(admin_id, period_start)`, `admin_payments(payment_status)`. |
| `activity_logs` | extend `action_type` recognised values to include `shift_start`, `shift_end`, `break_start`, `break_end`, `payment_made`, `rate_changed`, `force_end_shift` (free-text column, no CHECK — just the enum in the model + audit helper). |

All of this lands in `featherflow_schema.sql` + `postgres_backend_extension.sql`
(idempotent), plus `managed=False` Django models — the established pattern.

### C2. Backend endpoints (net-new)

**Every admin (own shift):**
- `GET  /api/admin-panel/my-shift/status/` — on/off, live seconds today, hours week/month, current break
- `POST /api/admin-panel/my-shift/start/` — start shift (rejects if already active)
- `POST /api/admin-panel/my-shift/end/` — end shift (computes `total_hours`)
- `POST /api/admin-panel/my-shift/break-start/` · `.../break-end/`
- `GET  /api/admin-panel/my-shift/hours/` — this-week / this-month totals
- `GET  /api/admin-panel/my-shift/history/` — own shift log
- `GET  /api/admin-panel/my-payments/` — own payment history

**Super Admin only:**
- `GET   /api/admin-panel/all-admins/` — every admin + role + hourly_rate + hours_week + hours_month + payment_due + is_on_shift + last_seen
- `GET   /api/admin-panel/online-admins/` · `.../offline-admins/`
- `GET   /api/admin-panel/shifts/` (filters: admin, date range) · `GET .../shifts/<id>/`
- `POST  /api/admin-panel/shifts/force-end/` — force-end a forgotten shift
- `PATCH /api/admin-panel/admins/<id>/hourly-rate/` — set/change rate (validated against `roles.hourly_rate_range_*`)
- `GET   /api/admin-panel/payments/` (filters) · `POST .../payments/` (generate a period's record) · `PATCH .../payments/<id>/` (mark paid) · `GET .../payments/export/` (CSV)

**Permission helpers to add:** `is_on_shift(user)`, `can_start_shift(user)`.
Reuse existing `is_super_admin` / `is_operations_admin` / `can_perform_action`.

**Hours calculation rules (need your confirmation — see §E):**
- Week = Monday 00:00 → Sunday 23:59 (server TZ = `Asia/Dhaka`).
- `total_hours = (end - start) - break_minutes`, rounded to 2 dp.
- A shift spanning midnight counts toward the day it **started** (simplest; alt: split — see §E).
- Auto-close: a shift left `is_active` for > 16 h is flagged for Super Admin to force-end (not auto-ended, to avoid losing legitimate long shifts).

### C3. Frontend (net-new)

| Screen / widget | Where |
|---|---|
| **`ShiftTimerWidget`** (Start / End / Break buttons, live `HH:MM:SS`, hours-this-week) | pinned on **every** admin dashboard + module screen app bar |
| **Super Admin → "Team & Payroll" screen** | new nav item, Super-only |
| ‣ All-admins table: name, role, rate, hrs/week, hrs/month, payment due, on-shift dot | |
| ‣ Who's-online / who's-offline filter toggle (polls every 10 s) | |
| ‣ Hourly-rate inline editor (per admin) | |
| ‣ Payment tab: generate period, mark paid, method + reference, CSV export | |
| ‣ Shift-history drill-down per admin (start/end/breaks/duration) | |
| ‣ Force-end-shift button | |
| **`AdminSession` additions** | `shiftStatus`, `hoursThisWeek/Month`, `hourlyRate`, `startShift()/endShift()/startBreak()/endBreak()`, own poll every 10 s while on a dashboard |
| Operations dashboard | + own `ShiftTimerWidget` (already gets Oversight) |

### C4. Real-time for shifts

- Admin starts/ends shift → `POST` returns immediately; `AdminSession` updates its
  own widget.
- Super Admin "Team & Payroll" screen polls `/all-admins/` + `/online-admins/`
  every 10 s (matches the spec) → who's-online refreshes live.
- `shift_started` / `shift_ended` notifications to Super Admin so the shared
  `/api/me/updates/` poll surfaces them too.

---

## Part D — What needs MODIFICATION (existing code)

| File | Change |
|---|---|
| `profiles/models.py` `AdminProfile` | +`hourly_rate`, `max_hours_per_week`, `last_shift_start`; `is_on_shift` property from `admin_shifts` |
| `users/models.py` `Role` | +`hourly_rate_range_min/max` |
| `api/admin_extra.py` `admin_me` | +`hourly_rate`, `shift` block (on/off, seconds today) so the dashboard widget has data on first paint |
| `api/admin_extra.py` `_admin_json` | +hours/rate/payment-due/on-shift for the all-admins table |
| `api/admin_views.py` `_log` / audit helper | accept the new `action_type` values |
| `admin/data/services/admin_session.dart` | shift state + timer methods + 10 s self-poll |
| `admin/data/models/admin_role.dart` | +`teamPayroll` module |
| `admin_sidebar.dart` | + "Team & Payroll" nav (Super only) |
| `app_router.dart` | + `/admin/payroll` route |
| every module dashboard screen | mount `ShiftTimerWidget` |
| `featherflow_schema.sql` + `postgres_backend_extension.sql` | the C1 DDL |
| `DATABASE_SETUP.md` | note the new tables |
| `scripts/test_admin_panel.py` | + shift/payment assertions |

**Doctor module** (pre-existing gap, not shift-related): `DoctorSession` is on
`doctor_demo_data.dart` with no `doctor_api_service.dart`. Real-time
verification/suspension now *works at the account level* (401 → redirect, toast),
but the doctor's appointment/case **lists** are demo data. Wiring the doctor
module to the backend is a separate module-level task — flag for a later pass
unless you want it in scope.

---

## Part E — Decisions I need from you

1. **Week boundary:** Monday–Sunday, `Asia/Dhaka` TZ — confirm.
2. **Midnight-spanning shift:** count toward the **start day** (simple), or
   **split** the hours across both calendar days (spec hints at "counted
   correctly for both days")? Split is more work but matches the spec literally.
3. **Payment period:** weekly (Mon–Sun) by default — or monthly? The models
   support any period; I'll default to **weekly** unless you say otherwise.
4. **Who generates the `AdminPayment` record:** Super Admin clicks "Generate this
   week's payroll" (manual), or a scheduled job? No scheduler infra exists →
   I'll do **manual generate** + a "recompute" button (Pass 2: cron).
5. **Rate change effective date:** immediate (affects the current open period) or
   next period? I'll do **next period** (the current period keeps the rate it
   started with) unless you prefer immediate.
6. **Break:** single break per shift, or multiple? Spec has one `break_start` /
   `break_end` pair → **single break** per shift; total unpaid break time
   subtracted. Confirm.
7. **Super Admin's own shifts:** spec says "except Super Admin who is
   owner/founder" — so Super Admin gets **no** shift widget and **no** payment
   records, but the spec's frontend list also says "Shift Timer Controls (for
   Super Admin's own shifts)". Contradiction — I'll assume **Super Admin has an
   optional shift timer for visibility but no payment/rate**. Confirm.
8. **`max_hours_per_week`:** just an alert when exceeded (no hard block) —
   confirm.
9. **Doctor module backend wiring** — in scope for this pass or deferred?

---

## Part F — Priority order (once approved)

| # | Item | Why |
|---|---|---|
| P0 | `admin_shifts` + `admin_payments` tables + `AdminProfile`/`Role` columns | everything depends on the schema |
| P0 | Own-shift endpoints (start/end/break/status/hours) + `is_on_shift` helper | the core clock |
| P0 | `ShiftTimerWidget` + `AdminSession` shift state on every dashboard | the visible feature |
| P1 | Super Admin `all-admins` / `online` / `offline` + "Team & Payroll" screen | the oversight the spec centres on |
| P1 | Hourly-rate editor + validation against `roles.hourly_rate_range_*` | Super-only control |
| P1 | `AdminPayment` generate / mark-paid / CSV export | payroll |
| P1 | Shift + payment audit-log events; `shift_started/ended` notifications | audit + real-time |
| P2 | Force-end-shift, `max_hours_per_week` alerts, shift-history drill-down | edge handling |
| P2 | e2e tests for the shift/payment flows | validation |
| Deferred (your list) | overtime rules, tax withholding, cron payroll, WebSockets | agreed |

---

## Rough size

| Phase | Backend | Frontend | DB |
|---|---|---|---|
| Bug fixes | done | done | — |
| Shift/Payment | ~12 endpoints, 2 models, ~250 LOC service logic | 1 widget + 1 screen + AdminSession additions + mount on ~12 screens | 2 tables, 6 columns, 5 indexes |

*Awaiting your answers to §E and a "proceed" on §F.*
