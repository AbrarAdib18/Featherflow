# F-004 Fix Report — Pharmacy GET handlers must not fabricate data

Date: 2026-10-01. **Nothing was committed** (`git log -1` = `6a036eb`; `git stash list` empty; no `git add/commit`). The fix is in the working tree only. Fault reference: `FEATHERFLOW_FAULT_REGISTER.md` F-004; cleanup of the already-fabricated rows: `FEATHERFLOW_DATA_RESTORATION_REPORT.md`.

## 1. Root cause

`backend/pharmacy/views.py` had a private `_seed(user)` that was called from **read paths**:

* `_records(user, module)` → used by `GET /api/pharmacy/dashboard/`, `GET /api/pharmacy/products/`, `GET /api/pharmacy/orders/` (legacy `collection`) and `GET /api/pharmacy/<kind>/<id>/` (`record`, which also called `_seed()` directly).
* If the caller owned no `pharmacy-products` / `pharmacy-orders` rows, `_seed()` **inserted** 4 hard-coded products (`MED-001 Oxytetracycline 20%`, `VAC-001`, `SUP-001`, `EQP-001`) and 3 hard-coded orders (`ORD-001..003`, farmers "Karim Hossain / Jamal Mia / Salma Akter", ids `F001..F003`) and then called `_sync_admin_medicine(..., status='Approved')`, which created pre-**approved** shared `medicines` records. The `medicines` record id is the bare `MED-001` (unscoped), so the last caller overwrote the owner.
* Any role that passes `IsPharmacyAccount` hit it — including Super Admin (hence the fabricated "Owner Admin" pharmacy) — and the legacy `/api/pharmacy/marketplace/` then listed the fabricated products as purchasable.
* Same pattern, second source found by the audit of "demo/fallback/seed" strings: `backend/api/admin_views.py` `SEEDS['pharmacies']` (P001–P003 MedPlus/AgroVet/PoultryMed) and `SEEDS['medicines']` (M001–M004) were inserted by `_seed(module)` on every `GET /api/admin-panel/medicines/` (the generic collection). Real admin views already read users/catalogue instead, so these rows were pure demo data.

Search results for `demo|fallback|seed|fake|sample|default medicines|default orders|create if empty` over `backend/pharmacy`, `backend/api/admin_pharmacy*.py`, `backend/api/admin_views.py` and `lib/features/pharmacy`, `lib/features/admin/.../admin_pharmacy_screen.dart`, `lib/features/farmer/.../pharmacy*`: only the two sources above create data on read. The remainder are legitimate (comments; `seed_pharmacy_demo_data` command; `get_or_create(PostCategory)` in community — unrelated; Flutter `fallbackIcon` image placeholders; "no mock numbers" comments). `pharmacy/catalogue_views.py` (`medicines/`, `orders/`…, relational catalogue) and `farmer_views.py` (`/api/farmers/medicines/search/`) are read-only and owner-scoped; Flutter reads only those real endpoints and contains no fallback data (`DoctorSession` demo data is a different module/fault F-008).

## 2. Files changed

| File | Change |
|---|---|
| `backend/pharmacy/views.py` | Deleted `_seed()`. `_records()` is now a read-only, owner-scoped query (`payload__owner_id == request.user.id`, ordered) with a docstring forbidding writes. Removed the `_seed()` call in `record()`. Dropped the now-unused `timedelta` import. (POST/PATCH/DELETE keep their explicit user-action behaviour; every record key stays `_key(user, id)` = per-owner, so object-level isolation is unchanged and now tested.) |
| `backend/api/admin_views.py` | Removed `SEEDS['pharmacies']` and `SEEDS['medicines']` (demo rows no longer inserted by `GET /api/admin-panel/<module>/`). Only `SEEDS['diseases']` remains (not pharmacy data). |
| `backend/scripts/test_pharmacy_no_fabricated_data.py` | **New** regression suite (32 assertions) — §5. |
| `test/pharmacy_empty_states_test.dart` | **New** Flutter regression tests (3) — §5. |
| `F-004_FIX_REPORT.md`, `audit_logs/f004/`, `audit_logs/data/f004_*` , `audit_logs/tools/{f004*.js,capture.py,mkclean.py,emptyresp.py}` | Evidence/tooling. |

