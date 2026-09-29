# Operations Admin Earnings

Server-side, database-backed hourly earnings for the logged-in Operations
Admin (and any other hourly-tracked admin role — the underlying shift/pay
system already applies to every non-Super-Admin tier). Nothing here was
committed to git.

## 1. Sidebar

A new "Earnings" item (`Icons.payments_outlined`) in `AdminSidebar`
(`lib/features/admin/presentation/widgets/admin_sidebar.dart`), placed
right under "Dashboard". It is gated on `AdminSession.tracksShifts` —
exactly the same boolean `ShiftTimerWidget`/`_ShiftChip` already use, sent
by the backend's `GET /api/admin-panel/me/` as `tracks_shifts: tier > 1 and
profile is not None` (`api/admin_extra.py`). This is deliberately **not**
gated through the module-permission map (`canAccess`) — personal earnings
aren't a "module" a role is granted/denied, they exist for anyone who has
shifts and a rate, the same way `_SidebarFooter`'s "My Profile" and
`teamPayroll`'s `isSuperAdmin` check both bypass `canAccess` for the same
reason.

**Who sees it:** Operations Admin and every other hourly-tracked admin
role (Finance/Content/Research/Delivery/Pharmacy/Doctor/Team/Support
Admin — tiers 2-4), each seeing only their own figures.
**Who never sees it:** Super Admin (tier 1, the platform owner — has no
shifts/pay, `tracks_shifts` is always false for that tier) and
`feed_admin`, which has no `AdminProfile` row at all (a completely
separate profile table), so `tracks_shifts` is `False` for it server-side
with no special-casing needed. Non-admin roles (farmer, doctor, pharmacy,
delivery rider, researcher, …) never see any admin-panel sidebar at all.

Route: `/admin/earnings` → `AdminEarningsScreen`, registered as a normal
sibling of `/admin/profile` inside the existing `/admin` shell in
`lib/core/router/app_router.dart` — no new navigation shell, no duplicate
scaffold. Back navigation uses `AdminScaffold`'s existing back control
(same mechanism as every other admin sub-screen).

## 2. Rate — how ৳450/hour is centrally configured

**Reused the existing structure, did not invent a new one.** This project
already has a per-admin, DB-backed hourly rate:

- `AdminProfile.hourly_rate` (`profiles/models.py`) — the admin's current
  rate.
- `AdminProfile.pending_hourly_rate` / `pending_rate_effective_from` — a
  queued rate change that takes effect the following Monday.
- `AdminProfile.effective_hourly_rate(on_date=None)` — the single method
  that resolves "current vs. pending" to one authoritative Decimal. This
  is what the new earnings endpoint calls; it is the same method
  `_status_payload`, `_admin_row`, and payroll generation already use.
- `Role.hourly_rate_range_min` / `hourly_rate_range_max` — a guardrail a
  Super Admin's rate change must fall within (`postgres_backend_extension.sql`
  sets `admin_operations`'s range to 400–900).
- The seed data (`users/management/commands/seed_platform_demo.py`) sets
  every non-super admin's `hourly_rate` to exactly `450.00`, which for
  `admin_operations` sits inside its role's 400–900 range. Verified live
  against this dev DB's real `ops.nusrat@example.com` account: `hourly_rate
  = 450.00`, `effective_hourly_rate() = 450.00`.

No literal `450` is scattered anywhere in Flutter or in the new backend
view — the Flutter `_EarningsCard`/`_ShiftStatusBanner` widgets only ever
render the `hourly_rate_bdt` string the API returns; the backend only ever
calls `profile.effective_hourly_rate()`. The number 450 exists in exactly
one place with real authority: the `admin_profiles.hourly_rate` column for
this admin (and, as a guardrail, the `admin_operations` row's rate range).

**Who can change it:** only a Super Admin, only via the pre-existing
`PATCH /api/admin-panel/admins/<id>/hourly-rate/` (`admin_hourly_rate`,
gated `_require_super`). The new earnings endpoint is `GET`-only — there
is no code path by which an Operations Admin's own request can alter their
own rate. Confirmed by test (`test_admin_earnings.py`: PATCHing the
earnings URL itself returns 405; PATCHing the rate endpoint as the caller
themselves — not a Super Admin — returns 403).

## 3. Calculation rules

### Duration — seconds, not pre-rounded hours

A new seconds-precision helper pair was added to
`backend/api/admin_shifts.py`, parallel to (and reusing the same overlap
logic as) the existing `_hours_between`/`_shift_hours_in_range`:

- `_shift_seconds_in_range(shift, r0, r1)` — paid seconds of one shift
  inside a window, work overlap minus break overlap. The existing
  `_shift_hours_in_range` (used by payroll/`_status_payload`, unchanged
  behavior) is now defined in terms of this.
- `_seconds_between(admin, r0, r1)` — sums that across the admin's shifts
  that could overlap the window (same shift-selection filter as
  `_hours_between`). Used for Today / This Week / This Month.
- `_completed_seconds_all(admin)` — lifetime completed-shift seconds, via
  a single DB aggregate (`Sum(end_time - start_time)` and
  `Sum(break_duration_minutes)`, one query, two `Sum()`s) rather than
  looping every historical shift row in Python. Used for Total Income.

### Earnings — Decimal only

```python
def _earnings_bdt(seconds, rate):
    seconds = max(0, int(seconds))
    if seconds == 0 or rate <= 0:
        return Decimal('0.00')
    hours = Decimal(seconds) / Decimal(3600)
    return (hours * rate).quantize(TWO_DP, rounding=ROUND_HALF_UP)
