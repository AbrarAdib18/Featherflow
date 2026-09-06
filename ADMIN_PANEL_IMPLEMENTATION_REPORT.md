# Admin Panel — Implementation Report

**Status: complete and tested.**

- **Backend** — RBAC, immutable audit, approval queue, admin management, oversight,
  escalations, real support desk, **real finance module**, **real security monitor**,
  per-module polling. `34/34` e2e assertions pass, full existing suite green,
  every endpoint verified over real HTTP with real login tokens per role.
- **Frontend** — `AdminSession` server-driven, demo switcher removed, 4 new screens,
  per-module activity sheets, real finance summary cards, user-side polling +
  access-revoked redirect. `flutter analyze` **0 errors**, `flutter build web`
  succeeds, `11/11` widget/logic tests pass (RBAC gate, every new screen renders,
  app boots to the panel). App confirmed booting in a real browser (screenshot).
- **Residual:** a human clicking every button in the running Flutter app against the
  live backend — the HTTP contract is proven end-to-end (login → JWT → every
  endpoint, RBAC boundaries), the canvas rendering is proven by widget tests and a
  browser screenshot, but the two haven't been driven together by hand. See §12.

---

## 1. What was inspected

- **Backend:** `api/admin_views.py` (1100 lines), `api/urls.py`, `api/admin_registry.py`;
  `users/{models,views,serializers,urls}`; `profiles/models.py` (`AdminProfile`);
  `audit/models.py`; `research/{views,permissions}.py` and `delivery/views.py` for
  conventions; `featherflow_backend/{settings,urls,database_router}.py`;
  `requirements.txt`; both SQL schema files; every app's `migrations/`.
- **Live database** (`featherflow` on localhost:5432): confirmed the connected
  schema, 11 users, `roles` 1–15 already using the `admin_*` prefix,
  `admin_profiles`, `activity_logs`, `permissions`/`role_permissions` (unused).
- **Frontend:** all 11 admin screens, `AdminSession`, `admin_role.dart`,
  `AdminApiService`, `audit_service.dart`, scaffold/sidebar/guard/dialogs,
  `admin_signup_screen`, `app_router.dart`, `core/network/auth_service.dart`,
  `main.dart`.
- **Environment:** Python 3.12 venv, PostgreSQL reachable, Flutter SDK present.

## 2. Gap analysis summary (what was missing)

See `ADMIN_PANEL_GAP_ANALYSIS.md`. Headline gaps that were closed:

| Gap | Resolution |
|---|---|
| RBAC was cosmetic — `AdminSession` hard-coded Super Admin, demo role switcher | `AdminSession` now loads role/tier/permissions from `/api/admin-panel/me/`; switcher removed |
| No tier system; `permissions`/`role_permissions` tables dead | `roles` carries `permissions` JSON + `tier_level`; seeded for all 10 roles |
| Anyone could self-register a live admin | Admin signup → `account_status='pending'` + `approval_status='pending'`; SimpleJWT blocks inactive login until approved |
| No permission helpers; most endpoints only checked `IsAdminUser` | `api/admin_rbac.py` — tier predicates + `can_perform_action`; `_gate()` chokepoint on every `admin_collection`/`admin_record` call |
| `roles.name` inconsistency (`super_admin` vs `admin_super` …) | Canonicalised on the `admin_*` prefix already in the DB; `is_superuser` bug fixed |
| Approval queue absent (Team "needs approval" was fake) | `admin_approval_queue` table + `api/admin_approvals.py` + endpoints; sensitive actions return **202 queued** |
| Audit not immutable, no `reason`/`user_agent`/`action_type`, no viewer | 4 columns added + DB trigger + model guard; list endpoint w/ filters + override; **Audit Trail screen** |
| No Operations tier / oversight / escalations | `admin_escalations` table + `/oversight/` + `/escalations/` endpoints + **Oversight screen** |
| Support/Team on JSON seed store | Real `support_tickets` + `support_ticket_replies` tables; Team now creates real `AdminProfile` rows |
| No real-time reflection to users | `/api/me/updates/?since=` polling endpoint + `UserUpdatesService` (12s) + router redirect on suspend |
| No rate limiting, no export | `api/throttling.py` scoped throttle; `/<module>/export/` CSV endpoint |

