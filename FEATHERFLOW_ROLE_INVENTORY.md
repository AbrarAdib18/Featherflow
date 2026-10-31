# FEATHERFLOW — Role Inventory

Sources: `roles` / `user_roles` tables in the live DB, `backend/api/admin_rbac.py`, `backend/users/{models,views,serializers}.py`, `backend/profiles/models.py`, `lib/core/network/auth_service.dart` (`getRoleDestination`), `lib/features/admin/data/models/admin_role.dart`, `lib/core/router/app_router.dart`, seed commands, plus live login probes (`POST /api/auth/login/`) and Chrome logins for 24 accounts.

**Result: 19 `roles` rows exist (not the 6–9 originally planned).** 7 non-admin + 12 admin-panel roles. Account counts below are from the live DB (including automated-test accounts).

## 1. Role matrix

`Login route` = destination from `AuthService.getRoleDestination(roles.first)`. All roles log in through the single `/login` screen and `POST /api/auth/login/` (email + password, JWT access/refresh). "Separate login" = does the role have its own login page/credentials *distinct from the shared screen* (none do; separation is by account + role-based routing).

| Role | DB value (`roles.name`) | Separate login | Profile model | Signup | Statuses (observed) | Login route | Flutter shell | Permission source | Demo account (password) | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| Farmer | `farmer` (28 users) | No (shared login) | `profiles.FarmerProfile` (+ `farms.Farm`, flocks) | Self-signup `/signup/farmer`, `POST /api/auth/register/` | `users.account_status`: active | `/farmer` | `FarmerDashboardScreen` (4-tab bottom nav) | JWT + `IsFarmer`-style class perms + object ownership | `farmer.rashed@example.com` (FeatherflowDemo@2026) | **Working** (UI+API verified live) |
| Veterinarian | `doctor` (16) | No | `profiles.DoctorProfile` | Self-signup `/signup/doctor` (docs upload) | users: active; approval via profile/verification (pending demo `dr.pending.kabir@…` shows `active` in users) | `/doctor` | `DoctorDashboardScreen` | JWT + `IsDoctor` | `dr.mahfuz.kabir@example.com` | **Working** |
| Pharmacy owner | `pharmacy` (5: 4 active, 1 suspended) | No | `profiles.PharmacyOrganization` + `pharmacy.PharmacyOrganization` (admin-panel record) | Self-signup `/signup/pharmacy` | active / suspended (suspended may still log in to a restricted session → appeal flow) | `/pharmacy` | `PharmacyDashboardScreen` (6 bottom tabs, state-based, no sub-routes in use) | JWT + `pharmacy.permissions` (lock state) | `pharmacy.agrocare@example.com` | **Working when active** (live); suspended/appeal path **broken in the UI** (F-002); locking/unlock only script-verified |
| Pharmacy employee | *no role row* — `pharmacy.PharmacyEmployee` roster only (`access_level` staff/manager/pharmacist) | **No login** (by design: "acts under the owner's account") | `PharmacyEmployee` | Added by owner | `is_active` | n/a | n/a | n/a | n/a | **By design not a login** — documented gap vs. the "employee login" expectation |
| `pharmacist` (legacy) | `pharmacist` (1 user `pharmacist.demo@example.com`) | Can authenticate | **none** (schema mentions `pharmacist_profiles`, no model) | No self-signup (not in allowed role list) | active | falls through to **`/farmer`** (default branch) | Farmer shell (wrong) — backend returns 403 on farmer & pharmacy APIs | none | `pharmacist.demo@example.com` | **Broken / orphan role** (F-ROLE-01) |
| Delivery rider | `delivery` (7) | No | `profiles.DeliveryProfile` | Self-signup `/signup/delivery` (license, vehicle docs) | active (+ profile approval; attendance present/absent) | `/delivery` | `DeliveryDashboardScreen` (5 tabs) | JWT + `IsDeliveryUser` | `rider.arif@example.com` | **Working** (route/ETA broken, F-DLV-01) |
| Researcher | `researcher` (5: 4 active, 1 suspended) | No | `profiles.ResearcherProfile` (+ change-applications) | Self-signup `/signup/researcher` | active / suspended (**suspended researcher cannot log in: 401**; suspended pharmacy can) | `/research` | `ResearchDashboardScreen` | JWT + researcher perms | `research.fariha@example.com` | **Working** |
| Feed Inventory Owner | `feed_owner` (1) (`panel_type='feed_owner'`, tier 4) | No | `profiles.FeedOwnerProfile` (+ `feed_companies`) | **No self-signup** (admin/seed created) | active | `/feed-owner` | `FeedOwnerHomeScreen` (3 actions only) | `feed_catalogue/owner_permissions.py` + admin 403 on `/api/admin-panel/*` | `feed.owner@featherflow.local` (ChangeMe@2026!) | **Working**, limited scope as designed |
| Feed Marketplace Admin | `feed_admin` (2) (`panel_type='admin'`, tier 3; name has no `admin_` prefix) | No | `profiles.AdminProfile` | No self-signup (seed) | active | `/admin` (explicit `feed_admin` branch) | `AdminScaffold` + role-filtered `AdminSidebar` | `roles.permissions` {`feed-orders`,`feed-delivery`,`feed-catalogue`,`audit`} | `feed.admin@featherflow.local` | **Working** |
| Pharmacy Admin | `admin_pharmacy` (4) (tier 3) | No | `AdminProfile` | Admin signup `/signup/admin` → approval, or seed | active | `/admin` | `AdminScaffold` | `roles.permissions.pharmacy` = view/create/edit/approve/reject/suspend/assign/export/refund/delete + `audit.view` | `pharmacy.admin@featherflow.local` (ChangeMe@2026!), `pharmacy.admin@featherflow.dev` | **Working** (see N+1 fault) |
| Super Admin | `admin_super` (7) (tier 1) | No | `AdminProfile` | Seed / created by Super | active | `/admin` | `AdminScaffold` (all modules) | `{"*":["*"]}` wildcard | `admin.super@example.com`, `super.admin@featherflow.dev` | **Working** |
| Operations Admin | `admin_operations` (3) (tier 2) | No | `AdminProfile` | Seed / Super | active | `/admin` | `AdminScaffold` | `roles.permissions` (users, doctors, finance view/export, support, articles, delivery, pharmacy, research, …) | `ops.nusrat@example.com` | **Working** |
| Legacy generic admin | `admin` (3) (tier 2) | No | `AdminProfile` | Admin signup → approval | active | `/admin` | `AdminScaffold`; Flutter maps `admin`→Operations | same as Operations (fallback map if JSON empty) | `dasd@gmail.com` (password unknown, unlogged) | **Duplicate/alias of `admin_operations`** (F-ROLE-02) |
| Finance Admin | `admin_finance` (4) (tier 3) | No | `AdminProfile` | Seed / Super | active | `/admin` | `AdminScaffold` | finance, cashouts, subscriptions + audit | `finance.tanvir@example.com` | **Working** |
| Content Admin | `admin_content` (4) | No | `AdminProfile` | Seed | active | `/admin` | `AdminScaffold` | articles CRUD, research approve/reject, community moderation | `content.admin@featherflow.dev` | **Working** |
| Research Admin | `admin_research` (3) | No | `AdminProfile` | Seed | active | `/admin` | `AdminScaffold` | articles, research (incl. suspend) | `research.admin@featherflow.dev` | **Working** |
| Delivery Admin | `admin_delivery` (4) | No | `AdminProfile` | Seed | active | `/admin` | `AdminScaffold` | delivery incl. refund/suspend/export | `delivery.admin@featherflow.dev` | **Working** |
| Doctor Admin | `admin_doctor` (2) | No | `AdminProfile` | Seed | active | `/admin` | `AdminScaffold` | doctors, support view, escalations view | `doctor.admin@featherflow.dev` | **Working** (extra role beyond the requested list) |
| Team Admin | `admin_team` (1) | No | `AdminProfile` | Seed | active | `/admin` | `AdminScaffold` | team (create/edit/assign/suspend), approvals view | `team.admin@featherflow.dev` | **Working** (extra role) |
| Support Agent | `admin_support` (4) (tier 4) | No | `AdminProfile` | Seed | active | `/admin` | `AdminScaffold` | users/doctors/community **view**, support create/edit/assign, escalations create/view | `support.raisa@example.com` | **Working** |

