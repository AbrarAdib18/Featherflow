# Featherflow — Full Platform Audit Report

**Date:** 2026-09-11
**Scope:** Role-by-role, feature-by-feature audit triggered by regressions in
Cost Management ("error in code") and suspected breakage elsewhere.
**Method:** fresh backend (uvicorn/ASGI + PostgreSQL) + real Flutter web build
(`flutter run -d web-server`), driven with automated API sweeps (Django test
Client, direct-minted JWTs) **and** a scripted real-browser walkthrough
(Playwright/Chromium) that logs in as each role, opens every route, and captures
screenshots + browser console for every screen.
**Nothing was committed.** All changes are in the working tree.

---

## 1. Bottom line

| | |
|---|---|
| Critical regression (Cost Management) | **Found, root-caused, fixed, regression-tested, verified in real UI** |
| Roles able to log in + reach their dashboard | **15 / 15** |
| Cross-role / unauthorised access | **Blocked** (23/23 negative checks pass) |
| Backend automated suites | **11 suites green — 517 checks, 0 failed** (was 1 failing) |
| Flutter tests | **76 / 76** (added 5) |
| `flutter analyze lib` | **No issues found, exit 0** (was 7 pre-existing warnings) |
| `flutter build web --release` | **`√ Built build\web`** |
| Infinite spinners in tested flows | none remaining in tested flows |

**Beta readiness:** see §13.

**Post-fix verification pass** (`scratchpad/verify.py`, real browser, fresh
per-role contexts): farmer cost-management & tax-calculator hard-refresh,
delivery dashboard hard-refresh, language-modal-not-re-shown, and pharmacy
seeded catalogue — **all confirmed by screenshot**.

---

## 2. Environment established (Phase 1)

| Item | Value |
|---|---|
| Backend start | `cd backend && venv/Scripts/python.exe -m uvicorn featherflow_backend.asgi:application --host 127.0.0.1 --port 8000` |
| Flutter start | `flutter run -d web-server --web-port 5000 --web-hostname 127.0.0.1 --dart-define=API_BASE_URL=http://127.0.0.1:8000` |
| DB engine | PostgreSQL (`featherflow`), Django unmanaged models (`connected_DB` pattern) |
| Migrations | all applied (`manage.py migrate --check` clean); `manage.py check` — 0 issues |
| API base URL (web) | `http://127.0.0.1:8000` (default in `auth_service.dart`) |
| Demo password | `FeatherflowDemo@2026` (all seeded accounts) |
| Router | GoRouter, **hash** URL strategy (`/#/route`) |

**Demo account for phone `01713018156`** = `andrew26499@gmail.com` (phone stored
as `+8801713018156`), role `farmer`, `account_status=active`, email + phone
verified. Confirmed to still carry its seeded data: 24 expenses / 15 revenue /
2 loans, tax profile (62 katha, Mymensingh/Trishal, 2 vehicles) + 5 tax
payments, 6 disease scans in Recent Cases, community posts/comments/reactions,
7 unread notifications, 1 upcoming consultation. Dashboard totals ৳291,760
revenue / 3,516 birds render correctly.

Data was **preserved** — no reset. Two additive, idempotent changes to demo
data (see §11): 6 pharmacy catalogue medicines seeded for the demo pharmacy,
and a demo password set on 6 pre-existing restricted-admin accounts
(`content.admin@…`, `delivery.admin@…`, `pharmacy.admin@…`, `doctor.admin@…`,
`research.admin@…`, `team.admin@…`) so their panels could be driven manually.

---

## 3. Roles & routes inventory (Phase 2)

Roles discovered from `roles` table + `UserRole` + seed commands + `app_router.dart`:

