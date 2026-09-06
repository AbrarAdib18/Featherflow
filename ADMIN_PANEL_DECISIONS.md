# Admin Panel — Locked Decisions (Phase 1 → Phase 2)

You delegated all §7 decisions ("best interest of an industry-ready project"). These are
now locked and will govern Phases 2–6. Everything reuses the existing stack; nothing new
is introduced.

---

### D0 — Requirements source
`Featherflow.pdf` is unavailable. **The prompt's admin hierarchy + real-time section is
treated as the authoritative spec.** If the PDF later contradicts it, we reconcile then.

### D1 — API prefix: **keep `/api/admin-panel/`**
The Flutter client (`AdminApiService`) is already built on it. New endpoints slot under
the same prefix instead of a parallel `/api/admin/`:

```
/api/admin-panel/admins/                     GET, POST
/api/admin-panel/admins/<uuid:id>/           GET, PATCH, DELETE
/api/admin-panel/admins/<uuid:id>/suspend/   POST
/api/admin-panel/admins/<uuid:id>/recover/   POST
/api/admin-panel/roles/                      GET   (+ PATCH permissions — super only)
/api/admin-panel/audit-logs/                 GET   (filters: admin, module, action, date range, target)
/api/admin-panel/audit-logs/<uuid:id>/override/   POST
/api/admin-panel/approval-queue/             GET
/api/admin-panel/approval-queue/<uuid:id>/decide/ POST
/api/admin-panel/oversight/                  GET
/api/admin-panel/escalations/                GET
/api/admin-panel/escalations/<uuid:id>/resolve/  POST
/api/admin-panel/<module>/export/            GET   (CSV)
/api/admin-panel/updates/poll/?since=<iso>   GET
```
Deviation from the prompt's literal `/api/admin/` paths is intentional and documented here.

### D2 — Audit storage: **extend `activity_logs`, one trail**
Add columns: `action_type VARCHAR(20)` (enum: create/edit/delete/approve/reject/suspend/
assign/export/refund/override/login), `reason TEXT`, `user_agent TEXT`,
`request_id UUID`. Keep the existing free-text `action` as the human-readable label.
No separate `admin_audit_logs` table.

**Immutability** enforced two ways:
1. DB: a `BEFORE UPDATE OR DELETE` trigger on `activity_logs` that raises an exception.
2. App: `ActivityLog.save()` raises if `self.pk` already exists; no delete path exposed.

### D3 — Roles: **extend the existing `roles` table**
Add columns: `permissions JSONB NOT NULL DEFAULT '{}'`, `tier_level SMALLINT`,
`is_system BOOLEAN DEFAULT FALSE`, `updated_at TIMESTAMP`. No separate `admin_roles`
table (would fork role storage away from `user_roles`, which FKs `roles.id`).
An "admin role" = a `roles` row with `panel_type = 'admin'`.
`permissions` shape:
```json
{ "users": ["view","edit","suspend","approve"], "finance": ["view","refund","export"], ... }
```
`tier_level`: 1 super_admin, 2 operations_admin, 3 module admins, 4 support_agent.
The 10 roles are seeded as `is_system = TRUE` (predefined; no custom-role UI this pass).

### D4 — Canonical role names — **REVISED after inspecting the live DB**
The database already standardised on the `admin_*` prefix
(`roles` rows 7–14: `admin_super, admin_operations, admin_finance, admin_content,
admin_research, admin_delivery, admin_pharmacy, admin_support`), and
`admin_views.py` helpers already use those names. So the canonical set keeps that
prefix rather than inventing `super_admin`:

`admin_super, admin_operations, admin_finance, admin_content, admin_research,
admin_delivery, admin_pharmacy, admin_doctor, admin_support, admin_team`

Only **two roles were added**: `admin_doctor`, `admin_team`. The legacy generic
`admin` role is kept as a tier-2 alias (same permission matrix as
`admin_operations`) for backward compatibility but is no longer issued — the
signup serializer now assigns the specific `admin_<sub_role>` role.
`User.is_superuser` was fixed: it checked `name == 'super_admin'` (which never
matched the DB) → now `name == 'admin_super'`. `is_staff` (`panel_type == 'admin'`)
unchanged. This is far less disruptive than a full rename and needs no data
migration of existing `user_roles`.

### D5 — `admin_profiles.admin_sub_role`
`ALTER` the CHECK constraint to add `doctor` and `team`. It becomes a **denormalized
mirror**; the authoritative role is always `user_roles → roles`. Also add the columns
the spec calls for that are missing: `admin_role_id INT REFERENCES roles(id)`,
`access_level_requested VARCHAR`, `prior_admin_operations_experience TEXT`,
`internal_approval_by_founder_hr BOOLEAN DEFAULT FALSE`,
`strong_password_2fa_enabled BOOLEAN DEFAULT FALSE`, `is_active BOOLEAN DEFAULT TRUE`,
`is_suspended BOOLEAN DEFAULT FALSE`, `suspended_at TIMESTAMP`,
`suspended_by UUID REFERENCES users(id)`.