## 3. Frontend screens created / modified

**Created**
- `admin/presentation/screens/admin_admins_screen.dart` — Admin Management (Super
  creates/edits/role-changes; Operations approves/suspends/recovers pending registrations).
- `admin/presentation/screens/admin_approvals_screen.dart` — Approval Queue
  (pending/approved/rejected/all tabs; approve / reject-with-reason / Super override).
- `admin/presentation/screens/admin_audit_screen.dart` — Audit Trail viewer
  (module + action-type filters, pagination, before/after diff, Super override).
- `admin/presentation/screens/admin_oversight_screen.dart` — Activity + Escalations tabs.
- `admin/presentation/widgets/admin_states.dart` — shared loading/empty/error.
- `core/network/user_updates_service.dart` — the user-side poller.

**Modified**
- `admin/data/models/admin_role.dart` — added `doctorAdmin`/`teamAdmin`, new modules
  (`approvals`, `auditTrail`, `oversight`, `escalations`, `adminManagement`,
  `platformSettings`), server-driven `AdminPermissions` (fallback matrix kept).
- `admin/data/services/admin_session.dart` — rewritten to load from `/me/`; exposes
  `tier`, `isSuperAdmin`, `isOperationsAdmin`, `permissions`.
- `admin/data/services/admin_api_service.dart` — ~20 new methods; 202→`AdminApprovalRequired`,
  403-suspended→`AdminApiException.isAccessRevoked`, CSV export.
- `admin/data/services/audit_service.dart` — in-memory mock replaced with API-backed `fetch()`; `log()` is now a no-op (backend records it).
- `admin/data/models/audit_log.dart` — real fields (`actionType`, `reason`, `oldValue`/`newValue`, `ipAddress`).
- `admin/presentation/screens/admin_dashboard_screen.dart` — **demo role switcher removed**, replaced with read-only role badge; dynamic alert banners (approvals / escalations / registrations); quick-links row.
- `admin/presentation/screens/admin_profile_screen.dart` — `setRole` call → `AdminSession.refresh()`.
- `admin/presentation/widgets/admin_sidebar.dart` — nav for Approval Queue / Oversight / Audit Trail / Admin Management (permission-gated).
- `core/router/app_router.dart` — 4 routes; `refreshListenable: UserUpdatesService.instance`; redirect to `login?revoked=1` when access is revoked mid-session.
- `core/network/auth_service.dart` — `getRoleDestination` recognises any `admin*` role.
- `core/network/*` + `main.dart` — start/stop the poller with the session.
- `auth/presentation/screens/login_screen.dart` — "access changed, sign in again" notice.

## 4. Database models / migrations added

**SQL** (both `featherflow_schema.sql` and `backend/postgres_backend_extension.sql`,
idempotent):

| Object | Change |
|---|---|
| `roles` | + `permissions JSONB`, `tier_level SMALLINT`, `is_system BOOLEAN`, `updated_at` |
| `roles` | + rows `admin_doctor`, `admin_team`; permission matrices + tiers seeded for all 10 |
| `admin_profiles` | + `admin_role_id` FK, `access_level_requested`, `prior_admin_operations_experience`, `internal_approval_by_founder_hr`, `strong_password_2fa_enabled`, `is_active`, `is_suspended`, `suspended_at`, `suspended_by`, `approval_status`; `admin_sub_role` CHECK extended with `doctor`,`team`; `updated_at` trigger |
| `activity_logs` | + `action_type`, `reason`, `user_agent`, `request_id`; **BEFORE UPDATE OR DELETE trigger** raising an exception (immutable); 4 indexes |
| `admin_approval_queue` | **new** — parked sensitive actions |
| `admin_escalations` | **new** — issues pushed up to Operations/Super |
| `support_tickets`, `support_ticket_replies` | **new** — real support desk |
| polling indexes | `idx_*_updated` on researcher/doctor/delivery/pharmacy profiles, medicines, articles; `idx_notifications_user_created`; `idx_delivery_orders_assigned` |

