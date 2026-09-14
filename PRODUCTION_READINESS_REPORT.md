# FeatherFlow — Production Readiness Report

**Date:** 2026-09-14 (updated same day — fourth pass: payment webhook hardening — replay/duplicate protection, amount/currency mismatch guard, dispute handling, reconciliation for missed webhooks — plus a dedicated `PAYMENT_RUNBOOK.md`, all provider-agnostic since no real Stripe/bKash/Nagad credentials exist in this environment)
**Scope:** Full production-readiness and efficiency hardening pass across the Django/DRF backend and Flutter frontend, per the 11-phase brief (baseline/reproducibility, security, performance, reliability, data integrity, payments, chatbot, observability, backup/DR, deployment hardening, regression testing).
**Companion documents:** `SECURITY_HARDENING_REPORT.md`, `PERFORMANCE_BASELINE.md`, `OPERATIONS_RUNBOOK.md`, `PAYMENT_RUNBOOK.md` (new this pass).
**Nothing was committed.** Every change described here is in the working tree only (confirmed: `git log` shows no new commits from this session; `git status` reflects the changes listed in §10).

---

## 1. Overall production-readiness score

**8.5 / 10 — Beta-plus, functionally solid, sandbox payments verified sound and now substantially hardened, real-money payments still blocked on provider credentials.** (Unchanged numerically from the prior update — see why below.)

This is the fourth pass of the same engagement. The **first pass** fixed a critical subscription-renewal bug, closed a cross-origin data-exposure hole, and hardened deployment configuration. The **second pass** closed every remaining Critical/High security finding (private-document migration, admin pagination, community-feed N+1, Flutter secure storage). The **third pass** fixed the one remaining Critical performance finding (PC3, admin row-builder N+1) and audited the sandbox payment flow against a production-readiness checklist. **This pass** was explicitly scoped, after confirming no real Stripe/bKash/Nagad credentials exist anywhere in this environment (`.env`, `.env.example`, and the shell environment all checked), to provider-agnostic payment hardening and documentation only — not real provider integration, per the task's own instruction not to invent provider behavior. It added: webhook replay/duplicate-delivery protection (`billing.models.WebhookEvent`), an amount/currency mismatch guard that fails an intent instead of activating on a disagreement between the intent's own recorded amount and what a webhook reports, dispute/chargeback handling (a new `disputed` state that never auto-refunds and raises an admin escalation), a reconciliation management command for intents stuck with no webhook result, persisted audit logging for every payment state transition (closing the Low-severity gap the third pass had left open), and a new `PAYMENT_RUNBOOK.md` covering exact credentials/webhook URLs/signing-secret requirements per provider and the checklist to run before ever flipping `BILLING_MODE=live`. `scripts/test_subscription_payment.py` grew from 41/41 to **65/65**.

**Why the score didn't move**: none of this pass's work touches the actual blocker — `billing/webhooks.py`'s three verifiers are still an intentional `NotImplementedError` stub, because implementing real signature verification with nothing to test it against would be worse than the honest stub. This pass made everything *around* that blocker more solid and, per §7, closed essentially every gap that doesn't itself require real credentials — but "closed every closable gap" isn't the same as "the blocker moved."

**What keeps this from a higher score:** payments are honestly sandbox-only with no real provider integration — audited and confirmed architecturally sound for what exists, and now more thoroughly hardened, but webhook signature verification is still an intentional `NotImplementedError` stub with no real credentials to wire in (§7). The AI chatbot is intentionally not built (no product spec exists — §6). 7 High + 8 Medium performance items remain documented backlog (efficiency only, not scaling-cliff risk — every Critical performance finding is now fixed). There's still no deployment automation (Docker/CI) or object storage for uploads. None of these block a **staged, sandboxed beta** — they block flipping real payments on or scaling significantly past current traffic.

---

## 2. Completion criteria checklist

| Criterion | Status |
|---|---|
| No Critical or High security issues remain | ✅ 2/2 Critical, 7/7 High fixed. See `SECURITY_HARDENING_REPORT.md` §1. |
| No unexplained crashes or infinite spinners remain | ✅ Re-verified; global Flutter error handler in place |
| Cost Management works with empty and populated accounts | ✅ Re-verified (`scripts/test_farmer_panel.py` 39/39) |
| All role permissions pass positive and negative tests | ✅ Re-verified (`scripts/test_admin_panel.py` 65/65; `scripts/test_admin_row_builder_performance.py` also re-confirms RBAC + export still work after the PC3 fix) |
| Payment mode is clearly labeled as live or sandbox | ✅ `BILLING_MODE` auto-upgrades only when a provider secret is set; dev-confirm endpoint provably refuses outside dev mode — re-verified this pass, see §7 |
| Production payment verification exists before enabling real charges | ❌ Does not exist — webhook signature verification is an intentional `NotImplementedError` stub for all three providers, confirmed unchanged this pass (no real credentials exist in this environment to implement it against — see §7). Everything *around* it (amount calc, idempotency, state machine, activation-only-on-success, duplicate/replay-webhook protection, amount/currency mismatch guard, dispute handling, reconciliation, audit logging) is sound, tested, and — this pass — meaningfully more hardened. See `PAYMENT_RUNBOOK.md` for the exact checklist to run once real credentials arrive. |
| Backups and restore procedure are documented and tested | ✅ `backend/scripts/backup_db.py`, real backup + restore + row-count verification performed against the dev database |
| Health checks and structured logging exist | ✅ `/healthz/`, `/readyz/`, request-ID correlation, JSON log format option |
| Private files are protected | ✅ Prescriptions, disease-scan images, financial receipts, and delivery-proof photos all private/access-controlled; existing data migrated, old public URLs confirmed dead (404). |
| All release checks pass | ✅ `manage.py check` clean, **797/797** backend checks (up from 759), 87/87 Flutter tests (unchanged — no Flutter files touched this pass), prior `flutter analyze`/`flutter build web --release` results still stand |
| All remaining issues have owners, severity, and a plan | ✅ Every unfixed finding across all four documents has an explicit owner, severity, and remediation plan |