No Flutter product code needed changing: the real screens already render proper empty states ("No medicines yet", "No orders here", "No suppliers yet", zero stat cards) when the API returns empty lists. Seed data is untouched in `seed_pharmacy_demo_data` and the other seed commands. Pre-existing uncommitted changes in these files (Pharmacy Admin work) are unrelated and were left as they were.

## 3. Before / after

### 3.1 API (clean database `featherflow_clean`: full schema, 19 roles, 5 users, 0 `backend_admin_records`)
Captured by `audit_logs/tools/capture.py` with the **original** code (via `git stash` of the two files) and with the fix: `audit_logs/data/f004_before_fix_clean_db.json` / `f004_after_fix_clean_db.json`.

| Request (as) | Before | After |
|---|---|---|
| `GET /api/pharmacy/dashboard/` (empty pharmacy) | `products: 4 (MED-001 Oxytetracycline 20%, VAC-001, SUP-001, EQP-001), orders: 3 (ORD-001..003 Karim Hossain…)` | `products: [], orders: []` |
| `GET /api/pharmacy/products/` (empty pharmacy) | 4 results | `{"results": []}` |
| `GET /api/pharmacy/orders/` (empty pharmacy) | 3 results | `{"results": []}` |
| `GET /api/pharmacy/medicines/` (empty pharmacy) | `[]` (relational catalogue; was never fabricated) | `[]` |
| `GET /api/pharmacy/marketplace/` (empty pharmacy) | 3 listings sold by "Empty Pharmacy" | `{"results": []}` |
| `GET /api/pharmacy/dashboard/` (**Super Admin**) | 4 products + 3 orders ("Clean Super Admin" becomes a pharmacy) | `[] / []` |
| `GET /api/pharmacy/marketplace/` (Super Admin) | 6 listings (2 fabricated "pharmacies") | `[]` |
| `GET /api/admin-panel/medicines/` (Super Admin) | 8 results (M001–M004 + MED/VAC/SUP/EQP) | 0 |
| `GET /api/admin-panel/pharmacy/orders/` (Pharmacy Admin) | — | 0 |
| `GET /api/pharmacy/inventory/summary/`, `/earnings/` (empty) | all zero | all zero (`total_products 0, low_stock 0, … gross_sales "0.00", total_orders 0`) |

### 3.2 Database row counts around repeated GET requests
Clean DB, 3 passes × (empty pharmacy, Super Admin, Pharmacy Admin) × (dashboard, products, orders, medicines, marketplace, inventory summary, earnings, + admin medicines/pharmacies/pharmacy lists):

| `backend_admin_records` | start | after pass 1 | pass 2 | pass 3 |
|---|---:|---:|---:|---:|
| **Original code** | 0 | **22** (`medicines 8, pharmacy-orders 6, pharmacy-products 8`) | 22 | 22 |
| **Fixed code** | 0 | 0 | 0 | 0 |

Live dev DB (`featherflow`), after the restoration, 3 passes for AgroCare, GreenVet, Super Admin, Pharmacy Admin and a farmer over the same endpoints (`audit_logs/data/f004_live_db_counts.txt`): `backend_admin_records` **367 → 367**, no module changed; AgroCare and Super Admin dashboards return `0 products / 0 orders` (before the fix AgroCare would have regenerated 7 fabricated rows on first open). The suite run that followed changed `pharmacy-orders` 307 → 316 — those are fixtures left by the *project's own* scripts for already-deleted test users (`unknown-owner` rows; pre-existing test-leakage), not GET side effects; 0 rows carry a fabricated id or `F00x` farmer.

## 4. Browser evidence (real Chrome 154 + Playwright, release web build, backend on the clean DB, :8000 / :8080)
Server: `POSTGRES_DB=featherflow_clean uvicorn … :8000` (verified: login of clean-DB-only accounts works; DB counts read from the same DB). Frontend unchanged (no Flutter product change). Log: `audit_logs/f004/browser_log.txt`, screenshots in `audit_logs/f004/`.

