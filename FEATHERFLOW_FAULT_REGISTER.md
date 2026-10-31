# FEATHERFLOW — Fault Register

All faults below were **observed** (live browser, HTTP probe, script run, or code + data reading) unless the Status says "Suspected". Nothing was fixed: per the audit rules, product code was not modified. Severity: **Critical** = blocks login, data safety or a core workflow; **High** = core feature unusable or wrong-role access; **Medium** = partial feature or serious UX/integration defect; **Low** = polish/minor/documentation.

**Totals: Critical 0 · High 5 · Medium 19 · Low 16 (40 faults).** No Critical fault was found; the five High faults each make a named core workflow impossible or unsafe in the real UI.

| ID | Sev | Role | One-line summary |
|---|---|---|---|
| F-001 | High | Doctor Admin / Super / Operations / Support | Admin "Doctors & Patients" fails with HTTP 500 (NULL `appointment_time`) |
| F-002 | High | Pharmacy owner (suspended) | Suspended pharmacy is signed out by the client → appeal flow unreachable in the UI |
| F-003 | High | Delivery rider | Route/ETA endpoint always fails: Google Directions (legacy) `REQUEST_DENIED`, returned as 404 |
| F-004 | High | Pharmacy owner / any account | GET handlers fabricate demo products/orders for any account and list them in the marketplace |
| F-005 | High | Feed Admin / Rider | No "arrival" state and no proof review/reject/resubmit/approve workflow exists |
| F-006 | Medium | `pharmacist` | Orphan role lands in the Farmer shell and gets 403s |
| F-007 | Medium | Every role | No role-based route guard in Flutter router; wrong-role shells open |
| F-008 | Medium | Doctor | `DoctorSession` pre-loads hard-coded demo data; real failures look like real data |
| F-009 | Medium | All admin roles | Dashboard "Recent activity" leaks authentication events (emails) across roles |
| F-010 | Medium | Farmer/Doctor/… (community) | Posts store raw HTML/script and unvalidated `media_urls` (e.g. `javascript:`) |
| F-011 | Medium | Farmer | Marketplace shows test/demo medicines and a suspended pharmacy's stock |
| F-012 | Medium | Pharmacy Admin / Super / Ops | N+1 and unpaginated admin lists (321 queries for one page) |
| F-013 | Medium | Researcher / Admin / Farmer | Poll storms: 5 endpoints every 6 s (researcher), 135 `admin-panel/profile` calls |
| F-014 | Medium | Engineering | `manage.py test` cannot run; all verification scripts hit the live DB |
| F-015 | Medium | Engineering | `seed_platform_demo` crashes; seeds overwrite account status and mutate shared data |
| F-016 | Medium | Farmer | Disease chatbot/follow-ups/report download/feedback/multi-image not implemented |
| F-017 | Medium | Researcher | The whole researcher write workflow has no automated test |
| F-018 | Medium | Pharmacy owner | Pharmacy shell tabs are state-only; routes exist but are unused |
| F-019 | Medium | Platform | CORS allow-all under DEBUG; Google Maps keys committed/hard-coded |
| F-020 | Medium | Admin (payroll) | A stale open admin shift (14.7 days) is still accruing hours |
| F-021 | Medium | Doctor | Doctor video relies on external Jitsi; `video_calls` table never written (unverified end-to-end) |
| F-022 | Medium | Data model | No dedicated storage for mortality, vaccine history, biosecurity notes, refunds, receipts, OTP/signature |
| F-023 | Medium | Farmer | Pharmacy/feed "order tracking" unverified end-to-end in UI (no live data path exercised) |
| F-024 | Medium | Finance/Pharmacy Admin | Sales / commission / settlement screens have **no live data** (tables empty) |
| F-025 | Low | Admin | `PATCH /api/admin-panel/<module>/<non-uuid>/` → 500 instead of 404 |
| F-026 | Low | All | Login throttle is per-IP 20/min and also blocks valid logins; no per-account lockout |
| F-027 | Low | Feed Admin | Dashboard shows "No overview data for your role" |
| F-028 | Low | Engineering | Duplicate/unused endpoint families (`/api/costs`, `/api/feed`, `/api/workers`, …) |
| F-029 | Low | Doctor/Pharmacy/Delivery/Researcher | Pending applicants have `account_status='active'` |
| F-030 | Low | Platform | Unbounded growth: notifications 11.5k rows, 4.8k outstanding JWTs |
| F-031 | Low | Pharmacy | Order IDs `ORD-001..003` not globally unique (per-pharmacy seed) |
| F-032 | Low | Pharmacy | Employees have no login (roster only) |
| F-033 | Low | Engineering | `flutter analyze`: 6 `prefer_const` infos |
| F-034 | Low | Researcher | Needs-revision content is announced as "hidden" |
| F-035 | Low | Farmer | Pharmacy email/phone/licence and vet lat/lng exposed to every farmer |
| F-036 | Low | Rider | `proof_of_delivery_url` stored unvalidated for non-final statuses |
| F-037 | Low | Auth | 2FA columns exist but no 2FA flow |
| F-038 | Low | Admin UI | Admin shell chrome (sidebar) renders for non-admins before the 403 |
| F-040 | Low | Doctor/Farmer | Consultation chat history is returned unbounded (no page size) |
| F-039 | Low | Farmer | `POST /api/farmers/costs/expenses/` has no idempotency/duplicate guard (two concurrent identical submits → 2 rows) |

