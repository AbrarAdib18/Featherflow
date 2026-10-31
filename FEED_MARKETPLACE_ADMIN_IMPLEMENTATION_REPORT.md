# Feed Marketplace Admin + Feed Inventory Owner — Implementation Report

**Nothing in this work was committed to git** (per instructions). All files
listed below are new/modified in the working tree only.

## Accounts

| Role | Email | Password |
|---|---|---|
| Feed Marketplace Admin | `feed.admin@featherflow.local` | `ChangeMe@2026!` |
| Feed Inventory Owner | `feed.owner@featherflow.local` | `ChangeMe@2026!` |

Created idempotently by `python manage.py seed_feed_marketplace_demo`
(`_seed_fixed_accounts`) — verified safe to run twice in a row
(`test_feed_owner_flow.py`'s first two checks, and manually run twice during
this session with `created=0, skipped=42` on the second run).

Feed Inventory Owner profile (real, not a stub):
business name "Featherflow Feed Inventory", inventory location "Savar,
Dhaka", assigned categories `[starter, grower, finisher, layer]`, status
`active`, `approved_by_admin` = the fixed Feed Admin account.

## Roles and permissions

- `feed_owner` — new role, `panel_type='feed_owner'` (the `roles.panel_type`
  CHECK constraint was widened to allow it — see
  `backend/feed_owner_extension.sql`). Not an admin-panel role: never passes
  `IsAdminUser`/`can_perform_action` on any `/api/admin-panel/...` endpoint.
- `feed_admin` — pre-existing (`feed_marketplace_extension.sql`), unchanged.
- Server-side enforcement verified directly via real HTTP requests (Django
  test `Client` + JWT, not internal function calls):
  - `feed_owner` → 403 on `/api/admin-panel/feed-catalogue/products/` and
    `/api/admin-panel/pharmacy-chats/`.
  - `farmer` / `delivery` → 403/401 on `/api/feed-owner/profile/` and
    `/api/admin-panel/feed-chats/`.
  - `admin_pharmacy` → 403 on `/api/admin-panel/feed-chats/` (no
    `feed-orders` permission grant).
  - A second `feed_owner` account cannot read or post into another owner's
    conversation (404, not leaked as 403 — doesn't even reveal existence).

## Models and migrations

- `profiles.FeedOwnerProfile` (table `feed_owner_profiles`) —
  `profiles/migrations/0007_feed_owner_profile.py`.
- `expenses.Expense.source_feed_order_id` (+ unique partial index, mirrors
  `source_pharmacy_order_id`) — `expenses/migrations/0003_source_order_mirrors.py`
  (also reconciled two pre-existing unmigrated fields —
  `source_intent_id`/`source_pharmacy_order_id` — that predate this session).
- DDL: `backend/feed_owner_extension.sql` (applied to the live dev DB during
  this session via `psql`).
- `manage.py check` and `manage.py migrate --check` are clean (0 pending)
  after applying the extension SQL and running `manage.py migrate`.

## APIs

```
GET/PATCH /api/feed-owner/profile/
GET/POST  /api/feed-owner/chat/
POST/PATCH /api/feed-owner/chat/<conversation_id>/

GET    /api/admin-panel/feed-chats/
GET    /api/admin-panel/feed-chats/<id>/
POST   /api/admin-panel/feed-chats/<id>/messages/
PATCH  /api/admin-panel/feed-chats/<id>/status/      (open|waiting_for_pharmacy|waiting_for_admin|resolved|reopened)
PATCH  /api/admin-panel/feed-chats/<id>/assign/
```

All endpoints: real authentication (JWT), role/permission-gated, object-level
scoped to the requesting user's own conversation (owner side) or RBAC'd team
inbox (admin side), structured JSON errors, and audit-visible via the
existing `Notification` model.

## Admin screens

- `lib/features/admin/presentation/screens/admin_feed_chats_screen.dart` —
  inbox (owner name, status chip, unread count, last message) + detail/reply
  screen with Resolve/Reopen.
- Sidebar: new **"Feed Owner Chat"** nav item (`admin_sidebar.dart`), gated by
  the existing `feed-orders` permission — no new backend permission key
  needed.
- Router: `/admin/feed-chats` (`app_router.dart`).

## Feed Inventory Owner screens

- `lib/features/feed_owner/presentation/screens/feed_owner_home_screen.dart` —
  profile summary (name, email, phone, role badge), inventory context
  (business name, location, categories, status), "Chat with Feed Marketplace
  Admin" tile with unread badge, Community tile (opens the real, existing
  `CommunityFeedScreen` — no separate community system), logout.
