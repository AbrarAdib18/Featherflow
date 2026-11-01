# FEATHERFLOW — Runtime Truth

Audit date: 2026-10-01 (machine clock, UTC+06:00). Nothing in this audit was committed.

## 1. Repository and source state

| Item | Value |
|---|---|
| Repository root | `D:\Featherflow Final` |
| Git branch / HEAD | `main` @ `6a036eb3469d1856b0314a3a8d7297e84af23979` ("Sub-admin roles fixed") |
| Tracked files modified (working tree) | 37 files, +3,942 / −114 lines (`git diff --stat`) |
| Untracked files | 48 at audit start (feed-owner/pharmacy-admin backend + Flutter code, migrations, reports) + the files this audit created |
| Tested code | **HEAD + uncommitted working tree** (the working tree contains the Pharmacy Admin / Feed Owner work; HEAD alone is *not* what was tested) |
| Audit-created artefacts | `FEATHERFLOW_*.md` (12 reports) and `audit_logs/` (raw test logs). Scratch tooling lives outside the repo (Claude scratchpad). |

## 2. Toolchain

| Tool | Version |
|---|---|
| Flutter | 3.47.2 (stable, framework rev `d3b14c8769`, engine `a804b26164`) |
| Dart | 3.13.2 |
| Python (backend venv `backend\venv`) | 3.12.10 |
| Django | 6.0 (`requirements.txt`: `Django==6.0`) |
| Django REST Framework | 3.16.1 (+ simplejwt 5.5.1, python-socketio 5.14.3, uvicorn 0.35.0) |
| Database engine | PostgreSQL **17.11** (x86_64-windows) via psycopg2 |
| Browser for automation | Google Chrome **154.0.8037.59** (headless), driven by `playwright-core` **1.63.0** (`executablePath` = installed Chrome) |
| Frontend renderer | Flutter CanvasKit (web), accessibility/semantics tree enabled by the harness to read and click widgets |

## 3. Database identity

* Engine: `django.db.backends.postgresql`
* Host/port: `localhost:5432` (Windows `postgres` service, PID 6396 listening)
* Database name: **`featherflow`** (from `backend\.env` → `POSTGRES_DB`; user `postgres`). Credentials not reproduced here.
* 119 public tables (108 Django models map onto them; 90 models are `managed=False`, i.e. tables owned by `featherflow_schema.sql` + `*_extension.sql`, 19 are Django-migration managed).
* `python manage.py migrate --check` → exit 0 (no unapplied migrations).
* This is the developer's **live dev database**, not an isolated copy. Backend test scripts and seed commands wrote to it (they self-clean/idempotent; see seed section of the complete report). A leftover empty `test_featherflow` database also exists from an earlier Django test run.
* `DJANGO_DEBUG=True` in `.env` (so CORS allows all origins — see security report F-SEC-02).

## 4. Processes actually under test

| Role | Command | URL / port | PID at audit |
|---|---|---|---|
| Backend (ASGI, as per `OPERATIONS_RUNBOOK.md` §6) | `cd backend; THROTTLE_AUTH_LOGIN=100000/min venv\Scripts\python.exe -m uvicorn featherflow_backend.asgi:application --host 127.0.0.1 --port 8000` | `http://127.0.0.1:8000` | 22864 (child of 26304) |
| Frontend (static) | `python spa_server.py "D:/Featherflow Final/build/web" 8080` (tiny SPA-fallback static server, `Cache-Control: no-store`) | `http://127.0.0.1:8080/` (hash routing: `/#/login`) | 26216 |
| Second backend (throttle probe only) | same uvicorn command **without** the throttle override on port 8001 | `http://127.0.0.1:8001` | started and stopped within the audit |

* Only the login throttle was raised on the :8000 server (20/min default → 100000/min) so that dozens of role logins from one IP in the browser/matrix tests are not rate-limited. The default behaviour was verified separately on :8001 (21st login attempt in a minute → `429`).
* Seed/demo commands were run from `backend` with `venv\Scripts\python.exe manage.py <cmd>`.

## 5. Frontend build and API base URL

