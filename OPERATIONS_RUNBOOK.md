# FeatherFlow — Operations Runbook

**Date:** 2026-09-14 (updated same day — fourth pass: payment webhook hardening, see `PAYMENT_RUNBOOK.md` for the dedicated payment-operations detail this file only summarizes). Companion to `PRODUCTION_READINESS_REPORT.md`, `SECURITY_HARDENING_REPORT.md`, `PERFORMANCE_BASELINE.md`, `PAYMENT_RUNBOOK.md`.

---

## 1. Local development setup (verified end-to-end in this pass)

```powershell
# 1. Backend dependencies
cd backend
python -m venv venv
venv\Scripts\pip install -r requirements.txt
# CPU-only PyTorch for disease detection (see requirements.txt comment):
venv\Scripts\pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
venv\Scripts\pip install "efficientnet-pytorch==0.7.1" numpy

# 2. Environment
copy .env.example .env
# edit .env — at minimum: DJANGO_SECRET_KEY, POSTGRES_* (see .env.example for the full list)

# 3. Database — fresh instance, exact order (verified against a real clean
#    Postgres database in this pass — see PRODUCTION_READINESS_REPORT.md §1):
psql "$DATABASE_URL" -f ..\featherflow_schema.sql
psql "$DATABASE_URL" -f postgres_backend_extension.sql
psql "$DATABASE_URL" -f verification_extension.sql
psql "$DATABASE_URL" -f farmers_panel_extension.sql
psql "$DATABASE_URL" -f production_hardening_extension.sql

# 4. Django-managed migrations (billing, tax, audit, community, consultations,
#    profiles, token_blacklist, and others own real migrated tables — this is
#    not a no-op)
venv\Scripts\python manage.py migrate

# 5. Seed demo data (idempotent — safe to re-run)
venv\Scripts\python manage.py seed_platform_demo

# 5b. One-time only, and only on a database that has pre-existing uploads from
#     before the private-document migration (SECURITY_HARDENING_REPORT.md C2):
#     moves any file still referenced by an old public /media/ URL to private
#     storage. Safe to run on a fresh database too — it's a no-op if there's
#     nothing to migrate. Always dry-run first.
venv\Scripts\python manage.py migrate_legacy_public_uploads --dry-run
venv\Scripts\python manage.py migrate_legacy_public_uploads

# 6. Run — ASGI (needed for Socket.IO doctor↔farmer chat; manage.py runserver
#    serves the REST API fine but not the realtime chat):
venv\Scripts\python -m uvicorn featherflow_backend.asgi:application --host 127.0.0.1 --port 8000 --reload
```