| Session | Observed | Evidence |
|---|---|---|
| `clean.pharmacy.empty@example.com` (empty pharmacy) | landed `/pharmacy`; Home: "Lifetime earnings ৳ 0.00 · 0 orders · **0 Total Products · 0 Low Stock · 0 Out of Stock · 0 Expiring Soon · 0 Incoming Orders · 0 Active Deliveries**" | `empty_pharmacy_home.png` |
| same — Catalogue tab | "**No medicines yet** — Tap Add to list your first medicine." | `empty_catalogue.png` |
| same — Orders tab | "**No orders here**" (Incoming; other tabs empty too) | `empty_orders.png` |
| same — Suppliers tab | "**No suppliers yet**" | `empty_suppliers.png` |
| same — Analytics / Inventory tabs | render without demo names | `empty_analytics.png`, `empty_inventory.png` |
| same — 3 reloads | totals still zero, no demo names (`Oxytetracycline / Newcastle Vaccine / Karim Hossain / Jamal Mia / Salma Akter / #PH-10xx` absent) | log |
| API calls seen by the browser | `/api/pharmacy/{profile,permissions,earnings,medicines,orders,suppliers,inventory/*,analytics/*}` all 200 | log |
| **DB rows during the whole session** | `backend_admin_records` 0 → 0 | log |
| Super Admin `clean.super@…` at `#/pharmacy` and `#/admin/pharmacy` | pharmacy shell all zeros; Admin Pharmacy overview "2 Pharmacies · 0 Pending approvals · 0 Active deliveries" (the 2 real pharmacy users); no "Owner Admin" listing | `super_admin_pharmacy_shell.png`, `super_admin_admin_pharmacy.png` |
| Pharmacy Admin `clean.pharmacyadmin@…` | Overview: 2 account holders, 0 pending, **0 total medicines, 0 active, 0 low stock, 0 out of stock, 0 pending approval**; Medicine Approvals and Orders & Delivery tabs empty | `pharmacy_admin_overview.png` |
| Isolation: pharmacy "Other" creates a real medicine (`201`) | Other's Home shows **1 Total Products** and its Catalogue shows "Isolation Real Medicine ৳50 · In stock 10" (`iso_other_catalogue.png`); the empty pharmacy still shows "No medicines yet" and zero totals (`iso_empty_catalogue.png`); API: empty pharmacy `GET /medicines/` → `[]`, `GET/PATCH /medicines/<other id>/` → **404 / 404** | log |

Caveat: DOM-text capture of Flutter's canvas only sees semantics-labelled nodes, so a few "present?" probes in the log read `false` even where the screenshot clearly shows the empty-state text (e.g. "No orders here"); the screenshots are the evidence of record.

## 5. Tests

### 5.1 Backend regression — `backend/scripts/test_pharmacy_no_fabricated_data.py` (32 assertions, live DB, `nofab+` throw-away accounts, self-cleaning)
Run: `backend/venv/Scripts/python.exe backend/scripts/test_pharmacy_no_fabricated_data.py` → **32 passed, 0 failed**.

| Required proof | Assertions |
|---|---|
| 1. Empty pharmacy returns zero medicines | dashboard `products == []`; `/products/ == []`; `/medicines/ == []`; marketplace has no listing for empty/admin accounts |
| 2. Empty pharmacy returns zero orders | dashboard `orders == []`; `/orders/` empty |
| 3. Repeated GETs create no records | single sweep and 3 sweeps × {pharmacy, Super Admin, Pharmacy Admin, farmer} × 16+ endpoints: `AdminPanelRecord` count and `PharmacyMedicine` count unchanged; admin `medicines`/`pharmacies` module counts unchanged; no fabricated ids; still nothing created after real data exists |
| 4. One pharmacy cannot see another's records | B creates a real product (201); B sees exactly 1 (also on its dashboard); A (empty) sees 0 and an empty dashboard; A `GET/PATCH/DELETE` B's product → **404**; B can read its own (200); a farmer gets 401/403 on the pharmacy dashboard |
| 5. Super Admin sees only real records | dashboard `[]/[]`; no marketplace listing for the Super Admin; Pharmacy Admin order list has no orders for the empty test accounts; legitimate `pharmacy-orders` rows unchanged by GETs |
| 7. Dashboard/inventory/earnings totals zero | inventory summary (all totals zero; `low_stock_threshold` is config and excluded) and earnings zero for an empty pharmacy |