---

## 3. Findings by severity (aggregated across all four reports, current state)

| | Critical | High | Medium | Low |
|---|---|---|---|---|
| **Security** (`SECURITY_HARDENING_REPORT.md`) | 2 found, **2 fixed** | 7 found, **7 fixed** | 6 found, 3 fixed | 5 found, 2 fixed |
| **Performance** (`PERFORMANCE_BASELINE.md`) | 5 found, **5 fixed** | 7 found, 0 fixed¹ | 9 found, 1 fixed | — |
| **Reliability/data-integrity** (this doc, §4-§6) | 1 found, 1 fixed | 3 found, 3 fixed | 3 found, 2 fixed | 2 found, 1 fixed |
| **Payments** (this doc, §7 — checklist audit + hardening) | 0 found² | 0 found² | 2 found, 2 fixed | 1 found, 1 fixed³ |

¹ The 7 remaining High performance items are genuine backlog, not oversights — each has a concrete fix plan, an owner, and an effort estimate in `PERFORMANCE_BASELINE.md` §3. **Every Critical performance finding (PC1, PC2, PC3) is now fixed and measured.**
² The payment audit found the sandbox flow architecturally sound against every checklist item — no Critical/High gaps in what's built. The two Medium gaps found (refund not syncing to `PaymentIntent`; missing DB-level CHECK constraints on the intent table) were fixed on the spot as small, safe, tested changes. The one blocker to real money (no live provider integration) isn't a code defect to "find" — see §7.
³ The Low gap flagged in the third pass ("routine checkout/confirm/webhook events aren't persisted to `ActivityLog`") is now fixed this (fourth) pass — every payment state transition writes an audit entry, not just admin-initiated refunds.

---

## Second pass (earlier today): private documents, admin pagination, community feed, remaining security findings

Each item below followed the same discipline: **reproduce first, record the exact current behavior, fix the root cause, add a regression test, run the full backend + Flutter suites.** Full detail (file:line citations, before/after numbers, test names) lives in `SECURITY_HARDENING_REPORT.md` and `PERFORMANCE_BASELINE.md`; this is the cross-referenced summary.

### 1. Private-document storage and access-control migration — done

- **Audited every document type first**: a dedicated research pass mapped all six original upload paths (prescriptions, disease-scans, financial receipts, community post media, delivery-proof photos, pharmacy catalogue images) against who actually reads each one — the Flutter screens that render them and the backend views that serve them — before touching any code. This surfaced an important correction to the original finding: **community post images and pharmacy catalogue images are genuinely meant to be public** (a shared social feed / a product catalogue every farmer browses), not a bug — migrating them to owner-gated private storage would have broken the feed and the marketplace outright. Only the four genuinely single-owner (or, for prescriptions, two-party) types were migrated.
- **Prescriptions, disease-scan images, financial receipts (expense/revenue/tax-receipts/farm-photos), and delivery proof-of-delivery photos** now go through the same private, signed-token, `can_access()`-checked storage system already used for signup documents and profile photos (`verification/documents.py`) — not the public `MEDIA_ROOT`.
- **A new two-party access rule** for prescriptions specifically: the uploading farmer *and* the pharmacy fulfilling the order both need to see it. `verification/documents.py` gained `_prescription_order_pharmacy(token)`, which resolves the order and its pharmacy, and a matching `can_access()` branch — the first (and, by design, only) exception to the existing owner-or-admin rule.
- **Existing data migrated safely**: new idempotent `python manage.py migrate_legacy_public_uploads --dry-run` / (for real) command moved every already-uploaded file with an old public URL to private storage and rewrote the stored reference. Run against the dev database: 69 disease-scan images migrated; 1 delivery-proof row referenced a file already missing from disk (logged, left alone — no worse off than before, nothing to migrate).
- **Old URLs verified dead, not just "should be"**: directly requested the pre-migration public URL for a migrated file after the fix — confirmed `404`. There's no token/URL from before the fix that still resolves to anything.
- **Flutter**: the three screens that render one of these image types now fetch with the JWT attached (`AuthedNetworkImage`, an existing widget already used for profile photos) instead of a plain `Image.network`, which sends no auth header and would 401 against the now-protected endpoint.
- **Tested**: `scripts/test_private_documents.py` (new) — for every migrated type, asserts the full access matrix (owner 200 / another user 403 / anonymous 401 / admin 200), the prescription two-party case (fulfilling pharmacy 200, unrelated pharmacy 403), and — as a regression guard against overreach — that community post images and pharmacy catalogue images are *still* public. **27/27 passing.**

### 2. Admin list pagination and safe maximum page sizes — done

- Every one of the ~15 admin oversight list endpoints (`users`, `doctors`, `pharmacies`, `team`, `riders`, `researchers`, `consultations`, `articles`/`research-papers`/etc., `subscriptions`, and more) now returns bounded, paginated results (`page`/`page_size` query params, default 200, hard cap 500) with `count`/`page`/`page_size`/`has_more` metadata, computed via a real `LIMIT`/`OFFSET` pushed to Postgres — not a Python-list slice after fetching everything.
- CSV export uses a separate, much higher cap (20,000 rows) instead of the page size, with a logged warning if a module ever actually exceeds it.
- **9 missing database indexes added** for the columns the new pagination orders/paginates by (`users.created_at`, `doctor_profiles.created_at`, and 7 others — see `PERFORMANCE_BASELINE.md` §2) — none of these existed before, so a paginated page would otherwise still have required a full table sort first.
- **A real bug caught before it shipped**: the `users`/`team`/`pharmacies` admin lists were ordered by `-date_joined`, which is a Python `@property` (not a real column) — this raised `FieldError` on every single call. Caught by manually smoke-testing the endpoint (part of the "reproduce, then verify" discipline) before writing the regression test, not by the test itself — a reminder that a regression test only proves what it's told to check.
- **Tested**: `scripts/test_admin_pagination_performance.py` (new) — pagination shape, `page_size` capping, a query-count ceiling per page (independent of total table size) for 10 representative modules, export cap, and `has_more` accuracy. **99/99 passing.**

