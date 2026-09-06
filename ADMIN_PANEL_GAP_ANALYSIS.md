# FeatherFlow Admin Panel — Phase 1 Gap Analysis

**Status:** Awaiting your review. No code has been changed.
**Date:** 2026-09-06
**Scope:** Admin Panel RBAC hierarchy + real-time reflection of admin actions.

---

## 0. Blocking input needed

**`Featherflow.pdf` is not present in the repository** (only an unrelated research-paper
PDF under `backend/media/`). I could not read section 10 "Admin Panel (Most Important)"
or the per-panel admin requirements.

This analysis is therefore built from:
- Your written admin hierarchy + real-time requirement in the prompt (treated as authoritative), and
- A full read of the existing frontend + backend + database.

**Please attach `Featherflow.pdf`** (or confirm the prompt hierarchy is the final spec). If
the PDF adds module-specific admin duties beyond what is below, the gap list will grow.

---

## 1. What I inspected

### Backend (Django 6 + DRF + SimpleJWT)
| Area | Files |
|---|---|
| Admin API | `backend/api/admin_views.py` (1110 lines), `backend/api/urls.py`, `backend/api/admin_registry.py` |
| Auth & users | `backend/users/{models,views,serializers,urls}.py` |
| Admin/role data | `backend/profiles/models.py` (`AdminProfile`), `backend/audit/models.py` (`ActivityLog`, `AdminPanelRecord`) |
| Module models used by admin | `articles`, `research`, `community`, `consultations`, `delivery`, `pharmacy`, `subscriptions`, `notifications` |
| Config | `backend/featherflow_backend/{settings,urls,database_router}.py`, `requirements.txt` |
| Schema | `featherflow_schema.sql` (1814 lines, 72 tables), `backend/postgres_backend_extension.sql` |
| Migration model | `backend/DATABASE_SETUP.md`, every app's `migrations/0001*.py` |

### Frontend (Flutter + go_router)
| Area | Files |
|---|---|
| Session / RBAC | `lib/features/admin/data/services/admin_session.dart`, `lib/features/admin/data/models/admin_role.dart` |
| API client | `lib/features/admin/data/services/admin_api_service.dart` |
| Audit (local) | `lib/features/admin/data/services/audit_service.dart`, `data/models/audit_log.dart` |
| Shell | `presentation/widgets/{admin_scaffold,admin_sidebar,permission_guard,admin_dialogs}.dart` |
| Screens (11) | `dashboard, users, doctors, delivery, pharmacy, content, finance, community, team, support, profile` |
| Signup | `lib/features/auth/presentation/screens/admin_signup_screen.dart` |
| Routing | `lib/core/router/app_router.dart`, `lib/core/network/auth_service.dart` |

---

## 2. Architecture facts that constrain Phase 2–6

These are the existing conventions. **Phase 2+ must not deviate from them.**

1. **"connected_DB" schema ownership.** PostgreSQL owns the schema via
   `featherflow_schema.sql` + `postgres_backend_extension.sql`. Every Django model is
   `managed = False`. `database_router.ExistingSchemaRouter` returns
   `allow_migrate = False` for all schema-owned apps (`users`, `profiles`, `audit`,
   `research`, `delivery`, …). **`python manage.py migrate` does NOT create these
   tables.** New tables are added by appending `CREATE TABLE`/`CREATE INDEX` to
   `postgres_backend_extension.sql` (and `featherflow_schema.sql` for a fresh install),
   plus a `managed = False` model. Existing migrations are state-only stubs.
2. **Auth.** JWT (`rest_framework_simplejwt`), 7-day access tokens. Custom `users.User`
   (UUID pk, `email` username). Roles are `roles` + `user_roles` M2M through table.
   `User.is_staff` = "has a role with `panel_type='admin'`"; `User.is_superuser` = "has
   role `name='super_admin'`".
3. **Admin API surface.** Everything is under `/api/admin-panel/` and handled by **4
   function-based views** in `admin_views.py`:
   `admin_dashboard`, `admin_profile`, `admin_collection(module)`,
   `admin_record(module, record_id)`. A single `IsAdminUser` permission class guards all
   of them. There are no DRF ViewSets/serializers for the admin panel — responses are
   hand-built dicts (`_user_json`, `_doctor_json`, `_rider_json`, …).
4. **`AdminPanelRecord`** (`backend_admin_records` table, JSON `payload`) is the
   catch-all store for modules not yet backed by real tables (pharmacies' seed data,
   payments, support tickets, security flags, medicines, delivery queue, …). `SEEDS`
   dict in `admin_views.py` seeds them on first read.