```powershell
# Flutter
flutter pub get
flutter run -d web-server --web-port 5000 --web-hostname 127.0.0.1 --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Demo accounts: see `manage.py seed_platform_demo` output — all share password `FeatherflowDemo@2026`. **Never run this command against a production database** — it creates real user rows with a publicly-known password (see §10, Known Risks).

---

## 2. Production configuration checklist

| Setting | Local dev | Production |
|---|---|---|
| `DJANGO_DEBUG` | `True` | `False` (now the fail-safe default if unset) |
| `DJANGO_SECRET_KEY` | any value | **required** — app refuses to start on the insecure default when `DEBUG=False` |
| `DJANGO_ALLOWED_HOSTS` | `localhost,127.0.0.1` | your real domain(s) |
| `CORS_ALLOWED_ORIGINS` | blank (falls back to allow-all under DEBUG) | **required, explicit list** — blank now fails closed under `DEBUG=False` |
| `DJANGO_TRUST_PROXY_SSL_HEADER` / `DJANGO_SECURE_SSL_REDIRECT` | off | on, **only once** HTTPS actually terminates in front of the app (directly or via a reverse proxy setting `X-Forwarded-Proto`) — turning these on prematurely causes a redirect loop |
| `DJANGO_SESSION_COOKIE_SECURE` / `DJANGO_CSRF_COOKIE_SECURE` | off | on (defaults to on automatically when `DEBUG=False`) |
| `DJANGO_HSTS_SECONDS` | `0` | e.g. `31536000` once HTTPS is confirmed stable — start smaller (`3600`) and ramp up; HSTS is hard to undo quickly if something's wrong |
| `REDIS_URL` | blank (in-process cache) | **required with more than one worker process** — throttling/cache correctness needs a shared backend |
| `EMAIL_BACKEND` | console (prints to terminal) | real SMTP backend + credentials |
| `SMS_BACKEND` | console | a real provider, once `verification/delivery.py::send_sms_code` has an implementation for one (currently `NotImplementedError` for anything but `console`) |
| `OTP_EXPOSE_CODES` | on (via DEBUG) | **must be off** — codes must never appear in API responses or logs in production |
| `BILLING_MODE` / `STRIPE_*` / `BKASH_*` / `NAGAD_*` | blank (dev/simulated checkout) | **do not set** until the provider integration work in `PRODUCTION_READINESS_REPORT.md` §7 lands and the full pre-flight checklist in `PAYMENT_RUNBOOK.md` §2 has been run against a real provider sandbox — setting a provider secret today auto-flips to `'live'` mode, which currently has no working webhook verification and will break checkout, not process real payments |
| Static files | Django dev server | `python manage.py collectstatic` once at deploy time; served by `whitenoise` (already wired into `MIDDLEWARE`) — no separate nginx static config required |
| Media (user uploads) | local disk (`backend/media/`, `backend/private_media/`) | see §9 — local disk does not survive a container redeploy or scale past one instance; needs object storage before a multi-instance production deploy |
| Process manager | `uvicorn --reload` | `gunicorn` managing `uvicorn` ASGI workers (Socket.IO needs ASGI — this isn't a WSGI-only deployment). See `requirements.txt`'s "Production-only" section for exact packages. |
| `FF_LOG_FORMAT` | unset (human-readable console) | `json` — structured logs for aggregation (see §5) |

---

## 3. Health checks

- **Liveness** — `GET /healthz/` (also `GET /api/health/`): process is up, no dependency checks. Point your orchestrator's restart-on-failure probe here.
- **Readiness** — `GET /readyz/` (also `GET /api/health/ready/`): checks database (`SELECT 1`) and cache connectivity, returns `503` if either is down. Point your load balancer's traffic-routing probe here — a `503` should take the instance out of rotation, not restart it (a DB outage isn't fixed by restarting app instances).

Both are unauthenticated by design and reveal nothing beyond up/down + per-check latency in milliseconds.

---

## 4. Backup & restore

`backend/scripts/backup_db.py` — wraps `pg_dump`/`pg_restore` with the project's `.env` credentials. **Verified in this pass**: a real backup was taken of the dev database, restored into a separate database (`featherflow_restore_test`), and row counts confirmed to match exactly, then the test database was dropped.

```powershell
# Backup (custom format, compressed, safe against a live DB — pg_dump runs
# inside one consistent snapshot transaction, it doesn't block readers/writers)
python scripts\backup_db.py backup --out D:\backups

