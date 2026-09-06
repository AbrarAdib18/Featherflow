# Farmer / User Panel — Gap Analysis (Pass 1)

**Date:** 2026-09-06
**Scope:** Complete the Farmer/User panel to 100% per `Featherflow.pdf` sections 1–5, 8–9, 11–13.
**Explicitly deferred (do NOT build):** ML disease detection, chatbot, tax calculation ("Calculate My Tax" / Due Tax logic), analytics charts, SMS/push, multi-language expansion, automated settlement.

> **STATUS: awaiting review before Phase 2.**

---

## 1. How the existing stack works (so new code matches it)

| Concern | Existing convention | Notes |
|---|---|---|
| Backend | Django + DRF, function-based `@api_view` views, `managed=False` models over `featherflow_schema.sql` | No serializers for most farmer modules — views hand-build dicts. |
| Farmer URL roots | `/api/costs/` → `expenses.urls`; `/api/workers/` → `workers.urls`; `/api/feed/` → `feed.urls`; `/api/farmers/` → `pharmacy.farmer_urls`; `/api/consultations/`; `/api/notifications/` | **The task brief's `/api/farmers/costs/...` scheme does NOT match the repo.** Extend the existing roots instead. |
| Auth | `rest_framework_simplejwt`; `request.user` is the custom `users.User`; permission classes `IsFarmer` (consultations), `IsFarmerUser` (pharmacy) | Reuse these; add a shared `IsFarmer` where missing. |
| Farm resolution | `workers.views.farm_for(user)` — get-or-creates `FarmerProfile` + primary `Farm` | Single source of truth; every new farmer view must call it. |
| File upload | `FarmManagementService.upload(path, bytes, filename)` posts multipart field **`file`**; pharmacy's `prescription_upload` uses field **`image`** and returns `{image_url}` | Two patterns exist — standardize new farmer uploads on `image` + `{image_url}` (matches pharmacy, which is the newer pass). |
| Realtime | 4 s `Timer.periodic` silent refresh (pharmacy screen); `/api/me/updates/?since=` delta poll; notifications 3 s poll on dashboard | Community/news already poll at 4 s. |
| Flutter structure | `lib/features/<x>/data/*_service.dart` (static methods) + `presentation/screens/*.dart`; routes in `lib/core/router/app_router.dart` (`AppRoutes` consts) | `FarmManagementService` is the generic farmer HTTP client. |
| Money display | `৳` prefix, Bengali numerals when locale=bn | |

---

## 2. Screen-by-screen state

| Screen (`lib/features/farmer/presentation/screens/`) | Route | Data source today | Verdict |
|---|---|---|---|
| `farmer_dashboard_screen.dart` | `/farmer` | **Mock** — "Green Valley Farm", "4,500 Birds", 3 hardcoded alerts, hardcoded farm stats. Only the notification bell is real (`GET /api/notifications/`, 3 s poll). | **Rewire — critical.** No financial stats, no real farm name/bird count, no real alerts, no quick "add expense/revenue" actions. |
| `farmer_profile_screen.dart` | `/farmer/profile` | **Mock** — farm type / bird count / experience from l10n string constants; edit button is `onPressed: (){}`; no photos; account status is the only real field (from session). | **Rewire + build — critical.** Needs a real farmer-profile GET/PUT endpoint + all PDF farm fields + photo gallery/upload + verification badge. |
| `cost_management_screen.dart` | `/farmer/cost-management` | **100 % mock** — no service import at all. Every number, expense card, loan, transaction row is a hardcoded literal. Buttons are `onPressed: (){}`. | **Rebuild — critical.** This is the single biggest gap. |
| `feed_management_screen.dart` | `/farmer/feed-management` | **Real** — `GET/POST /api/feed/`, PATCH/DELETE stock, schedules CRUD. `RefreshIndicator` + `initState` load. | **Enhance.** No 4 s poll; no consumption logging (the `feed_consumption` table is unused); no cost-per-bird. |
| `labor_management_screen.dart` | `/farmer/labor` | **Real** — `GET/POST /api/workers/`, PATCH attendance, POST payments, PATCH/DELETE worker. | **Enhance.** No 4 s poll; worker edit is status-only; no task assignment UI (`worker_tasks` table unused). |
| `farmer_pharmacy_screen.dart` | `/farmer/pharmacy` | **Real** — `FarmerPharmacyService` → `/api/farmers/…`; 4 s silent poll already. | **Verify only.** Previous pass. Confirm order→delivery status + rider contact render. |
| `farmer_consultations_screen.dart` | `/farmer/consultations` | **Real** — `FarmerConsultationService` → `/api/consultations/…`; 8 s poll. | **Verify + tighten poll to 4 s.** Previous pass. |
| `vet_map_screen.dart` | `/farmer/vet-map` | **Real** — `VetDiscoveryService` → `/api/consultations/vets/`. | **Verify only.** |
| `disease_detection_screen.dart` | `/farmer/disease-detection` | Mock UI. | **DEFERRED — leave as-is.** (ML + chatbot.) |
| `subscription_screen.dart` | `/subscription` | `GET /api/subscriptions/` (2 service refs). | **Verify only.** |
| Community feed / News / Notifications | `/community`, `/paper-portal` | Separate features, completed in Community Pass 1. Dashboard links out to them. | **Verify links + farmer can post/react/bookmark.** |