5. **Audit today.** `_log(request, module, action, record_id, old, new)` writes an
   `ActivityLog` row (`activity_logs` table: `old_value`, `new_value`, `ip_address`,
   `module`, `action`, `target_id`, `target_type`). It is **not immutable** and captures
   **no `user_agent` and no `reason`**.
6. **No realtime infra.** `requirements.txt` has no channels / redis / celery / ASGI.
   Realtime = **polling only**. `notifications` table + `GET/PATCH /api/notifications/`
   inbox already exist, and many admin actions already write `Notification` rows for the
   affected user (rider assigned, researcher verified, article status changed, payout
   paid, …).
7. **DRF config** (`settings.py`): no throttle classes configured at all.
8. **Frontend module gating** is driven by `admin_role.dart` `kRolePermissions` — a
   hardcoded `Map<AdminRole, Map<AdminModule, Set<AdminPermission>>>` — checked via
   `AdminSession.instance.can(module, permission)` and the `PermissionGuard` widget.

---

## 3. What EXISTS

### 3.1 Frontend — admin screens present

| Route | Screen | Backend module(s) it calls | Actions wired |
|---|---|---|---|
| `/admin` | `admin_dashboard_screen` | `dashboard/` | stat cards, task list, recent activity; **"Switch Role (Demo)"** picker |
| `/admin/users` | `admin_users_screen` | `users/` | approve / suspend / edit, detail sheet |
| `/admin/doctors` | `admin_doctors_screen` | `doctors/`, `consultations/` | verify / suspend / reject / edit |
| `/admin/delivery` | `admin_delivery_screen` | `delivery-orders/`, `riders/`, `payouts/` | assign / reassign / cancel, approve rider, mark payout paid |
| `/admin/pharmacy` | `admin_pharmacy_screen` | `pharmacies/`, `medicines/` | verify / suspend pharmacy, approve / remove medicine |
| `/admin/content` | `admin_content_screen` | `articles/`, `research-papers/…`, `team-updates/`, `profile-change-applications/`, `content-reports/` | 6 tabs: All / Pending / Featured / Team Updates / Profile Applications / Content Reports; publish / request-revision / hide / remove / feature |
| `/admin/finance` | `admin_finance_screen` | `payments/` | refund, detail sheet |
| `/admin/community` | `admin_community_screen` | `community-reports/`, `community-users/` | remove / dismiss report, mute / verify user |
| `/admin/team` | `admin_team_screen` | `team/`, `access-logs/` | add member, change role, deactivate, edit; Access Log tab |
| `/admin/support` | `admin_support_screen` | `support-tickets/`, `security-flags/` | resolve / escalate ticket, clear flag, reply |
| `/admin/profile` | `admin_profile_screen` | `profile/` | edit profile, change password, toggle 2FA (stub), notification prefs |

- `AdminScaffold` gives a responsive shell (persistent sidebar ≥900px, drawer below).
- `admin_dialogs.dart` provides reusable `showAdminDetails`, `showAdminTextPrompt`,
  `showAdminRecordEditor` bottom sheets.
- `admin_theme.dart` provides `AColors`, `aCard()`, `aChip()`.

### 3.2 Backend — admin endpoints present

- `GET  /api/admin-panel/dashboard/` — platform stat block + task counts + last 8 activity rows.
- `GET/PATCH/POST /api/admin-panel/profile/` — current admin's own profile + password + prefs.
- `GET/POST /api/admin-panel/<module>/` — list / create.
- `PATCH/DELETE /api/admin-panel/<module>/<record_id>/` — update / delete / action.
- Recognised modules: `users, doctors, team, pharmacies, consultations, access-logs,
  riders, delivery-orders, payouts, researchers, articles, research-papers,
  disease-updates, innovations, team-updates, profile-change-applications,
  content-reports, research-tags`, plus JSON-backed: `pharmacy-products, pharmacy-orders,
  medicines, payments, subscription-plans, diseases, support-tickets, security-flags,
  community-reports, community-users`.
- Ad-hoc module gating helpers: `_is_delivery_ops_admin(user)`
  (`admin_super | admin_operations | admin_delivery`),
  `_is_research_content_admin(user)` (`admin_super | admin_research | admin_content`).
- `_log(...)` writes `ActivityLog` on most mutations.
- Affected-user `Notification` rows already written for: rider approve/assign/reassign/
  cancel, payout paid, researcher verify, article status change, profile-change-app
  decision, medicine status change.

