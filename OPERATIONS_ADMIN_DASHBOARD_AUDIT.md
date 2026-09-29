# Operations Admin Dashboard / Navigation / Profile / Shift-Timer Audit

Scope: Operations Admin surfaces only (navbar/sidebar, both profile-avatar
buttons, the dashboard, the shift timer, the Operations Admin's own profile
screen once reachable). No other role's screens were changed. Nothing in
this pass was committed to git.

## 1. Navbar field readability

**Symptom:** on the narrow (mobile/tablet-width, `<kBreakpointWide` = 900px)
AppBar, the shift-status pill next to the stopwatch icon rendered as
illegible white-on-white text.

**Root cause:** `_ShiftChip` (`lib/features/admin/presentation/widgets/admin_scaffold.dart`)
used a Material 3 `ActionChip` on the green AppBar. `ActionChip`'s
`backgroundColor:` parameter is not a reliable override — Material 3's
ambient `ChipThemeData` / surface-tint elevation behavior can wash it out
toward the theme's default (white) surface color regardless of the color
passed in, leaving white text on a white/near-white pill.

**Fix:** the `onGreen: true` branch (used only on the green AppBar) no
longer uses `ActionChip` at all. It's a plain `Material` + `InkWell` +
`Container` with a translucent white fill (`Colors.white.withValues(alpha:
0.15)`), a `Colors.white38` border, and the shared
`AColors.navigationForegroundColor` token for both the icon and the text —
the same pattern already used (and already legible) for other on-green
status pills in this app. The `onGreen: false` (wide top-bar, light
background) branch was left as the original `ActionChip`, since it was not
reported broken and changing it was out of scope.

## 2. Both profile-avatar buttons

**Symptom:** tapping the navbar avatar and the sidebar-header avatar did
nothing.

**Root cause — not a routing bug.** Both `CircleAvatar`s had **no tap
handler at all**: no `GestureDetector`, `InkWell`, or `onTap` of any kind.
The already-working "My Profile" row in the sidebar *footer*
(`_SidebarFooter`, `admin_sidebar.dart`) was the only avatar-adjacent
control that actually navigated anywhere.

**Fix** — three avatars wrapped in `GestureDetector`, each navigating to
the existing shared `/admin/profile` route (`AdminProfileScreen` — no
duplicate profile screen was created):

| Avatar | File | Key |
|---|---|---|
| Wide-layout top bar | `admin_scaffold.dart` `_TopBar` | `adminProfileAvatarWide` |
| Narrow-layout AppBar | `admin_scaffold.dart` `_NarrowLayout` | `adminProfileAvatarNarrow` |
| Sidebar header (wide + narrow drawer) | `admin_sidebar.dart` `_SidebarHeader` | `adminProfileAvatarSidebar` |

The sidebar-header handler mirrors the sidebar footer's existing pattern
exactly (`if (Navigator.canPop(context)) Navigator.pop(context);
context.go('/admin/profile');`) so it also closes the drawer on narrow
layouts before navigating, instead of leaving the drawer open over the
profile screen. All three use `context.go`, matching the rest of the
sidebar's navigation — `/admin/profile` only ever resolves to the current
session's own profile (`AdminProfileScreen` reads `AdminSession.instance`,
not a route parameter), so there is no path by which this could route to
another role's or another admin's profile. Back navigation is provided by
`AdminScaffold`'s own back control (confirmed via the new widget test),
and browser refresh/direct navigation to `/admin/profile` is safe because
the screen has no required route arguments.

### Fallout: a real overflow bug this fix exposed

Because narrow-layout profile navigation was previously unreachable (dead
button), a pre-existing layout bug in `AdminProfileScreen` had never been
exercised there. `_InfoRow` (`admin_profile_screen.dart`) put an
unconstrained `Column` directly inside a `Row`, with no `Expanded` /
`Flexible` around it. A value long enough (a longer email, or the
"Cannot edit" `_ReadField` variant, which nests an `_InfoRow` inside
another `Row`) overflows the row's available width on anything narrower
than ~900px. Confirmed via a temporary probe test that isolated the exact
`RenderFlex` and file/line. Fixed by wrapping `_InfoRow`'s label/value
`Column` in `Expanded` (with `TextOverflow.ellipsis` on the value), and
wrapping `_ReadField`'s `_InfoRow` child in `Expanded` too (required so the
inner `Expanded` has a bounded parent). This is a general fix — it also
protects the wide layout against long values, not just narrow.

## 3. Shift timing

**Finding (investigation, not a fix):** the shift timer backend was
already fully real — start/end timestamps are DB-persisted
(`AdminShift`), associated with `request.user`'s `AdminProfile`, stored and
compared using this codebase's established naive-UTC-wall-clock convention
(the same `_aware()` pattern used in `delivery/views.py`). Elapsed time on
the dashboard increments client-side between polls without hammering the
backend; server-computed duration is authoritative on `my_shift_end`. No
mock/parallel shift model existed — `admin_shifts.py`'s existing
`AdminShift` model was reused as-is.

