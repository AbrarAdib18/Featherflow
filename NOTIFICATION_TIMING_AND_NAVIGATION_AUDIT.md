# Notification Timing & Navigation — Audit and Fix

Nothing in this work was committed. Companion: `NOTIFICATION_NAVIGATION_MATRIX.md`.

## 1. Reproduction (before the fix)

A notification created *this second* for `farmer.rashed@example.com`, read back
through the real API:

```text
timezone.now()          : 2026-10-29 20:00:10+00:00   (UTC)
datetime.now() (naive)  : 2026-10-30 02:00:10        (server local, Asia/Dhaka UTC+6)
stored created_at       : datetime(2026,10,29,20,0,10)  aware? False
GET /api/notifications/ : 200 {"time": "6\xa0hours ago", ...}   <- the screenshot
```

## 2. Root cause — backend, in the serializer's time arithmetic

Trace: `creation → DB → serializer → Flutter → rendered label`.

| Stage | Finding |
|---|---|
| Creation | Correct. `auto_now_add` writes `timezone.now()` (aware UTC); the column default `now()` runs in a UTC DB session. Both store **UTC**. |
| Database | `notifications.created_at` is `timestamp without time zone`, so the UTC wall-clock is stored **without an offset**, and Django reads it back **naive**. |
| Serializer — **the bug** | `notifications/views.py` returned **no timestamp at all**, only `'time': timesince(x.created_at)`. Given a naive value, Django's `timesince()` compares it with naive `datetime.now()`, which is the server's **local** time (UTC+6). So naive UTC 20:00 was compared against local 02:00 → **exactly 6 hours**, for every notification, every role. |
| Same bug, 2 more feeds | `/api/me/updates/` returned `created_at` via `.isoformat()` on the naive value, giving **no offset**, which any client parses as *local* time (6h off). `/api/community/notifications/` used `community.views._ago()`, which called `timesince()` without the `_aware()` helper that already existed in the same file. |
| Flutter | Not the cause, but compounded it: every surface printed the server's pre-rendered `time` string, so the label also **froze** at fetch time and never advanced. |
| Cache / UI refresh | No cache is involved. The frozen label was a design flaw (no client-side recompute), fixed alongside. |

**Verdict:** backend serializer/timezone bug (naive UTC timestamp treated as
local time), plus a missing API contract (no aware timestamp exposed) and a
frontend that couldn't recompute.

## 3. Timing fix

**Backend: one shared serializer** (`backend/notifications/serializers.py`),
used by all three feeds:

- `aware_created_at()` labels the naive DB value as UTC. This is the same
  convention as `api/admin_shifts._aware` and `community.views._aware`.
- `created_at` is returned as ISO 8601 **with offset**, e.g.
  `2026-10-29T20:07:02.948234+00:00`.
- `relative_time()` computes the label from the aware value:
  `Just now` (<1 min) · `1 min ago` · `N mins ago` · `1 hour ago` ·
  `N hours ago` · `1 day ago` · `N days ago` · `Oct 20, 2026` (7+ days).
  A future timestamp (clock skew) reads `Just now`.
- `time` is still returned for older clients, now correct.
- The DB column, stored values and creation sites are unchanged. Nothing is
  rewritten and no client-generated time is used.

**Flutter: one shared module** (`lib/core/notifications/`):

- `parseNotificationTimestamp()` parses the aware ISO value to UTC. An
  offset-less string is treated as **UTC, never device-local**, which is the
  exact failure mode.
- `formatNotificationTime()` uses the same rules as the backend. Elapsed time
  is computed between two absolute instants, so device timezone and
  daylight-saving changes cannot shift it. Local time is used only to display
  a 7+-day date.
- `NotificationTimeLabel` recomputes from the persisted `created_at` on
  **every fetch, pull-to-refresh, app foreground return, and every 30 s**,
  driven by a single app-wide `NotificationClock`. It never makes an API call
  and never mutates the original timestamp.

## 4. Navigation root cause

Tap handling was hard-coded separately in each surface, and incomplete:

| Surface | Before |
|---|---|
| Doctor dashboard | Only `consultation_rating` did anything. A **new consultation request** or **chat message** was a dead tap. |
| Feed management | **No `onTap` at all.** |
| Farmer dashboard | Only consultation/finance types navigated; everything else showed a text dialog. |
| Community notifications | Opened the post with no check; a removed post opened a broken screen. |
| Realtime toasts (all roles) | Display-only, with no way to open the target. |
| Pharmacy, delivery, research, all 9 admin roles | **No notification inbox existed at all.** |

## 5. Navigation fix

**Backend-owned destination.** Each notification now carries:

```json
"navigation": {"route": "/doctor/appointments", "target_type": "consultation",
               "target_id": "…", "available": true}
```

or `null` when the type has no meaningful destination. Details:

- It is resolved from the **recipient's own role**, because the same type
  reaches different people (`pharmacy_order` → farmer *and* pharmacy;
  `delivery_order` → rider *and* admins).
- **Admin RBAC:** an admin route is returned only if the recipient's role can
  view that module (`can_perform_action`). Finance Admin gets no route to the
  operational approval queue, and Operations Admin gets none to Super-Admin
  payroll.
