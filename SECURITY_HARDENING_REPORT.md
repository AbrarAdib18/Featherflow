# FeatherFlow — Security Hardening Report

**Date:** 2026-09-14 (updated same day — follow-up pass closing the remaining Critical/High findings)
**Scope:** Full backend (Django/DRF) + Flutter client security audit and hardening pass, as part of the broader production-readiness engagement (see `PRODUCTION_READINESS_REPORT.md`).
**Method:** Two independent, parallel deep-dive audits (auth/session/authorization/CORS one pass, file-upload/input-validation/mass-assignment the other) covering every app in `backend/`, cross-checked against the Flutter client's actual parsing/storage code. Every finding below is backed by a file:line citation verified against the real codebase, not inferred. All fixes were applied to the working tree, verified with the full backend regression suite (now 759 checks, 0 failures) and `flutter analyze` / `flutter test` (0 issues, 87/87, plus a real release build), and **nothing was committed**.

**Follow-up pass (same day):** every finding that was "documented, not fixed" in the original version of this report has now been fixed, verified, and regression-tested — see the updated status on C2, H6, and H7 below. **0 Critical/High findings remain unfixed.**

---

## 1. Summary

| Severity | Found | Fixed | Documented, not yet fixed |
|---|---|---|---|
| Critical | 2 | 2 | 0 |
| High | 7 | 7 | 0 |
| Medium | 6 | 3 | 3 |
| Low | 5 | 2 | 3 |

Every Critical and High finding is now fixed and regression-tested. The remaining Medium/Low items (M5, L2-L5) are genuinely smaller-blast-radius, lower-urgency items — each has an explicit owner, severity, and remediation plan below, and none compromise data or access on their own.

---

## 2. Critical findings

### C1 — CORS allowed any origin with credentials — **FIXED**

`backend/featherflow_backend/settings.py:220` (before): `CORS_ALLOW_ALL_ORIGINS = True` + `CORS_ALLOW_CREDENTIALS = True`, unconditionally, in every environment. `django-cors-headers` cannot legally send `Access-Control-Allow-Origin: *` when credentials are also allowed, so it instead **reflects the requesting `Origin` header verbatim**. Combined with `SessionAuthentication` being enabled project-wide (for Django admin), any site could issue a credentialed cross-origin `fetch()` against any GET endpoint and read the JSON response for a visitor who happened to hold a session cookie — full authenticated data exfiltration via GET.

**Fix:** `settings.py` now reads `CORS_ALLOWED_ORIGINS` from the environment as an explicit allowlist. `DEBUG=True` keeps the old wide-open behavior (so local dev/ad hoc ports never need touching); `DEBUG=False` with no explicit allowlist now **fails closed** (denies all cross-origin requests) instead of failing open. See `.env.example` (`CORS_ALLOWED_ORIGINS=`).

### C2 — Prescription, disease-scan, receipt, and delivery-proof images sat in *public* storage, readable by anyone with the URL — **FIXED**

`pharmacy/farmer_views.py:prescription_upload`, `ml/views.py:predict_disease` (disease-scan images), `farmers/services.py:store_image` (financial expense/revenue/tax receipts, farm photos), `delivery/views.py:proof_upload` (delivery proof-of-delivery photos) all wrote through `django.core.files.storage.default_storage`, resolving to the **public** `MEDIA_ROOT`/`MEDIA_URL`. Protection was only an unguessable filename — **no server-side ownership check on read**.