Role string conventions: platform-admin roles are `admin_<module>`; `feed_admin` (admin panel) and `feed_owner`, `pharmacist`, `delivery`, `doctor`, `farmer`, `pharmacy`, `researcher` have no prefix.

Counts by role (live DB `users` × `user_roles`): farmer 28, doctor 16, delivery 7, pharmacy 5, researcher 5, pharmacist 1, feed_admin 2, feed_owner 1, admin 3, admin_super 7, admin_operations 3, admin_finance 4, admin_content 4, admin_research 3, admin_delivery 4, admin_doctor 2, admin_pharmacy 4, admin_support 4, admin_team 1. 108 `user_roles` rows. Users by `account_status`: active 105, suspended 1, pending 1. One user (`selftestfc6b19@x.com`) has **no role**.

## 2. Account / session / login behaviour (verified)

| Topic | Behaviour |
|---|---|
| Login | `POST /api/auth/login/` {email,password} → `{user, access, refresh, next, user_url}`; `user.roles[]` is a list of role names; admin permissions come from a second call `GET /api/admin-panel/me/` (`roles, tier, permissions`). |
| Tokens | SimpleJWT access+refresh; tampered token → 401; `alg=none` token → 401. Stored client-side in `flutter_secure_storage` (IndexedDB/WebCrypto on web). |
| Pending applicants | Backend returns `next: "pending_approval"` + `account_status` for a genuinely pending doctor/pharmacy/rider/researcher/admin (script-verified: `test_signup_flows` 107, `test_verification_flows` 36). **No genuinely pending account existed to observe in the browser**: the demo accounts named `*.pending.*` are approved/active (`/api/pharmacy/permissions/` → `ACTIVE, review_state approved`), so the pending/locked UI was not seen live (F-029). |
| Suspended | Researcher/others: login refused (401, "suspended" — observed for `research.sabiha` *before* the seed runs re-activated it, F-015). Pharmacy: restricted API session so the owner can file an **appeal** (script-verified) — **but the Flutter client immediately ejects a suspended pharmacy back to `/login` (F-002)**. |
| Session revocation | `UserUpdatesService` polls `/api/me/updates/`; if an admin suspends the user the app signs out (`?revoked=1`). |
| Rate limit | `auth_login` 20/min per IP (verified 429 on the 21st attempt, which also blocks valid logins from that IP). |
| Multi-role | A user may hold several roles (e.g. `admin`+`admin_super`). The Flutter router uses `roles.first` (order from the API) for destination. |