**Django** (all `managed = False`; state-only migration since the router blocks
schema-owned apps):
- `audit/migrations/0003_admin_rbac.py` — `ActivityLog` fields, `AdminApprovalQueue`,
  `AdminEscalation`, `SupportTicket` (proxy → real), `SupportTicketReply`.
- Model edits: `users.Role` (+permissions/tier/is_system), `profiles.AdminProfile`
  (+10 fields), `audit.models` (rewrote `ActivityLog`, added 3 models, dropped the
  `SupportTicket` proxy).

## 5. APIs added / modified

**Added** (all under the existing `/api/admin-panel/` prefix — decision D1):

| Method + path | Purpose |
|---|---|
| `GET /me/` | caller's role, tier, permission matrix, accessible modules |
| `GET/POST /admins/` | list / create admin accounts (create = Super only) |
| `GET/PATCH/DELETE /admins/<uuid>/` | detail / edit / soft-deactivate (Super) |
| `POST /admins/<uuid>/action/` | suspend / recover / approve / reject (Operations+) |
| `GET/PATCH /roles/` | role catalogue; PATCH permissions (Super) |
| `GET /audit-logs/` | filters: `admin_id, module, action_type, target_id, since, until`, `limit/offset` |
| `POST /audit-logs/<uuid>/override/` | append-only reversal (Super) |
| `GET /approval-queue/` · `POST /approval-queue/<uuid>/decide/` | `decision` = approve / reject / override |
| `GET /oversight/` | 7-day activity by admin & module, module backlog (Operations+) |
| `GET/POST /escalations/` · `POST /escalations/<uuid>/resolve/` | claim / resolve (Operations+) |
| `GET /<module>/export/` | CSV of any module the caller can view |
| `GET /admin-panel/finance/summary/` | MRR, lifetime revenue, payout liability, refunds, plans |
| `GET /api/me/updates/?since=<iso>` | user-facing poll (notifications + account/verification state + `access_revoked`) |
| `GET /api/{research,delivery,pharmacy,doctors}/updates/?since=<iso>` | per-module aliases of the poll |
| `GET/POST /api/support/tickets/` | users file & track their own tickets |

**Modified**
- `GET /admin-panel/dashboard/` — real `SupportTicket` counts; + `pending_approval_requests`, `open_escalations`, `pending_admin_registrations`; activity carries `action_type`.
- `GET/POST /admin-panel/<module>/` and `PATCH/DELETE /<module>/<id>/` — now pass
  through `_gate()` (RBAC) and `_maybe_enqueue()` (approval routing). `support-tickets`
  now read/write the real table.
- `_log()` — records `action_type`, `reason` (from request body), `user_agent`.
- `POST /api/auth/register/` (role `admin`) — pending state + specific role + reviewer notifications.

## 6. Roles & permissions structure

`roles.tier_level`: **1** `admin_super` · **2** `admin_operations` (+ legacy `admin`)
· **3** `admin_finance / admin_content / admin_research / admin_delivery /
admin_pharmacy / admin_doctor / admin_team` · **4** `admin_support`.

`roles.permissions` = `{ "<module>": ["<action>", …] }`, or `{"*":["*"]}` for
`admin_super`. Modules: `users, doctors, delivery, pharmacy, research, articles,
community, subscriptions, finance, support, team, audit, approvals, escalations,
oversight, settings`. Actions: `view, create, edit, approve, reject, delete,
suspend, assign, export, refund, override`.

Resolution (`api/admin_rbac.py`): a user's effective permissions = the union of
every `panel_type='admin'` role they hold; their tier = the lowest `tier_level`.
`can_perform_action(user, module, action)` is checked on every admin endpoint;
the frontend receives the same map from `/me/` and gates the UI identically.
Privilege escalation is blocked: only Super assigns roles / creates admins, the
Super role can't be assigned through the API, and a user can't approve their own
queued request.

## 7. How audit logging works

Every admin mutation calls `_log(request, module, action, id, old, new,
action_type, reason)` → one `activity_logs` row with `user`, `ip_address`,
`user_agent`, JSON `old_value`/`new_value`, and a typed `action_type`.