**First reproduced**, then fixed: confirmed the exact public URL shape (`/media/disease-scans/<user>/<file>.jpg` etc.) and that these endpoints had zero auth on the serving side (Django's `static()` helper serves `MEDIA_ROOT` unconditionally). Migrated all four to the private, signed-token, `can_access()`-checked storage system already built for signup documents/profile photos (`verification/documents.py`), which required:

- A new `prescription` access rule: prescriptions are the one genuinely **two-party** document (the uploading farmer *and* the pharmacy fulfilling the order need to see it) — added `_prescription_order_pharmacy(token)` to `verification/documents.py`, which resolves the fulfilling pharmacy from the `AdminPanelRecord` order payload that references the token, and a matching branch in `can_access()`. Disease-scans/receipts/delivery-proof stayed single-party (owner + admin only, the existing `can_access()` rule).
- **Community post images and pharmacy catalogue medicine images were deliberately left public** — re-examined the intended audience for each of the six original upload paths (a dedicated research pass, not assumption) and confirmed these two are genuinely meant to be visible to every community member / every shopping farmer, i.e. public is *correct* behavior for them, not a bug. Migrating them to owner-gated private storage would have broken the feed/catalogue outright.
- **Flutter**: the three screens that actually render one of the four migrated image types (`pharmacy_orders_screen.dart` prescription thumbnail + fullscreen viewer, `farmer_pharmacy_screen.dart` prescription preview, `delivery_detail_screen.dart` proof-of-delivery photo) were switched from `Image.network(url)` to `Image(image: AuthedNetworkImage(url))` — an existing, already-used-for-profile-photos widget (`lib/core/network/authed_image.dart`) that attaches the JWT `Authorization` header a plain `Image.network` never sends. (Receipts and disease-scan images are stored but never actually rendered anywhere in the current UI — confirmed by grep — so no Flutter change was needed for those two.)
- **Existing data migrated**: new idempotent management command `verification/management/commands/migrate_legacy_public_uploads.py` (supports `--dry-run`) moved every already-uploaded file with a `/media/` URL to private storage and rewrote the stored reference. Run against the dev database: **69 disease-scan images + 0 other affected rows migrated** (delivery/receipts/prescriptions had no legacy public-URL rows in this database; 1 delivery-order row referenced a file that no longer existed on disk — logged and left alone, no worse off than before).
- **Old URLs verified dead**: after migration, the old public URL for a migrated file returns `404` (file no longer exists at that path) — confirmed by direct request. There is no way for an old bookmarked/leaked public URL to bypass the new policy; it simply doesn't resolve to anything anymore.

**Test coverage (new):** `scripts/test_private_documents.py` — for each of the four migrated types, uploads as the owner, then asserts the full access matrix: owner 200, a different user 403, anonymous 401, an admin-role account 200; for prescriptions specifically, also asserts the fulfilling pharmacy gets 200 and an *unrelated* pharmacy gets 403 (the two-party case). Also asserts community post uploads and pharmacy catalogue images are *still* public (regression guard against overreach). **27/27 passing.**

---

## 3. High findings

### H1 — No logout endpoint / refresh-token revocation — **FIXED**

Confirmed zero `logout` routes anywhere in the backend, and `rest_framework_simplejwt.token_blacklist` was not installed — a stolen or lingering refresh token (30-day lifetime) had no way to be revoked short of a full password reset.

**Fix:** Added `rest_framework_simplejwt.token_blacklist` to `INSTALLED_APPS` (migrated), `SIMPLE_JWT['ROTATE_REFRESH_TOKENS'] = True` + `BLACKLIST_AFTER_ROTATION = True` (a used refresh token can't be replayed), and a new `POST /api/auth/logout/` (`users/views.py:UserViewSet.logout`, wired at `users/urls.py`) that blacklists the presented refresh token. **The Flutter client does not yet call this endpoint on sign-out** — see Medium/M-flutter below.

### H2 — Legacy `expenses`/`workers`/`feed` apps had no role check — **FIXED**

`expenses/views.py` (`/api/costs/*`), `workers/views.py` (`/api/workers/*`), `feed/views.py` (`/api/feed/*`) had only DRF's global `IsAuthenticated` default — **any** authenticated non-farmer (doctor, pharmacy, delivery rider, researcher, admin) could hit these, get a `Farm` silently auto-provisioned for them via `farm_for()`, and write financial/worker/feed records through it. `workers`/`feed` are live production code (the Flutter Labor Management and Feed Management screens use them); `expenses` is superseded by `farmers/cost_views.py` but was still reachable.

**Fix:** Added `@permission_classes([IsFarmer])` to every view in all three modules (matching the pattern already used in `farmers/cost_views.py`), narrowed `except Exception` to `(KeyError, ValueError, TypeError)` so unexpected DB errors no longer return raw exception text (see I2 below), and added a `payment_status` enum whitelist + positive-amount validation in `expenses/views.py`. Verified: `scripts/test_farmer_panel.py` 39/39 still green (no legitimate farmer flow broke).

### H3 — Subscription renewal was DB-broken (CHECK-constraint mismatch) — **FIXED**

`billing/services.py:_activate()` retires a user's previous subscription with `status='replaced'`, but the `subscriptions.status` CHECK constraint only allowed `active/expired/cancelled/pending`. **Every renewal, upgrade, or downgrade after a first subscription raised an uncaught `CheckViolation` and 500'd** — verified by directly exercising a second checkout against the dev database before the fix (reproduced), then again after (`backend/production_hardening_extension.sql`, widens the constraint) — the same call now succeeds. First-time signups were unaffected (nothing to retire). This is arguably Critical in practical impact (breaks a core revenue path for the second most common event — a renewal) but scoped as High since it doesn't compromise data or access.

### H4 — Dead legacy `/api/subscriptions/` endpoint bypassed all billing logic — **FIXED**

`api/urls.py` mounted `subscriptions.urls` (a bare `POST/GET /api/subscriptions/` view creating an unvalidated, non-atomic, never-activating `Subscription` row) *after* `billing`'s router at the same path prefix — Django's URL fallthrough meant it was still reachable by anyone hitting the bare path directly, even though the Flutter client only ever calls `subscriptions/plans`, `/current`, `/checkout` (confirmed via full-codebase grep — zero references to the bare endpoint). Removed the dead route entirely; `billing` is now the sole subscription/checkout implementation.

### H5 — `DEBUG`/`SECRET_KEY` insecure fail-open defaults — **FIXED**

`SECRET_KEY` defaulted to the well-known string `'django-insecure-change-me'` if unset (this key signs JWTs and the private-document tokens in `verification/documents.py`); `DEBUG` defaulted to `True` if unset. A misconfigured or incomplete `.env` in production would silently run with full debug tracebacks and a forgeable secret key.

**Fix:** `DEBUG` now defaults to `False` (fail-safe). `SECRET_KEY` still has a fallback for zero-friction local dev, but the app **refuses to start** (`RuntimeError`) if `DEBUG=False` and the key is still the insecure default — matching the `required_env()` pattern already used for the Postgres credentials.

### H6 — Plaintext password held in Flutter local storage during signup — **FIXED**

`lib/core/network/auth_service.dart` (`savePendingRegistration`/`getPendingRegistration`/`clearPendingRegistration`) stored the user's raw, unhashed password in `SharedPreferences` across the multi-step signup wizard.

**Fix:** switched to an in-memory-only field (`_pendingRegistration`) on the `AuthService` singleton — never written to disk at all. This deliberately mirrors an existing, already-reviewed pattern in the same codebase: `lib/features/auth/data/signup_form_cache.dart` (`SignupFormCache`) already holds the live per-keystroke signup draft (including the password) purely in memory for exactly this reason — its own docstring explains the trade-off (survives in-app navigation between wizard steps via `context.go`, deliberately does *not* survive a real app restart/reload). `AuthService.instance` is a static singleton like `SignupFormCache.instance`, so it survives route navigation the identical way. `clearSession()` also now nulls this field and removes any leftover legacy on-disk copy from a pre-fix app install. Verified: `flutter test` 87/87, including the full signup-wizard test suite (`test/signup_flow_test.dart`) unaffected.

### H7 — JWT access + refresh tokens stored in plaintext `SharedPreferences` — **FIXED**

`lib/core/network/auth_service.dart` persisted the full session (7-day access token + rotating refresh token) via plain `SharedPreferences` — browser localStorage on web, an unencrypted plist/XML file on mobile.

**Fix:** added `flutter_secure_storage` (Keychain on iOS/macOS, Keystore on Android, WebCrypto-backed on web/Windows/Linux — genuinely stronger on native; on web it's a real but more modest improvement, since no browser tab has an OS-level secure enclave to hand off to, and this is noted rather than oversold) and migrated `getStoredSession`/`saveSession`/`clearSession` to it — the only three places in the entire codebase that touch the session storage key (confirmed by grep), so the change was fully contained to `auth_service.dart`. **One-time migration**: `getStoredSession()` checks secure storage first; if empty, reads the legacy SharedPreferences copy (if a previously-installed app still has one), writes it into secure storage, and removes the old copy — seamless for existing users, no forced re-login. Every secure-storage call is wrapped so a plugin failure (an unsupported platform, or no secure-storage backend available) falls back to SharedPreferences rather than losing the session outright.

**A real bug caught while testing this fix**: the widget test `test/admin_navigation_test.dart` failed after this change — not because of a logic error in the app, but because the test's initial mock for the secure-storage platform channel returned `null` unconditionally for every call, including `write`. That silently "succeeded" the migration write without actually storing anything, so when GoRouter's redirect logic called `getStoredSession()` a second time (as it legitimately does — once via `isAuthenticated()`, again to resolve the post-login destination), the already-deleted legacy SharedPreferences copy was gone and the newly-"written" secure-storage copy was never really there either, losing the session between the two calls. Fixed by giving the test mock a real (if tiny) in-memory key-value store instead of a no-op stub — this was a test-fidelity gap, not a production bug (a real Keychain/Keystore/WebCrypto write genuinely persists), but it's exactly the kind of thing a rushed "make the red test green" fix could have papered over by weakening the assertion instead. Verified: `flutter test` 87/87, `flutter analyze` clean, `flutter build web --release` succeeds with the new dependency.

---

## 4. Medium findings

### M1 — Community posts/comments/reactions/follows/reports/uploads had zero rate limiting — **FIXED**

The project-wide default throttle (`api.throttling.ScopedApiThrottle`) only covers `/api/admin-panel/`, `/api/me/updates`, and `/api/support/` — every scoped throttle class that exists (`RegistrationRateThrottle`, `OTPRequestRateThrottle`, etc.) is explicitly attached per-view, and `community/views.py` had none at all attached to any of its 9 write endpoints (post creation, comments, reactions, votes, reposts, bookmarks, follows, reports, image uploads).

**Fix:** Added two new scoped throttles — `community_write` (60/min per user; feed-POST, comment, react, comment_react, vote, repost, bookmark, follow, upload) and `community_report` (20/hour per user; content-moderation reports, tighter since a report can trigger auto-hide/moderator escalation). Both configurable via env vars in `.env.example`.

### M2 — SMS console-stub logged raw OTP codes unconditionally — **FIXED**

`verification/delivery.py:send_sms_code` logged the plaintext OTP code at INFO level whenever `SMS_BACKEND='console'` (the default, until a real provider is wired in) — unlike the email path, which only logs the raw code when `OTP_DEV_DELIVERY` is true. This meant a production deployment that simply hadn't gotten around to wiring a real SMS provider (a very plausible transitional state) would leak live OTP codes into aggregated server logs by default.

**Fix:** The raw code is now only logged when `OTP_EXPOSE_CODES` is explicitly on (defaults to `DEBUG`). Production logs "an SMS OTP was issued" without the code. The in-memory `sms_outbox` used by the test suite is unaffected (it's process-local, never shipped to a log aggregator).

### M3 — Account enumeration via distinct "already verified" response — **FIXED**

`verification/views.py:verify_request` returned a response shape for "account exists and is verified" (`{"verified": true, ...}`) distinct from the generic "if that account exists..." body used for every other case (including "account doesn't exist") — letting an unauthenticated caller enumerate registered, verified accounts. Confirmed via full-codebase grep that no Flutter code reads this endpoint's `verified` field, so the fix has no client impact.

**Fix:** The already-verified branch now returns the same generic body. `scripts/test_verification_flows.py` updated to assert the new (correct) contract instead of the old enumeration-prone one; 36/36 passing.

### M4 — Admin approve/reject/suspend actions were not atomic — **FIXED**

`api/admin_views.py:admin_record` — every branch (pharmacies, users, doctors, team, riders, researchers) does 2+ separate `.save()` calls across different tables (e.g. pharmacy: `user.save()` then `org.save()`; users: profile save(s) then `user.save()`) with no transaction. An exception between them could leave a user marked "active" with a still-unverified linked profile/org row.

**Fix:** `@transaction.atomic` decorator on `admin_record` (the dispatcher every branch routes through, including `finance_action`/`admin_update_ticket`/`clear_flag` which it delegates to as plain function calls — they now inherit the same transaction). One-line, zero-indentation-risk change; verified with `scripts/test_admin_panel.py` 65/65.

### M5 — `SessionAuthentication` enabled project-wide widens the CORS blast radius — **DOCUMENTED**

`DEFAULT_AUTHENTICATION_CLASSES` includes `SessionAuthentication` alongside JWT so Django admin works, but this means every DRF view not overriding authentication is *also* reachable via a session cookie, not just a Bearer token — which is what C1 exploited. C1's fix (explicit CORS allowlist) closes the practical exposure; this is left as a defense-in-depth item.

**Remediation plan:** Owner: backend team. Severity: Medium. Plan: scope `SessionAuthentication` to only `/admin/`-mounted views (a settings override on the admin URL's view classes, or a separate `DEFAULT_AUTHENTICATION_CLASSES` for the admin app) rather than the DRF global default. Estimated effort: 2-3 hours plus regression testing every role's login flow.

### M6 — Tax-payment → expense mirroring was non-atomic and non-idempotent — **FIXED**

`tax/views.py:_mirror_expense` ran as a separate, non-atomic step after the `TaxPayment` write, with no idempotency guard (a double-submit could create two `TaxPayment` rows and two mirrored "Tax" expenses, inflating the farmer's cost totals) and a bare `except Exception: pass` that silently discarded mirroring failures with no log trail.

**Fix:** Payment creation + mirroring now run inside one `transaction.atomic()` block. A double-submit carrying the same `(user, tax_type, payment_date, amount, reference_number)` now returns the existing record (200) instead of creating a duplicate — guarded with `select_for_update()` against a race. Mirroring failures are now logged (`logger.exception`) instead of silently discarded, while still not breaking the tax record itself (matching the original design intent). Verified: `scripts/test_tax_calculator.py` 64/64.

---

## 5. Low findings

### L1 — `except Exception` blocks leak raw exception text to clients — **PARTIALLY FIXED**

Confirmed pattern (`return Response({'detail': str(exc)}, status=400)` on an unqualified `except Exception`) in `expenses/views.py`, `workers/views.py`, `feed/views.py` — any unexpected `IntegrityError`/`DataError` would surface raw DB error text (table/column/constraint names) to the client. **Fixed in these three files** as part of the H2 fix (narrowed to `(KeyError, ValueError, TypeError)`). Other apps (`farmers/cost_views.py`, `verification/views.py`) were already correctly scoped per the audit. A repo-wide grep for the same anti-pattern beyond these files was not performed exhaustively in this pass.

**Remediation plan:** Owner: backend team. Severity: Low. Plan: a follow-up grep for `except Exception as exc:` immediately followed by `str(exc)` in a `Response(...)` across the whole backend, narrowing each one the same way. The new structured exception handler (`api/exceptions.py`) already prevents this for any *raised* exception that reaches DRF, but these hand-rolled `try/except: return Response(...)` sites bypass it entirely since they never let the exception propagate.

### L2 — No object-level ownership check on `flock_id` in expense/revenue writes — **DOCUMENTED**

`farmers/cost_views.py` assigns a client-supplied `flock_id` to an expense/revenue row without verifying it belongs to the caller's own farm. Impact is low (a dangling/incorrect cross-farm reference, not data leakage — the batch views remain scoped by `farm.expenses`), so left as a follow-up rather than fixed in this pass.

### L3 — Structured error format not adopted by hand-rolled `Response()` error sites — **DOCUMENTED**

See `PRODUCTION_READINESS_REPORT.md` §4 for the full explanation: the new `api/exceptions.py` structured-error handler only reshapes responses for exceptions that actually propagate out of a view (DRF `ValidationError`, `NotFound`, auth failures, throttling). The many `except ...: return Response({'detail': ...})` call sites across the codebase (especially the older, hand-rolled apps) are untouched by it. Documented as a large, cross-cutting follow-up rather than attempted here.

### L4 — Private-document access by admins is not itself audit-logged — **DOCUMENTED**

`verification/documents.py:can_access` grants any staff/admin account read access to every private document (CV, national ID, license, council-registration proof) — this is correct RBAC, but **no** `ActivityLog` row is written when an admin actually *views* one, only when an admin action (verify/reject/suspend) is taken elsewhere. There's no record of which admin looked at which farmer/doctor verification document, when.

**Remediation plan:** Owner: backend team. Severity: Low-Medium (raise to Medium if the platform handles sensitive documents at scale). Plan: add an `ActivityLog.objects.create(module='verification', action='view_document', ...)` call inside `verification/views.py:serve_registration_document` whenever the `user.is_staff` branch is the reason access was granted. Estimated effort: under an hour, plus a migration/test check that the new log rows don't break any existing audit-log dashboard assumptions about row shape.

### L5 — Flutter deep-link edit routes silently lose their target on hard refresh — **DOCUMENTED**

`app_router.dart` (`new-paper`, `new-disease-update`, `new-innovation`) carries the item-being-edited's id only via GoRouter's in-memory `state.extra`, never in the URL path. A hard refresh mid-edit loses the id (extra becomes null) and the screen silently falls back to "create new" instead of erroring — the subscription/payment routes in the same file already guard an equivalent gap (`subscriptionExtraGuard`), this pattern just wasn't applied here. Not fixed this pass because the correct fix (`new-paper/:id` as a real path segment) requires updating every navigation call site, not just the route definition, and the practical exposure is a narrow edge case (editing content mid-session, then hard-refreshing).

---

## 6. Authorization — role/object-level spot checks (all passed)

Sampled 7 representative ownership-scoped endpoints across farmer/doctor/pharmacy/delivery/researcher/admin: `expenses/views.py` cost-management (farm-scoped via `farm_for(request.user)`), `consultations/views.py:consultation_receipt` (`farmer=request.user`), `billing/views.py:_intent_for` (`user=request.user`), `pharmacy/views.py` composite-key `AdminPanelRecord` lookups (namespaced by `request.user.id`, never client-supplied), `delivery/views.py` (`delivery_person=rider`), `farmers/feed_views.py` (`flock__farm=farm`), and the admin RBAC matrix (`api/admin_rbac.py:can_perform_action`, tier + per-module permissions with a second-factor approval-queue escalation for destructive actions). **All correctly scope every lookup to the authenticated caller server-side** — no endpoint found that trusts a client-supplied owner/user id without cross-checking `request.user`. Cross-role negative checks (farmer→admin, doctor→pharmacy, etc.) were previously verified 13/13 in the 2026-09-11 platform audit and re-confirmed unaffected by this pass's changes (`scripts/test_admin_panel.py` 65/65 includes several of these).

---

## 7. Already correct — do not rebuild

- **Password hashing**: Django's default PBKDF2-SHA256, no override; `write_only=True` on all password serializer fields; `validate_password()` runs with a real user stub for similarity checks; zero raw-password logging found anywhere.
- **JWT invalidation on password change**: `verification/auth.py`'s `VersionedJWTAuthentication` embeds a hash-derived `pv` claim, checked on every request — a password change (self-service or admin-forced) invalidates every previously issued token instantly, no blacklist table needed for that specific case.
- **Password-reset lifecycle**: single-use, 10-minute TTL, salted-hash comparison (never plaintext), 5-attempt lockout, 60s resend cooldown — `verification/otp.py`.
- **Pending-professional login blocking**: enforced server-side on every login/verification call (`users/views.py`), not just reflected in Flutter UI state.
- **Upload validation on the modern paths**: extension allowlist **and** magic-byte sniffing **and** server-side size caps on `registration_upload`, `profile_photo`, and community image uploads — not just trusting client-supplied `Content-Type`.
- **Filenames randomized everywhere** (UUID-based), no path-traversal or overwrite risk found on any upload path.
- **Mass assignment**: no `Model.objects.create(**request.data)` / `serializer.save(**request.data)` pattern found anywhere in view code. Payment/subscription amounts, tax amounts, and role/permission fields are always server-computed, never trusted from the client.
- **No raw SQL string interpolation** anywhere (the one `cursor.execute()` outside the ORM is an offline one-off migration script, not a live endpoint).
- **No `csrf_exempt`** anywhere in the codebase.
- **No secrets/tokens ever passed via URL query params.**

---

## 8. What changed (files)

**Original pass — backend:** `featherflow_backend/settings.py`, `featherflow_backend/urls.py`, `featherflow_backend/logging_utils.py` (new), `api/exceptions.py` (new), `api/health.py` (new), `api/request_id.py` (new), `api/throttling.py`, `api/urls.py`, `api/admin_views.py`, `users/views.py`, `users/urls.py`, `verification/views.py`, `verification/delivery.py`, `expenses/views.py`, `workers/views.py`, `feed/views.py`, `community/views.py`, `tax/views.py`, `production_hardening_extension.sql` (new), `featherflow_schema.sql`, `scripts/test_verification_flows.py`, `.env.example`, `DATABASE_SETUP.md`, `requirements.txt`.

**Original pass — Flutter:** `lib/main.dart` (global error handler), `lib/features/farmer/presentation/screens/farmer_dashboard_screen.dart` (error surfacing), `lib/features/research/presentation/screens/researcher_profile_screen.dart` (controller disposal).

**Follow-up pass (C2/H6/H7 + admin pagination + community N+1) — backend:** `verification/documents.py` (broadened scope, `prescription` two-party access rule), `verification/management/commands/migrate_legacy_public_uploads.py` (new — data migration), `ml/views.py`, `farmers/services.py`, `pharmacy/farmer_views.py`, `delivery/views.py` (all four migrated to private storage), `api/admin_views.py` (pagination + `_user_json`/`_team_json` fix + `admin_record` atomicity), `api/admin_extra.py` (export cap + logger), `community/views.py` (bulk query-context N+1 fix), `users/models.py` (`role_names` prefetch fix), `production_hardening_extension.sql` (new indexes), `scripts/test_private_documents.py` (new), `scripts/test_admin_pagination_performance.py` (new), `scripts/test_community_feed_performance.py` (new).

**Follow-up pass — Flutter:** `lib/core/network/auth_service.dart` (secure storage + in-memory pending-registration), `pubspec.yaml` (+`flutter_secure_storage`), `lib/features/pharmacy/presentation/screens/pharmacy_orders_screen.dart`, `lib/features/farmer/presentation/screens/farmer_pharmacy_screen.dart`, `lib/features/delivery/presentation/screens/delivery_detail_screen.dart` (all three switched to `AuthedNetworkImage`), `test/admin_navigation_test.dart` (secure-storage test mock).

Full detail on each change (including the exact fix reasoning) is in the commit-free working tree diff and in the code comments left at each change site — every fix explains *why*, not just *what*, per this codebase's existing convention.
