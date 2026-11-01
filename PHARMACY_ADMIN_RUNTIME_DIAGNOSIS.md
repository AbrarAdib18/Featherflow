# Pharmacy Admin Runtime Diagnosis

Date: 2026-09-26. Diagnosis only. No code was changed to produce this report.
Read-only `curl` calls were made against the already-running backend
(`http://127.0.0.1:8000`) to capture the exact login/permissions payloads a
browser session would receive — no state was mutated. No browser-automation
tool is available in this environment (confirmed by tool search earlier in
this session), so the login was not re-driven through an actual browser click
here; the API-level evidence below is what a browser session receives and
acts on, byte for byte, since the Flutter code paths cited consume these
exact same endpoints.

## Observed UI

Per the reported screenshot, after logging in as `pharmacy.admin@featherflow.local`,
the sidebar shows exactly: **Dashboard, Pharmacy, Audit Trail, My Profile, Sign
Out**. It does not show separate entries for Pharmacy Accounts, Medicine
Catalogue, Inventory, Orders, Sales & Commissions, Settlements, Employees,
Appeals, Delivery Assignments, Pharmacy Chat, or Reports & Audit.

## Login response

`POST /api/auth/login/` with the given credentials returns (captured live,
this session and prior sessions, identical each time):
```
"roles": ["admin_pharmacy"], "account_status": "active", ...
```
File: `backend/users/views.py`, `UserViewSet.login` (registered
`backend/users/urls.py:8`).

## Role and permissions

The admin shell does **not** derive its sidebar from the login response's
`roles` field directly. After login, `AdminSession.load()` calls a second
endpoint, `GET /api/admin-panel/me/`
(`backend/api/admin_extra.py:97`, route `backend/api/urls.py:100`), and it is
**this** response's `permissions`/`accessible_modules` fields that gate the
sidebar. Captured live this session:

```json
{
  "role": "admin_pharmacy",
  "tier": 3,
  "permissions": {
    "audit": ["view"],
    "pharmacy": ["approve","assign","create","delete","edit","export","refund","reject","suspend","view"]
  },
  "accessible_modules": ["audit", "pharmacy"]
}
```

