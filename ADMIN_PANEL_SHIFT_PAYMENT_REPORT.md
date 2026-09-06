# Admin Panel — Bug fixes + Shift Timer / Hourly Payment — Implementation Report

**Status: complete and tested.**
Backend `65/65` e2e assertions + full existing suite green + live-HTTP verified per
role. Frontend `flutter analyze` 0 errors, `flutter build web` OK, `12/12`
widget/logic tests. App running: Flutter `http://localhost:5173`, Django
`http://127.0.0.1:8000`.

---

## 1. What I inspected

`backend/api/admin_views.py` (assignment path), `_is_delivery_ops_admin` /
`_is_research_content_admin` helpers; `delivery/{models,views}.py` and the
`delivery_attendance` / `worker_payments` tables (shift/pay precedents);
`ResearchSession` / `PharmacySession` / `DeliverySession` / `DoctorSession`
polling; `UserUpdatesService`; `admin_profiles` / `roles` schema; the SQL files.

## 2. Bug fixes completed

### Bug 1 — Delivery Admin could not assign riders → FIXED

**Root cause:** the assignment endpoints were guarded by
`_is_delivery_ops_admin(user)`, which checked a **hard-coded list of role names**
(`admin_super`/`admin_operations`/`admin_delivery`). Any account whose role
wasn't literally in that list — e.g. the generic `admin` role self-registration
used to grant — got `403 "You are not authorized to manage delivery assignments"`,
even though the RBAC matrix permits `delivery:assign`.

**Fix:** `_is_delivery_ops_admin` and `_is_research_content_admin` now delegate to
`can_perform_action(user, module, action)` — one source of truth, no hard-coded
role names (also satisfies the "don't hardcode role names" constraint).

**Tested** (`test_admin_panel.py`, 6 assertions): delivery admin assigns a queued
order → 201, real `delivery_orders` row created, queue row consumed, rider
notified; finance admin → 403; reassign of an active order → 200.

### Bug 2 — Admin approvals not reflecting in real-time → FIXED

**What already worked:** `ResearchSession` / `PharmacySession` / `DeliverySession`
self-poll every 4–6 s. **Gaps:** Doctor had no polling/hook; no user-facing toast;
`UserUpdatesService` only drove the suspend-redirect.

**Fix:**
- `UserUpdatesService` reworked — 10 s interval, tracks live
  `verified`/`accountStatus`/`profile`, dedupes notifications, exposes
  `consumeToast()` + `addRefreshHook()`.