### 3.3 Database — admin-relevant tables that ALREADY exist

| Table | Notes |
|---|---|
| `admin_profiles` | Rich: `account_id_number`, `job_title`, `department`, `reporting_manager_id`, `work_location`, `employment_type`, `start_date`, `admin_sub_role` CHECK(`super/operations/finance/content/research/delivery/pharmacy/support`), `tech_skill_level`, `confidentiality_agreement_accepted`, `background_check_consent`, `cv_url`, `previous_experience`, `approved_by_admin_id`, timestamps. Django model `profiles.AdminProfile` maps it. |
| `roles` | `id SERIAL`, `name UNIQUE`, `panel_type`, `description`. **No permissions column, no tier.** |
| `permissions` | `id`, `name`, `module`, `description`. **Table exists but NO code reads or writes it.** |
| `role_permissions` | `role_id` ↔ `permission_id`. **Also unused by code.** |
| `user_roles` | `user_id` ↔ `role_id`, `assigned_by`, `assigned_at`. |
| `activity_logs` | `user_id`, `action`, `module`, `target_id`, `target_type`, `old_value` JSONB, `new_value` JSONB, `ip_address`, `created_at`. |
| `backend_admin_records` | JSON catch-all store. |
| `notifications` | `user_id`, `title`, `body`, `notification_type` (incl. `approval`, `alert`, `system`), `reference_id`, `reference_type`, `is_read`. |
| Per-role profile tables | `doctor_profiles`, `researcher_profiles`, `delivery_profiles`, `pharmacy_organizations` — all have `is_verified` + `approved_by_admin_id` + `updated_at`. |
| `articles` | Has `version INT` + `updated_at` + `article_version_snapshots`. |

---

## 4. What is MISSING

### 4.1 RBAC / hierarchy — **the core gap**

| Requirement | Status | Detail |
|---|---|---|
| Tiered roles (Super / Operations / Module / Support) | ❌ Missing | No tier concept anywhere. `roles.name` is a flat string. |
| `AdminRole` with `permissions` JSON + `tier_level` | ❌ Missing | `roles` table has neither column. `permissions`/`role_permissions` tables exist but dead. |
| Frontend role derived from backend | ❌ Missing / broken | `AdminSession._loadRegisteredProfile()` sets name+email only; `_role` stays `AdminRole.superAdmin` **for every admin**. The dashboard ships a **"Switch Role (Demo)"** button that lets anyone become any role client-side. → **RBAC UI gating is currently cosmetic.** |
| `is_super_admin / is_operations_admin / is_module_admin / is_support_agent / can_perform_action` helpers | ❌ Missing | Only `IsAdminUser` (binary) + 2 ad-hoc helpers. |
| Per-endpoint granular permission checks | ⚠️ Partial | Delivery & research/content endpoints check a helper; **users, doctors, pharmacies, finance/payments, community, support, team endpoints only check `IsAdminUser`** — any admin can do anything there. |
| Privilege-escalation prevention | ❌ Missing | `admin-panel/team` PATCH lets any admin set any role string (`admin_super` included) on any team user. |
| Module admins restricted to their module(s) | ❌ Missing | No enforcement outside delivery/research. |
| Operations Admin = all module functions but not Super | ❌ Missing | No Operations tier. |
| Naming consistency | ❌ Broken | `super_admin` (User model) vs `admin_super` (`IsAdminUser`) vs `admin_sub_role='super'` (DB) vs `admin_operations`/`admin_delivery` (helpers) vs `admin_finance` (team-create) vs `AdminRole.superAdmin` (Flutter). No single source of truth. |
| Self-signup admin approval | ❌ Missing (security hole) | `admin_signup_screen` → `register(role:'admin')` → serializer sets `account_status='active'` and adds role `admin` immediately. **Anyone can self-register a working admin account.** No `internal_approval_by_founder_hr` gate, no pending state. |

### 4.2 Admin account management

| Requirement | Status |
|---|---|
| `GET/POST /api/admin/admins/` (list/create admin accounts) | ❌ Missing — only `admin-panel/team/` which creates a plain `User`, not an `AdminProfile`-backed admin, with a fabricated temp password. |
| `PUT/DELETE /api/admin/admins/<id>/` | ❌ Missing |
| `PATCH /api/admin/admins/<id>/suspend/` | ⚠️ Partial — `team` PATCH sets `account_status`; no `is_suspended`, `suspended_by`, `suspended_at`. |
| Super Admin can recover/reset another admin | ❌ Missing |
| Modify admin role permissions | ❌ Missing |