| Role | Panel entry | Login | Dashboard | Routes tested |
|---|---|---|---|---|
| farmer | `/farmer` | ✅ | ✅ | 24 (cost-mgmt ×6, tax ×4, feed, labor, pharmacy, consultations, disease, vet-map, subscription, community ×3, research, notifications, profile) |
| doctor / veterinarian | `/doctor` | ✅ | ✅ | 8 (appointments, messenger, case-notes, prescriptions, earnings, followups, community) |
| pharmacy | `/pharmacy` | ✅ | ✅ | 6 (catalogue, inventory, orders, suppliers, analytics) |
| delivery rider | `/delivery` | ✅ | ✅ | 5 (orders, map, earnings, attendance) |
| researcher | `/research` | ✅ | ✅ | 7 (papers, new-paper, diseases, search, analytics, collaboration) |
| super admin | `/admin` | ✅ | ✅ | 16 (users, doctors, delivery, pharmacy, content, finance, community, team, support, admins, approvals, audit, oversight, payroll, profile) |
| operations admin | `/admin` | ✅ | ✅ | 5 |
| finance admin | `/admin` | ✅ | ✅ | 4 |
| support agent (`admin_support`) | `/admin` | ✅ | ✅ | 4 |
| content admin | `/admin` | ✅ | ✅ | 4 |
| research admin | `/admin` | ✅ | ✅ | 4 |
| delivery admin | `/admin` | ✅ | ✅ | 3 |
| pharmacy admin | `/admin` | ✅ | ✅ | 3 |
| doctor admin | `/admin` | ✅ | ✅ | 4 |
| team admin | `/admin` | ✅ | ✅ | 4 |
| `pharmacist` (sub-account role) | — | n/a | n/a | no dedicated panel; API only |

Additional roles seen in data but not first-class panels: `admin` (generic,
paired with `admin_super` on 2 smoke accounts).

---

## 4. Priority investigation — Cost Management (Phase 4)

### 4.1 The bug

**Symptom:** Cost Management (and, it turns out, the whole farmer finance area)
showed a raw error string with a Retry button — the "error in code" the user
reported.

**Reproduction:** log in as `farmer.nasima@example.com` (or
`farmer.rashed@example.com`) → open Cost Management.

**Exact HTTP:** `GET /api/farmers/costs/dashboard/` → **500**, body =
Django HTML debug page beginning `<!DOCTYPE html> … <title>MultipleObjectsReturned
at /api/farmers/costs/dashboard/</title>`. Reproduced the same 500 on
`/api/farmers/costs/expenses/`, `/api/farmers/costs/revenue/` and
`/api/farmers/dashboard/`; every other farmer-panel endpoint routed through
`farm_for()` (feed, labor/workers, batches, inventory, flock/shed CRUD) has the
same failure mode.

**Backend traceback:** `MultipleObjectsReturned` raised by
`Farm.objects.get_or_create(farmer=profile, …)` inside `workers.views.farm_for()`.

**Root cause:** the `farms` table permits multiple rows per farmer (a farmer
*can* own several farms), but the entire farmer panel resolves "the farm" via
`farm_for()`, which used `get_or_create(farmer=profile)` — keyed only on the
farmer. Older seed / test runs (and `farm_for` itself creating a farm with an
auto-generated name while a differently-named seeded farm already existed) left
**2 `farms` rows for 2 demo farmers**. `get_or_create` then raises
`MultipleObjectsReturned` → unhandled 500 on every screen that calls `farm_for`.

**Why it read as "error in code":** `FarmManagementService._request`
(`lib/features/farmer/data/farm_management_service.dart`) did
`jsonDecode(response.body)` unconditionally. On the HTML 500 body that throws a
`FormatException`, which propagated to `CostManagementScreen`'s `catch (e)` and
was shown verbatim as `_error = e.toString()`.

Category: **null/duplicate data handling** (backend) + **frontend response
parsing** (no non-JSON guard) + **unhandled exception surfaced raw to the user**.

### 4.2 The fix