- `RealtimeToastHost` wraps every screen (via `MaterialApp.router`'s `builder`) →
  SnackBar on any admin-action notification ("Your account has been verified by
  admin", "New delivery assignment", …).
- research / pharmacy / delivery sessions register a refresh hook.
- `DoctorSession` now reflects `isPlatformVerified` / `accessRevoked` from the
  live `/api/me/updates/` payload.

**Tested live** (Django running, timed): verify researcher → poll shows
`is_verified=true` + toast in 0.09 s (≤10 s in-app); suspend verified researcher
(→ 202 queued → Ops approves) → researcher's next call 401 → redirect to
`/login?revoked=1`; delivery assign → rider poll returns "New delivery
assignment" in 0.22 s.

## 3. Gap analysis summary (what was missing)

The Shift Timer + Hourly Payment system was entirely absent — no tables, no
endpoints, no UI. Everything below is net-new. (RBAC, audit, approval queue,
oversight, escalations, support desk, finance module, security monitor, polling
were built in the earlier passes.)

## 4. Frontend screens created / modified

**Created**
- `admin/presentation/widgets/shift_timer_widget.dart` — Start / End / Break
  controls, live `HH:MM:SS` (1 s local tick + 10 s server sync), hours
  week/month, rate, over-limit warning. Renders nothing for Super Admin.
- `admin/presentation/screens/admin_payroll_screen.dart` — Super-only "Team &
  Payroll": **Team** tab (summary cards, who's-online / who's-offline filter,
  per-admin hours/rate/OT/payment-due, rate editor, force-end-shift) and
  **Payroll** tab (Generate Weekly Payroll, pending vs history, mark-paid with
  method + reference, CSV export). Polls every 10 s.
- `core/network/realtime_toast.dart` — the toast host.

**Modified**
- `admin/data/services/admin_session.dart` — shift state
  (`isOnShift`/`onBreak`/`hoursThisWeek`/…), `startShift/endShift/startBreak/
  endBreak`, a 10 s self-poll while an hourly admin is signed in.
- `admin/data/services/admin_api_service.dart` — ~18 shift/payroll methods +
  `exportPayroll()`.
- `admin/data/models/admin_role.dart` — `teamPayroll` module.
- `admin/presentation/widgets/admin_scaffold.dart` — `_ShiftChip` on-shift pill in
  every admin screen's app bar (taps to dashboard).
- `admin/presentation/screens/admin_dashboard_screen.dart` — mounts
  `ShiftTimerWidget` at the top.
- `admin_sidebar.dart` — "Team & Payroll" nav (Super only).
- `app_router.dart` — `/admin/payroll` route.
- `admin_audit_screen.dart` — shift/payment `action_type`s and `shifts`/`auth`
  modules in the filters.
- `core/network/user_updates_service.dart`, `main.dart`, `login_screen.dart`,
  `research/pharmacy/delivery/doctor` sessions (Bug 2).

## 5. Database models / migrations added

**SQL** (`featherflow_schema.sql` + `postgres_backend_extension.sql`, idempotent,
applied to the live DB):

| Object | Detail |
|---|---|
| `admin_shifts` **(new)** | shift_date, start_time, end_time, break_start/end, break_duration_minutes, total_hours, is_active, auto_flagged, ended_by, ip_address, timestamps. Partial unique index `(admin_id) WHERE is_active` — one open shift at a time. |
| `admin_payments` **(new)** | period_start/end, total_hours, **regular_hours, overtime_hours**, hourly_rate + **overtime_rate** (snapshots), total_payment, payment_status(pending/paid/failed), payment_date, payment_method(cash/bank_transfer/mobile_wallet), payment_reference, notes, generated_by, paid_by. `UNIQUE(admin_id, period_start)`. |
| `admin_profiles` **+5 cols** | `hourly_rate`, `max_hours_per_week`, `last_shift_start`, `pending_hourly_rate`, `pending_rate_effective_from`. |
| `roles` **+2 cols** | `hourly_rate_range_min/max` — indicative pay bands seeded per tier (Super Admin = 0). |
| indexes | `admin_shifts(admin_id, shift_date)`, `(is_active)`, `(start_time)`; `admin_payments(admin_id, period_start)`, `(payment_status)`. |
| `activity_logs` model | `ACTION_TYPES` extended with `shift_start/end`, `break_start/end`, `force_end_shift`, `rate_changed`, `payment_made`. |

**Django** (`managed=False`, state-only migration):
`profiles/migrations/0005_admin_shift_payment.py` — `AdminShift`, `AdminPayment`,
5 `AdminProfile` fields; `users.Role` +2 fields.

## 6. APIs added

All under `/api/admin-panel/`.

**Every hourly admin (own shift):**
| Method + path | |
|---|---|
| `GET  /my-shift/status/` | on/off, live seconds today, hours week/month, rate, pending rate, over-max flag |
| `POST /my-shift/start/` | 409 if already on shift |
| `POST /my-shift/end/` | computes `total_hours = worked − break` |
| `POST /my-shift/break-start/` · `break-end/` | one break per shift |
| `GET  /my-shift/hours/` | week + month + per-day breakdown |
| `GET  /my-shift/history/` · `GET /my-payments/` | |

**Super Admin only:**
| `GET  /all-admins/` | every admin + rate + hrs week/month + regular/OT + payment due + on-shift + break; plus a summary block |
| `GET  /online-admins/` · `/offline-admins/` | |
| `GET  /shifts/` (filters: admin, from, to, active) · `GET /shifts/<uuid>/` | |
| `POST /shifts/force-end/` | close a forgotten shift, attributed to the Super Admin |
| `PATCH /admins/<uuid>/hourly-rate/` | band-validated; first rate immediate, later changes effective next Monday |
| `PATCH /admins/<uuid>/max-hours/` | overtime threshold |
| `GET/POST /admin-payments/` | POST = generate the last completed week's payroll |
| `PATCH /admin-payments/<uuid>/` | `mark_paid` (method + reference) / `mark_failed` |
| `GET  /admin-payments/export/` | payroll CSV |

`GET /admin-panel/me/` also now returns `tracks_shifts` + a `shift` block so the
timer widget has data on first paint.

**Permission helpers added:** `is_on_shift(user)` (via `AdminProfile.is_on_shift`),
`_hourly_admin_or_response` (tier 2–4 with a profile; Super Admin → 403).

## 7. Admin roles & permissions

Unchanged from the earlier pass: 10 tiered `roles` rows with a
`permissions` JSON matrix and `tier_level` (1 Super … 4 Support); every endpoint
checks `can_perform_action`. New: each role carries an indicative
`hourly_rate_range_*` band that the rate editor validates against. Shift/payroll
endpoints add a hard tier gate — Super Admin only for team/payroll, and Super
Admin is **explicitly excluded** from shifts and payment (owner, not an
employee).

## 8 / 13. Audit logging

Unchanged mechanism (immutable `activity_logs`, DB trigger + model guard,
`reason`/`user_agent`/`action_type`). Shift/payment events now write audit rows:
`shift_start`, `shift_end`, `break_start`, `break_end`, `force_end_shift`
(with the Super Admin as actor + reason), `rate_changed` (old→new + when it
applies), `payment_made` (payroll generation and each mark-paid). Login attempts
(success/fail) also logged for the security monitor.

## 9 / 14. Approval queue

Unchanged: sensitive actions (delete admin, refund > ৳5 000, suspend a verified
user, team role change, override) return **202 queued**; a higher tier
approves and a bounded executor runs the parked action + audits it. Shift/payroll
actions are **not** routed through the queue — they're Super-Admin-direct.

## 10. How the shift timer works

- Admin opens their dashboard → `ShiftTimerWidget` (hidden for Super Admin).
- **Start Shift** → `POST /my-shift/start/` creates an `admin_shifts` row
  (`is_active=true`, `start_time=now`). A partial unique index guarantees one
  open shift per admin; a second start → 409.
- The widget shows a live `HH:MM:SS` — a 1 s local timer ticks up from the last
  server value; `AdminSession` re-syncs every 10 s.
- **Break** → `break-start` / `break-end`; one break per shift; break time is
  **unpaid** and subtracted. If a break is still open at end-of-shift it's
  auto-closed.
- **End Shift** → `POST /my-shift/end/` sets `end_time`, `is_active=false`, and
  `total_hours = (end − start) − break_minutes/60`, rounded to 2 dp.
- **Hours** (`/my-shift/hours/`, `all-admins`): computed by **interval overlap**,
  not from `total_hours` — a shift that spans midnight (e.g. 22:00 → 02:00) is
  one row but contributes 2 h to each calendar day and to whichever week each
  part falls in. Verified: a 22:00→02:00 shift splits **2 h + 2 h**.
- Week = Monday 00:00 → next Monday 00:00 in `Asia/Dhaka`.
- **Force-end:** a shift open > 16 h is flagged; Super Admin can
  `POST /shifts/force-end/` with a reason (audited, admin notified).

> Implementation note: all writes on shift rows use `save(update_fields=[…])`.
> A bare `save()` of an ORM-fetched row re-writes the naive `start_time` column
> through Django's "assume local timezone" path and shifts it by the UTC offset
> — a real bug that was caught and fixed in testing (`week hours stable at 2.5
> after close (no tz drift)`).

## 11. How hourly payment works

- **Rate:** Super Admin sets it via `PATCH /admins/<id>/hourly-rate/`. Validated
  against the role's `hourly_rate_range_*` band. The **first** rate (admin has no
  prior pay) applies immediately; every subsequent change is stored in
  `pending_hourly_rate` / `pending_rate_effective_from = next Monday` and
  promoted automatically when payroll for that week is generated.