---

## High

### F-001 — Admin consultations list returns 500
* **Severity:** High · **Role:** Doctor Admin, Super Admin, Operations Admin, Support Agent (anyone who opens Doctors & Patients)
* **Feature:** Admin → Doctors & Patients (All Doctors / Consultations tabs)
* **Observed:** `GET /api/admin-panel/consultations/` → `500 TypeError: unsupported format string passed to NoneType.__format__`. In the browser the screen shows **"No doctors found."** plus a red toast **"Admin request failed (500)."** (screenshot `admin_doctor_d0_21.png`); the 500 repeated 14× (Doctor Admin), 22× (Super), 15× (Support), 14× (Ops) during the crawl.
* **Expected:** list renders; consultations without a slot display "—".
* **Repro:** Log in as `doctor.admin@featherflow.dev` / `FeatherflowDemo@2026` → sidebar *Doctors & Patients*. Or `python backend/scripts/test_admin_pagination_performance.py` (fails with the same traceback).
* **Root cause:** `backend/api/admin_views.py:1051` (`f'{c.appointment_date} {c.appointment_time:%H:%M}'`) and `:444` format a `None` time. `farmer_panel_integrity_extension.sql:24` dropped `NOT NULL` on `appointment_time` (and date) so requested/emergency consultations can have no slot; the live DB has such a row (`665070c9-…`, status `requested`). The Django model (`consultations/models.py:22-23`) still declares both fields non-null — model/DB mismatch.
* **DB/API impact:** read-only; one NULL row breaks the whole page for every admin. **Security impact:** none (availability).
* **Fix:** null-safe formatting in both places; align model nullability with the SQL extension; add a NULL-time row to the admin tests.
* **Test required:** `test_admin_pagination_performance.py` (already fails) + a regression assertion for `requested` consultations without a slot.
* **Status:** **Fixed in the working tree (not committed)** — see `F-001_FIX_REPORT.md`.

### F-002 — Suspended pharmacy owner cannot reach the appeal flow in the UI
* **Severity:** High · **Role:** Pharmacy owner (suspended) · **Feature:** suspension → appeal → restoration
* **Observed:** `smoke.pharmacy@featherflow.dev` logs in (API 200, restricted session, `next:"pending_approval"`), the app flashes **"Login Successful! Opening your dashboard…"** and then lands back on the login form with no message. (`susp_pharm_1500.png`, `pharmacy_suspended_dashboard.png`.)
* **Expected:** per `pharmacy/auth.py`, a suspended pharmacy keeps a restricted authenticated session so it can open the appeal screen / chat with Pharmacy Admin (covered by `test_pharmacy_admin.py`).
* **Repro:** log in as the suspended pharmacy in the browser; watch `#/login` reappear within ~1 s.
* **Root cause (probable — derived from the code path and the observed timeline: login 200 at +1.1 s, `/api/me/updates/` 200 at +1.2 s, `context.go('/pharmacy')` at ~2.5 s, back on `/login` at +2.6 s with the typed credentials still in the form and no snackbar):** `lib/core/network/user_updates_service.dart:153` — `if (data['access_revoked'] == true || _accountStatus == 'suspended') _setAccessRevoked(true)`; the router `_redirect` (`app_router.dart:267-273`) then clears the session and redirects to `/login?revoked=1`. Because the login page is already mounted, its `initState` snackbar ("Your access was changed by an administrator…") never fires, so the owner sees nothing. The generic "suspended ⇒ revoke" rule ignores the pharmacy exception the backend deliberately made. (Not separately instrumented in Dart.)
* **Impact:** workflow steps 17–19 of the pharmacy-owner plan (suspension → appeal/revision → restoration) cannot be completed by the owner in the UI; the backend path is only script-verified.
* **Security impact:** none (fails closed). **Fix:** exempt role `pharmacy` (or honour a server flag `appeal_allowed`) in the revoke rule; route to the locked panel.
* **Test required:** Flutter widget/integration test for suspended pharmacy login; Playwright test.
* **Status:** **Fixed in the working tree (not committed)** — see `F-002_FIX_REPORT.md`.