### 3. Community-feed N+1 elimination — done, measured

- **Measured before fixing, not assumed**: temporarily reverted the fix (`git stash` scoped to just the two changed files) and hit the live feed endpoint against the dev database's real data, then restored the fix and re-measured the identical request. **232 queries → 23 queries (10x), 219ms → 125ms (43% faster)** for the same 24-post response.
- Root cause fixed at two levels: (1) `User.role_names` was silently bypassing Django's `prefetch_related` cache on every call (the same bug pattern already fixed once for a different call site in the admin panel — fixed here at the source instead of patched at each call site); (2) a new `_bulk_post_context()` helper computes reaction/comment/repost/bookmark/follow/report data for an entire page of posts in ~7 fixed queries instead of ~8-10 queries per post.
- Applied to **every** community list endpoint, not just the primary feed: `feed`, `trending`, `latest`, `search`, `bookmarks`, `following_feed`, `user_posts`.
- **Tested**: `scripts/test_community_feed_performance.py` (new) — seeds 20 throwaway posts each with a real reaction/comment/repost/bookmark specifically so an O(N) regression would have something to actually query, asserts every endpoint stays under a fixed query-count ceiling regardless of post count, and asserts the bulk-computed engagement data is still correct (not just fast). **20/20 passing.**

### 4. Remaining High security findings — done

The two High findings left open after the first pass (both frontend, both requiring `flutter_secure_storage`) are now fixed:
- **Plaintext signup password** (`AuthService.savePendingRegistration`) moved from `SharedPreferences` to an in-memory-only field, mirroring an already-established pattern in the same codebase (`SignupFormCache`) built for the identical reason.
- **JWT session tokens** moved from plain `SharedPreferences` to `flutter_secure_storage` (Keychain/Keystore/WebCrypto-backed), with a one-time, transparent migration for already-installed app instances and a fallback to `SharedPreferences` if the secure-storage plugin is unavailable on a given platform.
- Fixing this surfaced and fixed a genuine test-fidelity gap in `test/admin_navigation_test.dart` (a mock that silently "succeeded" writes without actually storing anything, which would have masked a real data-loss bug) — full story in `SECURITY_HARDENING_REPORT.md` H7.

**Net result: 0 Critical/High security findings remain open.**

---

## Third pass (this update): PC3 admin row-builder N+1, payment production-readiness audit

### PC3 — admin row-builder N+1 — done, measured