### D6 — Doctor Admin is a real tier-3 role — included.

### D7 — Real-time: **polling only, WebSocket-ready abstraction**
No channels/redis/celery added. `GET .../updates/poll/?since=<iso8601>` returns
notifications + changed-entity summaries since the timestamp. Per-module variants:
`/api/research/updates/`, `/api/delivery/updates/`, `/api/pharmacy/updates/`,
`/api/doctors/updates/`. Poll cadence: **8 s** approval/escalation queues + dashboards,
**20 s** module list screens, **30 s** analytics. `updated_at` indexes added to the
polled tables. Frontend gets one `AdminUpdatesService` / per-role `…Session` timer that
could later be swapped for a socket without touching callers.
Notification payload standardised:
```json
{ "type":"admin_approved", "target_type":"research_profile", "target_id":"…",
  "admin_id":"…", "admin_name":"…", "reason":"…",
  "action_data":{…}, "timestamp":"…" }
```
Suspended-mid-session: any admin/user API 403 with `code=account_suspended` drives the
client to an "Access Revoked" screen.

### D8 — Data-source cleanup (industry-ready, staged)
"No mock data in production paths" — the `SEEDS` fake rows get removed as each area moves
to real tables.

**This admin pass:**
- **Support** → new real tables `support_tickets` + `support_ticket_replies` (+ SLA,
  assignee, escalation link). Migrate off `backend_admin_records`.
- **Finance** → read from the **existing but unused** `payments`, `subscriptions`,
  `revenues`, `tax_records`, `revenue_sources` tables. Add real refund / payout-approval
  / cashout write paths. Remove the `payments` seed.
- **Team** → real `AdminProfile` creation (not bare `User` + fabricated password);
  remove the `team` seed.
- **Security flags** → back with real `activity_logs`-derived detection (repeated failed
  auth, impossible travel) instead of static seed rows.

**Deferred to the next pass (documented, not silently dropped):**
- Pharmacy `medicines` / `pharmacy-products` / `pharmacy-orders` stay on
  `backend_admin_records` — moving them needs coordinated changes in the pharmacy-role
  app and delivery queue. Admin **verification** of pharmacies already uses the real
  `pharmacy_organizations` / user role, so the RBAC + audit + approval layer still
  applies.
- `disease` / `subscription-plans` catalog editing stays JSON-backed.

---

## New database objects (Phase 3 preview)

| Object | Type | Purpose |
|---|---|---|
| `roles` +4 cols | ALTER | permissions JSON, tier_level, is_system, updated_at |
| `admin_profiles` +10 cols, CHECK alter | ALTER | lifecycle + approval + role FK |
| `activity_logs` +4 cols, immutability trigger | ALTER | reason, user_agent, action_type, request_id |
| `admin_approval_queue` | CREATE | pending sensitive actions |
| `support_tickets`, `support_ticket_replies` | CREATE | real support entity |
| `idx_*_updated_at` (~8) | CREATE INDEX | polling "since" queries |
| role permission seed | RunSQL | 10 system roles with permission matrices |
| legacy role remap | RunSQL / command | canonical names |

All of the above land in `backend/postgres_backend_extension.sql` (applied once by ops,
per `DATABASE_SETUP.md`) **and** `featherflow_schema.sql` (fresh installs). No
`manage.py migrate` schema changes — consistent with the connected_DB architecture.

---

## Phase 2 deliverables (frontend) once you approve

1. `AdminSession` + `admin_role.dart` rewrite — real role/permissions from
   `/api/admin-panel/me/`; delete the demo role switcher.
2. **Super Admin → Admin Management** screen (create/edit/suspend/recover admins,
   role-permission viewer).
3. **Audit Trail Viewer** screen (filters, pagination, override action).
4. **Approval Queue** screen (pending list, approve/reject/override, reason capture).
5. **Operations dashboard** variant + **Oversight** + **Escalations** views.
6. Per-module: analytics card row + "Activity" (audit) tab + `Export CSV` button +
   empty states.
7. New nav entries, `PermissionGuard` made real, 403→Access-Revoked handling.
8. Remove dead mock data (`admin_data.dart`, `_kStaff`, `_kAccessLog`, in-memory
   `AuditService`).

Frontend is built against the agreed API contract; backend (Phase 4) implements it.

---

*Awaiting "Proceed to Phase 2".*