**Gap found and fixed:** `my_shift_start` did a check-then-act
("no active shift exists" → create) with no row lock, so two concurrent
start requests for the same admin could both pass the check and create two
active shifts. Hardened with `transaction.atomic()` +
`AdminProfile.objects.select_for_update()`, re-checking
`profile.shifts.filter(is_active=True).exists()` inside the lock, plus an
`IntegrityError` catch as a backstop against the pre-existing partial
unique index `uq_admin_shifts_one_active` (in `postgres_backend_extension.sql`)
— so even a race that slips past the application-level lock is caught at
the DB level and returns the same `409 already_on_shift` response instead
of a 500. `my_shift_end` was given the same `select_for_update()` treatment
for consistency, closing the equivalent race on ending a shift.
Idempotency (double-start / double-end return `409`, not a duplicate row
or a crash) is covered by the existing `test_admin_panel.py` shift-timer
section, which continues to pass in full, including "double start blocked
(409)".

No changes were needed for cross-midnight/timezone handling — the existing
`_close_shift`/week-hours computation already used the naive-UTC
convention correctly (verified via the existing "midnight shift splits 2h
+ 2h" and "week hours stable at 2.5 after close (no tz drift)" tests,
which still pass).

## 4. Dashboard metrics — per-field definitions

`GET /api/admin-panel/dashboard/` (`backend/api/admin_views.py`,
`admin_dashboard()`), tier-gated via `admin_rbac.can_perform_action`.

| Card / field | Response key | Backend query | Notes |
|---|---|---|---|
| Active Users | `stats.active_users` | `User.objects.filter(account_status='active').count()` | **The bug**, see below. |
| (raw total, kept, not shown as "Active") | `stats.total_users` | `User.objects.count()` | Every row, any status — this is what "Active Users" used to be bound to. |
| Pending Users | `stats.pending_users` | pre-existing `pending_users` (users awaiting review) | Unchanged. |
| Suspended Users | `stats.suspended_users` | `User.objects.filter(account_status='suspended').count()` | New — previously not surfaced at all. |
| Doctors pending review | pre-existing key | unchanged | Not touched. |
| Pharmacies pending review | `stats.pending_pharmacies` | unchanged | Now has a dashboard alert banner (pre-existing). |
| Delivery workers pending review | `stats.pending_delivery` | `DeliveryProfile.objects.filter(approved_by_admin__isnull=True).count()` | New. Same query shape as `admin_extra.py`'s existing `unassigned_riders` metric. Now also has an alert banner (see below). |
| `generated_at` | top-level | `timezone.now().isoformat()` | New — lets the frontend/tests confirm freshness. |

**Root cause of the "Active Users: 54" bug:** the dashboard's "Active
Users" card was bound to `stats['total_users']`, which was (and still is,
under its own honest key) `User.objects.count()` — every user row
regardless of `account_status`, including pending, suspended, and rejected
accounts. There was no status filter anywhere in that value's derivation.
Fixed by adding a correctly-filtered `active_users` key on the backend and
rebinding the Flutter "Active Users" card
(`admin_dashboard_screen.dart`, `_OverviewGrid`) to it instead of
`total_users`.

**Metric definitions used** (matches the audit's recommended
distinction): *Active* = `account_status == 'active'`. *Pending* = the
existing pending-review definition (unchanged). *Suspended* =
`account_status == 'suspended'`. *Total* = all rows, no filter — kept
under its own key rather than removed, since it's an honest figure in its
own right, just not what "Active Users" should mean.

**Efficiency / RBAC:** all of the above are `.count()`/`.filter().count()`
calls — no N+1, no per-row Python loops. The view is already gated by the
existing `can_perform_action` RBAC check; no financial, medical, or
payment fields are present in this response.

## 5. Live-data integration

Covered by `backend/scripts/test_admin_dashboard_metrics.py` (new, 12/12
passing) — see `OPERATIONS_ADMIN_LIVE_DATA_VERIFICATION.md` for the
before/after delta results per lifecycle event.

## 6. Dummy data removed

- **Dashboard "Active Users" card** no longer shows `total_users` under an
  "Active" label (see §4).
- **`AdminDashboardScreen`** no longer renders `_OverviewGrid`'s cards (or
  any stat) before the first successful load — previously the first frame
  briefly built cards against an empty `_stats` map (`?? 0` fallback),
  which is functionally the same class of bug as a hardcoded "54": a
  number shown before it's known to be real. Now a spinner is shown until
  `_hasLoadedOnce`, per §7 below.