Immutability is enforced twice: a PostgreSQL `BEFORE UPDATE OR DELETE` trigger
raises an exception, and `ActivityLog.save()`/`delete()` refuse on an existing
row. "Override" never edits the original — it appends a new `action_type='override'`
row (with swapped old/new) and best-effort restores the affected record.

`GET /admin-panel/audit-logs/` supports admin / module / action-type / target /
date-range filters + `limit`/`offset`; the **Audit Trail** screen consumes it.

## 8. How the approval queue works

When `admin_rbac.requires_approval(user, module, action, context)` returns a tier
the caller doesn't hold, the mutation is **not executed** — `_maybe_enqueue()`
writes an `admin_approval_queue` row (`status='pending'`) and returns **HTTP 202**
with `approval_id`. Eligible approvers (tier ≤ required) get a notification.

Sensitive actions & who they need:
- suspend a **verified** user/doctor/researcher/pharmacy → Operations (tier ≤ 2)
- refund / payout **> ৳5000** → Operations
- delete an admin account, change a team member's role, override → Super (tier 1)

`POST /approval-queue/<id>/decide/` with `decision`:
- `approve` — a bounded executor (`execute_approved`) performs the parked action as
  the approver and audits it; `reject` requires a reason; `override` is Super-only.
- The requester cannot decide their own request.

## 9. How to run the migrations

The project is **schema-first** (`DATABASE_SETUP.md`) — Django does **not** create
these tables. Apply the SQL:

```powershell
# existing database (idempotent, safe to re-run):
psql -d featherflow -f backend/postgres_backend_extension.sql
# brand-new database:
psql -d featherflow -f featherflow_schema.sql
```

Then (optional, keeps `makemigrations` quiet — writes nothing to the DB):
```powershell
backend\venv\Scripts\python.exe backend\manage.py migrate audit --fake
```

Verify:
```powershell
backend\venv\Scripts\python.exe backend\manage.py check
```

## 10. How to run the application

```powershell
# backend
cd backend
venv\Scripts\python.exe manage.py runserver 127.0.0.1:8000

# frontend (from repo root) — desktop/web reach the server on 127.0.0.1,
# Android emulator on 10.0.2.2 (handled in AuthService.baseUrl)
flutter run            # or: flutter run -d chrome
```

Throttle rates are env-tunable: `THROTTLE_ADMIN_READ` (default `600/min`),
`_WRITE` (`120/min`), `_EXPORT` (`20/min`), `_POLL` (`240/min`). The throttle uses
Django's default in-process cache — fine for one worker; use a shared cache for
multi-worker deployments.

## 11. How to test each admin role's access

```powershell
backend\venv\Scripts\python.exe backend\scripts\test_admin_panel.py
```

Creates throw-away admins `adminpaneltest+{super,ops,finance,delivery,support,doc}@featherflow.dev`
(password `Testpass!2026`) and asserts, via Django's test client against the live DB:

- `/me/` returns the right tier + permission map per role
- Finance is blocked (403) from `riders`; Delivery is blocked from `payments`;
  Support is blocked from creating admins
- a mutation writes an audit row carrying `reason` + `action_type`, and that row
  cannot be `UPDATE`d
- a tier-3 admin suspending a **verified** doctor gets **202 queued**, cannot
  self-approve, Operations approves, the doctor ends up suspended
- Super creates an admin; Finance cannot
- Operations sees `/oversight/`; Support raises an escalation; Operations resolves it
- Finance exports `payments` CSV; Delivery cannot
- `/api/me/updates/` returns `server_time`; a suspended user's call is rejected

**Current result: 34 passed, 0 failed.** Full existing suite (`manage.py test`) also
green. Live-HTTP smoke with **real login tokens** for `super / finance / delivery /
support` → every endpoint returns the expected status; finance is 403 on riders /
delivery-export, 200 on payments; delivery is the mirror image.

Flutter side: `flutter test` → 11/11 (RBAC-gate logic per role, every new screen
renders, app boots to `/admin`). `flutter analyze` 0 errors. `flutter build web` OK.

Manual role check: sign in as `adminpaneltest+super@featherflow.dev` /
`Testpass!2026`, then approve the pending `adminpaneltest+*` accounts from Admin
Management and sign in as each — confirm the sidebar only shows permitted modules
and blocked actions surface a clear 403 toast.