Built by `effective_permissions(user)` / `accessible_modules(user)`
(`backend/api/admin_rbac.py:99` and `:142`), which union every admin role's
`role.permissions` JSON column (seeded in `postgres_backend_extension.sql`
and `admin_rbac.py`'s RBAC matrix). The `admin_pharmacy` role's permission map
in the database has exactly two keys: `pharmacy` (ten actions) and `audit`
(`view`). **There is no `medicines`, `orders`, `sales`, `settlements`,
`employees`, `appeals`, or `delivery` module key in this role's permission
map at all** — every one of those capabilities is modeled as an *action*
under the single `pharmacy` module, not as a separate module.

## Flutter role-routing condition

`lib/core/network/auth_service.dart:307-327`, `getRoleDestination()`:
```dart
if (normalizedRole == 'admin' || normalizedRole.startsWith('admin_') || normalizedRole == 'feed_admin') {
  return AppRoutes.adminDashboard;   // line 318
}
```
`admin_pharmacy` matches `startsWith('admin_')` → destination is
`AppRoutes.adminDashboard` = `/admin` (the **generic** admin dashboard, not
`/admin/pharmacy` directly).

## Route opened after login

`/admin` (`AppRoutes.adminDashboard`), rendering `AdminDashboardScreen`
wrapped in the same `AdminScaffold`/`AdminSidebar` used by every admin
screen. The user must click the "Pharmacy" sidebar item to navigate to
`/admin/pharmacy`.

## Rendered shell

`lib/features/admin/presentation/widgets/admin_scaffold.dart:61`
(`AdminScaffold`), which composes `AdminSidebar` (wide) or a `Drawer`
(narrow) — `admin_scaffold.dart:102` and `:213`.

## Sidebar source

`lib/features/admin/presentation/widgets/admin_sidebar.dart:9-190`
(`AdminSidebar.build`). It is a **flat, fixed list of top-level modules**,
each wrapped in `if (session.canAccess(AdminModule.X)) _NavItem(...)`. There
is exactly one pharmacy-related entry:

```dart
// admin_sidebar.dart:60-68
if (session.canAccess(AdminModule.pharmacyManagement))
  _NavItem(icon: Icons.local_pharmacy_outlined, label: 'Pharmacy',
    route: '/admin/pharmacy', module: AdminModule.pharmacyManagement, ...)
```

`My Profile` (`admin_sidebar.dart:239-259`) and `Sign Out`
(`admin_sidebar.dart:260-277`) are in `_SidebarFooter` and are **unconditional**
— not gated by any permission check at all, which is why they always appear
regardless of role.

There is no code path anywhere in this file, or anywhere in the codebase
(confirmed by search — see "Search results" below), that renders "Pharmacy
Accounts", "Medicine Catalogue", "Inventory", "Sales & Commissions",
"Settlements", "Employees", "Appeals", "Delivery Assignments", "Pharmacy
Chat", or "Reports & Audit" as their own sidebar entries. Those strings do
not exist as sidebar labels in the source at all.

## Pharmacy Admin route registration

`lib/core/router/app_router.dart:177` (`static const adminPharmacy = '/admin/pharmacy';`)
and `:770-772`:
```dart
GoRoute(path: 'pharmacy', name: 'adminPharmacy',
  builder: (context, state) => const AdminPharmacyScreen())
```
This route **is** registered and **does** point at the current
`AdminPharmacyScreen` (`lib/features/admin/presentation/screens/admin_pharmacy_screen.dart`).
That screen — reached only by clicking "Pharmacy" in the sidebar — contains
7 tabs: Pharmacies, Medicine Approvals, Expiry Monitoring, Orders & Delivery,
Chat & Appeals, Sales & Settlements, Reports & Audit (`admin_pharmacy_screen.dart:581-588`
in the version currently running; see "Build output" below for a caveat).
This is where most of the 11 requested sections actually live — as tabs
inside one screen, not as separate sidebar items:

| Requested sidebar item | Actual location |
|---|---|
| Pharmacy Accounts | "Pharmacies" tab |
| Medicine Catalogue | "Medicine Approvals" tab |
| Inventory | "Expiry Monitoring" tab (doubles as inventory view) |
| Orders | "Orders & Delivery" tab |
| Delivery Assignments | embedded widget inside "Orders & Delivery" tab |
| Sales & Commissions | "Sales & Settlements" tab |
| Settlements | "Sales & Settlements" tab |
| Employees | a button inside each pharmacy's account-review sheet (not a tab) |
| Appeals | "Chat & Appeals" tab |
| Pharmacy Chat | "Chat & Appeals" tab |
| Reports & Audit | "Reports & Audit" tab |

This consolidation was a **documented, deliberate decision from an earlier
work pass**, not an accident: `PHARMACY_ADMIN_IMPLEMENTATION_REPORT.md` §26
("Why one shell, not a second `/admin/pharmacy` route") explicitly argues
against building 11 separate sidebar entries, citing the platform's existing
"one coherent admin shell" convention and stating outright that "the
`AdminPharmacyScreen` reached from that shell's 'Pharmacy' sidebar item **is**
the Pharmacy Administration panel."

## Frontend URL / Backend URL

- Frontend base URL the Flutter app calls: `http://127.0.0.1:8000` — hardcoded
  default in `lib/core/network/auth_service.dart:222`, used unless a
  `--dart-define=API_BASE_URL=...` was passed at build/run time (none was, in
  this session).
- Backend process: Django/DRF served by `uvicorn` on `127.0.0.1:8000`
  (confirmed listening this session, PID captured via `netstat`).
- Frontend the browser would hit in this session: `http://127.0.0.1:8090`,
  served by `flutter run -d web-server --web-port 8090 --web-hostname
  127.0.0.1 --release` — **not** `flutter build web --release`'s static
  `build/web` output. This is a live dev-server process compiling from
  current source, not a pre-built static bundle.

## Build output

Two different build artifacts exist from this session's work and must not be
conflated:
1. `flutter build web --release` was run once, producing `build/web/` (a
   static bundle) — nothing currently serves this directory.
2. `flutter run -d web-server --web-port 8090 ...` is the actual running
   process. Unlike a static build, this dev-server pipeline normally requires
   an explicit hot-reload/hot-restart trigger (a keypress on its own stdin)
   to pick up source edits made after it started. This session has no
   interactive stdin channel into that background process, so **any source
   edit made after that process was last (re)started is not guaranteed to be
   reflected in what the browser currently receives from port 8090**,
   independent of anything reported above. The sidebar behavior described in
   this report, however, predates every edit made in this session (it is
   unchanged prior-session code, confirmed by reading it directly on disk)
   — so this staleness risk does not affect the conclusion below, but it is
   a real, separate risk for any other very recent edit and is flagged
   honestly rather than assumed away.
3. No Flutter web release build registers a service worker in dev-server
   mode (`flutter run -d web-server` does not use `flutter_service_worker.js`
   — that mechanism is specific to a `flutter build web` static bundle served
   as static files), so stale service-worker caching is not a factor for the
   port-8090 process specifically.

## Search results (for the terms requested)

- `pharmacy.admin@featherflow.local` — only in seed/credential-doc files and
  the account itself; no special-cased routing logic keyed on this literal
  email anywhere.
- `pharmacy_admin` / `admin_pharmacy` — the DB role name; drives RBAC only
  (`admin_rbac.py`), never referenced by the Flutter router or sidebar
  (they only ever see the resolved `permissions`/`accessible_modules` map,
  never the raw role string, except for the destination-routing check in
  `auth_service.dart:315-319` which only tests the `admin_` *prefix*, common
  to all seven admin sub-roles, not this role specifically).
- `Dashboard` / `Audit Trail` — sidebar labels defined once each, in
  `admin_sidebar.dart` (lines 30 and 159 respectively) and
  `admin_role.dart`'s `kModuleDisplayNames` map.
- `Sales`, `Settlements`, `Employees`, `Appeals`, `Reports` — all found only
  as tab labels/widget names *inside* `admin_pharmacy_screen.dart`
  (e.g. `Tab(text: 'Sales & Settlements')`), never as `AdminModule` enum
  values or sidebar strings. `AdminModule` (`admin_role.dart:76-103`) has no
  enum member for any of these — confirming they were never modeled as
  separate top-level modules in the Flutter permission system at all.

## Root cause

**This is not a routing bug, a stale build, a broken permission check, or a
disconnect between the backend and the real owner account.** The sidebar is
rendering exactly what the live backend's RBAC data says the `admin_pharmacy`
role can access: one module, `pharmacy`, with ten actions, plus universal
read-only `audit`. The Flutter sidebar has exactly one nav item per
`AdminModule` enum value, and no enum value exists for "Pharmacy Accounts,"
"Employees," "Settlements," etc., because an earlier work pass deliberately
built those as **tabs inside the single "Pharmacy" screen** rather than as
separate top-level admin modules with their own RBAC permission keys and
sidebar entries — a decision recorded in
`PHARMACY_ADMIN_IMPLEMENTATION_REPORT.md` §26, not something this session
introduced.

The gap between what's running and what was asked for is real, but it is an
**information-architecture mismatch against the original spec's literal
12-item nav list**, not a broken pipeline: clicking "Pharmacy" in the
sidebar does open a screen containing 7 (functionally overlapping) tabs that
cover most of the requested sections, just not as distinct, always-visible
sidebar entries, and not labeled to match the spec's exact section names.

## Minimal fix

Two independent, non-exclusive options, neither implemented in this pass:

1. **Cosmetic/navigational** (smaller change): rename the existing 7 tabs to
   match the spec's exact section names 1:1 where they don't already
   (e.g. "Medicine Approvals" → "Medicine Catalogue", "Expiry Monitoring" →
   "Inventory"), and add 2 missing dedicated tabs/sections for "Employees"
   and "Delivery Assignments" (currently embedded in other screens, not
   top-level tabs) — all inside the existing single `AdminPharmacyScreen`,
   no RBAC or router changes needed. This keeps the "one coherent shell, no
   duplicate sidebars" property `PHARMACY_ADMIN_IMPLEMENTATION_REPORT.md`
   §26 argued for.
2. **Literal spec match** (larger change): give each of the 11 sections its
   own `AdminModule` enum value, its own sidebar `_NavItem`, its own route,
   and its own backend RBAC permission key (splitting the single `pharmacy`
   module's action list into per-feature modules) — this is the change §26
   explicitly weighed and rejected in favor of option 1's approach, on the
   grounds that it fragments the admin shell and contradicts the platform's
   own "no duplicate navigation, one coherent shell" convention used by every
   other admin module.

Neither option was implemented. Which one to build is a product decision
(sidebar depth vs. tab depth), not a bug fix — flagged back to the user
rather than assumed.

## Command / URL to reproduce this diagnosis

- Backend already running: `http://127.0.0.1:8000` (uvicorn).
- Frontend already running: `http://127.0.0.1:8090` (`flutter run -d
  web-server --web-port 8090 --web-hostname 127.0.0.1 --release`).
- To see the tabs referenced above without any code change: open
  `http://127.0.0.1:8090`, log in with `pharmacy.admin@featherflow.local` /
  `ChangeMe@2026!`, and click the **"Pharmacy"** sidebar item (not just view
  the sidebar itself).