- **Object access:** consultation and conversation targets are checked in
  bulk (one query per type) for existence *and* that the recipient is a
  participant. Community posts are checked for still being active. A failed
  check gives `available: false, route: null`.
- Users only ever see their own notifications (`request.user.notifications`),
  and every destination screen's API is scoped to the caller server-side. The
  metadata exposes only `route/target_type/target_id/available`.

**Flutter: one handler** (`NotificationNavigator.open`):

- It validates the backend route against an allow-list of app sections. An
  external URL, `/login`, `..`, `//` or a `:param` placeholder is refused.
- A debounce prevents double-tap double navigation.
- `go` is used from dialogs (back goes to the section parent) and `push` from
  full-screen lists (back returns to the list).
- `available:false` shows **"This item is no longer available."**
- No destination keeps the user in the center and shows the full text. It
  never crashes on unknown types.
- Mark-read keeps the existing rule: everything is marked read when the center
  closes.

**Shared UI, used everywhere:**

- `showNotificationCenter()` / `NotificationTile` replace the three duplicated
  inline dialogs (farmer, feed management, doctor).
- The community list uses the same tile and handler.
- `NotificationBellButton` (badge from the app-wide `/api/me/updates/` poller)
  was added to the pharmacy, delivery and research app bars and to
  `AdminScaffold`, so **every admin role** now has a working inbox.
- Toasts gained an **Open** action that uses the same handler.

## 6. Files changed

Backend:
- `notifications/serializers.py` (new)
- `notifications/views.py`
- `api/admin_extra.py` (`/me/updates/`)
- `community/views.py` (`_ago` + community notifications)
- `scripts/test_notifications.py` (new)

Flutter:
- `lib/core/notifications/notification_time.dart` (new)
- `lib/core/notifications/notification_navigator.dart` (new)
- `lib/core/notifications/notification_widgets.dart` (new)
- `lib/core/network/realtime_toast.dart`
- `lib/main.dart`
- farmer dashboard, feed management, doctor dashboard, community notifications
- pharmacy dashboard, delivery dashboard, `research_scaffold.dart`, `admin_scaffold.dart`
- `test/notifications_test.dart` (new)

**API contract (additive, backward compatible):** `created_at` (aware ISO
8601) and `navigation` are added to all three feeds. `time` is kept and now
correct. The community feed keeps `message`/`post_id`. No migrations, no
model changes.

## 7. Verification

- **Backend:**
  - `test_notifications.py` passes **135/135**. It covers:
    - the aware timestamp and the "Just now" label
    - the 1 min / 30 mins / 6 hours / 1 day / 3 days / 7+ day labels against
      really back-dated DB rows
    - distinct, not-reused timestamps, and `created_at` unchanged by
      mark-read
    - every reference type in the DB serializing correctly
    - 21 role/type → route cases
    - RBAC withholding, another farmer's consultation, a removed post
    - feed isolation, the payload key set, and backend routes ⊆ Flutter
      allow-list
  - **Negative control:** with only the 3 endpoint fixes stashed, the suite
    fails immediately, and the failing row shows `'time': '6\xa0hours ago'`
    for a just-created notification.
- **Regression:** `manage.py check` clean, `migrate --check` exit 0.
  Consultation/booking/chat/doctor-flow/find-vet/finance/dashboard/earnings/
  vets-nearby suites are all green. `test_admin_panel` is 62/1, the known
  pre-existing `admin login 200` failure.
- **Flutter:**
  - `notifications_test.dart` passes **56/56**. It covers:
    - the formatter and its edge cases
    - aware/naive/Z parsing
    - recompute on refresh and on app foreground return
    - route allow-list
    - real-GoRouter taps to all 19 destinations
    - double tap, back navigation, unavailable target, no-destination
    - a source scan proving every surface uses the shared components
  - The full suite passes **275**. The 2 failures are the known
    `doctor_dashboard_fixes_test` navbar-photo tests; re-run with my
    doctor-dashboard change stashed, they fail identically, so they are
    pre-existing.
- `flutter analyze`: only the 6 pre-existing lints in
  `farmer_feed_marketplace_screen.dart`.

## 8. Limitations — stated plainly

- **Manual browser verification by role was not performed.** Evidence is the
  live-DB backend suite plus widget tests with a real GoRouter.
- **Destinations are section screens, not item detail screens.** Except for
  community posts (`/community/post/:id`), FeatherFlow has no per-item routes
  (no `/consultations/:id` etc.). Taps open the correct screen for the role,
  where the item appears in that user's list. `target_id` is returned for a
  future highlight/detail route. Inventing detail routes was out of scope.
- **Types with no meaningful destination** (navigation `null`, details shown
  in place): `community_follow`, author-side `community_moderation`, `farm`
  (no live producer), and non-admin `support_ticket` (no user-facing ticket
  screen). The toast also omits **Open** for these.
- **Timezone fix is read-side.** The column stays `timestamp without time
  zone`; correctness relies on every writer storing UTC, which every current
  creation site does. Migrating the column to `timestamptz` would make that
  structural.
- **Unread badge for the new bells** comes from the existing
  `/api/me/updates/` poller (~10 s), not a push channel.