**The suite fails on the old code**: run against the stashed original files it gave **18 passed, 14 failed** (fabricated `MED-001…` / `ORD-001…` returned by dashboard, `/products/`, `/orders/`, Super Admin; rows created: 358 → 369 → 376; marketplace listed the empty accounts). With the fix: 32/0.

### 5.2 Flutter — `test/pharmacy_empty_states_test.dart` (3 tests, run through the real `PharmacySession.refresh()` against a mock HTTP client that returns the actual empty-pharmacy JSON captured from the fixed backend, `audit_logs/data/f004_empty_pharmacy_responses.json`)
* Session after a real refresh: zero medicines/orders/totals (`totalProducts, lowStock, outOfStock, expiringSoon, incomingOrders, activeDeliveries`, `recentOrders` empty, earnings `total_orders 0`) — requirement 7 (client side).
* `PharmacyCatalogueScreen` shows **"No medicines yet / Tap Add to list your first medicine."** and none of the demo names — requirement 6.
* `PharmacyOrdersScreen` shows **"No orders here"** in every tab (Incoming/Preparing/Delivery/Completed/Cancelled) and no demo farmers/orders — requirement 6.

### 5.3 Full-suite regression (after the fix)
| Suite | Result |
|---|---|
| All backend scripts (`scripts/test_*.py`, 44 incl. the new one, live DB) | 43 pass, **1,513 assertions, 0 failed** (1,481 previous + 32 new); 1 script still crashes — `test_admin_pagination_performance` (F-001, unrelated, pre-existing). None of the existing pharmacy/admin suites depended on the removed seed data. |
| `flutter test` | **229 passed** (226 + 3), 0 failed |
| `flutter analyze` | same 6 pre-existing `info` hints, 0 errors/warnings (new test file clean) |
| `manage.py check` | no issues |

## 6. Behaviour notes / remaining items
* Requirement "preserve legitimate seeded records": `seed_pharmacy_demo_data`, the seeded relational catalogue, GreenVet/AgroCare real orders and the `Playwright…/Smoke…` fixtures are untouched. Pre-existing demo rows left in the dev DB by the old fallback were handled in the restoration report; `backend_admin_records` still holds `medicines` M001–M004 and `pharmacies` P001–P003 from older admin GETs (created 2026-09-04/05) — now inert (nothing reads P00x; M00x are listed only by the generic `/api/admin-panel/medicines/` and are not served to farmers) and **not deleted here** because deletion was outside this task's scope; delete them with the restoration script's method if desired.
* Not changed (separate faults): `/api/pharmacy/marketplace/` still returns any authenticated role's view and still lists suspended pharmacies' approved products (F-011/F-035); `_sync_admin_medicine` still keys the shared `medicines` record by the bare product id (cross-pharmacy overwrite risk for fixed ids — no fixed ids are generated any more).
* Environment left behind: Postgres database `featherflow_clean` (empty schema + roles + 5 test users) — safe to drop (`DROP DATABASE featherflow_clean`); servers on :8000/:8080 stopped.

## 7. Confirmation
Verified with a clean database and a real browser, not by code review alone: API before/after responses, row counts before/after repeated GETs (clean and live DB), 32 backend + 3 Flutter regression tests (the backend suite demonstrably fails on the old code), the full existing backend/Flutter suites, and Chrome sessions for an empty pharmacy, Super Admin, Pharmacy Admin and a cross-pharmacy isolation case. **Nothing was committed.**