### F-003 — Rider route/ETA always fails (Google Directions)
* **Severity:** High · **Role:** Delivery rider (and Feed/Pharmacy admins viewing routes)
* **Observed:** `GET /api/delivery/orders/<id>/route/` → `404 {"detail":"No route found."}` (browser console 404 on the delivery screen; `crawl_delivery.json`). Direct call to Google with the project key returns `REQUEST_DENIED — You're calling a legacy API, which is not enabled for your project`.
* **Expected:** polyline/distance/duration, or an explicit "routing unavailable" 503.
* **Repro:** log in as `rider.arif@example.com` → Dashboard → open the active order's map/route; or curl the endpoint with the rider token.
* **Root cause:** `backend/delivery/views.py:256-286` uses the legacy `maps.googleapis.com/maps/api/directions/json`; the key in `backend/.env` has only newer APIs enabled. Any non-`OK` Google status is mapped to **404** (misleading), and a synchronous `urlopen(timeout=8)` blocks a worker thread.
* **Impact:** feed workflow step 9 ("Rider sees map/route") and pharmacy delivery tracking have no route line; location capture itself works.
* **Security impact:** the same key is hard-coded in `web/index.html` (see F-019). **Fix:** enable the API (or migrate to Routes API), return 502/503 for upstream errors, cache results, add timeouts/circuit breaker.
* **Test required:** contract test with mocked Google responses (OK / REQUEST_DENIED / timeout).
* **Status:** **Fixed in the working tree (not committed)** — see `F-003_FIX_REPORT.md` (migrated to the Google Routes API behind `delivery/routing.py`; provider failures now map to 422/502/503/504 with a `code`, never 404; Flutter route card with ETA / error / retry / address fallback; 29-assertion backend contract test + 17 Flutter tests; verified live in Chrome). The hard-coded browser key in `web/index.html` (F-019) is a separate, still-open item.