### 4.3 Audit trail

| Requirement | Status |
|---|---|
| Audit list endpoint w/ filters (admin, module, date, action) | ⚠️ Partial — `access-logs` returns latest 100 rows, **no filters, no pagination**. |
| Capture `reason` (admin justification) | ❌ Missing from `_log` and every call site. |
| Capture `user_agent` | ❌ Missing. |
| `action_type` enum (create/edit/delete/approve/reject/suspend/assign/export/refund/override) | ❌ Missing — `action` is a free-text string. |
| Immutable (no edit/delete) | ❌ Not enforced (no DB trigger, no revoked UPDATE/DELETE grant, model is writable). |
| Override an action `POST /audit-logs/<id>/override/` | ❌ Missing. |
| Frontend audit-trail viewer screen | ❌ Missing — only a rows list inside the Team screen; `audit_service.dart` is an **in-memory mock** (`List<AuditEntry>` in RAM, lost on reload). |
| Per-module audit tab | ❌ Missing on all module screens. |

### 4.4 Approval queue

| Requirement | Status |
|---|---|
| `AdminApprovalQueue` model / `admin_approval_queue` table | ❌ Missing entirely. |
| `GET /api/admin/approval-queue/` + `POST …/<id>/decide/` | ❌ Missing. |
| Sensitive-action routing (delete admin, refund > threshold, suspend verified user) | ❌ Missing — actions execute immediately. |
| Team screen "role change needs Super Admin approval" | ⚠️ Fake — the toast says "sent for approval" but the PATCH **applies the role immediately** and only sets a cosmetic `pending_approval: true` flag in `profile_data`. |

### 4.5 Operations-tier features

| Requirement | Status |
|---|---|
| Operations Admin dashboard (module oversight view) | ❌ Missing |
| `GET /api/admin/oversight/` (platform-wide module activity) | ❌ Missing |
| `GET /api/admin/escalations/` + `POST …/<id>/resolve/` | ❌ Missing — support tickets have an "Escalated" status but no escalation entity / queue / assignee. |

### 4.6 Real-time reflection of admin actions

| Requirement | Status |
|---|---|
| `updated_at` on all user-facing models | ⚠️ Mostly present in DB; **not indexed**. |
| `version` / revision field for optimistic concurrency | ⚠️ Only `articles.version`. |
| `GET /api/admin/updates/poll/?since=<ts>` | ❌ Missing |
| Per-module `GET /api/<module>/updates/?since=<ts>` (research / delivery / pharmacy / doctors) | ❌ Missing |
| Standard notification event payload (`admin_approved`, `admin_rejected`, `admin_suspended`, `admin_assigned`, `admin_modified` + admin name/id/reason) | ⚠️ Partial — `Notification` rows are written but with ad-hoc titles/bodies, `notification_type` is coarse (`approval`/`alert`/`system`), and **no `admin_id` / `reason` / `action_data`**. |
| Frontend polling on affected user screens | ❌ Missing — `ResearchSession`, `DeliverySession` etc. fetch once; no timers. |
| "Suspended mid-session → Access Denied" handling | ❌ Missing — `is_active` is derived from `account_status` but no screen reacts to a 403. |
| Doctor & Pharmacy user apps still partly on demo data | ⚠️ `DoctorSession` imports `doctor_demo_data.dart`; `PharmacySession` seeds from `pharmacy_demo_data.dart` then refreshes. Realtime to the doctor app is not currently possible without wiring it to the API first. |

### 4.7 Module coverage vs your hierarchy