## 12. Remaining limitations

1. **Manual click-through not done.** No human has driven the running Flutter app
   against the live backend. Mitigation in place: (a) the HTTP contract is proven
   end-to-end with real login tokens for `super / finance / delivery / support` —
   every endpoint returns the expected status and RBAC boundaries hold; (b) every
   new screen renders in a widget test (error/empty states included); (c) the app
   boots in a real Chrome (`scratchpad/app_login.png`); (d) `AdminApiService` is
   the same `package:http` pattern as the 11 existing working screens. The only
   unproven bit is the two halves driven together by hand.
2. **Pharmacy medicine/order catalogue** stays JSON-backed (`backend_admin_records`).
   Pharmacy **verification / suspension** uses the real `pharmacy_organizations`
   table; RBAC + audit + approval + the per-module activity sheet all apply. Full
   catalogue migration needs matching changes in the pharmacy-role app + delivery
   queue and is the one genuinely deferred slice.
3. **`community-reports` / `subscription-plans` / `diseases`** remain in `SEEDS`
   (moderation reports have a real `reports` table via the Content screen's
   "Content Reports" tab; the dashboard's `flagged_content` still counts the seed
   community reports).
4. **Override auto-restore** is best-effort (user / doctor account status). Other
   targets record the override row (immutable audit) but need a manual reverse.
5. **Throttle cache** is Django's in-process `LocMemCache` — correct for a single
   worker; point `CACHES` at Redis/Memcached for a multi-worker deployment.
6. **Deferred per your Pass-2 list:** 2FA enforcement, chart dashboards, WebSockets
   (polling only), custom role-builder UI, full bulk import/export.
7. **Test artefacts:** `adminpaneltest+*` users remain in the DB (the e2e script is
   idempotent). Remove with `DELETE FROM users WHERE email LIKE 'adminpaneltest+%';`
   (cascades). One admin, `adminpaneltest+super`, has a known password
   (`Testpass!2026`) for manual sign-in.
8. **Dead mock `const _kXxx` lists** in 6 pre-existing admin screens are still there
   (unreferenced, tree-shaken, zero runtime cost). Not touched — model classes are
   interleaved in the same trailing block and an earlier blind trim broke the build.

## What changed in the second pass (finance / security / polish)

| Area | Change |
|---|---|
| Finance | `api/admin_finance.py` — `payments` module now aggregates **real** `payments` + `subscriptions` + `delivery_earnings`; `GET /admin-panel/finance/summary/` (MRR, lifetime, payout liability, refunds, plans); refund flips the real row / cancels the sub; `subscriptions` module lists real rows; dashboard `monthly_revenue` from real active subs. Finance screen's `_SummaryBar` was hard-coded `৳2.4M` → now live. |
| Security | `api/admin_security.py` — `security-flags` module derives **real** signals: brute-force (≥8 failed logins/IP/hour), impossible travel (3+ IPs/2h), admin action spikes, plus real content-abuse flags; login attempts now recorded to `activity_logs` (`action_type='login'`); clearing a derived flag suppresses it. |
| Per-module audit | `ModuleActivityButton` + `showModuleActivity` sheet wired into Users / Doctors / Delivery / Pharmacy / Finance / Community / Content app bars — shows that module's `activity_logs` rows, gated on `audit:view`. |
| Per-module polling | `GET /api/{research,delivery,pharmacy,doctors}/updates/?since=` added (the spec's per-module endpoints; same payload as `/api/me/updates/`). |
| Dashboard | resilient to a failed fetch (error banner + pull-to-refresh) instead of an unhandled async throw. |
| Regression fixed | `UserSerializer.get_profile_data` choked on the new `admin_role` / `suspended_by` FKs → `login` returned 500. Now emits the related row's name/id. Covered by 3 new e2e assertions. |
| Tests added | `backend/scripts/test_admin_panel.py` → 34 assertions; `test/admin_screens_smoke_test.dart` (5 screens render); `test/admin_navigation_test.dart` (RBAC-gate logic + app boots to panel). |