---

## 3. Backend gap table

### 3a. Cost Management — `expenses` app (`/api/costs/`)

| Endpoint | Exists? | Gap |
|---|---|---|
| `GET /api/costs/` (dashboard summary) | ✅ | Returns `total_expense/total_revenue/net_profit/loan_balance/tax_due` + category rollup + 10 recent tx + active loans. **Missing:** cash balance, per-category pending/paid split, per-category cost-per-bird, `lifetime`/`custom` date range (only `monthly`/`yearly`/none), revenue source breakdown, alerts. |
| `GET /api/costs/expenses/` (list w/ filters) | ❌ | **POST only.** No list, no `?category=&status=&flock=&from=&to=` filtering. |
| `GET/PUT/DELETE /api/costs/expenses/<id>/` | ❌ | No detail / edit / delete. |
| `PATCH /api/costs/expense-status/` | ✅ | Mark paid/pending/overdue by id. OK. |
| `POST /api/costs/expenses/upload-receipt/` | ❌ | No receipt image upload (model has `receipt_url`). |
| `GET /api/costs/revenues/` (list) | ❌ | **POST only.** No list, no source/date/flock filter, no by-batch/month/year rollup. |
| `GET/PUT/DELETE /api/costs/revenues/<id>/` | ❌ | Missing. |
| `POST /api/costs/revenues/upload-receipt/` | ❌ | Missing. |
| `GET /api/costs/loans/` (list + installments + next payment + overdue) | ❌ | Dashboard returns active loans only; no dedicated list, no `loan_installments` (table exists, unused), no "next payment date / overdue amount". |
| `POST /api/costs/loans/` (request loan / application) | ⚠️ | Exists but creates an **active** loan directly. PDF wants a *Get Loan* application flow with status pending→approved/rejected (admin side). No `status='pending_approval'` path, no admin approval endpoint. |
| `PATCH /api/costs/loans/` (repay) | ✅ | Reduces `remaining_balance`. OK; should also write an installment/payment row. |
| `GET /api/costs/inventory/` (feed+meds+vaccines+chicks+litter summary + low-stock) | ❌ | Missing entirely. Only feed_stock is queryable (via `/api/feed/`). |
| `GET /api/costs/batches/` (per-flock cost/revenue/profit) | ❌ | Missing. `expenses.flock_id` / `revenues.flock_id` columns exist but nothing aggregates by flock. |
| `GET /api/costs/reports/?type=&from=&to=&format=pdf\|xlsx` | ❌ | Missing. No PDF/Excel export. (`reportlab`/`openpyxl` — check `requirements.txt`.) |
| `POST /api/costs/cashout/` (bKash/Nagad/bank payout) + payment history | ❌ | Missing. `payments` table + `users.bank_mobile_payment_details` exist; no cashout view, no receipt log endpoint. |
| Alerts (due bills, loan dates, low cash, low stock) | ❌ | No aggregation endpoint; dashboard alerts are frontend-hardcoded. |
| Tax (`/tax/calculate/`, `/tax/pay/`) | ✅ | **DEFERRED** — leave endpoints, frontend shows "Coming Soon". |

### 3b. Farm Profile — no app owns this

