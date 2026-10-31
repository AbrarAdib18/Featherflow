# FEATHERFLOW — Performance & Reliability Report

Evidence: Django `CaptureQueriesContext` over 149 role-appropriate GET endpoints (authenticated test client against the live DB), live HTTP sweep timings (2,869 requests, 28 s total with 8 threads), browser network captures (24 roles, ~5,100 API calls), the 43 script suites, and code reading. All numbers are from a **single-developer dev DB** (e.g. 316 pharmacy orders, 7.5k audit rows) — they show *query shape*, not production latency.

## 1. Query-count / payload hot spots

| Endpoint | Role | Queries | Rows | Bytes | Paginated | Verdict |
|---|---|---:|---:|---:|---|---|
| `/api/admin-panel/pharmacy/orders/` | Ops/Pharmacy Admin | **321** | 316 | 208,398 | no | **N+1** (≈1 query/row), 346 ms (F-012) |
| `/api/community/follows/suggestions/` | any | **124** | – | 2,779 | no | N+1 |
| `/api/admin-panel/offline-admins/` | Super | **111** | 25 | 15,263 | no | N+1 |
| `/api/admin-panel/all-admins/` | Super | **98** | 31 | 19,384 | no | N+1 |
| `/api/farmers/costs/dashboard/` | Farmer | 65 | – | 7,597 | n/a | heavy aggregation |
| `/api/admin-panel/online-admins/` | Super | 54 | 6 | 4,029 | no | N+1 |
| `/api/pharmacy/orders/` | Pharmacy | 39 | 36 | 25,709 | no | N+1 |
| `/api/delivery/orders/` | Rider | 35 | 15 | 10,751 | yes | N+1 |
| `/api/farmers/labor/workers/` (and duplicate `/api/workers/`) | Farmer | 34 | 14 | 2,360 | no | N+1 |
| `/api/admin-panel/pharmacy/audit/` | Ops | 33 | **500** | **260,650** | no | hard cap of 500, no paging |
| `/api/consultations/` | Farmer | 31 | – | 5,922 | no | |
| `/api/farmers/dashboard/` | Farmer | 28 | – | 2,779 | n/a | polled (see §3) |
| `/api/pharmacy/dashboard/` | Pharmacy | 12 | – | **44,081** | n/a | large payload for a dashboard |
| `/api/community/*` feeds | any | 13–22 | 28 | ~28.6 KB | no | whole feed returned |

Slowest single calls (test client, warm): pharmacy orders 346 ms, all-admins 84 ms, offline-admins 59 ms; nothing above 350 ms and no endpoint above 1.5 s in the HTTP sweep. The tests `test_admin_pagination_performance.py` / `test_admin_row_builder_performance.py` / `test_community_feed_performance.py` exist; the first crashes (F-001), the others pass (35 + 20 assertions).

**Unbounded reads:** consultation chat history returns *every* message (`consultations/views.py:648-658`, no limit); community feeds, pharmacy orders, admin pharmacy orders, notifications list (11.5k rows in table) have no page size. **Missing indexes:** not exhaustively audited; `production_hardening_extension.sql` adds appointment/consult indexes; `activity_logs` (7.3k) and `notifications` (11.5k) rely on per-user filters.

## 2. Browser-observed errors (24 role sessions)

| Item | Count | Detail |
|---|---:|---|
| HTTP 5xx | **65** | all `GET /api/admin-panel/consultations/` (Super 22, Support 15, Doctor Admin 14, Ops 14) → F-001 |
| HTTP 4xx | 63 | 62 × 403 for the legacy `pharmacist` in the farmer shell (F-006); 1 × 404 `…/route/` (F-003) |
| Console errors/warnings | 1 per non-error session | only "Noto fonts missing for some characters" (Bengali/₹ glyph fallback — `flutter` warning) and Google Maps "loading=async" notice (filtered) |
| Flutter overflow exceptions | 0 in `flutter test` (226 tests), none visible in 320/390 px screenshots reviewed (admin dashboard, doctor earnings, pharmacy orders) — release builds do not print overflow stripes, so this is visual only |
| Blank page / crash | 0 |
| Image/media errors | none seen; marketplace images render; signed document/photo URLs 200 |

## 3. Polling / duplicate calls / stale state

| Screen | Behaviour | Source |
|---|---|---|
| Researcher panel | 5 endpoints (`bookmarks`, `innovations`, `disease-updates`, `papers`, `profile`) re-fetched every **6 s** — 99 times each in one ~10 min session (615 calls) | `research_session.dart:50` |
| Admin shell | `GET /api/admin-panel/profile/` 135×, `/api/me/updates/` 76× in one session (Super) | `UserUpdatesService` 10 s + per-screen refresh |
| Farmer home | `/api/farmers/dashboard/` ~38×, `/api/notifications/` ~49× in ~2 min; costs dashboard + tax summary re-fetched on every tab/segment tap | listeners + timers |
| Doctor | `/api/notifications/` 21×, appointments/dashboard/conversations 7× each | `DoctorSession` refresh on lifecycle + timer |
| Reload | all roles stay logged in on reload (24/24); data re-fetched | secure-storage session |
| Stale caches | none observed after mutations in the farmer add-expense test (list refreshed; dashboard totals recalculated server-side) | — |

Recommendation: collapse all panel polling onto `/api/me/updates/` with a server-side change token, pause when the tab is hidden, and apply exponential back-off (F-013).

## 4. Failure handling

| Case | Observed |
|---|---|
| Backend 500 (admin consultations) | Flutter shows an empty list + red toast "Admin request failed (500)" — error is surfaced but the screen then claims **"No doctors found"** (confusing empty state) |
| Backend 403 (wrong role) | Screens show "A farmer account is required." / "An active admin account is required." with Retry; doctor panel instead shows demo data (F-008) |
| Offline / network loss | not simulated (no browser offline test run) — **untested** |
| Retry buttons | present on error states (`Retry`, `Try again`), clicked in the crawl without error |
| External services | Google Directions failure → 404 (F-003); Jitsi/maps not reachable-tested; payment gateway in dev mode only |
| ASGI blocking | `delivery.route` performs a synchronous `urllib` call (8 s timeout) inside a request thread; `uvicorn` runs DRF views in the threadpool, so a slow upstream ties up a worker thread |
| Throttling | `429` with `Retry-After` text and `THROTTLED` error code; per-IP (F-026) |
| Duplicate submissions | expense create duplicates (F-039); feed order stock decrement atomic (1/6 parallel succeeds); subscription checkout idempotent via `idempotency_key` |
| Data growth | notifications 11.5k, JWT outstanding 4.8k rows, no cleanup command except `purge_orphan_signup_documents` (F-030) |

## 5. Backend exceptions during the audit

`audit_logs/server_audit_run.log` (the :8000 server, whole audit): 164 tracebacks, all from two causes — `TypeError … NoneType.__format__` at `admin_views.py:1051` (74 × HTTP 500 on `/api/admin-panel/consultations/`, F-001) and the malformed-UUID `ValidationError`/`ValueError` 500s on `/api/admin-panel/research-papers/<bad id>/` (4 × HTTP 500, F-025). No other 5xx in 2,869 sweep requests, 76 IDOR requests, 24 browser sessions or the HTTP workflows.

## 6. Not measured

Concurrent-user load, memory growth of the Flutter web app, cold-start time of `main.dart.js` (6.6 MB, CanvasKit), image-heavy pages, large-upload behaviour above the 5 MB limit, database index usage (`EXPLAIN`), Socket.IO scaling.