### F-004 — GET handlers fabricate demo pharmacy data for any account
* **Severity:** High (data integrity) · **Role:** every pharmacy account; also any admin that calls a pharmacy GET
* **Observed:** `/api/farmers/medicines/…` is clean, but `/api/pharmacy/marketplace/` lists **"Oxytetracycline 20%", "Newcastle Vaccine", "Vitamin AD3E Supplement"** sold by AgroCare, GreenVet **and "Owner Admin"** (the Super Admin account, created by this audit's read-only GET sweep). Pharmacy order lists contain fabricated orders `ORD-001..003` (farmers "Karim Hossain", "Jamal Mia", "Salma Akter"; `ORD-003` "delivered" ৳1,160) that exist for *every* pharmacy.
* **Expected:** GET endpoints are side-effect free; no fabricated records outside seed commands.
* **Repro:** `GET /api/pharmacy/dashboard/` as any pharmacy (or `admin.super@…`) with no prior records → 4 products + 3 orders + approved admin-medicine records appear.
* **Root cause:** `backend/pharmacy/views.py:177-215` — `_records()` calls `_seed(user)` on read; `_sync_admin_medicine(..., status='Approved')` pre-approves the fabricated medicines (bypasses Pharmacy Admin approval).
* **Impact:** fake approved medicines/orders in real accounts; reports/earnings can be polluted; a non-pharmacy admin appears as a pharmacy in the legacy marketplace.
* **Security impact:** approval bypass for the fabricated items. **Fix:** remove `_seed` from request paths (keep in seed commands), and delete existing fabricated rows.
* **Test required:** assert GET does not create `AdminPanelRecord` rows.
* **Status:** **Fixed in the working tree (not committed)** — see `F-004_FIX_REPORT.md` (`_seed()` removed from `pharmacy/views.py`; demo `SEEDS['pharmacies'|'medicines']` removed from `api/admin_views.py`; 32-assertion backend regression + 3 Flutter tests; verified on a clean DB and in Chrome). Previously fabricated rows were removed in `FEATHERFLOW_DATA_RESTORATION_REPORT.md`.

### F-005 — Missing delivery workflow steps: arrival, proof review, rejection, resubmission, approval
* **Severity:** High (missing feature) · **Role:** Feed Marketplace Admin, Delivery rider
* **Observed:** delivery state machine is `accepted → picked_up → on_the_way → delivered|failed` (`delivery/views.py:361-365`); there is **no "arrived" state**, and `grep -i proof` finds no admin/feed code at all — the admin can neither review, reject, request resubmission nor approve the proof photo; completion is final when the rider uploads a valid signed proof token. `SignaturePadScreen` exists in Flutter but no signature/OTP storage table exists for feed orders (OTP exists only for pharmacy deliveries).
* **Expected (from the audit scope):** rider marks arrival → mandatory proof photo → admin reviews → reject/resubmit → approve → final completion → financial record once.
* **Repro:** read `_TRANSITIONS`; no endpoint exists in `/api/admin-panel/feed-catalogue/*` (14 routes) for proof.
* **Impact:** feed workflow steps 10–15 cannot be executed. The "financial record appears once" step *is* implemented and script-verified (`test_feed_order_delivery.py`, `test_delivery_proof_and_earnings.py`).
* **Fix:** add `arrived` status, `proof_status` (pending/approved/rejected) with admin endpoints + notifications, and gate earnings on approval.
* **Status:** **Fixed in the working tree (not committed)** — see `F-005_FIX_REPORT.md` (`arrived` / `proof_submitted` / `proof_rejected` states, `delivery_proofs` + `delivery_order_events` tables, rider multipart proof endpoint, admin review queue with approve / reject-with-reason, completion + earning + expense only on approval; 75-assertion backend regression + 13 Flutter tests; verified end-to-end in Chrome).

## Medium

### F-006 — `pharmacist` orphan role
* **Observed:** `pharmacist.demo@example.com` → `/farmer` shell with *"A farmer account is required."* + Retry; 62 console 403s (`GET /api/farmers/dashboard/` 31×, etc.). **Root cause:** `AuthService.getRoleDestination` default branch returns the farmer dashboard (`auth_service.dart:320-327`); role has no profile model, permissions or route. **Fix:** retire the role or give it a shell/permissions; make unknown roles go to a "no panel" screen. **Status:** Open.

### F-007 — No role-based route guard
* **Observed (browser, `guard_results.json`):** a logged-in farmer who opens `#/admin`, `#/admin/users`, `#/admin/audit`, `#/pharmacy`, `#/doctor`, `#/delivery`, `#/research`, `#/feed-owner` sees those shells (admin chrome + "An active admin account is required"; pharmacy zeros; **doctor panel with demo numbers**; research panel "Unverified"). Pharmacy owner opening `#/doctor` sees the doctor panel; Support Agent opening `#/admin/finance|team|pharmacy` sees the shell with 403 toasts.
* **Root cause:** `_redirect` in `lib/core/router/app_router.dart:251-289` only tests authenticated/not. **Security impact:** none on data (every API call returns 403 — verified), but it leaks UI structure and enables confusing states. **Fix:** map path prefix → allowed roles in `_redirect`. **Status:** Open.

### F-008 — Doctor panel shows hard-coded demo data
* **Observed:** a **farmer** opening `#/doctor` sees "Good afternoon, Doctor · 4.7 Verified · 6 Total Clients · 3 Today's Appts · 2 Active Cases" with **no API error** (the real `/api/doctor/*` calls 403). **Root cause:** `lib/features/doctor/data/services/doctor_session.dart:15-19` initialises from `doctor_demo_data.dart` (`demoAppointments`, `demoCases`, `demoChatThreads`, `demoEarnings`, `demoRatings`) and never clears on failure. A real doctor whose API fails would see fake clients/earnings. **Fix:** start empty; show error/empty state. **Status:** Open.

### F-009 — Dashboard activity feed leaks login events across roles
* **Observed:** `GET /api/admin-panel/dashboard/` → `activity` = 12 `auth` events ("Login failed for dasd@gmail.com", "Login success for rider.pending.belal@example.com" …) for **Feed Admin, Pharmacy Admin, Content, Support, Finance** alike, while `/audit-logs/` is correctly scoped per role (Feed Admin: none). Visible in the UI "Recent Activity" card. **Root cause:** the dashboard query is not module-scoped. **Impact:** other users' emails and login times disclosed to module admins. **Fix:** apply the same module filter. **Status:** Open.

### F-010 — Unsanitised community content
* **Observed:** `POST /api/community/` with `content='<script>alert(1)</script><img src=x onerror=alert(2)>'` and `media_urls=['javascript:alert(1)','http://evil.example/x.png']` → 201; `GET /api/community/posts/<id>/` returns the raw script and both URLs. **Root cause:** `community/views.py:401-457` stores `content`, `title`, `media_urls`, `category` verbatim (any user also creates unlimited `PostCategory` rows via `category`). Flutter `Text` widgets don't execute HTML, so the current client is safe; any HTML consumer (admin web, e-mail digests, future web) is not. **Fix:** length/allow-list validation of URLs (https + own media host), escape/strip HTML server-side, restrict categories. **Status:** Open.

### F-011 — Test/demo data and suspended pharmacy visible in the farmer marketplace
* **Observed:** `GET /api/farmers/medicines/search/` (the endpoint the Flutter screen uses) returns 13 items including **"Playwright Photo Medicine" ×3, "Playwright Test Medicine", "Smoke Test Medicine/Vaccine", "Repro 500 Medicine"**; two items belong to **Smoke Pharmacy, a suspended account**. **Impact:** farmers can see/attempt to buy test products and a suspended seller's stock (purchase blocking not verified). **Fix:** purge test data; filter listings to active+approved pharmacies. **Status:** Open.

### F-012 — N+1 queries and unpaginated admin lists
* **Measured (Django `CaptureQueriesContext`):** `/api/admin-panel/pharmacy/orders/` **321 queries, 316 rows, 208 KB, no pagination** (new Pharmacy Admin code); `/api/admin-panel/pharmacy/audit/` 500 rows / 260 KB; `/api/community/follows/suggestions/` 124 queries; `/api/admin-panel/offline-admins/` 111; `/all-admins/` 98 queries for 31 rows; `/api/farmers/costs/dashboard/` 65; `/api/pharmacy/orders/` 39 for 36 rows. **Fix:** `select_related/prefetch_related`, pagination (`limit/offset`) and caps; add query-count assertions. **Status:** Open.

### F-013 — Poll storms
* **Observed (crawl counters):** Researcher panel = **615 API calls** in one session (5 endpoints × 99, `research_session.dart:50` polls every 6 s); Super Admin = 640 calls (`/admin-panel/profile/` ×135); farmer dashboard + notifications each re-fetched ~40–50×. **Fix:** use `/api/me/updates/` delta polling, back-off when hidden, ETag/If-Modified-Since. **Status:** Open.

### F-014 — Test infrastructure
* `python manage.py test` → "Found 31 tests" then `relation "users" does not exist` (90 of 108 models are `managed=False`; schema is raw SQL) — **0 Django tests can run** (`doctor/tests.py`, `pharmacy/tests.py`). All 43 `scripts/test_*.py` run against the **live** `featherflow` database (they self-clean but can mutate shared data and are order-dependent). **Fix:** a test settings module that loads `featherflow_schema.sql` + extensions into a throw-away DB. **Status:** Open.

### F-015 — Seed commands
* `seed_platform_demo` exits 1 on every run (`Farm.MultipleObjectsReturned`: farmers `e25fb388-…` and `324fbf2e-…` have 2 farms each); remaining seeds were idempotent from the 2nd run, but the **first** run changed 8 tables (e.g. `cashout_reviews 1→5`, `payments 7→15`, `revenue_entries 4→8`, `subscription_plans 5→9`, `subscriptions 5→9`, `users 103→107`) and **re-activated the previously suspended `research.sabiha@example.com`** (pre-seed login → 401 suspended; post-seed → active). **Fix:** de-duplicate farms + add a unique constraint; make seeds never overwrite status of existing rows. **Status:** `seed_platform_demo` part **fixed in the working tree (not committed)** — see `SEED_PLATFORM_DEMO_FIX_REPORT.md` (create-only seed, deterministic farm, `dedupe_farms`, `uq_farms_farmer_name`). The other seeds (e.g. the one that re-activated `research.sabiha`) were not part of that fix and remain open.

### F-016 — Disease detection extras not implemented
* `_AssistantSheet` is a static card (what-to-do / avoid / prevention) built from the scan result; there is **no chatbot API** (`/api/ml/*` has only `predict-disease`, scans, diseases, health), `chatbot_*` tables are empty (proxies of `AdminPanelRecord`), no follow-up questions, no report download, no feedback endpoint, single-image upload only. Free-limit throttle (`disease_predict` 30/h) and `_PaywallBanner` exist. **Status:** Open (feature gap vs audit scope).

### F-017 — Researcher workflow lacks automated tests
* No `scripts/test_*.py` references `/api/research/`. This audit ran an **ad-hoc HTTP workflow** (22 steps, 21 effective passes — draft → edit → submit → request revision → resubmit → version history → publish → farmer reads/searches/bookmarks); the only "fail" was the RBAC-correct 403 when *Research Admin* tried to archive (needs `articles.delete`, held only by Content Admin). **Fix:** add `test_research_flow.py`. **Status:** Open (test gap).

### F-018 — Pharmacy shell not route-addressable
* Clicking Catalogue/Inventory/Orders/Suppliers/Analytics/Profile never changes the URL (`#/pharmacy` throughout); routes `/pharmacy/catalogue|inventory|orders|suppliers|analytics|profile` are declared (`app_router.dart:680-715`) but unused by the tab bar. Back button, deep links and refresh always return to Home. **Status:** Open.

### F-019 — Configuration/secrets
* CORS: with `DJANGO_DEBUG=True` any origin is allowed with credentials (`OPTIONS` from `http://evil.example` → `Access-Control-Allow-Origin: http://evil.example`). Production path requires an allow-list (settings.py:240-256) — acceptable only if DEBUG is off. A Google Maps key is **hard-coded in `web/index.html`** (tracked) and another in `backend/.env`; the Directions key is also what F-003 fails on. **Fix:** restrict keys by referrer/API, inject at build time, never ship DEBUG. **Status:** Open.

### F-020 — Stale open admin shift
* `ops.nusrat@example.com` has been "on shift" since **2026-09-16T18:10Z** (≈14.7 days, `hours_this_week 88.94`, rate ৳450/h). No auto-close/flag (`auto_flagged:false`). Payroll integrity risk. **Fix:** auto-end after N hours / on missed heartbeat; super-admin `shifts/force-end` exists. **Status:** Open (pre-existing).

### F-021 — Video consultation depends on Jitsi, not recorded
* `consultations/views.py:706` returns a Jitsi room URL; `video_calls` (0 rows) is never written, so call start/end/duration are not auditable. Not exercised end-to-end (needs two real clients). **Status:** Unverified/Partial.

### F-022 — Data-model gaps vs scope
* No dedicated tables for mortality, vaccine history, biosecurity notes, refunds, receipts, delivery OTP/signature (feed), bonus/penalty, delivery status history, download counts, 2FA flow (see Data Dictionary coverage map). **Status:** Open.

### F-023 — Pharmacy/feed order tracking not verified in UI end-to-end
* Farmer "Orders" screens render, but no order was driven all the way through the browser (see Live Browser Verification §Not verified). Backend flows are script-verified. **Status:** Unverified.

### F-024 — Money screens have no live data
* `pharmacy_sales`, `pharmacy_commissions`, `pharmacy_settlements`, `pharmacy_appeals`, `pharmacy_employees` = 0 rows. Pharmacy Admin Overview shows `৳0.00` gross/commission; the 20/80 split, settlements, appeals and Request-Revision are verified only by `test_pharmacy_admin.py` (132 assertions), not by live UI data. **Status:** Unverified in UI.

## Low

* **F-025** `PATCH /api/admin-panel/research-papers/not-a-uuid/` → 500 (`admin_views.py:1611` catches `ValueError`, Django raises `ValidationError`). Return 404.
* **F-026** Login throttle 20/min/IP (`THROTTLE_AUTH_LOGIN`): the 21st request returned 429 **even with the correct password** (verified on :8001). No per-account lockout/back-off.
* **F-027** Feed Admin dashboard (`feed_admin`): "No overview data for your role. / No pending tasks" — no feed KPIs.
* **F-028** Unused/duplicate endpoints (no Flutter reference, parallel families): `/api/costs/*` (7), `/api/feed/*` (4), `/api/workers/*` (4), `/api/farmers/tax/payment/` vs `/payments/`, `/api/vets/nearby/` vs `/api/consultations/vets/nearby/`, `/api/doctor(s)/updates/`, `/api/pharmacy/<kind>/` legacy JSON bridge.
* **F-029** Pending demo applicants (`dr.pending.kabir`, `pharmacy.pending.agrocare`, `rider.pending.belal`, `research.pending.mahmud`) all have `users.account_status='active'`; pending-ness lives in profile/approval tables.
* **F-030** `notifications` 11,572 rows, `token_blacklist_outstandingtoken` 4,784, `activity_logs` 7,303 — no retention job.
* **F-031** `ORD-001..003` exist once **per pharmacy** (different `record_pk`); public order id is not globally unique.
* **F-032** `PharmacyEmployee` is a roster only (documented).
* **F-033** `flutter analyze`: 6 infos `prefer_const_constructors/literals` in `farmer_feed_marketplace_screen.dart:251-287`.
* **F-034** `needs_revision` articles notify the author as "Your content is now **hidden**".
* **F-035** `/api/farmers/pharmacies/` returns pharmacy `email`, `phone`, `license_number` to every farmer; `/api/consultations/vets/` returns doctor `latitude/longitude/address`; `/api/pharmacy/marketplace/` exposes `owner_id`/`pharmacy_user_id` to every authenticated role.
* **F-036** `delivery/views.py:554-555` assigns `proof_of_delivery_url` from the request body before validation; the `delivered` transition re-validates a signed token, other transitions store the string unchecked.
* **F-037** `users.two_factor_secret/enabled` exist; no setup/verify endpoint or screen.
* **F-039** Two concurrent identical `POST /api/farmers/costs/expenses/` calls both return 201 and create two rows (verified live, then deleted). Contrast: subscription checkout (`idempotency_key`) and feed-stock decrement (6 parallel over-stock orders → exactly 1 `201`, 5 `409`, no oversell, stock restored on cancel) are safe. Add an idempotency key or server-side de-dup window for expenses/revenue.
* **F-040** `consultations/views.py:648-658` serialises every message of a conversation on each fetch; no `limit`/`before` cursor.
* **F-038** Opening an admin route as a non-admin first paints the full admin sidebar ("Administrator / Support Agent") before showing "An active admin account is required."

---

## Audit-induced side effects (not product faults — disclosed for cleanup)

| # | What | Cause | State |
|---|---|---|---|
| S-1 | 8 admin demo accounts had a paid shift started (`finance.tanvir`, `content.admin`, `research.admin`, `delivery.admin`, `doctor.admin`, `pharmacy.admin@featherflow.local`, `support.raisa`, `team.admin`) | crawler clicked "Start Shift" | **ended via product API**; ~0.5–0.7 h of hours accrued per account |
| S-2 | Riders `rider.arif`, `rider.pending.belal` toggled Online | crawler clicked the Offline/Online toggle | **restored to offline** via product API |
| S-3 | **4 queued delivery orders cancelled** (ids `1590748f…`, `5e3dd2a1…`, `1b2c9453…`, `09463453…`, "Cancelled by admin.") and one `content-report` marked reviewed (`1b99d316…`) by the Super/Content Admin crawl | stale-coordinate click + generic "OK" dismiss | **not reversible via UI/API** — flagged for the owner |
| S-4 | Consultation `c31dd3fb…` changed `accepted → no_show` by the Doctor crawl | stale-coordinate click | not reverted |
| S-5 | `research.sabiha@example.com` re-activated by `seed_research_demo` | seed overwrites status | **not restored** (the permission layer blocked a direct DB write); run `UPDATE users SET account_status='suspended' WHERE email='research.sabiha@example.com'` or suspend in Admin → Researchers |
| S-6 | `Owner Admin` pharmacy seed rows (3 products + 3 orders + 3 approved admin-medicine records) created for `admin.super@example.com` by the GET sweep | F-004 | not removed |
| S-7 | Seed first-run row additions (users +4, payments +8, revenue_entries +4, cashout_reviews +4, subscriptions +4, plans +4, user_roles +4, pharmacy_suppliers +2) | seed commands | not removed |
| S-8 | Temporary expense (`AUDIT-UI-EXPENSE`, ৳1,234), community post (`AUDIT-XSS`) + category, research paper `AUDIT-E2E…` | audit workflows | **all deleted/archived** |
| S-9 | Many `activity_logs` login rows, notifications and JWT outstanding tokens | normal logins | not removed |

## Final disposition (2026-10-02, after the full eight-role matrix)

Legend - **Blocks**: *commit review* = must be resolved before the working tree is reviewed for commit; *production* = must be fixed before production release; *no* = scheduled work. "Owner" is a role, to be named by the project owner. Nothing here is "accepted" merely because it is medium/low: the decision column is explicit, and every *deferred* item still needs the owner's sign-off.

### Fixed in this repair cycle (verified)
F-001, F-002, F-003, F-004 (re-browsed: empty pharmacy stays empty), F-005 (proof lifecycle in two roles), F-006, F-007, F-008, F-009, F-010, F-011, F-012 (pharmacy admin orders only), F-014, F-015, F-020, F-023 (tracking verified in the farmer UI for pharmacy and feed orders), **F-024** (the Sales/Settlements screens were empty because proof-approved pharmacy deliveries wrote no sale/commission - fixed + backfill command + test), F-025, F-033, F-034, F-035, F-036 (verified: status updates ignore a client `proof_of_delivery_url`; test added), F-038, F-039, F-040. Partial: F-013 (polling), F-017 (no full researcher write-flow script, but the whole workflow ran in the matrix), F-019 (CORS fixed; Maps key repository side fixed, **rotation still required** - `MAPS_KEY_SECURITY_REPORT.md`), F-030 (commands exist, not scheduled).

### Still OPEN (not closed, not accepted)
* **F-029 pending applicants stored as `active`:** the code and seeds are right (new pending applicants are `pending`, sign-in returns 403), but the **legacy rows in the development database are still `active`** (e.g. `dr.pending.kabir`, `rider.pending.belal`, `research.pending.mahmud`, `pharmacy.pending.agrocare`). Stays open until a data correction is **run and verified** (suggested: set `account_status='pending'` for accounts whose profile/approval record is not approved, on a backed-up copy first, then confirm sign-in is refused and approval still works).
* **F-026, F-037 (admin roles), F-022 (while refunds/receipts are offered):** production-blocking, **not accepted**, not scheduled as accepted risk - see below.

### Deferred - with explicit decisions
| Fault | Severity | User impact | Security / data-integrity impact | Workaround | Owner | Target | Acceptance criteria | Blocks |
|---|---|---|---|---|---|---|---|---|
| F-016 disease chatbot extras | Medium | Farmers get a static assistant card, no chat/follow-up/report/feedback, one image | none | use the consultation flow with a vet | Product owner / ML lead | Next repair cycle | chat endpoint + tests, report download, multi-image upload, feedback saved | no |
| F-018 pharmacy shell not route-addressable | Medium | back button / deep links / refresh return to Home | none | use in-app tabs | Flutter lead | Next repair cycle | each tab has a URL, refresh keeps the tab, widget test | no |
| F-021 video calls via Jitsi, not recorded | Medium | works, but no call start/end/duration | auditability gap (no `video_calls` rows) - not authorization/financial | none needed | Backend lead | Next repair cycle, before video consultations are advertised | call lifecycle written, visible to admin | no (release note: calls are unaudited) |
| F-022 data-model gaps (mortality, vaccine history, refunds, receipts, OTP/signature, bonus/penalty) | Medium | refunds/receipts are kept in the JSON bridge, not first-class tables | **financial record integrity** (refunds/receipts) | handle refunds manually and record them in the admin audit trail | Backend lead + finance | Before production if refunds/receipts are offered; otherwise next cycle | first-class refund/receipt tables, migration of the JSON bridge records, tests | **production (conditional)** |
| F-026 login throttle 20/min per IP, no per-account lockout | Low | users behind one shared IP can be locked out of sign-in | brute force protection is coarse | raise `THROTTLE_AUTH_LOGIN` | Backend lead | **Before production** | throttle keyed by IP+account with a higher IP ceiling, lockout/back-off per account, tests | **production** |
| F-027 Feed Admin dashboard has no KPIs | Low | empty overview | none | use Orders & Delivery / Products tabs | Feed owner lead | Next repair cycle | KPI cards backed by live data | no |
| F-028 unused duplicate endpoint families | Low | none | extra surface (verified: all return 401 without a token) | none | Backend lead | Next repair cycle | unused families removed or documented, route audit | no |
| F-031 pharmacy order ids `ORD-001..003` unique only per pharmacy | Low | none for new orders (ids are random) | legacy/seeded rows only | none | Backend lead | Next repair cycle | unique index on (module, order id), seed ids made unique | no |
| F-032 pharmacy employees have no login | Low | roster only (documented design) | none (no privacy/permission exposure) | none | Product owner | Backlog | decision recorded: roster-only or logins with RBAC | no |
| F-037 two-factor authentication columns without a flow | Low | none | admin accounts have password-only sign-in | strong passwords, throttle | Security lead | **Before production for admin roles** | TOTP setup/verify flow for admin roles, tests | production (recommended) |

### Release decisions (owner sign-off column)
| Fault | Release decision | Sign-off |
|---|---|---|
| F-026, F-037 (admin), F-022 (if refunds/receipts offered) | **Production blocker - NOT accepted** | not applicable |
| F-029 | **Open** until the legacy-row data fix is completed and verified | not applicable |
| F-016, F-018, F-021, F-027, F-028, F-031, F-032 | Non-blocking; **scheduled work** (owner, target, workaround and acceptance criteria are in the table above) | **pending the project owner's explicit sign-off** |

### Release-blocking items outstanding
1. **Revoke/rotate the Google key and issue three restricted keys** (owner action in the Google Cloud Console; the old key must be deleted or disabled and shown to fail with a foreign Referer).
2. **F-026** and **F-037** (admin) before production; **F-022** while refunds/receipts are offered.
3. **F-029** legacy-row data correction run and verified.
4. Owner sign-off on the non-blocking scheduled items.
