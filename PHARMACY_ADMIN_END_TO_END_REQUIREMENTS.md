# Pharmacy Admin — End-to-End Requirements Traceability Matrix

Date: 2026-09-26. This matrix is the deliverable requested by the Pharmacy
Admin build instructions (§1). It consolidates `PHARMACY_ADMIN_AUDIT.md` and
`PHARMACY_ADMIN_IMPLEMENTATION_REPORT.md` (two prior work passes, dated
2026-09-25/26) with a **third, independent verification pass** performed in
this session, which re-ran every backend test suite live, restarted the
backend and frontend processes to confirm the running code matches disk, and
drove real HTTP calls against the running server as the actual dedicated
Pharmacy Admin account rather than trusting the prior reports' claims. That
verification pass found and fixed one real, previously-undetected bug (see
DEL-02 below) and added regression coverage for it.

Status legend: **Complete** = backend + API + Flutter UI all real, wired,
and confirmed working end-to-end against the live app · **In progress** =
one layer real, another missing/partial · **Blocked** = not implemented,
reason given.

Nothing in this document, or any code change made in this session, has been
committed to git.

| ID | Requirement | Role | Database model | API endpoint | Flutter screen | Permission | Automated test | Live/manual verification | Status |
|---|---|---|---|---|---|---|---|---|---|
| PA-01 | Dedicated Pharmacy Admin account, idempotent seed | Pharmacy Admin | `users.User`+`UserRole` (role `admin_pharmacy`) | `/api/auth/login/`, `/api/auth/logout/` | Login screen | `admin_pharmacy` role | `test_pharmacy_admin.py` permission matrix (11 actor types) | **Re-verified this session**: `curl` login → 200, real tokens, `roles:["admin_pharmacy"]`, `account_status:"active"`; wrong password → 401; logout → 205 | Complete |
| PA-02 | Pharmacy owner signup → pending, centralized status engine | Pharmacy owner | `PharmacyOrganization.review_state` + `User.account_status` | `/api/auth/register/` | Signup wizard | n/a (pre-auth) | `test_signup_flows.py` (107 checks, re-run this session, 0 failed) | Not re-driven through the UI this session; verified via the passing automated suite | Complete |
| PA-03 | Centralized transition engine (approve/reject/request-info/suspend/reinstate), no divergent cascades | Pharmacy Admin | `pharmacy.services.transition_pharmacy_status` | `PATCH /admin-panel/pharmacy/<id>/{approve,reject,request-info,suspend,reinstate}/` | Account-review sheet, Pharmacies tab | `pharmacy:approve/reject/suspend` | `test_pharmacy_admin.py` (lifecycle section) | Re-run this session, 0 failed | Complete |
| PA-04 | Pending/suspended pharmacy still gets a session; profile/earnings/chat/appeal reachable, operational actions locked server-side | Pharmacy owner | `pharmacy.auth.PharmacyAlwaysOnAuthentication`, `IsPharmacyAccount` | `/api/pharmacy/permissions/`, `/profile/`, `/earnings/`, `/dashboard/` | `PharmacyLockedBanner`, dashboard | `IsPharmacyAccount` vs `IsPharmacyUser` split | `test_pharmacy_admin.py` lock/unlock section | Re-run this session, 0 failed | Complete |
| PA-05 | Locked-state UI: banner, reason, allowed/locked lists, appeal/chat/refresh actions | Pharmacy owner | derived from PA-04's permission snapshot | `GET /api/pharmacy/permissions/` | `pharmacy_locked_banner.dart`, `pharmacy_dashboard_screen.dart` | n/a | covered indirectly via permission-snapshot tests | Not click-driven this session (no browser-automation tool available in this environment — see Limitations) | Complete (backend contract verified; UI not re-clicked this pass) |
| PA-06 | Pharmacy↔Admin support chat (send/reply/read state/isolation) | Both | `doctor.Conversation`/`Message` + 2 pharmacy-only columns | `/api/pharmacy/support-conversation/`, `/admin-panel/pharmacy-chats/*` | `pharmacy_support_chat_screen.dart`, Chat & Appeals tab | `pharmacy:view/edit` | `test_pharmacy_admin.py` chat+isolation section (2 pharmacies, cross-access denied) | Re-run this session, 0 failed; live dashboard shows a real `recent_chats` row from a genuine prior conversation | Complete |
| PA-07 | Appeals lifecycle (submit → under_review/more_info → approve/deny), tied to suspension | Both | `PharmacyAppeal` | `/api/pharmacy/appeals/`, `PATCH /admin-panel/pharmacy/appeals/<id>/decide/` | `pharmacy_appeal_screen.dart`, Chat & Appeals tab | `pharmacy:approve/reject` | `test_pharmacy_admin.py` appeal section | Re-run this session, 0 failed | Complete |
| PA-08 | Admin medicine create/edit/archive/restore, image upload, no hard delete | Pharmacy Admin | `PharmacyMedicine` | `POST .../medicines/create/`, `PATCH .../{update,archive,restore,stock,price}/` | `_AddMedicineDialog`, per-pharmacy card chips | `pharmacy:create/edit/delete` | `test_pharmacy_admin.py` add-medicine section | Re-run this session (5 checks), 0 failed | Complete |
| PA-09 | Inventory: stock adjust, low-stock/expiry alerts | Pharmacy Admin | `PharmacyMedicine`, `PharmacyExpiryAlert` | `PATCH .../medicines/<id>/stock/` | Expiry Monitoring tab, "Adjust stock" action | `pharmacy:edit` | `test_pharmacy_admin.py` (+/- delta, negative-stock rejection) | Re-run this session, 0 failed; live dashboard shows real `low_stock:2, out_of_stock:4` | Complete |
| PA-09b | Inventory **stock-movement history** (per-medicine timeline, not just current-state adjust) | Pharmacy Admin | no dedicated table — reconstructable from `ActivityLog` only | none dedicated | none dedicated | — | none | Not built — confirmed absent again this session | Blocked (reason: unchanged from prior report; would need either a new `PharmacyStockMovement` table or a filtered `ActivityLog` view scoped per-medicine; out of the fixes attempted this session, which focused on verifying and repairing what already existed) |
| PA-10 | Employee roster CRUD, owner-vs-employee counts kept separate | Pharmacy Admin | `PharmacyEmployee` | `/admin-panel/pharmacy/<id>/employees/` | Employees sheet on account-review | `pharmacy:view/edit` | `test_pharmacy_admin.py` (workforce counting) | Re-run this session, 0 failed; live dashboard `total_employees:0` (real, no employees added to seed pharmacies) | Complete |
| PA-11 | Orders: JSON-bridge order model, status transitions, refund | Pharmacy Admin | `AdminPanelRecord module='pharmacy-orders'` | `/admin-panel/pharmacy/orders/`, `POST .../orders/<id>/refund/` | Orders & Delivery tab | `pharmacy:view/refund` | `test_pharmacy_flow.py` (22, re-run 0 failed), refund-exclusion checks in `test_pharmacy_admin.py` | Re-run this session, 0 failed | Complete |
| **DEL-01** | Delivery-queue surfacing scoped to Pharmacy Admin | Pharmacy Admin | `AdminPanelRecord module='delivery-queue'` | `GET /admin-panel/pharmacy-deliveries/` | `_DeliveryQueueSection` | `pharmacy:view` | pre-existing | Re-verified live this session: `curl` with the real Pharmacy Admin token → 200 | Complete |
| **DEL-02** | Rider picker for delivery assignment | Pharmacy Admin | `profiles.DeliveryProfile` | **new this session**: `GET /admin-panel/pharmacy-riders/` | `_assign()` rider picker dialog | `pharmacy:assign` | **new this session**: 4 checks in `test_pharmacy_admin.py` | **Real bug found and fixed this session** — see below | **Was Blocked, now Complete** |
| DEL-03 | Assign / reassign, offline-rider pre-confirmation dialog, warning in result | Pharmacy Admin | `delivery.DeliveryOrder` | `POST /admin-panel/pharmacy-orders/<id>/assign-delivery/` | offline-rider confirm dialog | `pharmacy:assign` | **new this session**: assign-to-offline-rider check, warning-field check | **Live-verified this session via a real API call against the running server** (not click-driven — see Limitations): assigned a genuinely offline, approved rider to a freshly created delivery-queue order → `201`, `warning:"The assigned rider is currently marked offline."` | Complete |
| PA-12 | Sales/commission 20%/80% split, Decimal-safe, idempotent, rate-at-sale-time | Pharmacy Admin | `PharmacySale`, `PharmacyCommission` | `GET /admin/pharmacies/{sales,commissions}/` | Sales & Settlements tab | `pharmacy:view/export` | `test_pharmacy_admin.py` commission section (BDT 100 → 20/80 exact, idempotency, refund exclusion) | Re-run this session, 0 failed | Complete |
| PA-13 | Settlements generate/list/mark-paid/reject | Pharmacy Admin | `PharmacySettlement` | `POST .../settlements/generate/`, `PATCH .../settlements/<id>/`, `GET /admin-panel/pharmacy/settlements/` | Sales & Settlements tab | `pharmacy:approve/export` | `test_pharmacy_admin.py` settlement section | Re-run this session, 0 failed | Complete |
| PA-14 | Dashboard: live account/medicine/employee/sales/chat/appeal/delivery metrics, no hardcoded values | Pharmacy Admin | aggregate queries only | `GET /admin-panel/pharmacy/dashboard/` | Overview stat bar | `pharmacy:view` | dashboard-sanity checks in `test_pharmacy_admin.py` | **Re-verified live this session**: real `curl` response shown below, all values genuine (5 accounts, 13 active medicines, 2 low-stock, 4 out-of-stock, real audit rows) | Complete |
| PA-15 | Reports & Audit: 14 CSV export types + dedicated audit-log view | Pharmacy Admin | reuses each module's existing query | `GET /admin-panel/pharmacy/export/<type>/`, `/admin-panel/pharmacy/audit/` | Reports & Audit tab (7th tab) | `pharmacy:export` | `test_pharmacy_admin.py` (15 checks incl. the 406-header regression) | Re-run this session, 0 failed | Complete |
| PA-16 | RBAC isolation across 11 actor types (Pharmacy Admin, 6 other admin tiers, Support Agent, Pharmacy owner, Farmer, unauthenticated) | All | `admin_rbac.can_perform_action` | any `/admin-panel/pharmacy/*` endpoint | n/a | full matrix | `test_pharmacy_admin.py` permission-matrix section (14 checks) | Re-run this session, 0 failed | Complete |
| PA-17 | One coherent admin shell, no duplicate navigation, role-aware sidebar | Pharmacy Admin | n/a | n/a | `AdminScaffold` + `AdminPharmacyScreen` (7 tabs) | role-aware menu | `admin_screens_smoke_test.dart` (3 tests: 7 tabs render, 320px no-overflow, Reports tab selectable) | Re-run this session (full 192-test Flutter suite), 0 failed; `flutter analyze` clean | Complete |
| PA-18 | Nothing hardcoded on the admin dashboard | Pharmacy Admin | all live DB queries | `/admin-panel/pharmacy/dashboard/` | Overview | n/a | n/a | Confirmed by direct field-by-field inspection of a live response this session | Complete |
| PA-19 | `seed_platform_demo` creates the Pharmacy Admin account end-to-end on a clean DB | n/a | `seed_platform_demo.py` | mgmt command | n/a | n/a | n/a | **Still blocked** — confirmed again this session: the command fails before reaching the admin section on an unrelated pre-existing bug (`farmer.rashed@example.com` has duplicate `Farm` rows, `get_or_create` raises `MultipleObjectsReturned`). `_create_pharmacy_admin.py` remains the reliable workaround. | Blocked (reason: pre-existing, unrelated farmer-seed data bug; fixing it would touch farm/flock/expense data with real FK dependents, out of scope for a pharmacy-only task) |
| PA-20 | Nothing committed to git | n/a | n/a | n/a | n/a | n/a | n/a | `git status` confirmed at the end of this session shows only working-tree changes; no `git add`/`commit` run | Complete |