## 3. Admin RBAC (server-enforced) — Flutter sidebar vs API

Tier/permission source: `roles.tier_level` + `roles.permissions` JSON; enforced in `ModulePermission`/`IsAdminUser` (`api/admin_rbac.py`). The read-only authorization sweep (151 param-free GET routes × 19 identities, 2,869 requests) found **0 non-admin roles with 2xx on any `/admin*` route and 0 anonymous 2xx on protected routes**; admin sub-roles are limited to their modules (matrix in `FEATHERFLOW_SECURITY_AND_DATA_INTEGRITY_REPORT.md` §3). Audit-log reads are scoped per role (Super/Ops 7,523 rows; Support 1,409; Pharmacy Admin 1,156; Content 341; Feed Admin none).

## 4. Findings flagged by this inventory

IDs `F-ROLE-0x` below map to the fault register as: F-ROLE-01 = F-006, F-ROLE-03 = F-007, F-ROLE-07 = F-029, F-ROLE-04 = F-032 (the others are informational).

| ID | Finding |
|---|---|
| F-ROLE-01 | `pharmacist` role is an orphan: can log in, has no profile model, no route, no permissions; Flutter falls through to the **farmer shell** (default branch of `getRoleDestination`). |
| F-ROLE-02 | `admin` (legacy) duplicates `admin_operations` (same tier + permissions); both exist, and `adminRoleFromName` maps `admin`→Operations. Unknown admin role names map to *Support Agent* (safe least-privilege fallback). |
| F-ROLE-03 | No role-based **route guard** in the Flutter router: `_redirect` only checks "authenticated or not". Any signed-in user can open `#/admin/...`, `#/pharmacy/...` etc. by URL; the backend then returns 403 (data safe) but the user sees a broken shell. Verify in browser report. |
| F-ROLE-04 | Pharmacy employees have no login (roster only). Fine if intended; contradicts any requirement that employees sign in separately. |
| F-ROLE-05 | `roles.first` is used to decide the shell; users with several roles land in whichever role the API lists first. |
| F-ROLE-06 | Roles present in backend but not in Flutter enum: `admin` (aliased), `pharmacist` (none). Roles in Flutter but not backend: none. |
| F-ROLE-07 | Pending demo accounts have `account_status='active'`; the users table alone cannot identify pending applicants. |
| F-ROLE-08 | Super-admin accounts are plentiful (7 accounts incl. test/smoke accounts `smoke.admin*`, `doctortest+admin@…`, `adminpaneltest+super@…`) — remove automated-test super admins from non-dev databases. |