| Endpoint | Exists? | Gap |
|---|---|---|
| `GET /api/farmers/profile/` | ❌ | No read endpoint for `FarmerProfile` + primary `Farm` + verification status. (`/api/auth/me/` returns user-level fields + some `profile_data` only.) |
| `PUT /api/farmers/profile/` | ❌ | No update. All PDF farm fields (`farm_name, owner_name, farm_type, number_of_birds, farm_registration_number, years_in_farming, experience_level, primary_diseases_faced, feed_type, feed_sourcing_method, existing_vet_consultant, number_of_active_workers, consent_data_collection`) are only settable at signup. |
| `POST /api/farmers/profile/upload-photo/` (multi) | ❌ | `FarmerProfile.farm_photos` (JSON array) — no upload endpoint. |
| Sheds / flocks (batches) CRUD | ❌ | `farms` app has **empty `urls.py`, no `views.py`**, not even `include()`d. Farmers cannot create/list sheds or flock batches except implicitly via consultation booking. Needed for batch cost tracking. |

### 3c. Labor — `workers` app (`/api/workers/`)

| Endpoint | Exists? | Gap |
|---|---|---|
| `GET/POST /api/workers/`, `PATCH /attendance/`, `POST /payments/`, `PATCH/DELETE /detail/` | ✅ | Functional. |
| Worker task assignment (`worker_tasks` table) | ❌ | Table exists; no endpoint. PDF labor scope is light ("initial plans") — **low priority**, tasks_completed count is already surfaced. |
| Full worker edit (name/phone/role/wage) | ⚠️ | `/detail/` PATCH only changes `status`. |

### 3d. Feed — `feed` app (`/api/feed/`)

| Endpoint | Exists? | Gap |
|---|---|---|
| `GET/POST /api/feed/`, stock PATCH/DELETE, schedules CRUD | ✅ | Functional. |
| `POST /api/feed/consumption/` + `GET` logs | ❌ | `feed_consumption` table unused; `orders()` returns 501. Consumption logging + cost-per-bird missing. |

### 3e. Integration reads (dashboard aggregation)

| Need | Exists? | Gap |
|---|---|---|
| Pharmacy orders for farmer | ✅ `/api/farmers/orders/` | OK. |
| Consultations for farmer | ✅ `/api/consultations/` | OK. |
| Delivery status inside an order | ✅ (order JSON bridge) | Verify rider name/phone surfaced. |
| Community posts / notifications for farmer | ✅ `/api/community/…`, `/api/notifications/` | OK. |
| News / research articles | ✅ `/api/articles/`, `/api/research/` | OK (view-only for farmer). |
| Loan approval + farm verification status (admin→farmer) | ⚠️ | Farm verification: `FarmerProfile.approved_by_admin` exists but no farmer-facing read. Loan approval workflow: not implemented (see 3a). |
| One combined `GET /api/farmers/dashboard/` | ❌ | Dashboard currently makes only the notifications call; needs a real aggregate (farm summary + finance stats + recent activity + alerts). |

---

## 4. Frontend gap summary

**Rebuild (mock → real):**
1. `cost_management_screen.dart` — bind to real dashboard; 9 expense categories (feed, medicines, labor, utilities, chicks, vaccines, litter, transport, repairs) each with total/pending/paid + Manage + Pay; revenue sections (5 sources); quick actions (Add Expense, Add Revenue, Request Loan, Generate Report); filters lifetime/monthly/yearly/custom; Due-Tax card → "Coming Soon".
2. `farmer_dashboard_screen.dart` — real welcome (farm name), real stat cards (Revenue big, Expense, Net Profit, Cash Balance), real recent activity, real alerts banner, quick-action buttons.
3. `farmer_profile_screen.dart` — real farm details from new endpoint, edit form (all PDF fields), photo gallery + multi-upload, verification badge.

**New screens:**
4. Expense-per-category management screen (list + add form + receipt upload + edit/delete + pay).
5. Revenue management screen (list + add + receipt + edit/delete).
6. Loan management screen (list + detail w/ installments + Request Loan form + status).
7. Inventory management screen (tabs: feed/meds/vaccines/chicks/litter + low-stock + add/consume).
8. Reports screen (type + date range + generate → PDF/Excel download + preview).

**New data services:** `cost_management_service.dart`, `farmer_profile_service.dart` (or extend `FarmManagementService`).