# Restore — ALWAYS into a separate database, never directly over POSTGRES_DB
# (the script refuses to target POSTGRES_DB directly)
python scripts\backup_db.py restore --file D:\backups\featherflow_featherflow_20260914T....dump --into featherflow_restore_check
```

**Recommended policy** (not yet automated — needs a scheduler, see §10):
- **Frequency:** daily full backup at minimum; hourly if the recovery-point objective below needs it.
- **Retention:** 7 daily + 4 weekly + 3 monthly, or per your compliance requirements — this platform holds financial (expenses/revenue/loans/tax) and medical (consultations/prescriptions) records.
- **RPO (Recovery Point Objective):** with daily backups, up to 24h of data loss in the worst case. If that's unacceptable, move to continuous WAL archiving (`pg_receivewal` / a managed Postgres provider's point-in-time recovery) rather than more frequent `pg_dump` runs.
- **RTO (Recovery Time Objective):** a `pg_restore` of the current dev-scale database (~1MB dumped) took under 5 seconds in this pass's test; budget more at production scale — measure it against a realistic-size dump, not the current demo data.
- **Private media backup:** `backend/private_media/` (signup documents, verification files) and `backend/media/` (everything else — see `SECURITY_HARDENING_REPORT.md` C2 for why some of what's in `media/` shouldn't be public) are **not currently included in any backup strategy** — they're plain local disk, gitignored, untouched by `backup_db.py`. This is a real gap: a database restore without the matching media restore leaves every uploaded document/photo/receipt referencing a file that no longer exists. See §9.

---

## 5. Observability

- **Structured logs**: set `FF_LOG_FORMAT=json` for one-JSON-object-per-line logs (`featherflow_backend/logging_utils.py`), suitable for any log aggregator (CloudWatch, Datadog, ELK, etc.) without a separate parser. Human-readable format (default) for local dev.
- **Request correlation**: every request gets an `X-Request-ID` (reused from an inbound header if the load balancer/gateway already sets one, otherwise minted) — present on every log line for that request and echoed back in every error response's `error.request_id` field (see `PRODUCTION_READINESS_REPORT.md` §4). When a user reports "I got an error," ask for this id and grep the logs for it directly.
- **What's already logged**: OTP delivery (redacted per `SECURITY_HARDENING_REPORT.md` M2), signup/verification flows, unhandled exceptions (`api/exceptions.py`, with full traceback + request id), admin login attempts, and — as of this pass — every payment state transition (checkout confirm/fail/cancel, webhook-driven success/failure/mismatch-reject/dispute, admin refunds), all in `ActivityLog` (append-only, DB-trigger-enforced) via `billing.services.record_audit_event`, never with secrets/tokens/card data. See `PAYMENT_RUNBOOK.md` §5-§7 for what to watch and how to respond.
- **What's not wired up yet** (documented, not built this pass — needs a provider/account decision, not just code): error tracking (Sentry or similar — `requirements.txt` has a commented-out `sentry-sdk` line and the exact spot to call `sentry_sdk.init()` is `featherflow_backend/settings.py`, right after the `LOGGING` block), metrics/dashboards (request count, latency percentiles, error rate, login/OTP/upload/ML-inference/payment failure counts — the raw log lines to derive these from already exist; turning them into dashboards needs a metrics backend like Prometheus or your aggregator's built-in log-based metrics).

**Recommended alert thresholds** (tune after real traffic data exists — these are starting points, not measured):
| Signal | Warn | Page |
|---|---|---|
| `/readyz/` failing | 1 consecutive failure | 3 consecutive failures across >50% of instances |
| 5xx rate | >1% of requests over 5 min | >5% of requests over 5 min |
| Login failure rate | >20% over 15 min (possible credential-stuffing) | sustained >50% over 15 min |
| OTP confirm failure rate | >30% over 15 min | — (informational; the existing per-identity lockout in `verification/otp.py` already contains abuse) |
| Payment webhook failures / amount-mismatch rejections | any, once live-mode payments are implemented | >3 in 10 min — see `PAYMENT_RUNBOOK.md` §7 for the response per symptom |
| `PaymentIntent`s timed out by `reconcile_pending_payments` | any | sustained growth run over run (provider webhook delivery may be broken) |
| DB connection pool exhaustion | — | any occurrence |

---

## 6. Deployment topology (recommended, not yet codified as IaC/Docker in this repo)

No `Dockerfile`/`docker-compose.yml`/CI workflow exists in this repo today — this pass did not add one (see `PRODUCTION_READINESS_REPORT.md` §10 for why: a container/CI setup is infrastructure-as-code that needs to match your actual hosting target, which wasn't specified). What's confirmed ready to containerize:

```
[Internet] → [TLS-terminating LB/reverse proxy] → [gunicorn + uvicorn ASGI workers (N instances)]
                                                          ↓
                                        [PostgreSQL] [Redis] [SMTP provider] [SMS provider]