## Live dashboard response captured this session (real, not illustrative)

```
GET /api/admin-panel/pharmacy/dashboard/  (as pharmacy.admin@featherflow.local)
{"summary":{"pharmacy_accounts":5,"pending_verification":0,"active_medicines":13,
"medicine_categories":7,"total_employees":0,"total_sold":0,"gross_sales":"0.00",
"featherflow_commission":"0.00","pharmacy_share":"0.00"},
"medicine_alerts":{"pending_approval":0,"low_stock":2,"out_of_stock":4},
"orders_needing_delivery_assignment":0, ...}
```

## The one real bug found this session (DEL-02/DEL-03)

**Symptom**: the delivery-assignment rider picker in
`admin_pharmacy_screen.dart` called `_api.list('riders')`, which hits the
generic `/api/admin-panel/riders/` collection. That collection's RBAC gate
maps module `riders` → permission `delivery` (`admin_rbac.py:51`), a module
the `admin_pharmacy` role does not have. Confirmed live: logging in as the
real dedicated Pharmacy Admin account and calling that endpoint returns
`403 {"detail":"Your admin role cannot \"view\" in the \"delivery\" module."}`.

**Why the prior reports missed it**: their live-verification passes (§27/§36
of the implementation report) used the account that was logged in for the
*rest* of that walkthrough, and the report explicitly states no offline
riders existed in the seed to click through the dialog interactively — the
403 would only surface on that specific click, which was never attempted with
the real Pharmacy Admin session. `admin_super` (wildcard RBAC) never hits
this gate, which is why earlier informal checks with a super-admin account
looked fine.