- **Overtime:** hours beyond `max_hours_per_week` are paid at **1.5×**.
  `regular_hours = min(total, max)`, `overtime_hours = max(0, total − max)`,
  `total_payment = regular·rate + overtime·rate·1.5`. If `max_hours_per_week`
  is unset, everything is regular. Verified: 2.5 h with max 2 → 2.0 reg + 0.5 OT
  → `2·300 + 0.5·300·1.5 = ৳825`.
- **Payroll run:** Super Admin clicks **Generate Weekly Payroll** →
  `POST /admin-payments/` computes one `admin_payments` row per admin for the
  last completed week. `hourly_rate` / `overtime_rate` are **snapshotted** on the
  row. Re-running recomputes **pending** rows and **never touches paid** ones.
- **Mark paid:** `PATCH /admin-payments/<id>/` with `payment_method` (cash /
  bank_transfer / mobile_wallet) + optional reference → status `paid`,
  `payment_date`, `paid_by`; the admin is notified.
- **Export:** `GET /admin-payments/export/` → CSV for accounting.
- **No scheduler** — generation is a manual button (agreed). Overtime is 1.5×
  (agreed); tax withholding deferred (agreed).

## 12. How Super Admin sees all admins' hours / status / payments

`GET /all-admins/` returns, per admin (Super Admin excluded): name, role, tier,
department, current `hourly_rate` (+ pending), rate band, `max_hours_per_week`,
`hours_this_week` / `hours_this_month`, `regular_hours_week` / `overtime_hours_week`,
`payment_due_this_week`, `is_on_shift`, `on_break`, `shift_started_at`,
`is_suspended`, `last_shift_start` — plus a summary (`total_admins`, `on_shift`,
`payment_due_this_week`, `total_hours_this_week`). `online-admins` / `offline-admins`
are filtered views. The **Team & Payroll** screen renders this with a
who's-online / who's-offline toggle and polls every 10 s. Shift history per admin
via `GET /shifts/?admin_id=<id>`.

