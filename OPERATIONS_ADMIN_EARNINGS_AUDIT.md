# Operations Admin Earnings — Pre-Change Audit

What was inspected before writing any code, and what it showed. Companion
to `OPERATIONS_ADMIN_EARNINGS.md` (the design/calculation doc) — this file
is the "what already existed" record.

## Dashboard / sidebar navigation

`lib/features/admin/presentation/widgets/admin_sidebar.dart` already had a
precedent for a personal, non-module-permission-gated nav item:
`_SidebarFooter`'s "My Profile" row, and `teamPayroll`'s
`if (session.isSuperAdmin) ...` item. Both bypass `AdminModule.canAccess`
entirely. This is the pattern the new "Earnings" item follows.

## Shift Timer / work-session models

Found a **complete, already-real** shift system in
`profiles/models.py`/`backend/api/admin_shifts.py`:

- `AdminShift` (managed=False, `admin_shifts` table) — one row per work
  session, `start_time`/`end_time`/`break_start`/`break_end`/
  `break_duration_minutes`/`is_active`, with a DB partial unique index
  (`uq_admin_shifts_one_active`) guaranteeing at most one active shift per
  admin.
- Midnight-spanning shifts are kept as one row; per-window hours are
  computed by interval overlap (`_overlap_seconds`/`_shift_hours_in_range`/
  `_hours_between`) — this convention was reused as-is for the new
  seconds-precision earnings helpers rather than re-implemented.
- Both `my_shift_start` and `my_shift_end` already had row-locking
  (`select_for_update`) and an `IntegrityError` backstop against the
  DB unique index — hardened earlier this session
  (`OPERATIONS_ADMIN_DASHBOARD_AUDIT.md` §3) and unchanged by this pass.
  This is why the earnings work didn't need to re-solve duplicate-shift
  prevention: it already existed and is already tested
  (`test_admin_panel.py`, "double start blocked (409)").

## Existing admin hourly-payment / payroll / earnings logic

`AdminProfile.hourly_rate`/`pending_hourly_rate`/`pending_rate_effective_from`/
`effective_hourly_rate()`, `AdminPayment` (a weekly, manually-generated,
Super-Admin-only payroll ledger with overtime split at 1.5×), and
`_generate_payroll`/`admin_payment_update`/`admin_payments_export` — a
full existing payroll subsystem, entirely Super-Admin-facing (team-wide
view + payout tracking). Nothing under this feature's `my-shift/*` prefix
existed for the caller's own **earnings** (only their own **hours** —
`my_shift_hours`/`my_shift_status`) before this pass. The new
`my_shift_earnings` endpoint fills that specific gap; it deliberately does
not touch `AdminPayment` at all (read-only, no ledger writes — see
`OPERATIONS_ADMIN_EARNINGS.md` §4).

## Operations Admin profile and dashboard stats API

`GET /api/admin-panel/me/` already returns `tracks_shifts` (`tier > 1 and
profile is not None`) and an embedded `shift` block
(`_status_payload`) for any hourly admin. This is the exact boolean now
reused to gate the sidebar item. `GET /api/admin-panel/dashboard/`
(reworked earlier this session, `OPERATIONS_ADMIN_DASHBOARD_AUDIT.md`) is
unrelated to per-admin earnings and was not touched by this pass.

## Existing weekly/monthly working-time calculations

`_week_bounds()`/`_month_bounds()`/`_day_bounds()`/`_hours_between()` in
`admin_shifts.py` already existed, used by `_status_payload`
(dashboard's shift-timer widget), `_admin_row` (Super Admin's team view),
and `_generate_payroll`. All four were reused unchanged for the new
seconds-precision earnings windows rather than re-implemented — the new
`_seconds_between()` is a seconds-typed sibling of `_hours_between()`
sharing its exact shift-selection filter and overlap logic.

## Timezone configuration and week-start policy

`featherflow_backend/settings.py`: `TIME_ZONE = 'Asia/Dhaka'`,
`USE_TZ = True`. Week start: **Monday**, per the existing `_week_bounds()`
docstring and the "Design (per the approved decisions)" comment at the top
of `admin_shifts.py` — "weekly Mon–Sun periods (server TZ = Asia/Dhaka)".
Bangladesh has no DST.

## Admin RBAC and Operations Admin permission scope