**Fix**: new endpoint `GET /api/admin-panel/pharmacy-riders/`
(`backend/api/admin_pharmacy.py`), gated on `pharmacy:assign` (not
`delivery:view`), reusing the existing `_rider_json`/`_bulk_rider_context`
serializer verbatim — same response shape, so no Flutter model changes were
needed beyond pointing the picker at the new endpoint
(`AdminApiService.pharmacyAvailableRiders()`).

**Verified, not just fixed**: also discovered along the way that the dev DB
already contains several genuinely offline riders (the prior report's claim
that none existed was itself stale) — used one of them to drive a real,
non-synthetic assignment through the actual endpoint chain and confirmed the
offline-rider `warning` field is returned exactly as designed. New regression
tests added to `test_pharmacy_admin.py` (6 checks) so this cannot silently
regress again.

## Limitations of this session's verification (stated honestly)

- **No browser-automation tool (Playwright/similar) is available in this
  environment.** All "live verification" in this pass was done by restarting
  the real backend/frontend processes and driving the actual running backend
  with authenticated HTTP requests (`curl`, using the real dedicated Pharmacy
  Admin login) — the strongest verification available without a browser
  tool, and how the one real bug in this report was actually found (a Django
  test-client-only check would not have caught it, the same lesson the prior
  report drew from the CSV-406 bug). The rendered Flutter UI's click paths
  for locked-state banners, the Add Medicine dialog, and the offline-rider
  confirmation dialog were re-confirmed only via `flutter analyze` (clean),
  the full `flutter test` suite (192/192 passing), and a successful
  `flutter build web --release` — not by clicking through them in a real
  browser this pass. The prior sessions did do that click-through (with
  screenshots, per §27/§36 of the implementation report) before this pass's
  fix; the fixed rider-picker call itself has not yet been clicked through in
  a live browser, only verified at the API layer end-to-end.
- **PA-09b** (inventory stock-movement history) remains an open, named gap.
- **PA-19** (`seed_platform_demo` end-to-end) remains blocked on a pre-existing,
  unrelated farmer-data bug.