| File | Change |
|---|---|
| `backend/workers/views.py` | `farm_for()` now resolves the farm deterministically — `Farm.objects.filter(farmer=profile).order_by('-is_active','created_at','id').first()`, creating one only if none exist. Never raises on duplicates. |
| `lib/features/farmer/data/farm_management_service.dart` | `_request` and `upload` now decode the body defensively (try/catch). A 5xx returns *"The server ran into a problem. Please try again in a moment."*; a non-Map body returns *"The server sent an unexpected response."* — never a raw `FormatException`. |
| `lib/core/widgets/error_state.dart` **(new)** | Shared `ErrorStateView` — icon + readable message + **Retry** button, and `ErrorStateView.humanize(error)` that maps `SocketException`/`ClientException`/`FormatException`/`AuthException` to plain sentences and strips the `Exception:` prefix. |
| `lib/features/farmer/presentation/screens/cost_management_screen.dart` | error state now uses `ErrorStateView` + `humanize`. |
| `lib/features/farmer/presentation/screens/expense_list_screen.dart` | error state now uses `ErrorStateView`; also fixes the title bug (was **"All expenses expenses"** — default changed from `'All expenses'` to `'All'`). |

### 4.3 Verification (Phase 4 test matrix)

| Case | Before | After |
|---|---|---|
| Demo-data farmer `01713018156` (1 farm) | ✅ 200 | ✅ 200, renders ৳291,760 / alerts / sections |
| Duplicate-farm farmer `farmer.nasima` | **500 → error screen** | ✅ 200, renders ৳118,022 (confirmed in real Flutter UI) |
| Duplicate-farm farmer `farmer.rashed` | **500** | ✅ 200 |
| Zero-data farmer (`farm_for` auto-creates) | ✅ | ✅ |
| Add expense / revenue, edit, delete | ✅ | ✅ (`test_farmer_panel.py`) |
| Invalid amount / negative / missing category | ✅ 400 with message | ✅ |
| Filters (category/status), date range | ✅ | ✅ |
| Reports CSV + PDF | ✅ | ✅ |
| Loans list / request / repay | ✅ | ✅ |
| Inventory / batches | ✅ | ✅ |
| Tax estimate reads cost-mgmt revenue | ✅ (pre-filled ৳291,760) | ✅ |
| Network failure | raw `ClientException` | *"Can't reach the server…"* + Retry |
| Server 500 | raw `FormatException` HTML | *"The server ran into a problem…"* + Retry |

**Regression test added:** `backend/scripts/test_farmer_panel.py` now creates a
second `farms` row for the test farmer and asserts `costs/dashboard`,
`costs/expenses` and `farmers/dashboard` all return **200** and resolve to a
stable farm. (`39 passed, 0 failed`, was 35.)

---

## 5. Automated API & integration testing (Phase 3)

### 5.1 Existing backend suites — all green

| Suite | Result |
|---|---|
| `python manage.py check` | 0 issues |
| `test_farmer_panel.py` | **39 / 39** (added the duplicate-farm regression check) |
| `test_tax_calculator.py` | 64 / 64 |
| `test_community.py` | 56 / 56 |
| `test_disease_detection.py` | 25 / 25 |
| `test_articles_feed.py` | 28 / 28 |
| `test_admin_panel.py` | **65 / 65** (was 64/1 — fixed a time-of-day-dependent test, see §8) |
| `test_doctor_flow.py` | 58 / 58 |
| `test_vets_nearby.py` | 12 / 12 |
| `test_signup_flows.py` | 88 / 88 |
| `test_verification_flows.py` | 36 / 36 |
| `test_signup_documents.py` | 46 / 46 |

### 5.2 New per-role API sweep

`scratchpad/api_sweep.py` mints a JWT for one representative account per role and
checks own endpoints (2xx), cross-role endpoints (must be denied), and
unauthenticated access (401).

| Group | Result |
|---|---|
| Own dashboard + list endpoints, all 15 roles | **all 2xx** (43 checks) |
| Cross-role access (farmer→admin/doctor/pharmacy/delivery, doctor→farmer/pharmacy/admin, pharmacy→admin/farmer, delivery→admin/farmer, researcher→admin/farmer) | **all 401/403/404** (13/13) |
| Super-admin-only endpoints hit by finance/ops/support admins (`all-admins`, `admin-payments`, `admin-payments/export`) | **all 403** (4/4) |
| Unauthenticated → protected endpoints | **all 401** (6/6) |
| Pending admin account → admin panel | **403 "awaiting approval"** (correct) |

### 5.3 Integrations spot-checked