- `feed_owner_chat_screen.dart` — the private conversation, matches
  `PharmacySupportChatScreen`'s UX exactly (send, realtime push with REST
  fallback, error/retry state).
- Router: `/feed-owner` is the post-login destination for the `feed_owner`
  role (`auth_service.dart::getRoleDestination`).
- No admin sidebar/shell is shown to this role — it's a standalone screen,
  confirmed both by code (it doesn't reuse `AdminShell`) and by the live
  screenshot below.

## Community access

No backend change was required for access (Community has no posting-role
gate — see the audit doc §3); `feed_owner` was added to
`community/permissions.py::_BADGE_ROLES` for a "Verified Feed Supplier"
badge. Live-verified: the Feed Inventory Owner opened the real farmer
Community feed (existing posts, categories including "Feed Prices", and a
visible "Post" FAB) directly from its home screen tile.

## Financial integration

`feed_catalogue.services.mirror_feed_expense(payload)` — mirrors
`pharmacy.services.mirror_pharmacy_expense` exactly: looks up the pre-seeded
`ExpenseCategory` named "Feed" (already seeded by
`farmers_panel_extension.sql`), builds the farmer's `Farm` via
`workers.views.farm_for` (auto-creates if missing), and `get_or_create`s an
`Expense` keyed on the new unique `source_feed_order_id` column — exactly
once per order, verified by calling it twice with the same payload in
`test_feed_owner_flow.py` (same `Expense.id` both times, only one row exists).
Wired into `delivery.views._sync_feed_order`'s `delivered` branch, alongside
the existing status/notification sync.

## Test results

### Backend (`backend/venv/Scripts/python.exe manage.py check` / individual scripts)

- `manage.py check` — clean.
- `manage.py migrate --check` — clean (after applying the extension SQL +
  `manage.py migrate`).
- **New**: `scripts/test_feed_owner_flow.py` — **32 passed, 0 failed** (seed
  idempotency, login/profile, restricted-module denial, full chat lifecycle
  incl. resolve/reopen, cross-user isolation, finance-mirror idempotency).
- **Full existing suite re-run** (39 scripts, not just new ones):
  - 37 passed outright.
  - `scripts/test_feed_order_delivery.py` — initially failed at **cleanup**
    only (a `ProtectedError` deleting test users who now own a mirrored
    `Expense` row, a direct and expected consequence of wiring the finance
    mirror in). Fixed by adding `Expense.objects.filter(created_by__in=users)
    .delete()` to its `cleanup()`, mirroring `test_pharmacy_admin.py`'s
    convention. Re-ran clean: **26 passed, 0 failed**.
  - `scripts/test_admin_pagination_performance.py` — fails on an unrelated,
    pre-existing bug (`TypeError: unsupported format string passed to
    NoneType.__format__` in `api/admin_views.py`'s consultations pagination,
    triggered by a consultation row with `appointment_time=None`). Not
    touched by this work (confirmed no this-session diff anywhere near that
    code path); left as a documented pre-existing gap rather than
    "fixed" out of scope.

### Flutter

- `flutter pub get` — clean.
- `flutter analyze` (new/changed files) — **no issues found**.
- `flutter test test/feed_owner_smoke_test.dart` — **2 passed**.
- `flutter test` (full suite, 27 files) — **194 passed, 0 failed**.
- `flutter build web --release` — **succeeded** (`build/web`); pre-existing
  Wasm-compat warnings (`flutter_secure_storage_web`, `socket_io_common`) are
  unrelated to this change and don't block the build.

## Live browser verification

**Environment note**: no `chromium-cli`/Playwright/browser tool was
pre-installed in this session's environment. I installed `playwright` via
`npm` locally (no browser download needed — used the machine's existing
Google Chrome via `channel: 'chrome'`) and drove it headlessly against the
real running app. Flutter web (CanvasKit) renders no accessible DOM text
nodes without the accessibility tree enabled, so interaction was done by
screen-coordinate click + real keyboard input (confirmed correct by
screenshotting after every step) rather than DOM text selectors — this is
real user-equivalent input (mouse + keyboard events into the actual canvas),
not a mocked/simulated call.

**Setup**: Django `runserver` on `127.0.0.1:8000` (real Postgres DB, seeded);
`flutter build web --release` output served via `python -m http.server 8080`.

**Verified, in order, with a screenshot at each step**:

1. **Feed Owner login** (`feed.owner@featherflow.local` / real password) →
   landed on `/#/feed-owner` (not the admin shell, not the farmer dashboard).
   Screen showed the real profile (business name, location, categories,
   status), a chat tile, a Community tile, and logout — **no admin controls
   visible**.
2. Opened "Chat with Feed Marketplace Admin", sent a real message via the
   text field (canvas-level keyboard input) → message appeared as a sent
   bubble immediately (REST call, confirmed via the backend's own inbox
   afterward).
3. Logged in as **Feed Marketplace Admin** (real password) → landed on
   `/#/admin`, sidebar shows **Dashboard / Feed / Clients / Feed Owner Chat /
   Audit Trail**, dashboard's real Recent Activity feed showed the actual
   login events from this session (`Login success for feed.owner@...`,
   `feed.admin@...`) — proving this is live data, not a fixture.
4. Opened **Feed Owner Chat** → inbox listed the real conversation with
   status `waiting_for_admin` and the owner's message.
5. Opened the conversation, replied ("Restocking starter feed today, thanks
   for flagging.") → reply appeared; clicked **Resolve** → button flipped to
   **Reopen**, confirming the status transition round-trip.
6. Logged back in as the Feed Owner (fresh session) → chat screen showed
   **both** messages in order — conversation history persisted across
   logout/relogin, exactly as required.
7. From the Feed Owner home screen, tapped **Community** → opened the real,
   existing farmer Community feed (actual posts, category chips including
   "Feed Prices", a working "Post" composer FAB) — not a separate/mocked
   screen.
8. Console error check at every step: **zero JS errors**, except three
   expected `WebSocket ... 404` warnings when the realtime chat layer tried
   to reach Socket.IO — expected because `runserver` is WSGI-only (the
   realtime layer needs an ASGI server); the REST path (which is what every
   message send/read in this verification actually used) was unaffected.

Screenshots captured this session (paths under this machine's scratchpad,
not committed anywhere):
`01_login.png`, `02_feed_owner_home.png`, `03_owner_chat_screen.png`,
`04_owner_chat_message_sent.png`, `05_admin_dashboard.png`,
`06_admin_feed_chat_inbox.png`, `07_admin_feed_chat_detail.png`,
`08_admin_reply_sent.png`, `09_admin_resolved.png`,
`10_owner_sees_reply_after_relogin.png`, `11_owner_community.png`.

## Exact URLs / ports / build identifier

- Frontend (verification session): `http://127.0.0.1:8080` (static
  `flutter build web --release` output from `build/web`).
- Backend: `http://127.0.0.1:8000` (Django `runserver`, WSGI, dev Postgres DB
  `featherflow`).
- Flutter: `3.47.2` stable, Dart `3.13.2`.
- Both dev servers were stopped at the end of this session (ports 8000 and
  8080 confirmed free).

## What was NOT built (explicitly out of scope for this pass)

This session's mandate (per the follow-up instruction) was the **Feed
Inventory Owner role, its chat with Feed Admin, and Community access for both
roles** — the broader "Feed Marketplace Admin complete rebuild" prompt's
items (dashboard metrics, product/stock CRUD, order queue, delivery
assignment, proof review, maps) were **already implemented** before this
session (§1 of the audit doc) and were not re-verified screen-by-screen in
this browser pass beyond confirming the admin dashboard and sidebar still
render correctly with the new nav item added. If a full re-verification of
that pre-existing surface is wanted, it should be scoped as its own pass.

## Confirmation

Nothing was committed. `git status` still shows every file below as
modified/untracked in the working tree only.