* Build command (run by this audit): `flutter build web --release --dart-define=API_BASE_URL=http://127.0.0.1:8000`
* Result: success, `Compiling lib\main.dart for the Web... 71.0s`; log `audit_logs/build_web_release.log`.
* Build window: 2026-10-01T15:54:25+06:00 → 15:55:38+06:00; `build/web/.last_build_id` = `b7a8d41cbb2142f9deb55caf65fab5ea`; `main.dart.js` 6,647,778 bytes.
* Output directory served: `D:\Featherflow Final\build\web` (the previous build from 2026-09-26 20:41 was overwritten).
* API base URL used by Flutter: `AuthService.baseUrl` (`lib/core/network/auth_service.dart:211`) → compile-time `API_BASE_URL`, default `http://127.0.0.1:8000` (`10.0.2.2:8000` on Android). Confirmed: the string `127.0.0.1:8000` is present in the built `main.dart.js`, and browser network capture shows every call going to `http://127.0.0.1:8000/api/...`.
* Service worker / cache: Flutter's generated `flutter_service_worker.js` is present in `build/web`; the test server sends `Cache-Control: no-store`; every browser role run used a **fresh Playwright context** (empty localStorage / IndexedDB / cache / service-worker registrations). Session tokens are stored by `flutter_secure_storage` (IndexedDB/WebCrypto on web).
* Hard-coded Google Maps JS key in `web/index.html` (see security report).

## 6. How the frontend and backend under test were proven to be the intended versions

1. Backend: `GET /healthz/` → 200 and `GET /readyz/` → `{"status":"ok","checks":{"database":{"ok":true},"cache":{"ok":true}}}` on port 8000; `netstat`/`Get-NetTCPConnection` shows PID 22864 as the only listener on 8000. Every API response seen in the browser captures came from this PID (no other server listens on 8000/8080).
2. Frontend: the bundle was built *during* this audit from the working tree and served from the directory above; `main.dart.js` timestamp (15:55:38) is later than the last source edit.
3. Same data: the demo login for `farmer.rashed@example.com` returns `Md. Rashed Karim`, and the browser dashboard rendered `Welcome back, Md. Rashed Karim! … Expense ৳198,550 / Net Profit −৳35,893 / Cash ৳148,167`, matching `GET /api/farmers/dashboard/` for the same token — UI and API are the same system.

## 7. Stale processes / duplicate servers / mismatches

* No backend or frontend server was running when the audit started (ports 8000/8080/8001 free). Only PostgreSQL, IDE `dart mcp-server` processes and a Node process were up.
* Old log artefacts in the repo (`backend/server.log`, `uvicorn.log`, `flutter_run.log`, …) are stale and were not used as evidence.
* Mismatch 1 — **Django built-in test runner cannot run** against this schema: `manage.py test` aborts creating the test DB (`relation "users" does not exist`) because 90 models are `managed=False` and the schema comes from SQL files. All backend verification therefore uses the project's 43 script suites against the live DB (see complete report).
* Mismatch 2 — `seed_platform_demo` fails (pre-existing duplicate `Farm` rows).
* Mismatch 3 — pending-approval demo accounts have `users.account_status='active'`; "pending" is represented in profile/approval tables, so the status column alone does not identify pending applicants.

## 8. Seed / demo commands

`manage.py` commands found: `seed_news_demo`, `seed_farmer_demo_data`, `seed_feeding_guidelines`, `seed_feed_demo_data`, `seed_feed_marketplace_demo`, `seed_disease_reference`, `seed_pharmacy_demo_data`, `seed_research_demo`, `seed_finance_demo_data`, `seed_platform_demo`, plus utilities (`seed_demo_data_for_phone` needs a phone arg; `migrate_legacy_sqlite`, `migrate_pharmacy_catalogue`, `backfill_contact_verification`, `purge_orphan_signup_documents`, `migrate_legacy_public_uploads`, `reconcile_pending_payments`, `generate_feed_notifications` are maintenance jobs, not run). Standalone scripts `backend/scripts/_create_*admin*.py`. Demo passwords: `FeatherflowDemo@2026` (platform/finance/research/etc. demo accounts) and `ChangeMe@2026!` (pharmacy admin, feed admin, feed owner).

## 9. Audit-time server configuration changes

None to product code. Only the environment variable override described in §4 was applied to the :8000 server, and the test server was started without `--reload`.