- **`AdminProfileScreen`'s `_StatsRow`** (found during this pass, while
  auditing the screen my §2 fix newly made reachable from the narrow
  layout) rendered three **completely hardcoded** numbers with no backend
  binding whatsoever: `'1,240'` Users Managed, `'38'` Actions Today, `'7'`
  Open Tickets. No endpoint currently returns any of these. Removed
  entirely (along with the now-unused `_StatCard` widget) rather than
  wired to a fabricated endpoint, since inventing backend numbers to match
  a fabricated frontend card would just move the fabrication, not remove
  it.
- **`AdminProfileScreen`'s initial field values**: `_phoneCtrl`,
  `_deptCtrl`, and `_bioCtrl` were seeded with realistic-looking but
  entirely fake placeholder text (`'+880 1700-000000'`, `'IT &
  Operations'`, a canned bio) *before* the real `/profile/` fetch
  resolved — and, because the fetch failure path is `catch (_) {}` (silent
  no-op), these fake values would remain on screen permanently and
  indistinguishably from real data if that fetch ever failed. Changed to
  start empty; the fields now only ever show the admin's own fetched data.
  `_nameCtrl` keeps its same-session fallback (`AdminSession.instance.name`,
  already known from login, not fabricated).

**Not removed** (out of scope / not fabricated): seeded demo accounts
created by `seed_platform_demo.py` earlier in this session are real DB
rows, honestly reflected — per this task's own instructions, legitimate
demo/dev data is not to be deleted, only presentation-layer fabrication.

## 7. Visual consistency

- Navbar shift pill contrast: fixed, §1.
- Both/all three profile avatars: now actionable and visually unchanged
  otherwise (same `CircleAvatar` styling, just wrapped).
- `_InfoRow` overflow on the profile screen at narrow widths: fixed, §2.
- Dashboard loading/error states: previously there was no loading state at
  all (cards could render against an empty stats map before the fetch
  resolved) and no retry control on error. `_DashboardBodyState` now
  tracks `_hasLoadedOnce`/`_loading`; `build()` shows a centered spinner
  until the first successful load, and a failed *background* refresh (one
  that happens after data has already loaded once) keeps showing the last
  good data with a small error banner + "Retry" button instead of
  blanking the screen. First-load failure and refresh failure show
  different banner text so it's clear which happened.
- `pending_delivery` alert banner added to `_DashboardAlerts`, mirroring
  the existing `pending_pharmacies` banner pattern exactly (same
  `_AlertBanner` widget, same amber styling, gated on
  `session.canAccess(AdminModule.deliveryManagement)`) — closes the gap
  where the new backend metric (§4) had no UI surface.
- The rest of the dashboard (charts/tables, confirmation dialogs, other
  panels) was reviewed and not found to have obvious, in-scope problems;
  no changes were made there, per the explicit "targeted fixes only, no
  broad redesign" instruction.

## 8. Known limitations (undocumented until now, disclosed here)

- `AdminApiService` / `AdminSession` have no injectable test seam (real
  HTTP singletons — unlike `DeliverySession`'s `@visibleForTesting
  debugSet*` pattern used elsewhere in this codebase). This means the new
  Flutter test file cannot assert a *specific* live dashboard value
  end-to-end in-process; that correctness is instead covered by the new
  backend delta test (`test_admin_dashboard_metrics.py`) plus code review
  of the binding itself (`stats['active_users']`, not `stats['total_users']`).
- The navbar shift-chip's on-green contrast fix is not directly
  widget-testable in this harness either: `AdminSession._tracksShifts`
  defaults to `false` with no session, so `_ShiftChip` always renders
  `SizedBox.shrink()` in tests. Verified instead by code reading (the
  `Container`/`Material`/`InkWell` replacement no longer goes through
  `ActionChip` at all) and by `flutter analyze` + manual reasoning about
  Material 3 chip theming.

## Files changed

- `backend/api/admin_views.py` — dashboard metric fixes/additions (§4).
- `backend/api/admin_shifts.py` — shift start/end race hardening (§3).
- `lib/features/admin/presentation/widgets/admin_scaffold.dart` — navbar
  chip contrast (§1), two profile-avatar handlers (§2).
- `lib/features/admin/presentation/widgets/admin_sidebar.dart` — sidebar
  header avatar handler (§2).
- `lib/features/admin/presentation/screens/admin_dashboard_screen.dart` —
  loading/error/retry states (§7), `active_users` rebinding (§4/§6),
  `pending_delivery` alert banner (§7).
- `lib/features/admin/presentation/screens/admin_profile_screen.dart` —
  `_InfoRow`/`_ReadField` overflow fix (§2), removed fabricated
  `_StatsRow`/`_StatCard` (§6), removed fake placeholder field values (§6).
- `backend/scripts/test_admin_dashboard_metrics.py` — new backend test
  (§4/§5).
- `test/admin_dashboard_and_profile_buttons_test.dart` — new Flutter test
  (§2/§7).

No files were committed — all of the above are working-tree changes only.