**Enhance existing:**
9. Feed screen — 4 s poll + consumption logging UI.
10. Labor screen — 4 s poll + full worker edit.
11. Consultations screen — poll 8 s → 4 s.

**New routes** in `AppRoutes`: `costExpenses`, `costRevenue`, `costLoans`, `costInventory`, `costReports`.

---

## 5. Image upload

- **Backend:** add `upload-receipt` (expense + revenue) and `profile/upload-photo` views. Reuse pharmacy's validator (`MAX_IMAGE_BYTES`, `ALLOWED_IMAGE_EXT` in `pharmacy/catalogue_views.py`), multipart field `image`, return `{image_url}`. Store under `MEDIA_ROOT` via `default_storage` (same as `prescription_upload`).
- **Frontend:** `image_picker` is already a dependency (pharmacy prescription upload). Reuse: single-image for receipts, multi-image for farm photos, thumbnail + remove, retry on failure.

---

## 6. Real-time integration plan (4 s)

| Data | Screen | Mechanism |
|---|---|---|
| Dashboard finance stats + alerts + activity | `/farmer` | 4 s silent refresh of `GET /api/farmers/dashboard/` |
| Cost dashboard summary + tx list | `/farmer/cost-management` | 4 s silent refresh |
| Expense / revenue lists | category / revenue screens | 4 s silent refresh |
| Inventory low-stock | inventory screen | 4 s silent refresh |
| Loan status | loan screen | 4 s silent refresh (+ `/api/me/updates/` for admin decisions) |
| Pharmacy orders | pharmacy screen | already 4 s |
| Consultations | consultations screen | 8 s → **4 s** |
| Notifications | dashboard bell | already 3 s |

---

## 7. Priority order

**P0 — farmer cannot do the core job without these**
1. `GET /api/farmers/dashboard/` + rewire dashboard.
2. Cost Management backend: expense list/detail/CRUD, revenue list/CRUD, dashboard v2 (cash balance, pending/paid split, lifetime/custom, revenue breakdown).
3. Rebuild `cost_management_screen.dart` + expense/revenue management screens + services.
4. Receipt upload (expense + revenue).
5. `GET/PUT /api/farmers/profile/` + rewire `farmer_profile_screen.dart` + photo upload.

**P1 — completes the PDF spec**
6. Loan list + installments + Request Loan flow + loan screen.
7. Inventory summary endpoint + inventory screen.
8. Batch/flock tracking endpoint + minimal shed/flock CRUD (`farms` app).
9. Reports endpoint (PDF/Excel) + reports screen.
10. Cashout endpoint + payment history + Pay/Cashout buttons.
11. Alerts aggregation (due bills, loan dates, low stock, low cash).

**P2 — polish**
12. Feed consumption logging + cost-per-bird.
13. Labor: full worker edit; 4 s polls on feed/labor.
14. Consultations poll → 4 s; verify pharmacy/community/news integration end-to-end.
15. Budget vs actual, supplier payment history, mortality cost impact.

---

## 8. Open questions for review

1. **URL root:** confirm extend `/api/costs/`, `/api/workers/`, `/api/feed/` and add a small `/api/farmers/profile/…` + `/api/farmers/dashboard/` — rather than the brief's `/api/farmers/costs/…`. (Recommended: yes, match repo.)
2. **Loan "Get Loan" flow:** real admin approval queue entry (like `admin_approval_queue`), or a simple `status=pending` loan the farmer's own admin can approve? (Recommended: reuse `admin_approval_queue` pattern, minimal.)
3. **Reports:** `reportlab==4.4.3` is already in `requirements.txt` (used for prescription PDFs) → PDF export is free. Excel has no dep — OK to add `openpyxl`, or ship **CSV** (zero-dep) for the "Excel" export in Pass 1? (Recommended: PDF via reportlab + CSV; add openpyxl only if a true .xlsx is required.)
4. **Cashout:** Pass 1 = record a `payments` row with `status=pending` + notification only (no gateway), matching "manual payout in Pass 1". Confirm.
5. **Shed/flock CRUD:** build minimal farmer-facing endpoints in the empty `farms` app, or keep batches implicit and only aggregate existing flocks? (Recommended: minimal CRUD — needed for batch cost tracking to be usable.)