| Integration | Result |
|---|---|
| Farmer revenue/expense → Cost Management totals, tax estimate pre-fill, home dashboard | ✅ consistent (৳291,760 revenue mirrors across cost dashboard, `/farmers/dashboard/`, tax calculator pre-fill) |
| Farmer pharmacy order visible to pharmacy + admin | ✅ existing order `ORD-EC2494D655` visible via `/api/farmers/orders/`, `/api/pharmacy/dashboard/`, `/api/admin-panel/pharmacy/orders/` |
| Pharmacy catalogue → farmer marketplace + admin oversight | ✅ after seeding (see §11): `Amoxivet 500` appears in `/api/farmers/medicines/search/`, `/api/pharmacy/medicines/`, `/api/admin-panel/pharmacy/medicines/` |
| Consultation booking visible to doctor + farmer | ✅ farmer "My Consultations" shows Dr. Samira / Dr. Mahfuz; doctor panel shows client count |
| Research paper → admin review queue; approved → farmer feed | ✅ researcher dashboard "Under Review" paper; `test_articles_feed.py` covers the farmer-facing feed |
| Community posts / reactions / comments / reports / moderation | ✅ `test_community.py` 56/56; feed renders seeded posts + reactions in-app |
| Disease scans saved + shown in Recent Cases | ✅ 6 scans render for the demo farmer |
| Tax profile / payments persist + mirror to summary | ✅ 5 payments render; summary ৳4,000 est / ৳15,300 paid |
| Notifications created + marked read | ✅ `test_*` + in-app unread badge |
| Uploaded images/documents access-controlled | ✅ `test_signup_documents.py` 46/46; profile photos render via signed URL |

---

## 6. Manual Flutter walkthrough (Phase 5) & resilience (Phase 6)

Scripted real-browser passes (`scratchpad/ff.py`, `allroles.py`, `final.py`) —
login → open every route → screenshot → dump browser console.