```

`rate` is always a `Decimal` (`AdminProfile.hourly_rate` is a
`DecimalField`; `effective_hourly_rate()` returns one of its two Decimal
fields). No `float` ever touches a money value — the only floats in the
whole pipeline are the intermediate `_overlap_seconds()` results (Python
`timedelta.total_seconds()`), which are pure durations, not currency, and
are converted to `int` seconds and then `Decimal` before any
rate-multiplication happens. Rounding happens exactly once, at
`_earnings_bdt`'s final `.quantize(TWO_DP, ROUND_HALF_UP)` — the same
rounding rule this codebase's existing `_dec()` (payroll) already uses, so
there are now two independent-but-consistent rounding paths in this file,
not two different rules.

### Breaks

Unchanged, reused as-is: a single logged break per shift, subtracted from
paid time. No new break policy was invented — `break_start`/`break_end`/
`break_duration_minutes` on `AdminShift` are the same fields the shift
timer and payroll already use.

### Active shift — provisional, not finalized

`today` / `this_week` / `this_month` **include** a currently active
shift's running elapsed time (the same convention `_status_payload`'s
`hours_today` etc. already uses — an active shift's `end` is `_now()`
until it actually ends). `total_income` **excludes** it — it is completed
(`end_time IS NOT NULL`) shifts only. The active shift's own running total
is surfaced **separately**, under `active_shift.provisional_duration_seconds`
/ `provisional_earnings_bdt`, with `total_income.includes_active_shift:
false` stated explicitly in the response so no client has to infer it.

When the shift ends, it becomes a completed row and is thereafter counted
exactly once in `total_income` on the next fetch — verified by test
(`test_admin_earnings.py`: end an active shift, refetch, confirm
`total_income` increases by that shift's duration and `active_shift`
becomes `null`). There is no ledger row created or mutated by this
endpoint at all — it is a pure read/aggregate over `AdminShift`, so there
is no way for it to create a duplicate earnings row from a repeated
Start/End tap (that guarantee belongs to `my_shift_start`/`my_shift_end`'s
own row-locking + the DB's partial unique index, unchanged by this work —
see `OPERATIONS_ADMIN_DASHBOARD_AUDIT.md` §3).

### Time windows, timezone, week policy

`TIME_ZONE = 'Asia/Dhaka'` (`featherflow_backend/settings.py`, `USE_TZ =
True`). Bangladesh does not observe daylight saving time (UTC+6
year-round), so DST is not a relevant concern here. Week boundary is
**Monday–Sunday local time**, reusing the existing `_week_bounds()` (the
same policy this project's weekly payroll already runs on — see the
"Design" note atop `admin_shifts.py`). Today/This-Week/This-Month all
reuse the existing `_day_bounds()`/`_week_bounds()`/`_month_bounds()`
helpers unchanged.

**Boundary allocation:** a shift that spans midnight, a week boundary, or
a month boundary is stored as a single row (unchanged, existing
convention) and its seconds are allocated to each window by interval
overlap — the same `_overlap_seconds()` machinery `_hours_between` already
uses. A 2-hour shift straddling midnight by 1 hour on each side
contributes exactly 1 hour (3600s) to "today" and the full 2 hours to
lifetime total — verified by test for the day, week, and month boundaries
independently, using the endpoint's own boundary functions so the tests
are correct regardless of what day/time they happen to run.

## 4. API

`GET /api/admin-panel/my-shift/earnings/` (`my_shift_earnings`,
`backend/api/admin_shifts.py`), alongside the existing `my-shift/*`
family (`status`, `start`, `end`, `break-start`, `break-end`, `hours`,
`history`). Self-only: there is no `admin_id`/user-id parameter anywhere
in the request — it always operates on `request.user`'s own
`AdminProfile`, via the same `_hourly_admin_or_response()` guard
`my_shift_status` already uses (which also rejects Super Admin with a 403,
since the owner has no shifts/pay).

```json
{
  "hourly_rate_bdt": "450.00",
  "currency": "BDT",
  "timezone": "Asia/Dhaka",
  "generated_at": "2026-09-25T00:15:29.656196+00:00",
  "week_start": "2026-09-21",
  "active_shift": null,
  "today": {"duration_seconds": 0, "earnings_bdt": "0.00"},
  "this_week": {"duration_seconds": 0, "earnings_bdt": "0.00"},
  "this_month": {"duration_seconds": 0, "earnings_bdt": "0.00"},
  "total_income": {
    "completed_duration_seconds": 0,
    "earnings_bdt": "0.00",
    "includes_active_shift": false
  }
}
```

When a shift is active, `active_shift` is:

```json
{
  "id": "…",
  "started_at": "2026-09-25T00:00:00+00:00",
  "on_break": false,
  "provisional_duration_seconds": 1200,
  "provisional_earnings_bdt": "150.00"
}
```

### Security

- `IsAdminUser` + `_hourly_admin_or_response`: unauthenticated → 401;
  authenticated non-admin → 403; Super Admin → 403 (owner, no shifts/pay).
- No parameter of any kind selects a different admin — cross-user access
  isn't just denied, the capability doesn't exist in this endpoint's
  contract at all. Verified by test (two distinct admins each see only
  their own totals).
- `GET`-only — a `PATCH`/`POST`/`DELETE` to this URL is a plain DRF 405,
  since `@api_view(['GET'])` is the only method registered.
- No financial/medical/payment data beyond this admin's own pay figures is
  present in the response.

### Data integrity / efficiency

- `today`/`this_week`/`this_month`: same bounded, indexed query shape as
  the pre-existing `_hours_between` (`idx_admin_shifts_admin_date`,
  `idx_admin_shifts_start` already cover `admin_id` + date/time filters —
  reviewed, no new index needed).
- `total_income`: one DB aggregate query (2 `Sum()`s), not a Python loop
  over every historical shift.
- Nothing here writes to the database — no new model, no new migration,
  no new ledger row, so there is no risk of this endpoint itself creating
  duplicate or conflicting payroll data. It is a read view over the
  existing `AdminShift` source of truth.

## 5. Real-time behavior (Flutter)

`AdminEarningsScreen`
(`lib/features/admin/presentation/screens/admin_earnings_screen.dart`):

- Fetches on entry (`initState`), on app foreground resume
  (`WidgetsBindingObserver.didChangeAppLifecycleState`), on manual
  pull-to-refresh (`RefreshIndicator`), and — while a shift is active — on
  a 20-second periodic timer (not per-second).
- Listens to `AdminSession` (the same global session `ShiftTimerWidget`
  updates) and detects `isOnShift` **transitions** to trigger an immediate
  reconcile fetch right after a shift starts or ends, wherever that action
  was taken (the dashboard's `ShiftTimerWidget`, not this screen — this
  screen doesn't duplicate Start/End controls).
- A separate 1-second `Timer` only ever calls `setState` to repaint —
  Today's displayed duration/earnings are extrapolated locally between
  fetches (`generated_at` timestamp + elapsed wall time × the
  already-fetched rate), exactly mirroring `ShiftTimerWidget`'s existing
  base+delta pattern. This is display-only, per the task's explicit
  instruction — the periodic 20s fetch (and every other reconcile trigger
  above) is what keeps the server-authoritative figures from drifting.
- A failed background refresh leaves `_data` untouched and shows a small
  "Could not refresh… (showing last loaded data)" banner with a working
  Retry, not a blank/zeroed screen — the same convention already
  established for the dashboard (`OPERATIONS_ADMIN_DASHBOARD_AUDIT.md`
  §7).
- Provisional vs. finalized is labeled in the UI: Today/This Week/This
  Month show a small "Live" chip while a shift is active; Total Income
  always shows a "Completed shifts only…" caption and never ticks.

## 6. Known limitation

`AdminShift` has no historical rate snapshot (only `AdminPayment`, the
existing weekly-payroll ledger, records the rate that actually applied to
a *generated* pay period). `Total Income` here is therefore computed as
`completed_seconds × today's effective rate`, uniformly across the
admin's whole history — correct as long as the rate hasn't changed, which
holds for every seeded account in this environment (constant ৳450/hour).
If a rate change ever occurs mid-history, this lifetime total would not
retroactively match the sum of already-paid `AdminPayment` rows (those
correctly snapshot the rate in force for each period). Building a fully
rate-history-accurate lifetime total would require either a new per-shift
rate snapshot or reconciling against `AdminPayment` for already-generated
periods — judged out of scope for this task (the existing weekly payroll
ledger remains the authoritative record for anything that has actually
been paid; this screen is a personal live-visibility feature, not a
payroll ledger, and never writes to `AdminPayment`).