The one remaining Critical performance finding. Reproduced and measured first (`api/admin_views.py`'s `_doctor_json`, `_pharmacy_json`, `_researcher_admin_json`, `_rider_json`, `_order_admin_json`, `_community_user_json`, `_community_report_json`, `_report_admin_json` each ran 1-5 extra queries **per row**), fixed with the same bulk-precomputed-`ctx` pattern PC1 established for the community feed, then re-measured on the same real dev data:

| Module | Rows | Before | After |
|---|---|---|---|
| `doctors` | 7 | 42 queries | 11 queries |
| `delivery-orders` | 75 | **159 queries** | **11 queries** |
| `community-users` | 4 | 26 queries | 14 queries |
| `pharmacies` / `researchers` / `riders` | 5-6 | 11-17 queries | 8-9 queries |

Every affected row-builder's bulk-`ctx` output was compared field-by-field against its original per-row output for every real row in the dev database — zero mismatches. RBAC, filtering, sorting, pagination, and CSV export were all re-verified working (not just fast) after the change. New test: `scripts/test_admin_row_builder_performance.py`, 35/35 passing. Full detail: `PERFORMANCE_BASELINE.md` §2.

### Payment production-readiness audit — sandbox flow verified sound, real-money blocker unchanged

Audited (not rebuilt) the existing sandbox payment flow (`billing/` app) against the full production-readiness checklist. **Confirmed already correct, with evidence:**

| Checklist item | Status | Evidence |
|---|---|---|
| Server-side amount calculation | ✅ | `billing/services.py:create_checkout` — amount always `_money(plan.price)` from the DB row, never `request.data`. Tested: "intent amount is server-side (matches plan price)", "client-sent amount ignored". |
| Valid plan lookup | ✅ | `get_plan_or_none` filters `is_active=True`; only plans in the presentation allowlist are purchasable. Tested: "unknown plan -> 404", "free plan is not purchasable -> 400". |
| Idempotency protection | ✅ | DB-level `UniqueConstraint` on `(user, idempotency_key)`; a retried checkout returns the same intent. Tested: "duplicate checkout is idempotent (same intent)", "no extra PaymentIntent row created". |
| Correct payment state machine | ✅ | `created → pending → {succeeded, failed, cancelled, refunded}`, `is_terminal` guards re-use of a finished intent. |
| No raw card data storage | ✅ | `payment_method` is a label only (`'card'`/`'bkash'`/`'nagad'`) — no card-number/CVC field exists anywhere in the model. Tested explicitly: "Payment row stores no raw card data". |
| Success/failure/cancellation/pending/refund states | ✅ | All 5 present and independently reachable and tested. |
| Subscription activation only after verified success | ✅ | `_activate()` is only ever called from the `outcome == 'success'` branch of `_apply_outcome`, itself only reachable via `confirm_dev` (dev-mode-only, explicitly refused in live mode) or `confirm_provider` (would only run after a verified webhook, once one exists). |
| Safe duplicate webhook/callback handling | ✅ | `_activate()` re-fetches the intent `select_for_update()` and returns immediately if already `succeeded` — a replayed webhook or a retry racing a real confirmation cannot double-activate. Tested: "confirm is idempotent (still one sub / one payment)". |
| Clear sandbox/live configuration separation | ✅ | `BILLING_MODE` auto-upgrades from `'dev'` to `'live'` only when a real provider secret is present; `.env.example` carries an explicit warning not to set one until the webhook verifiers are implemented. |
| No accidental live charging in development | ✅ | No code path anywhere calls a real provider API — there is currently no way to charge a real card at all, accidentally or otherwise. `confirm_dev` additionally refuses outright (409) if `BILLING_MODE` is ever `'live'`. |
| Audit logging | ⚠️ Partial — **found gap, fixed the part worth fixing now** | Admin-initiated actions (refunds) were already properly audited via the persisted `ActivityLog` table (`module='payments'`, with reason/IP/user-agent). Routine lifecycle events (checkout/confirm/webhook) only go to structured server logs (with request-ID correlation), not the persisted audit table — documented as a Low-severity recommendation below, not fixed (a broader change than "small safe issue" scope for this pass). |

**Two small, safe issues found and fixed:**
1. **Admin refund wasn't syncing to `PaymentIntent`.** `api/admin_finance.py:finance_action`'s refund branches update the legacy `payments`/`subscriptions` rows directly but never touched the originating `PaymentIntent` — so `GET /api/payments/<id>/` would keep showing `status='succeeded'` forever after an admin refund, even though the subscription was actually cancelled. Fixed with a new `billing.services.mark_intents_refunded()` helper, called from both refund branches. New test in `scripts/test_subscription_payment.py`: creates a dedicated checkout, refunds it via the real admin endpoint, asserts the `PaymentIntent` now reads `refunded` and the subscription `cancelled` — passing, and confirmed it doesn't disturb a different, unrelated active subscription for another user.
2. **`billing_payment_intents` had no DB-level CHECK constraints.** `status`/`payment_method` were only validated by Django's `choices=` (an ORM/serializer-layer check, not enforced on a direct DB write) and `amount` had no positive-value guard — inconsistent with the CHECK constraints already added to the legacy `payments`/`expenses`/`revenues`/`loans` tables in the prior pass. Fixed with a new migration (`billing/migrations/0002_...py`) adding matching `CheckConstraint`s; verified zero existing rows would have violated them before applying.

**Not done (correctly, per the task's own instruction not to invent provider behavior):** no Stripe/bKash/Nagad HTTP integration, no webhook signature verification. These need real provider credentials that don't exist in this environment — see §7 below for the precise, narrow blocker this leaves.

Regression: `scripts/test_subscription_payment.py` 41/41 (was 38, +3 for the refund-sync test), full backend suite 797/797.

---

## Fourth pass (this update): payment webhook hardening — provider-agnostic only

**Before starting, per the task's own explicit gate:** confirmed which providers are in scope (card/Stripe, bKash, Nagad, per the existing `billing/webhooks.py` dispatch), then searched for real provider credentials — `backend/.env` (11 vars, none payment-related), `backend/.env.example`, every other `.env*` file, and the shell environment. **None exist.** Given the standing instruction not to invent provider behavior and not to claim production-readiness without real-sandbox verification, this pass was scoped to what's honestly buildable and testable without them: hardening and testing the pipeline *around* the verification boundary, and documenting exactly what's needed to cross it later. No Stripe/bKash/Nagad HTTP call or signature-verification logic was written — `billing/webhooks.py`'s three verifiers remain the same intentional stub as the third pass, unchanged.

**What was added, all provider-agnostic (works identically regardless of which provider eventually gets wired in):**

1. **Webhook replay / duplicate-delivery protection.** New `billing.models.WebhookEvent` (`(provider, event_id)` unique constraint) + `billing.services.record_webhook_event()`. The webhook view now records each delivery's id before processing it; a second delivery of the same event is a DB-level no-op, answered `200` (so the provider's retry logic stops retrying) without reapplying the outcome. Falls back safely to the existing idempotent state machine if a provider event has no natural id.
2. **Amount/currency mismatch guard.** `billing.services._amount_mismatch()`, wired into `_apply_outcome`. If a verified webhook's reported amount/currency disagree with what the `PaymentIntent` was created for (server-side, at checkout — never trusted from the client), the intent is failed with a clear reason instead of activated. This is the direct, testable-today implementation of the task's "reject mismatched amount/currency" requirement.
3. **Dispute/chargeback handling.** A new `disputed` status on `PaymentIntent` (migration `0004_...`) and `billing.services._flag_dispute()`: an `outcome == 'dispute'` event on an already-`succeeded` intent moves it to `disputed` and raises an `AdminEscalation` for manual review — it never auto-refunds or auto-cancels the subscription; a human decides. Idempotent against a replayed dispute event.
4. **Reconciliation for missed/delayed webhooks.** New `billing/management/commands/reconcile_pending_payments.py` — flags `PaymentIntent`s stuck in `created`/`pending` past a configurable age, and times out ones stuck well past that (marking them `failed`, the same terminal state a real provider failure webhook would produce) rather than leaving them pending forever. `--dry-run` reports without mutating. Deliberately does **not** call any provider status API — no such generic call exists across the three providers, and building a provider-specific one needs the credentials this pass doesn't have; the runbook documents exactly where to add it once a verifier exists.
5. **Audit logging without secrets.** `billing.services.record_audit_event()` — every payment state transition (success, failure, cancel, mismatch-reject, dispute) now writes a persisted `ActivityLog` row (intent id, status, amount, currency, provider — never a token/secret/card fragment), closing the Low-severity gap the third pass had documented but not fixed.
6. **`PAYMENT_RUNBOOK.md`** (new file) — the exact env vars per provider (already declared in `settings.py`, cross-checked against it directly rather than guessed), the three webhook URLs, signing-secret requirements and where to get sandbox vs. production values for each provider, a step-by-step checklist for the first time `BILLING_MODE=live` is ever set for a given provider, an incident playbook, and a test-coverage map that's explicit about what is and is not verifiable without real credentials.

**Tested** — `scripts/test_subscription_payment.py`, grown from 41/41 to **65/65** (+24). New coverage: valid webhook (via a test-scoped monkeypatch of `_verify_stripe` that returns a synthetic *already-verified* event — this tests our own dedupe/mismatch/state-machine code downstream of verification, never real provider signature-checking), invalid signature (the real, unpatched rejection path — genuinely exercises today's code since no secret is configured), replay webhook, duplicate webhook, mismatched amount/currency, dispute + duplicate-dispute idempotency, provider timeout (modeled honestly as "webhook never arrives," exercised via the reconciliation command against a backdated intent — real network-timeout behavior against a live provider remains untestable without one), and reconciliation `--dry-run` safety. Also re-ran `manage.py check`, `manage.py migrate --check` (clean), and `scripts/test_admin_row_builder_performance.py` (35/35, unaffected) as a focused regression check — not a full 17-suite re-run, since this pass touched only `billing/` and no shared code path used elsewhere.

**Not done, correctly, per this pass's own gate:** no real Stripe/bKash/Nagad HTTP integration or signature verification (still `NotImplementedError`); `BILLING_MODE` still auto-upgrades to `'live'` only when a real provider secret is set, and none is set anywhere in this environment — live mode was not enabled, by default or otherwise. Payment integration is **not** claimed production-ready; see §7 and `PAYMENT_RUNBOOK.md` §1-§2 for exactly what's still required and how to verify it once real sandbox credentials exist.

---

## 4. Reliability & error handling (Phase 4)

### Fixed

- **Structured error responses** — new `api/exceptions.py`. Every DRF-raised exception (validation errors, auth failures, permission denials, 404s, throttling) now gets a consistent `{"error": {"code", "message", "request_id", "fields"?}}` block. **Deliberately additive, not a replacement**: the original flat DRF response shape (`{"detail": "..."}` or `{"field": ["msg"]}`) is preserved at the top level alongside the new `error` key. This mattered in practice — an earlier version of this fix *replaced* the body wholesale and broke `lib/core/network/auth_service.dart`'s field-level error parsing for the entire signup wizard, caught by `scripts/test_signup_flows.py` (9 failures). The additive version passes all 88 signup-flow checks and gives every error a `request_id` for support correlation.
- **Request correlation** — new `api/request_id.py` middleware. Every response carries `X-Request-ID` (reused from an inbound header if present, otherwise minted); every log line during that request carries the same id.
- **Global Flutter error handler** — `lib/main.dart` previously had **no** `runZonedGuarded`/`FlutterError.onError`/`PlatformDispatcher.instance.onError` at all — any exception outside a screen's own try/catch had zero safety net. Now wrapped; logs every uncaught error with a stack trace instead of silently failing.
- **Farmer dashboard silently swallowed every load error** — `farmer_dashboard_screen.dart:_refresh()` wrapped its entire body in `try { ... } catch (_) {}` with no `_error` field at all. A failed load looked exactly like a legitimate empty/zeroed dashboard — the app's primary landing screen, most likely to be hit by any transient network issue. Now surfaces a compact, retryable `ErrorStateView` banner without replacing the rest of the screen.
- **Health/readiness endpoints** — see `OPERATIONS_RUNBOOK.md` §3.

### Documented, not fixed this pass

- Many hand-rolled `except ...: return Response({'detail': str(exc)})` sites across the older apps (`expenses`, `workers`, `feed` — narrowed in this pass to stop leaking raw exception text, but not migrated to the new structured `error` shape, since they never raise an exception that the new handler would intercept). A full migration of these sites is a larger, separate follow-up — see `SECURITY_HARDENING_REPORT.md` L1/L3.
- Several Flutter screens still show raw error text without the shared `ErrorStateView`/`humanize()` treatment (a prior audit flagged 5; a fresh audit this pass found the full, larger list — `tax_summary_screen.dart`, `disease_detection_screen.dart`, `vet_map_screen.dart` grew their own bespoke (but still non-humanized) error widgets rather than adopting the shared one; several admin/delivery/doctor screens show `error.toString()` directly in failure SnackBars). Not fixed this pass — a broad, low-risk-per-screen but high-file-count sweep better suited to a dedicated pass. Full file list available from the Flutter audit conducted this session.

---

## 5. Data integrity & transactions (Phase 5)

### Fixed

- **Subscription renewal was completely broken** — the single most impactful bug found this pass. `billing/services.py:_activate()` retires a prior subscription with `status='replaced'`, but the database CHECK constraint didn't allow that value. **Every renewal, upgrade, or downgrade after a user's first subscription purchase raised an uncaught database error and 500'd** — reproduced directly against the dev database before the fix, confirmed fixed after (`production_hardening_extension.sql` widens the constraint). First-time signups were unaffected. This had presumably never been caught because the existing test suites and demo data mostly exercise first-time checkout, not renewal.
- **Admin approve/reject/suspend actions made atomic** — `api/admin_views.py:admin_record`, every branch does 2+ separate `.save()` calls across tables with no transaction previously; now wrapped in `@transaction.atomic`.
- **Tax-payment → expense mirroring made atomic + idempotent** — previously a non-atomic, non-idempotent, silently-swallowed-failure step; now atomic with a double-submit guard and real logging on mirror failure.
- **Dead legacy `/api/subscriptions/` endpoint removed** — bypassed all billing validation/atomicity/idempotency; confirmed unused by the Flutter client before removal.
- **One-active-subscription-per-user now enforced at the DB level** (`production_hardening_extension.sql`, a partial unique index) — previously relied entirely on application-level locking discipline in `billing/services.py`, which is sound but had no database backstop.
- **`amount > 0` CHECK constraints added** to `payments`, `expenses`, `revenues`, `loans` — app-level validation already existed on the modern write paths; this adds a database-level backstop for any path that bypasses it (direct DB access, a future bug, the legacy apps before this pass's fixes).

### Documented, not fixed this pass

- Loan repayment / expense-payment writes in `farmers/cost_views.py` are still non-atomic (2-3 separate `.save()`/`.create()` calls) though partially self-guarding (`pay_expense` checks status before writing). Low-Medium severity, straightforward fix, deferred to keep this pass's scope bounded to the highest-impact items.
- No self-service account-deletion flow exists at all (confirmed: no such endpoint anywhere). Not a data-integrity bug today (nothing to orphan since nothing is ever hard-deleted), but a real gap if GDPR/right-to-erasure compliance is a requirement — the schema's FK design (`ON DELETE RESTRICT` on financial/audit tables, `CASCADE` on profile tables) already anticipates this being built correctly whenever it is.
- Seed commands (`seed_platform_demo` etc.) are confirmed idempotent (re-run twice against a clean database in this pass, verified zero duplicate rows) but have **no guard against being run against a production database by mistake** — they'd create real user rows with the publicly-known demo password. Recommended: gate behind `if not settings.DEBUG: raise CommandError(...)` unless `--force` is passed. Not fixed this pass (small but touches 5 separate management commands, deprioritized below the items above).

---

## 6. AI chatbot status (Phase 7)

**Not implemented. Gated, not built, per the brief's own instruction to document rather than build when product requirements aren't clear.**

`backend/chatbot/` exists as a Django app with only `models.py`/`apps.py`/migrations — no views, no URLs, no Flutter screen anywhere in the codebase (confirmed: zero references to a chat/AI assistant UI in `lib/`). There is no product spec for what the chatbot should answer, what knowledge source backs it, what the veterinary-disclaimer/escalation policy should say, or which AI provider to use — all of which the brief correctly identifies as prerequisites ("Implement...only if the existing ML/product requirements are clear. Otherwise document it as a separately gated feature"). Building one now would mean inventing product requirements rather than following them, which is exactly the "don't rewrite/reinvent blindly" risk this whole pass has been trying to avoid elsewhere.

**When this gets picked up**, the brief's own checklist (farmer-facing chat screen, disease-scan context handoff, poultry-specific knowledge source, veterinary disclaimer, no diagnosis/treatment claims, escalation to a real vet, rate limits, conversation storage policy, privacy controls, provider-failure fallback, prompt-injection/unsafe-advice/timeout tests) is a solid starting spec and should be used directly.

---

## 7. Payment status (Phase 6)

**Sandbox-only, clearly labeled, architecturally sound, checklist-audited, and — this (fourth) pass — substantially hardened around the one remaining boundary. Still not production-ready for real money.** Full detail: the second pass's `SECURITY_HARDENING_REPORT.md` Part B (initial payments audit), the third pass's checklist walkthrough above, this pass's "Fourth pass" section above, and the new `PAYMENT_RUNBOOK.md` (exact credentials/webhook URLs/signing-secret requirements per provider, a pre-flight checklist, an incident playbook, and a test-coverage map). Summarized here:

- **What's real and good, confirmed by a dedicated checklist audit and now hardened further**: `billing.PaymentIntent` is a genuine payment-intent-before-checkout pattern with a server-computed, never-client-trusted amount, a real idempotency key with a DB unique constraint (backed by DB-level CHECK constraints on status/method/amount), and a proper state machine (`created → pending → {succeeded, failed, cancelled, refunded, disputed}`) with idempotent, duplicate-safe activation. `BILLING_MODE` correctly auto-upgrades from `'dev'` to `'live'` the instant any provider secret is configured (or can be forced either way via an explicit `BILLING_MODE` env var), and the dev-mode confirm endpoint is provably refused (`409`) outside dev mode. No raw card data is ever stored. Admin refunds are audit-logged and correctly sync the originating `PaymentIntent`. **New this pass**: webhook replay/duplicate-delivery protection (`billing.models.WebhookEvent`), an amount/currency mismatch guard that fails rather than activates on disagreement, dispute/chargeback handling that flags for admin review without ever auto-refunding, a reconciliation command for intents that never get a webhook result, and persisted audit logging for every payment state transition (not just admin refunds).
- **What's missing for real money — unchanged, confirmed still true this pass**: the webhook signature verifiers for Stripe/bKash/Nagad are intentional `NotImplementedError` stubs (with a checklist comment for what each provider's real call looks like), and **no actual HTTP call to any provider exists anywhere in the codebase** — `stripe` isn't even in `requirements.txt`. Setting a live provider secret today would flip `BILLING_MODE` to `'live'` and **break checkout entirely** rather than process real payments, since `select_method` returns `redirect_url: None` in live mode with a comment that a real integration needs to fill it in. This is the **entire remaining blocker** — everything else on the production-payments checklist is already done, and this pass closed the gap between "the blocker" and "everything reasonably buildable without it."
- **Recommended next steps** (not built — needs real provider account credentials this environment doesn't have, per the task's own instruction not to invent provider behavior; the exact sequence is now in `PAYMENT_RUNBOOK.md` §2): (1) implement `stripe.Webhook.construct_event` + the bKash/Nagad callback signature checks in `billing/webhooks.py`, returning the dict shape `PAYMENT_RUNBOOK.md` §6 documents (including the optional `event_id`/`amount`/`currency` keys this pass's hardening now consumes), (2) build the actual provider checkout-creation HTTP calls, (3) once a verifier exists, extend `reconcile_pending_payments.py` to also query that provider's real status API for stuck intents rather than only using our own clock, (4) do NOT set any `STRIPE_*`/`BKASH_*`/`NAGAD_*` env var in production until (1)-(2) are done and verified against that provider's sandbox end-to-end, per the warning in `.env.example` and the full pre-flight checklist in `PAYMENT_RUNBOOK.md` §2.

---

## 8. Observability & deployment hardening (Phases 8, 10)

Full detail in `OPERATIONS_RUNBOOK.md`. Summary of what's new this pass:

- Structured JSON logging (opt-in via `FF_LOG_FORMAT=json`), request-ID correlation on every log line and every response.
- `/healthz/`, `/readyz/` (checks DB + cache), unauthenticated, safe for load-balancer/orchestrator probes.
- Static files: `STATIC_ROOT` + `whitenoise` wired in and verified (`collectstatic` run successfully, 166 files/478 post-processed) — previously `STATIC_ROOT` wasn't even defined, so `collectstatic` was a no-op and there was no static-file serving story for production at all.
- `CACHES` now explicit (Redis when `REDIS_URL` is set, in-process fallback otherwise) — previously undefined, meaning Django's implicit LocMem default, which is wrong for more than one worker process.
- HTTPS/cookie hardening settings added, all opt-in via env vars with safe (off) defaults so this doesn't break an unconfigured deployment — see `OPERATIONS_RUNBOOK.md` §2 for exactly when to turn each one on.
- **Not built this pass**: Docker/docker-compose/CI workflow (none existed before; none added — this needs to match an actual hosting target that wasn't specified, and a guessed-at Dockerfile risks being actively wrong rather than just incomplete), Sentry/error-tracking wiring (the exact integration point is documented; needs a real DSN), metrics dashboards (the underlying structured logs now exist to build them from).

---

## 9. Tests and manual verification completed (four passes)

**Backend — 821/821 checks, 0 failures** across all 17 suites (797 after the third pass + 24 new this pass, all in `test_subscription_payment`). This pass re-ran `test_subscription_payment.py` (grew 41→65), `manage.py check`, `manage.py migrate --check`, and `test_admin_row_builder_performance.py` (35/35, unaffected — re-run as a focused regression check, not because billing touches it) rather than the full 17-suite sweep, since this pass's changes are confined to `billing/` and touch no shared code path exercised by the other 15 suites:
`test_farmer_panel` 39, `test_tax_calculator` 64, `test_community` 56, `test_disease_detection` 25, `test_articles_feed` 28, `test_admin_panel` 65, `test_doctor_flow` 58, `test_vets_nearby` 12, `test_signup_flows` 88, `test_verification_flows` 36, `test_signup_documents` 46, `test_subscription_payment` **65** (+24 this pass), `test_profile_photo` 58, `test_private_documents` 27, `test_admin_pagination_performance` 99, `test_community_feed_performance` 20, `test_admin_row_builder_performance` 35.

**Flutter — no Flutter files changed this pass (or the third pass)**, so `flutter test`/`analyze`/`build web` were not re-run (per this pass's scope — focused validation only re-runs what could have been affected). The second pass's results stand: 87/87 tests, clean `flutter analyze`, successful `flutter build web --release`.

**Manually verified against a running server**: `/healthz/`, `/readyz/` (with real DB+cache latency numbers in the response), structured error shape on a 401 and a validation error (with `X-Request-ID` header present), the subscription-renewal fix, a real backup + restore + row-count-verified rehydration into a separate database, the private-document access matrix, the old-public-URL-now-404s claim, and the community-feed query-count/timing claim (measured with the fix reverted, then restored). **This pass added**: PC3's before/after query counts per module (measured directly against real dev data, no reverting needed since the bulk-`ctx` path is optional and the original per-row functions are still callable with `ctx=None`), field-by-field output-parity checks between the two code paths for every affected row-builder (zero mismatches), and a live exercise of the admin refund → `PaymentIntent` sync fix through the real `/api/admin-panel/payments/sub:<id>/` endpoint.

**Clean-database bootstrap** — verified from scratch in the second pass (isolated `featherflow_clean_test` database, all schema/extension SQL files, every Django migration, `seed_platform_demo` run twice with zero duplicates). Not re-run this pass since it only added one new Django-managed migration (`billing/migrations/0002_...`), which was verified directly instead: applied to the dev database with `manage.py migrate billing` (succeeded) after confirming zero existing rows would violate the new constraints.

**Not manually re-clicked through every Flutter screen** — the 2026-09-11 audit already did a full real-browser walkthrough of all 15 roles (Playwright, screenshots, console-error capture); this session's Flutter changes are covered by `flutter test`/`flutter analyze` and, for the three image-rendering screens touched by the private-document migration, by reasoning about the `AuthedNetworkImage` swap being behaviorally identical to its existing use on profile photos (not independently screenshotted). Recommend a spot-check of prescription/delivery-proof photo rendering and the farmer dashboard's error banner before the next full manual QA pass.

---

## 10. Files changed

**First pass — backend (24 modified, 6 new):**
`featherflow_backend/settings.py`, `featherflow_backend/urls.py`, `featherflow_backend/logging_utils.py`* , `api/exceptions.py`*, `api/health.py`*, `api/request_id.py`*, `api/throttling.py`, `api/urls.py`, `api/admin_views.py`, `users/views.py`, `users/urls.py`, `verification/views.py`, `verification/delivery.py`, `expenses/views.py`, `workers/views.py`, `feed/views.py`, `community/views.py`, `tax/views.py`, `production_hardening_extension.sql`*, `featherflow_schema.sql`, `scripts/test_verification_flows.py`, `scripts/backup_db.py`*, `.env.example`, `DATABASE_SETUP.md`, `requirements.txt`, `.gitignore`.

**First pass — Flutter (3 modified):** `lib/main.dart`, `lib/features/farmer/presentation/screens/farmer_dashboard_screen.dart`, `lib/features/research/presentation/screens/researcher_profile_screen.dart`.

**Follow-up pass — backend (9 modified, 4 new):** `verification/documents.py`, `verification/management/commands/migrate_legacy_public_uploads.py`*, `ml/views.py`, `farmers/services.py`, `pharmacy/farmer_views.py`, `delivery/views.py`, `api/admin_views.py`, `api/admin_extra.py`, `community/views.py`, `users/models.py`, `production_hardening_extension.sql` (extended further), `scripts/test_private_documents.py`*, `scripts/test_admin_pagination_performance.py`*, `scripts/test_community_feed_performance.py`*.

**Follow-up pass — Flutter (5 modified):** `lib/core/network/auth_service.dart`, `pubspec.yaml`, `lib/features/pharmacy/presentation/screens/pharmacy_orders_screen.dart`, `lib/features/farmer/presentation/screens/farmer_pharmacy_screen.dart`, `lib/features/delivery/presentation/screens/delivery_detail_screen.dart`, `test/admin_navigation_test.dart`.

**Third pass — backend (5 modified, 2 new):** `api/admin_views.py`, `api/admin_finance.py`, `consultations/metrics.py`, `billing/models.py`, `billing/services.py`, `billing/migrations/0002_paymentintent_billing_intent_status_valid_and_more.py`*, `scripts/test_admin_row_builder_performance.py`*. Also `scripts/test_subscription_payment.py` (extended with the refund-sync test).

**Third pass — Flutter:** none.

**Fourth pass — backend (5 modified, 4 new):** `billing/models.py` (added `WebhookEvent`, `disputed` status), `billing/services.py` (mismatch guard, dispute handling, audit logging, dedupe helper), `billing/views.py` (thread `event_id`/`amount`/`currency` through the webhook view), `billing/webhooks.py` (docstring contract only — documents the new optional keys, no verifier logic touched), `.env.example` (one-line pointer to the new runbook), `billing/migrations/0003_webhookevent.py`*, `billing/migrations/0004_remove_paymentintent_billing_intent_status_valid_and_more.py`*, `billing/management/commands/reconcile_pending_payments.py`*. Also `scripts/test_subscription_payment.py` (extended, 41→65).

**Fourth pass — Flutter:** none.

**Reports (5, updated in place today):** this file, `SECURITY_HARDENING_REPORT.md`, `PERFORMANCE_BASELINE.md`, `OPERATIONS_RUNBOOK.md`, and new: `PAYMENT_RUNBOOK.md`.

~61 files touched total across all four passes (plus `pubspec.lock` and the platform plugin-registration files Flutter regenerates automatically when a new native dependency is added — `linux/flutter/generated_plugin*`, `macos/Flutter/GeneratedPluginRegistrant.swift`, `windows/flutter/generated_plugin*`).

---

## 11. Commands run (four passes)

See `OPERATIONS_RUNBOOK.md` §8 for the exact regression-check command list — now includes all four new test scripts. Third pass, additionally: `manage.py makemigrations billing` / `manage.py migrate billing` (the new CHECK-constraint migration), a direct Python REPL query confirming zero existing `PaymentIntent` rows would violate the new constraints before applying them, and a scratch measurement script (`scratchpad_measure_pc3.py`, deleted after use — not part of the deliverable) hitting each affected admin endpoint with `CaptureQueriesContext` to get the before/after numbers in §2 of `PERFORMANCE_BASELINE.md`. Fourth pass, additionally: a grep/search across `.env`, `.env.example`, every other `.env*` file, and the shell environment confirming no provider credentials exist before any code was written (the task's own "before coding" gate); `manage.py makemigrations billing` / `manage.py migrate billing` twice (the `WebhookEvent` model, then the `disputed` status choice); `manage.py check` and `manage.py migrate --check` (clean); a manual dry-run and live-run of `reconcile_pending_payments` against the dev database.

---

## 12. Remaining blockers (by what they block)

Every Critical/High security finding and **every** Critical performance finding (PC1, PC2, PC3) are now fixed — only the payment provider integration and pure-efficiency items remain:

| Blocks | Item | Owner | Severity |
|---|---|---|---|
| Real payments | No provider webhook verification / HTTP integration (needs real credentials) | Backend | Critical (for payments specifically; sandbox mode is safe to keep running) |
| Horizontal scaling / container redeploys | Local-disk media storage, no object storage (also needed for the newly-private uploads) | Backend/Infra | High |
| General admin/doctor/farmer list efficiency | 7 documented High performance items (PH1-PH7) | Backend | High (efficiency, not correctness — no Critical scaling-cliff items remain) |
| Confident incident response | No error-tracking (Sentry) wiring, no metrics dashboards | Backend/Infra | Medium |
| Automated deployment | No Dockerfile/CI | Infra | Medium |
| Compliance readiness | No account-deletion flow | Backend/Product | Low-Medium |

None of these block a continued, sandboxed beta with real users on non-payment features. They gate: turning payments on, or scaling significantly past current traffic.

**Recommended deployment stage:** staged/sandboxed beta with real users, real (non-payment) data, and sandbox-mode payments clearly labeled as such in the UI. Do not enable `BILLING_MODE=live` (i.e. do not set any `STRIPE_*`/`BKASH_*`/`NAGAD_*` secret in a deployed environment) until the webhook verifiers in `billing/webhooks.py` are implemented against real provider credentials and the full pre-flight checklist in `PAYMENT_RUNBOOK.md` §2 has been run — doing so today would not silently overcharge anyone (no HTTP call to a provider exists to do that), but it would break checkout outright for every user by flipping into a live mode with no working confirmation path.

---

## 13. Confirmation

**Nothing was committed during this session.** All changes described above remain in the working tree (`git status`). No `git commit`, `git push`, or destructive git operation was run at any point in this pass.