`api/admin_rbac.py`: `IsAdminUser` (any active, approved admin role),
tier system (1 Super / 2 Operations / 3 module admins / 4 Support),
`effective_permissions`/`can_perform_action` (module-keyed permission
map). The new endpoint intentionally does **not** go through
`can_perform_action` — it's gated the same way every other `my-shift/*`
own-shift endpoint already is (`_hourly_admin_or_response`, tier > 1,
self-only), since "view my own earnings" isn't a module a role is
granted/denied, it's a property of being an hourly admin at all. Staff-wide
earnings visibility for Super Admin/Finance already exists through the
pre-existing `all_admins`/`admin_shifts_list`/`admin_payments_list`
endpoints (all `_require_super`-gated) — nothing new was added there,
since the task's requirement ("Super Admin and authorized Finance/Admin
payroll roles may view staff earnings only through explicitly permitted
endpoints") was already satisfied before this pass.

## Existing database migrations, tests, and audit logging

- `managed=False` models over hand-written SQL (`postgres_backend_extension.sql`)
  is this project's established schema convention (not Django migrations —
  confirmed via `manage.py migrate --check`, clean, 0 pending). No schema
  change was needed: every column the earnings endpoint reads
  (`hourly_rate`, `pending_hourly_rate`, `start_time`, `end_time`,
  `break_start`, `break_end`, `break_duration_minutes`) already exists.
- Indexes already present and sufficient for this endpoint's query shape:
  `idx_admin_shifts_admin_date (admin_id, shift_date)`,
  `idx_admin_shifts_active (is_active)`, `idx_admin_shifts_start
  (start_time)` — reviewed; no new index migration was added.
- Audit logging (`audit.models.ActivityLog`, via `_audit()` in
  `admin_shifts.py`) already covers every *mutating* shift/rate action
  (start, end, break start/end, rate change, force-end, payment mark-paid).
  The new earnings endpoint is read-only and creates no state change, so
  it does not call `_audit()` — there is nothing to audit about a GET.
- `test_admin_panel.py`'s existing shift-timer section already covers
  lifecycle races; `test_admin_dashboard_metrics.py`
  (added earlier this session) covers the dashboard metrics endpoint. The
  new `test_admin_earnings.py` is scoped specifically to what neither of
  those covers: the earnings calculation formula and the earnings
  endpoint's own access scoping.

## Prior Operations Admin dashboard fixes (this session)

`OPERATIONS_ADMIN_DASHBOARD_AUDIT.md`/`OPERATIONS_ADMIN_LIVE_DATA_VERIFICATION.md`
(same session, immediately prior task): fixed the navbar shift-chip
contrast, wired up all three profile-avatar buttons, fixed the "Active
Users" dashboard mislabeling, hardened the shift start/end race, added
dashboard loading/error/retry states, and removed fabricated data from the
Operations Admin's own profile screen (`_StatsRow`, fake placeholder
fields). This earnings work builds directly on that pass — the sidebar
item sits in the same `AdminSidebar` file already touched there, the
screen reuses the same `AdminScaffold`/`AdminLoading`/`AdminError`
conventions established there, and the profile-screen dummy-data removal
from that pass is why this new screen was written from the start to never
show a placeholder number before its first real fetch resolves.

## Result of this audit: what was reused vs. what was new

| Needed | Status | Action |
|---|---|---|
| Shift/work-session records | Existed, complete | Reused unchanged |
| Break policy | Existed | Reused unchanged, not reinvented |
| Hourly rate storage + resolution | Existed (`effective_hourly_rate`) | Reused unchanged |
| Rate change authorization (Super-only) | Existed | Reused unchanged, verified still enforced |
| Week/month/day boundary functions | Existed | Reused unchanged |
| RBAC / self-only shift access pattern | Existed (`_hourly_admin_or_response`) | Reused unchanged |
| Indexes for admin_id + shift timestamps | Existed, sufficient | Reviewed, no new index |
| Audit logging for shift/rate mutations | Existed | Unaffected (this endpoint is read-only) |
| A **caller's own earnings** endpoint | Did not exist (only own hours/status existed) | **New**: `my_shift_earnings` |
| Seconds-precision duration helpers | Did not exist (existing helpers rounded to hours) | **New**: `_shift_seconds_in_range`, `_seconds_between`, `_completed_seconds_all` |
| Lifetime completed-shift efficient aggregate | Did not exist | **New**: single DB `Sum()` aggregate |
| A sidebar Earnings item / screen | Did not exist | **New**: `AdminEarningsScreen` + sidebar entry + route |