| Hierarchy module | Frontend screen | Backend real table | Gap |
|---|---|---|---|
| Users / Farmers | ✅ users | ✅ `users` | RBAC + audit `reason` + realtime |
| Doctor Admin | ✅ doctors | ✅ `doctor_profiles`, `consultations` | disputes/escalations entity missing; response-time metrics missing |
| Delivery Admin | ✅ delivery | ✅ `delivery_*` | payout **approval queue** vs direct mark-paid; attendance view missing from admin |
| Pharmacy Admin | ✅ pharmacy | ⚠️ pharmacies+medicines are **JSON `backend_admin_records`**, not `pharmacy_medicines`/`pharmacy_organizations` tables | supplier performance, expiry monitoring, pricing rules missing; needs migration off JSON store |
| Research Admin | ✅ content (tabs) | ✅ `researcher_profiles`, `articles`, `research_tags` | featured-research management partial; researcher verification realtime |
| Content Admin | ✅ content + community | ✅ `articles`, `reports` | verified-badge management for creators missing |
| Finance Admin | ✅ finance | ❌ `payments` table exists but admin uses **JSON seed data**; `subscriptions`, `revenues`, `tax_records`, `loans` tables exist and are unused by admin | refunds/cashouts/payout-approvals/tax/revenue analytics essentially not implemented |
| Support Agent | ✅ support | ❌ `support-tickets` + `security-flags` are **JSON seed data** only | no real ticket entity, no SLA, no escalation link |
| Team Admin (internal) | ⚠️ team screen exists | ⚠️ creates plain `User` + `admin_*` role | no `AdminProfile` creation, no real approval, activity tracking = raw `activity_logs` |
| Operations Admin | ❌ no dedicated view | ❌ | entire tier missing |
| Super Admin | ⚠️ same dashboard as everyone | ❌ | admin-management section, audit viewer, approval queue, alert area missing |
| Platform settings | ❌ | ❌ | not present at all |

### 4.8 Cross-cutting

| Requirement | Status |
|---|---|
| Rate limiting on admin endpoints | ❌ No throttle config in DRF settings. |
| IP-based suspicious-activity detection | ❌ Missing (security-flags is static seed data). |
| Export (CSV/Excel) for any module | ❌ Missing entirely (`export` permission exists in the enum, no endpoint, no button). |
| Bulk actions | ❌ Missing. |
| Loading / error / empty states | ⚠️ Loading + error present on most screens; **empty states inconsistent**. |
| Localization | ⚠️ Admin screens use hardcoded English strings; `core/l10n` exists but is not applied to admin. |
| Dead mock data in repo | ⚠️ `admin_data.dart` (`kAdminUsers`), `admin_team_screen` (`_kStaff`, `_kAccessLog`), `audit_service.dart` — unused/parallel to real API, should be removed. |

---

## 5. What needs MODIFICATION (not new-build)

| File | Change |
|---|---|
| `lib/features/admin/data/models/admin_role.dart` | Add `teamAdmin`; add missing `AdminModule` values (approvals, audit, oversight, escalations, platform settings); keep `kRolePermissions` as a **fallback default only** — real permissions come from backend. |
| `lib/features/admin/data/services/admin_session.dart` | Derive `role` + effective permission map from `/api/auth/me` (roles) or a new `/api/admin-panel/me/`. Expose `tier`. Remove "always Super Admin". |
| `lib/features/admin/presentation/screens/admin_dashboard_screen.dart` | Remove the **demo role switcher**; render role-aware cards + quick links + alert area; split Super vs Operations content. |
| `lib/features/admin/presentation/widgets/admin_sidebar.dart` | Drive nav items from `AdminSession.accessibleModules` (already does) + add new routes. |
| `lib/features/admin/data/services/audit_service.dart` | Replace in-memory list with API-backed reads, or delete and call the new audit endpoint directly. |
| `backend/api/admin_views.py` | Replace `IsAdminUser` with tiered permission classes + `can_perform_action`; add `reason`/`user_agent` to `_log`; add admin-management, audit-list, approval-queue, oversight, escalations, export, polling endpoints. Consider splitting this 1100-line file into `backend/api/admin/` package (keeps the existing function-view style). |
| `backend/api/urls.py` | Register new admin routes. Decide: keep `/api/admin-panel/` prefix (frontend already uses it) vs the `/api/admin/` prefix in the prompt spec — **recommend keeping `/api/admin-panel/`** to avoid touching the working client, and documenting the deviation. |
| `backend/users/serializers.py` | Admin self-signup: create `AdminProfile` in a **pending** state, do **not** set `account_status='active'`, assign a non-privileged pending role; require Super/Operations approval. |
| `backend/featherflow_backend/settings.py` | Add `DEFAULT_THROTTLE_CLASSES` + scoped rates for admin endpoints. |
| `featherflow_schema.sql` + `backend/postgres_backend_extension.sql` | Add `admin_roles`, `admin_approval_queue`, extra `admin_profiles` columns, audit columns, `updated_at` indexes. |
| Delete/clean | `lib/features/admin/data/admin_data.dart`, mock consts in `admin_team_screen.dart`. |

---

## 6. Priority order

### P0 — Critical (panel has no real access control today)
1. **Backend RBAC foundation** — `admin_roles` table + `permissions` JSON + tier;
   permission helpers (`is_super_admin`, `is_operations_admin`, `is_module_admin`,
   `is_support_agent`, `can_perform_action`); apply to **every** admin endpoint.