## 15. How to run the migrations

Schema-first (no `manage.py migrate` for schema):

```powershell
psql -d featherflow -f backend/postgres_backend_extension.sql   # existing DB (idempotent)
# or, fresh DB:
psql -d featherflow -f featherflow_schema.sql
backend\venv\Scripts\python.exe backend\manage.py migrate profiles --fake   # optional, keeps makemigrations quiet
backend\venv\Scripts\python.exe backend\manage.py check
```

## 16. How to run the application

Already running: Django `http://127.0.0.1:8000`, Flutter `http://localhost:5173`.
To restart:

```powershell
cd backend
venv\Scripts\python.exe manage.py runserver 127.0.0.1:8000
# repo root, new terminal:
flutter run -d chrome --web-port 5173
```

## 17. How to test each admin role's access

```powershell
backend\venv\Scripts\python.exe backend\scripts\test_admin_panel.py    # 65 assertions, all pass
```

Or manually — sign in (all `Featherflow@2026`):

| Role | Email |
|---|---|
| Super Admin | `super.admin@featherflow.dev` |
| Operations Admin | `operations.admin@featherflow.dev` |
| Finance / Content / Research / Delivery / Pharmacy / Doctor / Team / Support | `<name>.admin@featherflow.dev` |

Confirm: sidebar shows only permitted modules; blocked actions surface a 403
toast; **Team & Payroll** appears for Super Admin only.

## 18. How to test the shift timer + payment system

`test_admin_panel.py` covers it (section "SHIFT TIMER + HOURLY PAYMENT", 26
assertions). Manually:
1. Sign in as `content.admin` → dashboard shows the shift widget → **Start
   Shift** → the `HH:MM:SS` ticks; the app-bar pill on every screen shows
   "x.x h today".
2. **Break** → timer freezes; **Resume** → continues; **End Shift** → hours
   land in "This week".
3. Sign in as `super.admin` → **Team & Payroll** → "Content Admin" shows under
   **Who's online**; set their rate (rejected if outside the band); **Generate
   Weekly Payroll** → a pending row → **Mark paid** (bank_transfer + ref) →
   **Export**.
4. Super Admin tries to Start Shift on their own dashboard → no widget; the API
   returns 403.

## 19. How to test real-time updates (admin action → user within 10 s)

- Sign in as a researcher in one browser, `research.admin` in another.
- Admin clicks **Verify** on the researcher → within ≤10 s the researcher's
  dashboard shows the "Verified" badge and a toast "You are verified".
- Admin **suspends** the researcher → their next navigation redirects to the
  login screen with "Your access was changed by an administrator".
- Admin **starts a shift** → the Super Admin's Team & Payroll "Who's online"
  updates within 10 s (both the admin's `/me/` poll and the Super Admin screen's
  own 10 s poll).

## 20. Remaining limitations

1. **Doctor module backend** — deferred to Pass 2 (agreed). `DoctorSession` now
   reflects account-level verification/suspension from `/api/me/updates/`, but
   the doctor's appointment/case **lists** are still `doctor_demo_data.dart`;
   there is no `doctor_api_service.dart`.
2. **Shift UI not hand-clicked** — every shift/payroll endpoint is verified over
   real HTTP per role (65/65), the `ShiftTimerWidget` and `AdminPayrollScreen`
   pass widget-render tests, and the whole start→online→end→payroll loop was run
   live against the server; but no human has clicked the buttons in the browser
   yet. The app is running on `:5173` for you to try.
3. **Payroll scheduler** — manual "Generate Weekly Payroll" button only (agreed;
   no cron infra exists).
4. **Rate promotion** happens lazily during payroll generation — if you never
   run payroll, a pending rate is applied on the first generation whose period
   start is on/after its effective Monday. `effective_hourly_rate(date)` always
   returns the correct rate for reads in the meantime.
5. **Deferred (agreed):** 2FA enforcement, chart dashboards, WebSockets, custom
   role-builder UI, full bulk import, tax withholding, load tests.
6. Pre-existing: `community-reports` / `subscription-plans` / `diseases` still
   JSON-backed; pharmacy medicine catalogue still JSON-backed (needs coordinated
   pharmacy-app changes).

## Test artefacts

`test_admin_panel.py` creates `adminpaneltest+*` accounts (idempotent). Remove:
`DELETE FROM users WHERE email LIKE 'adminpaneltest+%' AND email NOT LIKE '%rider%';`
The 10 demo admins (`*.admin@featherflow.dev`, `Featherflow@2026`) are permanent.