```

- The app is stateless per-request (sessions/JWT, no server-side session state beyond the DB) — horizontal scaling is safe **once** `REDIS_URL` is set (throttling correctness requires a shared cache across instances — see `PERFORMANCE_BASELINE.md`).
- Static files: `collectstatic` + `whitenoise` serves them from the app process — fine at moderate scale, move to a CDN in front of `STATIC_ROOT` if static traffic becomes significant.
- Media files: **do not** put `backend/media/`/`backend/private_media/` on local/ephemeral container disk in a multi-instance deployment — see §9.
- ASGI is required (not optional) because of the Socket.IO real-time chat (`messaging/realtime.py`) — a WSGI-only deployment breaks doctor↔farmer chat silently (REST endpoints still work, chat won't connect).

---

## 7. Incident basics

- **Rollback**: this pass made no destructive schema changes — every SQL change (`production_hardening_extension.sql`) is additive (widened CHECK constraints, new indexes, new unique index) and safe to leave in place even if the application-code changes around it are rolled back. Rolling back the application code alone (without reverting the SQL) is safe.
- **Stuck/failed migration**: `python manage.py showmigrations` to see what's applied; `python manage.py migrate <app> <migration_name>` to target a specific state. The unmanaged (schema.sql-owned) apps' migrations are state-only — they don't run DDL, so they can't "fail" in the traditional sense, only get out of sync with what Django thinks the schema looks like.
- **Suspected credential leak (token/password)**: the new `POST /api/auth/logout/` blacklists one refresh token; there is currently no "revoke all sessions for this user" admin action — the closest equivalent is forcing a password reset (which invalidates every token via the `pv` claim mechanism, see `SECURITY_HARDENING_REPORT.md` §7). Building a dedicated "revoke all" admin action is a reasonable near-term follow-up.

---

## 8. Regression checklist (run before every deploy)

```powershell
cd backend
python manage.py check
python manage.py migrate --check
python scripts\test_farmer_panel.py
python scripts\test_tax_calculator.py
python scripts\test_community.py
python scripts\test_disease_detection.py
python scripts\test_articles_feed.py
python scripts\test_admin_panel.py
python scripts\test_doctor_flow.py
python scripts\test_vets_nearby.py
python scripts\test_signup_flows.py
python scripts\test_verification_flows.py
python scripts\test_signup_documents.py
python scripts\test_subscription_payment.py
python scripts\test_profile_photo.py
python scripts\test_private_documents.py
python scripts\test_admin_pagination_performance.py
python scripts\test_community_feed_performance.py
python scripts\test_admin_row_builder_performance.py

cd ..
flutter analyze lib test
flutter test
flutter build web --release
```

All of the above have been run and passed across this engagement's four passes (**821/821** backend checks as of the fourth pass, up from 797 — the +24 is entirely `test_subscription_payment.py`'s new webhook-hardening coverage; 87/87 Flutter tests, clean analyze, successful release build from the second pass, unaffected since) — see `PRODUCTION_READINESS_REPORT.md` §9 for the full run log. (A focused validation pass that only touches backend files can skip the three `flutter` commands — nothing they'd catch changed. The fourth pass additionally re-ran only `test_subscription_payment.py` and `test_admin_row_builder_performance.py` plus `manage.py check`/`migrate --check`, not the full 17-suite sweep, since its changes were confined to `billing/`.)

Also run after any change to `billing/`: `python manage.py reconcile_pending_payments --dry-run` (see `PAYMENT_RUNBOOK.md` §5, §7) to confirm the reconciliation command itself still runs cleanly against the current schema.

---

## 9. Known risk: local-disk media storage (flagged for follow-up, not fixed this pass)

`MEDIA_ROOT`/`PRIVATE_MEDIA_ROOT` are plain local filesystem paths. This works for a single-instance deployment but has two real risks: (1) no backup coverage today (see §4), (2) breaks entirely in any horizontally-scaled or container-redeployed setup (an upload lands on instance A's disk; a later request routed to instance B can't see it; a redeploy wipes it unless a persistent volume is explicitly attached). **Recommendation:** move to S3-compatible object storage (`django-storages` + a bucket) before scaling past one instance or introducing container redeploys — this is a prerequisite for horizontal scaling, not an optional nice-to-have.

*Update:* the access-*control* half of `SECURITY_HARDENING_REPORT.md` C2 is now fixed — prescriptions/disease-scans/receipts/delivery-proof photos are private and access-checked (`verification/documents.py`, `PRIVATE_MEDIA_ROOT`). This risk (local disk vs. object storage) is a separate, still-open concern about *where* the bytes live, not who can read them — it applies equally to `MEDIA_ROOT` (still public, still local disk — community/catalogue images) and `PRIVATE_MEDIA_ROOT` (now access-checked, still local disk). Moving to S3-compatible storage is the same `django-storages` swap for both.

## 10. Known risk: no scheduler for backups/cleanup jobs

`backup_db.py`, `verification/management/commands/purge_orphan_signup_documents.py`, and — new this pass — `billing/management/commands/reconcile_pending_payments.py` all need to run on a schedule — none is currently wired into cron/Windows Task Scheduler/a cloud scheduler. Set this up as part of the deployment, not left as a manual "someone remembers to run it" process. `reconcile_pending_payments` only matters once live-mode payments exist (it's a no-op today — nothing calls a provider, so no intent can be "stuck awaiting a webhook" outside dev-mode testing), but wire it in at the same time the provider integration itself goes live, not as an afterthought — a stuck-intent backlog is exactly the kind of thing that's easy to forget until a user complains their payment "vanished."