2. **Wire frontend to real roles** — `AdminSession` reads role/permissions from backend;
   delete the demo role switcher; `PermissionGuard` becomes meaningful.
3. **Close the self-signup hole** — admin registration goes to a pending/approval state.
4. **Naming unification** — one canonical set of role names (proposal:
   `super_admin`, `operations_admin`, `finance_admin`, `content_admin`, `research_admin`,
   `delivery_admin`, `pharmacy_admin`, `doctor_admin`, `support_agent`, `team_admin`),
   migration to remap existing `admin_*` rows, update `IsAdminUser` + helpers + Flutter enum.

### P1 — Core hierarchy features
5. **Admin management** endpoints + Super Admin "Admin Management" screen
   (create / edit / suspend / recover, backed by `AdminProfile`).
6. **Immutable audit** — add `reason` + `user_agent` + `action_type`; revoke
   UPDATE/DELETE at the DB level; audit-list endpoint with filters + pagination;
   **Audit Trail viewer screen**; per-module audit tab.
7. **Approval queue** — `admin_approval_queue` table + endpoints + UI; route sensitive
   actions (delete admin, refund > threshold, suspend verified user, role change)
   through it; Super Admin override.
8. **Operations tier** — Operations dashboard, `oversight`, `escalations`.

### P2 — Real-time + module depth
9. **Polling realtime** — `updated_at` indexes; `/updates/poll/?since=` +
   per-module update endpoints; standard notification payload with `admin_id`/`reason`/
   `action_data`; frontend pollers on researcher/rider/pharmacy/doctor screens;
   403-on-suspend handling.
10. **Move Finance / Support / Pharmacy off the JSON `backend_admin_records` store**
    onto their real tables (`payments`, `subscriptions`, `pharmacy_*`, a new
    `support_tickets` table).
11. Per-module analytics cards; export (CSV) for critical modules (users, finance,
    audit).
12. Rate limiting; localization of admin strings; remove dead mock data.

### Deferred (your "Pass 2" list — confirmed)
2FA enforcement, chart dashboards, automated tests, WebSockets, full bulk import/export,
custom role-builder UI.

---

## 7. Key decisions I need from you before Phase 2

1. **Attach `Featherflow.pdf`** or confirm the prompt hierarchy is final.
2. **API prefix:** keep the existing `/api/admin-panel/` (recommended — client already
   uses it) or introduce `/api/admin/` as written in the prompt spec (client rewrite)?
3. **Audit storage:** extend the existing `activity_logs` table with
   `reason` / `user_agent` / `action_type` (recommended — one audit trail), or create a
   separate `admin_audit_logs` table as in the prompt spec (two overlapping trails)?
4. **`roles` table:** add `permissions JSONB` + `tier_level` columns to the existing
   `roles` table (recommended), or a **separate `admin_roles` table** as in the prompt
   spec? The existing `roles.id` is `SERIAL`; the spec wants a UUID `role_id`.
5. **`admin_sub_role`:** the DB column is `VARCHAR CHECK(...)` and lacks `doctor` +
   `team`. OK to `ALTER` the CHECK constraint to add them, or keep `admin_sub_role`
   as-is and put the authoritative role in `user_roles`?
6. **Doctor Admin** appears in your hierarchy but not in the DB `admin_sub_role` CHECK
   nor the Flutter enum — confirm it's a required tier-3 role.
7. **Realtime:** confirm **polling-only** for Pass 1 (no new infra), intervals 5–10s
   dashboards / 15–30s elsewhere, as in your spec.
8. **Finance/Support/Pharmacy data migration** off the JSON store — in scope for this
   pass, or keep JSON-backed for now and only build the RBAC/audit/approval layer on top?

---

## 8. Rough size estimate (for planning, after decisions)

| Phase | Backend | Frontend | DB |
|---|---|---|---|
| 3 — DB | — | — | ~4 tables / ~15 columns / ~10 indexes in the `.sql` files |
| 4 — Backend | ~8 new endpoints, 1 permission module, audit refactor, throttle | — | — |
| 2 — Frontend | — | ~4 new screens (Admin Mgmt, Audit Viewer, Approval Queue, Operations/Oversight) + modify 11 | — |
| 5 — Integration | polling endpoints | pollers + session rewrite | `updated_at` indexes |

---

*Prepared in Phase 1. Awaiting "Proceed to Phase 2" (and the answers in §7).*