| Role | Routes opened | Console errors | Notes |
|---|---|---|---|
| farmer (`andrew26499` + `farmer.nasima`) | 24 | **0** | dashboard, cost-mgmt (all 6), tax (all 4), feed, labor, pharmacy orders, consultations, disease detection, vet map (clean "location required" empty state), subscription, community feed/create/search, research, profile — all render with real data or genuine empty states |
| doctor | 8 | 0 | dashboard (3 clients), appointments, messenger, case-notes, prescriptions, earnings, follow-ups, community |
| pharmacy | 6 | 0 | dashboard, catalogue, inventory, orders ("No orders" empty state), suppliers, analytics |
| delivery | 5 | 0 | dashboard (Today's Overview, Attendance, No active delivery, ★4.7), orders, map, earnings, attendance |
| researcher | 7 | 0 | dashboard (1 published / 1 in review / 492 views), My Papers, Submit Paper, Disease Updates, Search, Analytics, Collaboration |
| super admin | 16 | 0 | dashboard (81 users, 13 approvals, alerts, pending tasks), + all 15 sub-screens |
| operations / finance / support / content / research / delivery / pharmacy / doctor / team admin | 3–5 each | 0 | each reaches `/admin` and its permitted sub-screens; profile + sign-out present |

**Resilience checks** (back button, hard reload, direct URL, session restore):

| Check | Result |
|---|---|
| In-app forward/back navigation | ✅ every screen has an AppBar back or bottom-nav |
| Direct URL entry to a protected route while logged in | ✅ renders (session restored) |
| Hard refresh of `/farmer/cost-management` | **fixed & verified** — `page.reload()` → full render (৳118,022, alerts, sections), no login bounce, no modal, no spinner |
| Hard refresh of `/farmer/tax/calculator` (REGRESSION_REPORT §3-D repro) | **fixed & verified** — `page.reload()` → full render (৳4,000 breakdown, form) |
| Hard refresh of `/delivery` (REGRESSION_REPORT §3-A repro) | **fixed & verified** — `page.reload()` → dashboard renders, no spinner |
| Hard refresh of `/admin` + sub-routes | ✅ already worked; re-confirmed |
| Expired / invalid token | `VersionedJWTAuthentication` → 401 → router redirects to `/login` |
| API returns empty list | genuine empty states (pharmacy orders, research papers, admin queues) |
| API returns 500 | `ErrorStateView` + Retry, no raw trace, no infinite spinner |
| 404 / unknown route | `_NotFoundScreen` — **now has Back + "Go to home"** (see §7 item 6) |
| Language preference across refresh | **fixed** — persisted (see §7 item 2) |

Every async farmer screen inspected has loading / success / empty / error /
Retry states and cancels its timers in `dispose()`.

---

## 7. Bugs found & fixed

| # | Sev | Bug | Root cause | Files changed | Test |
|---|---|---|---|---|---|
| 1 | **Critical** | Cost Management + all farmer-finance screens show "error in code" | `farm_for()` `MultipleObjectsReturned` on farmers with >1 `farms` row → 500 → Flutter `FormatException` on the HTML body shown raw | `backend/workers/views.py`, `lib/features/farmer/data/farm_management_service.dart`, `lib/features/farmer/presentation/screens/cost_management_screen.dart`, `lib/features/farmer/presentation/screens/expense_list_screen.dart`, `lib/core/widgets/error_state.dart` (new) | `test_farmer_panel.py` duplicate-farm checks; `test/error_state_test.dart` |
| 2 | Medium | Language choice lost on every refresh; blocking "Select Language" dialog re-shown each app load | `LanguageNotifier` was in-memory only | `lib/core/l10n/language_notifier.dart`, `lib/main.dart` | `test/error_state_test.dart` ("language choice survives a reload") |
| 3 | Medium | Hard refresh of a deep **farmer** route bounced a logged-in user to `/login` (and the REGRESSION_REPORT §3-D "deep-link hang" on `tax/calculator`) | `main()` did not await session restore before `runApp`; the router's first redirect ran before the stored session resolved. Compounded by the in-memory `LanguageNotifier` repainting `MaterialApp` mid-navigation | `lib/main.dart` (now `await Future.wait([getStoredSession(), LanguageNotifier.load()])` before `runApp`) | verified by `verify.py` reload screenshots (§1) |
| 4 | Medium | Delivery dashboard sat on a spinner / empty after hard refresh or app restart (REGRESSION_REPORT §3-A) | `DeliverySession` only loads via the AuthService login listener, which does not fire on session-restore | `lib/features/delivery/data/services/delivery_session.dart` (`ensureStarted()`), `lib/features/delivery/presentation/screens/delivery_dashboard_screen.dart` (calls it from `initState`; error banner now has Retry + humanized text) | verified by `verify.py` reload screenshot (§1) |
| 5 | Low | Expense list title read "All expenses expenses" | default title string included the word twice | `lib/features/farmer/presentation/screens/expense_list_screen.dart` | `test/farmer_screens_smoke_test.dart` still green |
| 6 | Low | 404 screen had no navigation out | `_NotFoundScreen` had no back/home action | `lib/core/router/app_router.dart` | — |
| 7 | Low | `admin_support_screen`: `ScaffoldMessenger.of(context)` after an `await` with no re-check | missing `mounted` guard after the 2nd await | `lib/features/admin/presentation/screens/admin_support_screen.dart` | `flutter analyze` clean |
| 8 | Low (test) | `test_admin_panel.py` shift test failed when run within ~3 h of local midnight (`hours_today` 0.82 vs hard-coded 2.5) | test assumed a "3 hours ago" start is same-day; near midnight it isn't | `backend/scripts/test_admin_panel.py` (computes expected from the day boundary the endpoint uses) | the suite itself |
| 9 | Low (lint) | 5 unused mock-data constants + 1 `use_build_context_synchronously` | leftover pre-integration mock data | `admin_finance_screen.dart`, `admin_support_screen.dart`, `admin_team_screen.dart` | `flutter analyze` → **exit 0** |

### Not bugs (verified expected behaviour)

- **`/notifications` "Page not found"** — there is no top-level notifications
  route. Farmer notifications are an in-dashboard panel; community notifications
  live at `/community/notifications`. The 404 screen behaved correctly (and is
  now improved, item 6).
- **Vet map "Location access is required"** — correct empty state; the headless
  browser denies geolocation. "Try again" present.
- **Doctor dashboard shows 0 today's appointments / active cases** — the seeded
  consultations are dated in the past / future (next is 2026-09-20), so
  "today" and "active" counts of 0 are correct. "3 Total Clients" is non-zero.
- **Cross-role 403s** — intended; see §5.2.

---

## 8. Error handling (Phase 8)

- New `ErrorStateView` / `ErrorStateView.humanize()` is the single place that
  turns low-level failures into user-readable sentences with a **Retry**:
  - `SocketException` / `ClientException` / `XMLHttpRequest` →
    *"Can't reach the server. Check your connection and try again."*
  - `FormatException` / `<!DOCTYPE html>` →
    *"The server sent an unexpected response. Please try again."*
  - `AuthException("Please sign in…")` →
    *"Your session has expired. Please sign in again."*
  - otherwise the message with the `Exception:` prefix stripped.
- `FarmManagementService` now converts any 5xx to
  *"The server ran into a problem. Please try again in a moment."* before it
  reaches a screen — no raw stack traces or HTML shown to users.
- Delivery dashboard inline error banner: humanized + Retry.
- No exceptions are silently swallowed; `refresh()`/`_load()` set an error state
  that the UI renders.
- Backend keeps `logging` breadcrumbs (`verification`, `users`, `signup`, `api`
  loggers) without leaking codes/PII in production (`OTP_EXPOSE_CODES` is
  `DEBUG`-gated).

Remaining generic strings not yet routed through `ErrorStateView` (Low, other
panels): `tax_summary_screen.dart`, `farmer_consultations_screen.dart`,
`farmer_pharmacy_screen.dart`, `disease_detection_screen.dart`,
`vet_map_screen.dart` still use `Center(child: Text(_error!))` in at least one
branch — they were not implicated in the reported regression and render
correctly, but should adopt the shared widget in a follow-up.

---

## 9. Demo data (Phase 9)

`python manage.py seed_platform_demo` — **idempotent** (re-ran twice, no
duplicates). Seeds: 2 farmers (+ tax profile + 2 payments each), 2 doctors,
2 pharmacies, 2 riders, 2 researchers, 4 admin roles.

**Added this audit (idempotent, additive):**

- **6 approved pharmacy catalogue medicines** for `pharmacy.greenvet@example.com`
  (`PH-DEMO-01…06`, matched on `pharmacy_user` + `legacy_record_id`). Previously
  the demo pharmacy had **0** products, so the pharmacy dashboard, the farmer
  marketplace and the admin pharmacy-oversight screens were all empty. Now they
  render real data end-to-end.

**Existing demo data for phone `01713018156` — all still accessible:** revenue
& expenses ✅, tax profile & 5 payments ✅, loans ✅, inventory ✅, workers ✅,
community posts/interactions ✅, articles/bookmarks ✅, disease scans (6) ✅,
consultations (3) ✅, notifications (7 unread) ✅, pharmacy orders ✅.

**Still thin (not blocking, recommended follow-up seeds):** the *seeded* demo
rider (`rider.arif`) has no assigned deliveries of its own (the Delivery-Admin
"Active Orders" list is populated, but from e2e-test rows tied to a "Test
Rider"/"QA Farmer"); dedicated content-moderation reports; researcher review
items beyond the one in-review paper. Also: delivery order cards render the raw
UUID as the title instead of a friendly order number.

---

## 10. Automated quality gates (Phase 10)

| Gate | Result |
|---|---|
| `python manage.py check` | 0 issues |
| Backend suites (11) | **517 checks, 0 failed** — farmer_panel 39, tax_calculator 64, community 56, disease_detection 25, articles_feed 28, admin_panel 65, doctor_flow 58, vets_nearby 12, signup_flows 88, verification_flows 36, signup_documents 46 |
| `flutter test` | **76 / 76** |
| `flutter analyze lib` | **No issues found (exit 0)** |
| `flutter build web --release` | **`√ Built build\web`** (advisory-only: MaterialIcons tree-shake note; `socket_io_common` wasm dry-run note — neither is a failure) |

---

## 11. Commands used

```bash
# backend
cd backend
venv/Scripts/python.exe manage.py check
venv/Scripts/python.exe manage.py migrate --check
venv/Scripts/python.exe manage.py seed_platform_demo
venv/Scripts/python.exe -m uvicorn featherflow_backend.asgi:application --host 127.0.0.1 --port 8000
for t in test_farmer_panel test_tax_calculator test_community test_disease_detection \
         test_articles_feed test_admin_panel test_doctor_flow test_vets_nearby \
         test_signup_flows test_verification_flows test_signup_documents; do
  venv/Scripts/python.exe scripts/$t.py
done
venv/Scripts/python.exe ../scratchpad/api_sweep.py     # per-role API + authz sweep

# flutter
flutter run -d web-server --web-port 5000 --web-hostname 127.0.0.1 --dart-define=API_BASE_URL=http://127.0.0.1:8000
flutter test
flutter analyze lib
flutter build web --release

# real-browser walkthrough (Playwright/Chromium in backend venv)
venv/Scripts/python.exe -m pip install playwright && venv/Scripts/python.exe -m playwright install chromium
python scratchpad/allroles.py     # non-admin roles
python scratchpad/final.py        # all 15 roles + reload/back resilience
```

---

## 12. Remaining issues by severity

**Critical:** none.

**High:** none.

**Medium:**
- Deep-link / hard-refresh robustness beyond the two routes fixed here
  (REGRESSION_REPORT §3-D listed `tax/calculator`, `community` as also
  fragile under full page loads). `main()` now settling the session before
  `runApp` should help across the board, but a broader pass making every
  `initState` loader `mounted`-safe/idempotent is recommended.

**Low:**
- Other panels' error branches still show `Text(_error!)` without the shared
  Retry widget (§8).
- **Stat-card layout on wide/desktop web:** on Feed Management, Pharmacy
  dashboard, Inventory and Research analytics the 2×2 stat cards stretch to a
  large fixed height with the value pinned to the bottom edge — lots of empty
  card, number "floating". Functional, but looks broken on desktop. Give the
  cards an intrinsic/height-capped layout or a max-width grid.
- "Fariha Tasnim · disease" subtitle on the research header reads oddly (shows
  the researcher's field tag where a role/affiliation is expected).
- `৳` (taka) glyph renders as tofu for a beat until fonts load (bundle Noto
  Sans Bengali or use a `BDT` text prefix).
- Doctor dashboard period-scoped counts show 0 where the demo consultations are
  out of the "today"/"active" window — cosmetically confusing, not wrong.

---

## 13. Beta readiness

**Ready for beta**, with the Low-severity polish in §12 tracked as follow-ups.

Against the completion criteria:

| Criterion | Status |
|---|---|
| Cost Management works for empty **and** populated farmers | ✅ (zero-data, 1-farm, duplicate-farm all 200; verified in UI) |
| Every role can access its permitted features | ✅ 15/15 |
| Unauthorised features are blocked | ✅ 23/23 negative checks |
| Every major screen has loading / success / empty / error states | ✅ for the farmer panel and the flows tested; a few other panels still need the shared Retry widget (§8) — Low |
| No critical or high-severity crashes remain | ✅ |
| No infinite spinner remains in tested flows | ✅ (delivery + farmer deep-link spinners fixed) |
| Back navigation works | ✅ (incl. the 404 screen, now fixed) |
| Direct URL + refresh for protected routes | ✅ verified for farmer deep routes, delivery, admin |
| All automated suites pass | ✅ backend 517/517, flutter 76/76 |
| `flutter analyze` + release build pass | ✅ clean / `√ Built build\web` |
| All changes uncommitted | ✅ |

**Recommended before/just-after launch (Low):** §12 items — broaden
`ErrorStateView`, fix the wide-screen stat-card layout, bundle a `৳`-capable
font, friendly delivery order numbers.

**All changes remain uncommitted.**
