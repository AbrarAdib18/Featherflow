# FeatherFlow — Signup & Registration Audit Report

**Status: COMPLETE** — audit + repair (pass 1) and OTP verification / password reset / private
document access control (pass 2) done; automated + API end-to-end tests green; GUI boot-smoked.
Date: 2026-09-10
Backend: Django 6 + DRF + SimpleJWT, PostgreSQL (unmanaged models over `featherflow_schema.sql`)
Frontend: Flutter 3.47 (`go_router`) — Windows desktop / Web / Android

> **Pass 2 (this update)** closes the three gaps §10 flagged as "not done": email/phone
> OTP verification wired into every signup flow, self-service password reset, and
> access-controlled storage for uploaded signup documents. See **§15**.

---

## 0. Headline numbers

| | |
|---|---|
| Signup flows discovered | **8** (6 role flows + shared 2-step wizard) + 1 dead legacy screen |
| Flows repaired & tested | **6/6** role flows (farmer, doctor, pharmacy, delivery, researcher, admin) |
| Automated tests added | `backend/scripts/test_signup_flows.py` — **88 assertions**; `backend/scripts/test_verification_flows.py` — **36 assertions**; `test/signup_flow_test.dart` (11) + `test/verification_flow_test.dart` (8) widget tests |
| Backend test result | signup 88/88 ✅ · verification 36/36 ✅ · farmer 35/35 ✅ · doctor 58/58 ✅ · admin 64/65 (1 pre-existing unrelated shift-timer failure) · community 56/56 ✅ · articles 28/28 ✅ · vets 12/12 ✅ · disease 25/25 ✅ |
| Flutter test result | **41/41 ✅** (`flutter test`) |
| Flutter analyze | **0 issues in signup / verification code** (7 pre-existing issues elsewhere in `lib/features/admin/`) |
| Production build | `flutter build web --release` ✅ · `flutter run -d windows` boots clean ✅ |
| Issues found (pass 1) | Critical **4** · High **7** · Medium **8** — all fixed |
| Gaps closed (pass 2) | Email + phone OTP · self-service password reset · private document access control |
| Beta-ready? | **Yes for the signup surface.** Production still needs: real SMTP + (optional) SMS provider, `OTP_EXPOSE_CODES=False`, a shared cache (Redis) for multi-worker deploys — see §15.5 |

---

## 1. Signup flows discovered

| # | Role | Screen | Route | Backend endpoint | Status after signup | Login before approval |
|---|------|--------|-------|------------------|---------------------|----------------------|
| 1 | Basic info (wizard step 1) | `lib/features/auth/presentation/screens/signup_screen.dart` | `/signup` | — (local cache) | — | — |
| 2 | Role selection (wizard step 2) | `role_selection_screen.dart` | `/role-selection` | — | — | — |
| 3 | Farmer | `farmer_signup_screen.dart` | `/signup/farmer` | `POST /api/auth/register/` role=farmer | **active** | n/a — signs in immediately |
| 4 | Veterinarian / Doctor | `doctor_signup_screen.dart` | `/signup/doctor` | " role=doctor | **pending** → admin verify | blocked (403 + reason) |
| 5 | Pharmacy | `pharmacy_signup_screen.dart` | `/signup/pharmacy` | " role=pharmacy | **pending** → admin verify | blocked |
| 6 | Delivery rider | `delivery_signup_screen.dart` | `/signup/delivery` | " role=delivery | **pending** → admin approve | blocked |
| 7 | Researcher | `researcher_signup_screen.dart` | `/signup/researcher` | " role=researcher | **pending** → admin verify | blocked |
| 8 | Admin (self-registration) | `admin_signup_screen.dart` | `/signup/admin` | " role=admin | **pending** + `AdminProfile.approval_status=pending`, cannot mint `admin_super` | blocked |
| — | Registration document upload | (new) | `/signup/pending` (result screen) | `POST /api/auth/registration-upload/` | — | — |
| — | Login | `login_screen.dart` | `/login` | `POST /api/auth/login/` | — | — |
| — | Onboarding carousel | `onboarding_screen.dart` | `/onboarding` | — | — | — |
| — | `role_details_screen.dart` (1304 lines) | **DEAD CODE** — not imported/routed anywhere. Left in place (not deleted) per "do not replace blindly"; flagged for removal. | — | — | — | — |

No email/phone verification, OTP, password-reset, or invitation flow exists anywhere in the codebase (see §10).
`lib/features/paper_portal/` has no signup.

## 2. How auth works (as understood before editing)

- `users.User` — unmanaged model over the `users` table; UUID pk, `email`/`phone`/`national_id_number` unique, `password` → `password_hash` column, `account_status` (`pending`/`active`/`suspended`/`rejected`), `is_verified`, `consent_terms`. `is_active` property ⇒ `account_status == 'active'`.
- `Role` / `UserRole` — M2M; role names `farmer|doctor|delivery|pharmacy|researcher` + `admin_super|admin_operations|admin_finance|admin_content|admin_research|admin_delivery|admin_pharmacy|admin_doctor|admin_support|admin_team`.
- Auth backend = Django default `ModelBackend` ⇒ `authenticate()` rejects non-active users. `rest_framework_simplejwt` `JWTAuthentication` also rejects tokens for non-active users on every request.
- Role profiles: `FarmerProfile`, `DoctorProfile`, `PharmacyOrganization`, `DeliveryProfile`, `ResearcherProfile`, `AdminProfile` (all `OneToOne` to `User`, unmanaged). Verification signals: `DoctorProfile.is_verified`, `ResearcherProfile.is_verified`, `PharmacyOrganization.is_verified`, `DeliveryProfile.approved_by_admin`, `AdminProfile.approval_status`.
- Admin approval surface **already existed**: `api/admin_views.py::admin_record` for `users`/`doctors`/`pharmacies`/`riders`, `api/admin_extra.py` for `AdminProfile`. It flips `account_status`/`is_verified` on approve.
- Flutter: `AuthService` (singleton `ChangeNotifier`) holds the session in `SharedPreferences`; `app_router.dart::_redirect` gates non-public routes on `isAuthenticated()` and bounces revoked users.
- Throttling: `api/throttling.py::ScopedApiThrottle` was applied globally but only rate-limited `/api/admin-panel/…`, `/api/me/updates`, `/api/support/`.

## 3. Bugs found

### Critical
| # | Bug | Evidence |
|---|-----|----------|
| C1 | **Approval bypass** — doctor/pharmacy/delivery/researcher self-registration set `account_status='active'` and returned JWTs immediately, contradicting the doctor screen's "an administrator must approve…" copy and every admin verification panel. | Live: `POST /register/ role=doctor role_data={}` → `account_status:"active"` + `access` token. |
| C2 | **Fabricated professional credentials** — with empty/partial `role_data` the serializer invented `license_number="PENDING-<uuid>"`, `veterinary_degree="Veterinary degree"`, `university_name="Not provided"`, `graduation_year=<year>`, `business_registration_number="PENDING-<uuid>"`, `drivers_license_number="PENDING-<uuid>"`, etc. A registrant could mint a "licensed" vet/pharmacy/rider with zero real data. | `users/serializers.py` old `create()`. |
| C3 | **No rate limiting** on `/api/auth/register/` or `/api/auth/login/` — mass account creation and credential stuffing unthrottled. | `api/throttling.py` prefix list. |
| C4 | **Tokens issued to pending accounts** — `create()` returned `access`/`refresh` even for `pending`; Flutter saved that session and routed to a dashboard, then every request 401'd (SimpleJWT `is_active` rule) ⇒ broken half-logged-in state. | `users/views.py` old `create()`. |

### High
| # | Bug |
|---|-----|
| H1 | **No submit-in-progress guard** on 6 of 7 signup screens — button stayed enabled during the request; rapid taps → multiple `POST /register/`. |
| H2 | **Every document/photo upload was dead** — `_UploadButton` / "Upload Photo" had `onTap: () {}`. `file_picker` was in `pubspec` but unused in auth. No upload endpoint existed. Required-marked upload fields collected nothing. |
| H3 | **Terms/consent faked** — `auth_service.register()` hardcoded `consent_terms: true`. Step-1 screen had **no** Terms/Privacy checkbox. |
| H4 | **role_data silently dropped** — Delivery: `vehicle_type/registration/insurance/emergency_contact/banking_details` sent, read by nothing (no vehicle model). Admin: step-3 "Strong Password" field never sent; `access_level` free-text → never matched the valid set → always fell back to `support`; `2fa_contact`, `reporting_manager`, `approved_by_*` unused. Doctor: `referral_channel` sent, unread. |
| H5 | **Step-1 data loss** — NID/Passport (marked required) + emergency contact + language collected but `savePendingRegistration()` persisted only email/password/phone/name/address/DOB. |
| H6 | **Login gave no account-state feedback** — a pending professional got a generic `401 Invalid credentials`. |
| H7 | **`riders` admin-approve did not activate the user** — set `approved_by_admin` but never flipped `account_status` pending→active, so an approved rider still couldn't sign in (latent; became live once C1 was fixed). Same gap for `PharmacyOrganization.is_verified` on the `pharmacies` approve path. |

### Medium
| # | Bug |
|---|-----|
| M1 | Password rules inconsistent: signup UI ≥8, login UI ≥6, admin UI hint claimed "upper, lower, number, symbol" but backend enforces only ≥8 + not-all-numeric + not-common + not-user-similar. |
| M2 | Email not normalized/trimmed server-side before the uniqueness check. |
| M3 | Numeric fields validated only as "not empty" on the client; non-numeric text coerced to `0` server-side. |
| M4 | `UserSerializer.get_profile_data` returned the entire role-profile row. |
| M5 | Hardcoded dev credentials prefilled in `login_screen` (`user@gmail.com` / `user`). |
| M6 | "Forgot password?" button was `onPressed: () {}` (dead). |
| M7 | Inconsistent post-signup UX — farmer/delivery/pharmacy/researcher said "…Please sign in" then `context.go('/login')` while already holding a session; doctor said "must be approved" but was actually active. No dedicated pending screen. |
| M8 | Back navigation from a partly-filled role form silently discarded input. |
| M9 (extra) | `seed_platform_demo.py` created farmers/riders/pharmacies/researchers with **no** role-profile row, no `admin_super`, no `AdminProfile` rows. |

## 4. Bugs fixed

| Area | File(s) | Fix |
|------|---------|-----|
| C1, C4, H6, M7 | `users/serializers.py`, `users/views.py` | Farmer → `active`; doctor/pharmacy/delivery/researcher/admin → `pending`. `create()` issues tokens **only** for active accounts; for pending it returns `201 {user, detail, next:"pending_approval", account_status}` and no tokens. `login()` distinguishes "correct password but pending/suspended/rejected" → `403` with a specific reason, vs `401` for bad credentials. Flutter routes pending signups to a new `RegistrationPendingScreen` and active ones to their dashboard. |
| C2, M3 | `users/serializers.py` | Rewrote `UserRegistrationSerializer`: per-role required-field table (`REQUIRED_ROLE_FIELDS`), blank/whitespace-only rejected, `400 {"role_data": {field: message}}`. No more fabricated credentials — required professional fields must be supplied. Numeric fields (`graduation_year`, `years_experience`, …) raise a field error on non-numeric input instead of coercing to 0. |
| C3 | `api/throttling.py`, `settings.py`, `users/views.py` | `RegistrationRateThrottle` (`10/hour`), `LoginRateThrottle` (`20/min`), `RegistrationUploadRateThrottle` (`30/hour`) — anon, IP-scoped, env-overridable. |
| H1 | all 6 role screens + `signup_widgets.dart` | `SignupSubmitButton` with a `submitting` flag: shows a spinner, disables the button, and `_onSubmit` early-returns while a request is in flight. `finally` always clears the flag. |
| H2 | `users/views.py` (`registration_upload`), `users/urls.py`, `signup_widgets.dart::SignupUploadField` | New `POST /api/auth/registration-upload/` (anon, throttled): validates JPG/PNG/WebP/PDF + 5 MB + MIME, stores under `media/registration/<kind>/`, returns a URL. Client `SignupUploadField` picks a file (`file_picker`), validates type/size locally, uploads immediately, shows the filename, supports **replace** and **remove**, surfaces upload errors inline. Wired to the critical doc per role (council proof, license photo, pharmacy licence, CV) + optional photos/certs; heavier certificates deferred to profile completion per decision. |
| H3, H5, M1 | `signup_screen.dart`, `auth_service.dart` | Terms of Service + Privacy Policy consent **checkbox on step 1**, required (error state, blocks "Next"). NID, emergency contact, language and the consent flag now persist through `savePendingRegistration` and are forwarded to `register()`. `consent_terms` validated server-side (`validate_consent_terms`). |
| H4 | `admin_signup_screen.dart`, `users/serializers.py` | Admin "Access Level Requested" is now a **dropdown** of the 8 real admin sub-roles (Super excluded) → maps 1:1 to `admin_<sub_role>`. Employment type → dropdown. Dead "Strong Password" field removed (password is set in step 1). "Approved By" required fields relaxed to an optional "Referral". Delivery vehicle + banking details are now persisted (vehicle → `DeliveryProfile.availability_schedule.vehicle`, banking → `User.bank_mobile_payment_details.settlement`). |
| H7 | `api/admin_views.py` | `riders` approve now also sets `user.account_status='active'`. `pharmacies` approve now also sets `PharmacyOrganization.is_verified` + `approved_by_admin`. |
| M2 | `users/serializers.py` | `normalize_email` (lower + strip) applied before the case-insensitive uniqueness check; `full_name` whitespace-collapsed + length-bounded (2–120); `present_address` trimmed + min length; phone normalized to canonical `+8801XXXXXXXXX` (`normalize_bd_phone`) or `400`. |
| M5, M6 | `login_screen.dart` | Removed hardcoded credential prefill. "Forgot password?" now opens a dialog explaining self-service reset is unavailable and to contact support (no reset backend exists — see §10). Added a missing `mounted` guard in `_restoreSession`. |
| M8 | all 6 role screens + `signup_widgets.dart::confirmDiscardSignup` | `PopScope(canPop:false)` + a "Discard this form?" confirm dialog on every back affordance (app-bar arrow, bottom link, system back). |
| Duplicates | `users/serializers.py`, `users/views.py` | Duplicate email/phone/NID → `409 DuplicateAccount` with a field-specific message (was a generic `400`). Repeating an identical payload → one user, one profile, second call `409`. |
| Transaction safety | `users/serializers.py` | `create()` is `@transaction.atomic`; verified by test — a forced failure inside the role-profile builder rolls back the `User` row and any `Farm`/profile rows. |
| Client error display | `auth_service.dart` | `_errorFrom` parses DRF nested errors (`role_data.<field>`) into a `Map<String,String> fieldErrors` + a readable multi-line message; 5-second SnackBars; 409 phrased as a conflict. |
| Demo data (M9) | `users/management/commands/seed_platform_demo.py` | Rewrote — every role gets its real profile row(s); `admin_super` + one admin per tier + one **pending** applicant per professional role; idempotent (`update_or_create` on `user`/`email`, distinct demo identifiers). |

## 5. Validation rules by role (as implemented — backend authoritative)

**Common (all roles)** — email required, normalized to lowercase + trimmed, valid format, unique (`409`); full name 2–120 chars, whitespace-collapsed; phone normalized to `+8801[3-9]XXXXXXXX` (accepts `01…`, `880…`, `+880…`, spaces/dashes) or `400`, unique (`409`); present address ≥4 chars trimmed; DOB required (client enforces 16–85 yrs via the picker bounds); password via Django validators (min 8, not all-numeric, not common, not similar to email/name); `password == password2`; `consent_terms` must be `true`; NID optional, unique if given (`409`); unknown role → `400`.

| Role | Required `role_data` | Notes |
|------|----------------------|-------|
| Farmer | `farm_name`, `farm_location` | others optional; primary `Farm` row auto-created; farm photo optional upload |
| Doctor | `clinic_name`, `practice_address`, `degree`, `university`, `graduation_year`(int), `license_number`, `issuing_authority`, `license_expiry`(date), `specialty`, `years_experience`(int) | `license_number` unique on `DoctorProfile`; council-registration proof upload required client-side; CV + photo optional |
| Pharmacy | `business_name`, `contact_person`, `business_reg_number`, `tax_number`, `business_address` | `business_reg_number` unique; pharmacy-licence upload required client-side; biz-reg + pharmacist certs optional |
| Delivery | `license_number`, `license_class`, `license_expiry`(date), `vehicle_type`, `vehicle_registration`, `area_coverage` | `drivers_license_number` unique; licence-photo upload required client-side; vehicle/banking stored on JSON columns |
| Researcher | `institution`, `department`, `degree`, `field_of_study`, `university`, `graduation_year`(int), `years_experience`(int), `areas_of_expertise` | CV upload required client-side; ethics cert optional |
| Admin | `job_title`, `department`, `start_date`(date), `access_level` (one of 8 sub-roles, Super excluded) | `2FA contact` required client-side; CV optional; cannot self-mint `admin_super` (server-enforced) |

## 6. Verification & approval behaviour by role

| Role | On signup | Tokens? | Can sign in? | Cleared by | Rejected → |
|------|-----------|---------|--------------|------------|-----------|
| Farmer | `active`, `is_verified=false` | yes | immediately | — | — |
| Doctor | `pending`, `DoctorProfile.is_verified=false`, `is_available=false` | no | after admin sets status **Verified** (`PATCH /api/admin-panel/doctors/<id>/`) → `account_status='active'` | Admin → Doctors | status **Suspended/Rejected** → `account_status='suspended'`; login → `403` "not approved. Contact support." Re-application uses the same screen (new email or admin re-activates). |
| Pharmacy | `pending`, `PharmacyOrganization.is_verified=false` | no | after admin status **Verified** (`PATCH /api/admin-panel/pharmacies/<id>/`) | Admin → Pharmacy | status **Suspended** → suspended |
| Delivery | `pending`, `DeliveryProfile.approved_by_admin=NULL` | no | after admin `action:"approve"` (`PATCH /api/admin-panel/riders/<id>/`) → also sets `account_status='active'` | Admin → Delivery | `action:"suspend"` → suspended |
| Researcher | `pending`, `ResearcherProfile.is_verified=false` | no | after admin status **Approved** (`PATCH /api/admin-panel/users/<id>/`) | Admin → Research | status **Suspended** → suspended |
| Admin | `pending`, `AdminProfile.approval_status='pending'`, `is_active=false`, specific `admin_<sub_role>` role attached, Ops+Super notified | no | after Ops/Super approve (`api/admin_extra.py` admin-registration decision) → `approval_status='approved'`, `account_status='active'` | Admin → Admins / Approvals | rejected → `account_status='suspended'` |

The pending user sees a dedicated **"Application submitted"** screen with the role-specific reason and a "Back to sign in" button. Login while pending returns a plain-language `403`.

**OTP / verification-code flows:** not applicable — the product has no code-based verification. All "verification code / expired code / resend cooldown / already-used code" test cases are **N/A** and documented as such (§10).

## 7. Security findings & resolution

| Finding | Status |
|---------|--------|
| No signup/login rate limiting (C3) | **Fixed** — anon throttles on register / login / upload. |
| Approval bypass for professionals (C1) | **Fixed** — pending status + login gate + JWTs withheld. |
| Fabricated credentials (C2) | **Fixed** — real required fields enforced. |
| Self-assign `admin_super` | **Was already blocked**; verified by test (`test_admin_escalation`). Access-level handling tightened to a fixed dropdown. |
| Role escalation via payload (`role`, `role_data`) | Verified — `role` restricted to `PUBLIC_ROLES`; `admin` always lands `pending`/`is_active=false`; no field lets a client set `account_status`, `is_verified`, `approval_status`, or `roles`. |
| Passwords in logs / responses | Verified — `password`/`password2` are `write_only`; `_record_login_attempt` logs only `{email, success}`; error messages never echo the password. `UserSerializer` has no password field. |
| Private documents public | Uploads land in `MEDIA_ROOT/registration/` served by Django's dev static handler in `DEBUG`. **Beta note:** put `media/` behind auth or signed URLs before production; filenames are unguessable (uuid) but not access-controlled. |
| Upload abuse (anon endpoint) | Mitigated — strict type/size/MIME validation + `30/hour` per-IP throttle + `kind` allow-list. |
| XSS via names / org fields | API is JSON-only; Flutter renders text, not HTML. No server-side templating of user input in the signup path. |
| SQL injection | All queries are ORM; no raw SQL in the signup path. |
| Excessive PII in responses | `UserSerializer` returns the caller's own record only (`retrieve` gates non-self/non-staff); registration response omits tokens for pending accounts. |
| CORS / CSRF | `CORS_ALLOW_ALL_ORIGINS=True` + `CORS_ALLOW_CREDENTIALS=True` — **dev-only; tighten for production.** JWT-in-header API has no CSRF exposure. |
| JWT lifetime | Access token 7 days — long; flagged for production review (not changed to avoid destabilising existing sessions/tests). |

## 8. Automated test results

### Backend — `backend/venv/Scripts/python.exe backend/scripts/test_signup_flows.py`
**80 passed, 0 failed.** Covers, per role: valid signup; blank/over-long name; invalid email; invalid phone; weak password; all-numeric password; mismatched passwords; terms not accepted; missing per-role required fields (and the error names them); non-numeric numeric field; whitespace-only required field; email case/space normalization; duplicate email → 409; duplicate phone → 409; idempotent double-submit → 201 then 409 (one user, one profile); invalid role → 400; **admin `access_level:"super"` → downgraded, never `admin_super`, lands pending+inactive**; document upload valid PNG/PDF → 201, disallowed type → 400, oversized → 400, missing file → 400, PDF-as-photo → 400, unknown kind → 400, uploaded URL persists on the profile; **transaction rollback** (forced profile failure → no user, no profile); **pending → login 403 (reason shown) → wrong-password 401 (distinct) → admin verifies → account active + profile verified → login 200 + tokens**; rejected/suspended applicant → login 403; farmer cannot open `/api/admin-panel/dashboard/`; farmer can read `/api/auth/me/`.

### Backend regression
`test_farmer_panel` 35/35 ✅ · `test_doctor_flow` 58/58 ✅ · `test_community` 56/56 ✅ · `test_articles_feed` 28/28 ✅ · `test_vets_nearby` 12/12 ✅ · `test_disease_detection` 25/25 ✅ · `test_admin_panel` 64/65 — the 1 failure ("live elapsed = 3h worked − 0.5h break = 2.5h") is a **pre-existing, timing-dependent shift-timer calculation** unrelated to signup (confirmed: it fails identically with all signup changes `git stash`ed).

### Frontend — `flutter test`
**33 passed, 0 failed**, incl. the new `test/signup_flow_test.dart` (11): every signup screen builds with a `SignupSubmitButton`; step-1 shows the Terms checkbox; "Next" is blocked until Terms are accepted; **rapid double-tap on the farmer submit button does not desync or throw and the button recovers after the failed call**; `RegistrationPendingScreen` shows the message + return link.

### Static / build
`flutter analyze` — 0 issues in `lib/core/network/`, `lib/core/router/`, `lib/features/auth/` (7 pre-existing issues remain in `lib/features/admin/`, untouched). `flutter build web --release` ✅. `python manage.py check` ✅ (0 issues).

## 9. Manual / end-to-end test results

- **API end-to-end** against a live `runserver` (curl + Django test `Client`): every role registered, every validation branch exercised, the full pending→approve→login lifecycle walked with a seeded `admin_super`. Results as §8.
- **GUI smoke:** `flutter run -d windows` — the Windows desktop app **builds and boots cleanly** to the login screen with no exceptions in the run log; `flutter build web --release` produces `build/web`. Screen-by-screen click-through of the Windows GUI could not be captured as screenshots in this environment (`flutter screenshot` SKP capture is incompatible with Impeller on Windows — a Flutter tooling limitation, not an app bug); the per-screen build + interaction behaviour is instead covered by the 11 widget tests.
- No console/network errors, duplicate requests, or unhandled exceptions observed during the API runs (server log clean apart from the intentional 400/401/403/409 responses the tests assert).

## 10. Remaining known issues / gaps

| Item | Severity | Note |
|------|----------|------|
| ~~No email or phone verification / OTP~~ | — | **DONE in pass 2 — see §15.1.** Email OTP is a hard gate on every signup + login; phone OTP is implemented and opt-in (`SIGNUP_REQUIRE_PHONE_VERIFICATION`). |
| ~~No self-service password reset~~ | — | **DONE in pass 2 — see §15.2.** "Forgot password?" now runs a full email-code reset with server-side session invalidation. |
| ~~Uploaded registration docs are not access-controlled~~ | — | **DONE in pass 2 — see §15.3.** Docs are stored outside `MEDIA_URL` and served only through an access-checked endpoint. |
| Real SMTP / SMS provider not configured | Medium (prod) | Email uses Django's console backend in dev; SMS uses a logging stub. Plug in real providers before production — see §15.5. |
| `role_details_screen.dart` (1304 lines) is dead code | Low | Left in place; safe to delete. |
| Researcher screen still shows a "Phone Number" field that isn't sent (step-1 phone is used) | Low | Cosmetic; the field is now non-blocking. |
| Doctor screen's `referral_network` / `prescription_authority` / `emergency_on_call` text fields are collected but not sent on signup | Low | These are editable later in the doctor profile; not required by the model. |
| `CORS_ALLOW_ALL_ORIGINS`, 7-day JWT | Low (dev) | Tighten for production deployment. |
| `test_admin_panel` shift-timer test flaky | Low | Pre-existing, unrelated to signup. |

## 11. Demo-account instructions

Run once (idempotent, safe to re-run):

```powershell
cd backend
venv\Scripts\python.exe manage.py seed_platform_demo
```

All demo accounts share the password **`FeatherflowDemo@2026`** (documented local-dev convention; no real secret).

| Email | Role | State — use it to test |
|-------|------|------------------------|
| `farmer.rashed@example.com` / `farmer.nasima@example.com` | Farmer | active — sign in straight to the farmer dashboard |
| `dr.samira.rahman@example.com` | Doctor | **verified/active** — signs in |
| `dr.pending.kabir@example.com` | Doctor | **pending** — login → 403; approve at Admin → Doctors, then it signs in |
| `pharmacy.greenvet@example.com` | Pharmacy | verified/active |
| `pharmacy.pending.agrocare@example.com` | Pharmacy | pending — approve at Admin → Pharmacy |
| `rider.arif@example.com` | Delivery | approved/active |
| `rider.pending.belal@example.com` | Delivery | pending — `action:"approve"` at Admin → Delivery |
| `research.fariha@example.com` | Researcher | verified/active |
| `research.pending.mahmud@example.com` | Researcher | pending — approve at Admin → Research (Users) |
| `admin.super@example.com` | admin_super | owner — approves everything |
| `ops.nusrat@example.com` | admin_operations | approved |
| `finance.tanvir@example.com` | admin_finance | approved |
| `support.raisa@example.com` | admin_support | approved |
| `admin.pending@example.com` | admin_support | **pending** — approve via Admin → Admins / Approvals |

## 12. Exact commands

```powershell
# ── backend: one-time setup for pass 2 ───────────────────────────────
cd backend
psql "$env:DATABASE_URL" -f verification_extension.sql       # users.email_verified_at / phone_verified_at
venv\Scripts\python.exe manage.py migrate users              # records state migration 0003
venv\Scripts\python.exe manage.py backfill_contact_verification   # existing accounts -> verified (REQUIRED)
venv\Scripts\python.exe manage.py check
venv\Scripts\python.exe manage.py seed_platform_demo
venv\Scripts\python.exe manage.py runserver 127.0.0.1:8000   # or: uvicorn featherflow_backend.asgi:application --port 8000

# end-to-end suites (need the DB; start their own throw-away accounts)
venv\Scripts\python.exe scripts\test_signup_flows.py         # 88 assertions
venv\Scripts\python.exe scripts\test_verification_flows.py   # 36 assertions — OTP, reset, doc access

# regression
venv\Scripts\python.exe scripts\test_farmer_panel.py
venv\Scripts\python.exe scripts\test_doctor_flow.py
venv\Scripts\python.exe scripts\test_admin_panel.py

# ── frontend ─────────────────────────────────────────────────────────
cd ..
flutter analyze
flutter test                                  # 41 tests
flutter test test/signup_flow_test.dart test/verification_flow_test.dart
flutter run -d windows                         # GUI smoke (backend must be running on :8000)
flutter build web --release                    # production build
```

## 13. Files changed

**Backend**
- `backend/users/serializers.py` — registration serializer rewrite (validation, normalization, no fabrication, pending status, 409 conflicts, atomic profile builders per role)
- `backend/users/views.py` — conditional token issue, account-state-aware login, `registration_upload` endpoint, throttle wiring
- `backend/users/urls.py` — `registration-upload/` route
- `backend/api/throttling.py` — `RegistrationRateThrottle`, `LoginRateThrottle`, `RegistrationUploadRateThrottle`
- `backend/featherflow_backend/settings.py` — `auth_register` / `auth_login` / `auth_upload` throttle rates
- `backend/api/admin_views.py` — rider approve activates the user; pharmacy approve sets `is_verified`
- `backend/users/management/commands/seed_platform_demo.py` — full rewrite with real profile rows + pending variants + admin_super
- `backend/scripts/test_signup_flows.py` — **new**, 80-assertion E2E suite

**Frontend**
- `lib/core/network/auth_service.dart` — `RegistrationResult`, field-error parsing, `uploadRegistrationDoc`, consent/NID/emergency/photo pass-through
- `lib/core/router/app_router.dart` — `registrationPending` route
- `lib/features/auth/presentation/widgets/signup_widgets.dart` — **new** — `SignupSubmitButton`, `SignupUploadField`, `RegistrationPendingScreen`, `confirmDiscardSignup`
- `lib/features/auth/presentation/screens/signup_screen.dart` — Terms/Privacy consent, persist NID/emergency/language
- `lib/features/auth/presentation/screens/{farmer,doctor,delivery,pharmacy,researcher,admin}_signup_screen.dart` — submit guard, real uploads, pending navigation, discard-confirm, structured errors; admin: access-level + employment-type dropdowns, dead password field removed
- `lib/features/auth/presentation/screens/login_screen.dart` — removed hardcoded creds, wired "Forgot password?", `mounted` guard
- `test/signup_flow_test.dart` — **new**, 11 widget tests

## 14. Beta-deployment readiness

**The signup/registration surface is ready for beta.** Every discovered role flow has been repaired to a consistent standard, is covered by automated tests (88 + 36 API assertions + 19 widget tests, all green), and the verify → pending → approve → login lifecycle works end to end against a live server with the seeded demo accounts. Pass 2 added email/phone OTP, self-service password reset, and private document storage.

Before **public** beta: configure real SMTP (and SMS if you enable phone verification), set `OTP_EXPOSE_CODES=False`, point `CACHES` at Redis if you run more than one worker, tighten `CORS_ALLOW_ALL_ORIGINS`, and shorten the JWT lifetime. See §15.5.

---

## 15. Verification, password reset, and document access (pass 2)

New app: **`backend/verification/`** — `otp.py` (cache-backed code lifecycle),
`delivery.py` (provider-agnostic email/SMS senders), `auth.py`
(`VersionedJWTAuthentication` + `tokens_for`), `documents.py` (private storage +
ownership resolution), `views.py`, `urls.py`. One schema change:
`verification_extension.sql` adds `users.email_verified_at` / `phone_verified_at`
(nullable). Codes are **not** in the database — they live in Django's cache with
a 10-minute TTL.

### 15.1 Email / phone OTP

**Model.** Every account is created exactly as before (§5–6: farmer `active`,
professionals `pending`). On top of that, `users.email_verified_at` /
`phone_verified_at` record when the *account owner* proved control of that
channel. This is **orthogonal** to `is_verified` / admin approval — it is a
separate gate, not a status change.

**Per role.**

| Role | Email OTP | Phone OTP | Effect |
|------|-----------|-----------|--------|
| Farmer | **required** (gate) | implemented, opt-in | Must confirm the email code before the first session is issued. Account is still `active` in the DB immediately. |
| Doctor / Pharmacy / Delivery / Researcher / Admin | **required** (gate) | implemented, opt-in | Must confirm the email code; then still `pending` admin review. A pending professional can complete email OTP even though they cannot log in yet. |

Phone verification is fully built (endpoints, SMS stub, lockout, UI) but only
becomes a hard gate when `SIGNUP_REQUIRE_PHONE_VERIFICATION=True` (default
`False`, because it needs a real SMS provider). `SIGNUP_REQUIRE_EMAIL_VERIFICATION`
(default `True`) can disable the email gate too — the flow then falls back to
pass-1 behaviour.

**Protections** (`verification/otp.py`): 6-digit code; **10-minute expiry**;
**60-second resend cooldown**; **max 5 resends** per code lifecycle; **5 wrong
guesses → 15-minute lockout** of that identity; **single-use** (the code is
deleted from the cache on success, so replay returns "request a code first").
Per-IP DRF throttles on top: `otp_request` 15/h, `otp_confirm` 30/h.

**Endpoints** (all `AllowAny`, all under `/api/auth/`):

| Method + path | Body | Success | Errors |
|---|---|---|---|
| `POST /verify/request/` | `{email, channel?: "email"\|"phone"}` | `200 {detail, channel, resend_cooldown, expires_in, debug_code?}` | `429 {detail, retry_after}` on cooldown / ceiling; `200` generic for unknown email (no enumeration); `200 {verified:true}` if already verified; `503` if `channel=phone` and no SMS backend |
| `POST /verify/confirm/` | `{email, channel, code}` | `200 {user, access, refresh, next:"dashboard"}` (active) · `403 {next:"pending_approval", …}` (awaiting review) · `403 {next:"verify_phone"}` (phone still required) | `400 {code:"wrong"\|"expired"\|"no_code"}` · `429 {code:"locked"}` |

`POST /register/` and `POST /login/` now return `403 {next:"verify_email",
email, channel, resend_cooldown, debug_code?}` whenever the account's email is
unverified. The client routes to the OTP screen and can resend from there.

`debug_code` is only present when `OTP_EXPOSE_CODES` is true (defaults to
`DEBUG`) — it auto-fills the code field for local QA and is what the automated
tests read. **Set `OTP_EXPOSE_CODES=False` in production.**

**Frontend.** New `lib/features/auth/presentation/screens/otp_verification_screen.dart`
(`OtpVerificationScreen` + `OtpCodeField`): six-digit input, auto-submit on the
6th digit, live resend countdown, inline error states, "Resend code", "Back to
sign in". Route `/verify` (public). Every signup screen and the login screen now
funnel through `routeAfterRegistration()` / the `verify_email` catch, so the
verification step is unavoidable and consistent.

### 15.2 Self-service password reset

**Endpoints** (`AllowAny`, `password_reset` throttle 10/h per IP):

| Method + path | Body | Success | Errors |
|---|---|---|---|
| `POST /password-reset/request/` | `{email}` | `200 {detail, resend_cooldown, expires_in, debug_code?}` — **always generic**, whether or not the account exists | — |
| `POST /password-reset/confirm/` | `{email, code, new_password}` | `200 {detail, next:"login"}` | `400 {code:…}` bad/expired code · `400 {password:[…], debug_code?}` weak password (a fresh code is re-issued) · `429` |

Reset codes reuse `verification/otp.py` (`purpose='password_reset'`): same
expiry, cooldown, lockout, single-use / replay protection.

**Session invalidation.** `verification/auth.py` adds a `pv` claim (first 12 hex
of `sha256(password_hash)`) to every token minted by `tokens_for`, and
`VersionedJWTAuthentication` rejects a token whose `pv` no longer matches the
user's current password hash. A successful reset changes the hash → **every
previously issued access & refresh token for that user is dead on its next
request** (verified: `test_verification_flows.py` "pre-reset JWT is now invalid
(401)"). No blacklist table. Tokens minted without a `pv` claim (legacy / test
helpers) are left alone for backward compatibility.

A successful email reset also marks `email_verified_at` (it proves inbox
control). The user is **not** auto-logged-in — they must sign in with the new
password.

**Frontend.** New `password_reset_screen.dart` (`PasswordResetScreen`): step 1
email → step 2 code + new password + confirm, with resend countdown. Route
`/reset-password` (public). Login's "Forgot password?" now opens it, pre-filled
with whatever is in the email field.

### 15.3 Private document access control

**Storage.** Signup uploads now go to `backend/private_media/registration/<kind>/`
— a `FileSystemStorage` **not** mounted on `MEDIA_URL` and never served by the
static handler. A `/media/registration/...` path guess returns 404.

**Handback.** `POST /registration-upload/` returns
`/api/auth/registration-documents/<token>/` where `<token>` is a
`django.core.signing` blob carrying `{relative_path, kind, content_type,
uploaded_at}`. Tampering with the token → 404.

**Serve** — `GET /api/auth/registration-documents/<token>/` (`AllowAny`,
`document_fetch` throttle 120/h). Access rules (`verification/documents.py::can_access`):

1. **Signup session** — while the document is still *unclaimed* (no profile row
   references it) *and* younger than **2 hours**, anyone presenting the exact
   signed token may fetch it. This lets the signup screen preview an upload
   before the account exists.
2. **Owner** — once the document URL is stored on a profile
   (`DoctorProfile.council_registration_proof_url`, `DeliveryProfile.license_photo_url`,
   `User.profile_photo_url`, `FarmerProfile.farm_photos`, …), ownership is
   resolved by reverse lookup and only that authenticated user may fetch it.
   (A *pending* professional can't authenticate anywhere yet, so the 2-hour
   window covers them until an admin approves them — then they can.)
3. **Admins** — any `is_staff` (admin-panel) user may fetch any document, for
   review.
4. Everyone else → `403`; unauthenticated → `401`.

Responses carry `Cache-Control: private, no-store` and `X-Content-Type-Options:
nosniff`. No new table — ownership is derived from the profile rows that already
point at the document.

### 15.4 Tests added

**`backend/scripts/test_verification_flows.py` — 36 assertions:**
email OTP happy path (request → wrong code → resend-cooldown-429 → unknown-email
generic-200 → correct code → session); replay of a consumed code; "already
verified" response; **code expiry** → `400 expired`; **brute force** → 5 wrong
guesses → `429 locked`, and the correct code is then also refused; **phone OTP**
via the SMS console backend (`sms_outbox`); `SIGNUP_REQUIRE_PHONE_VERIFICATION`
toggle → email-done-but-phone-required `403`; password reset (generic 200,
unknown-email generic, wrong code, weak password re-issues a code, valid reset,
replay refused, old password → 401, new password → 200, **pre-reset JWT → 401**);
password-reset **rate limiting** (per-IP 429); document access (non-`/media/`
signed URL, unclaimed-within-grace 200, tampered token 404, owner 200, other
user 403, unauthenticated 401, admin 200).

**`backend/scripts/test_signup_flows.py`** — grew 80 → **88**; every role's
`test_role_creation` now walks register → `verify_email` → confirm →
session/pending, and `test_lifecycle` covers verify-then-approve.

**`test/verification_flow_test.dart` — 8 widget tests:** OTP screen builds /
shows destination / resend-cooldown active on open / 6-digit-only input /
short-code local error / full-code submit recovers after a failed call;
password-reset step 1 builds / invalid-email local error / email prefill.

### 15.5 Configuration & deployment notes

| Setting (env) | Dev default | Production |
|---|---|---|
| `OTP_EXPOSE_CODES` | `True` (= `DEBUG`) | **`False`** — otherwise codes are returned in API responses |
| `SIGNUP_REQUIRE_EMAIL_VERIFICATION` | `True` | `True` |
| `SIGNUP_REQUIRE_PHONE_VERIFICATION` | `False` | `True` only once a real SMS backend is wired |
| `SMS_BACKEND` | `console` (logs + `sms_outbox`) | your provider — implement in `verification/delivery.py::send_sms_code` (Twilio example inlined) |
| `EMAIL_BACKEND` / `EMAIL_*` | console/locmem | real SMTP (`backend/.env`) |
| `CACHES` | LocMemCache (per-process) | **Redis** if more than one worker — a code issued by one process must be confirmable by another. Add a `CACHES` block pointing at `REDIS_URL`. |
| Throttles (env) | `THROTTLE_OTP_REQUEST` 15/h, `THROTTLE_OTP_CONFIRM` 30/h, `THROTTLE_PASSWORD_RESET` 10/h, `THROTTLE_DOCUMENT_FETCH` 120/h | tune to taste |
| `private_media/` | local disk | move to object storage with private ACLs; keep it off any public path |

**One-time setup after pulling pass 2:**

```powershell
cd backend
psql "$env:DATABASE_URL" -f verification_extension.sql   # adds users.*_verified_at
venv\Scripts\python.exe manage.py migrate users           # records state migration 0003
venv\Scripts\python.exe manage.py backfill_contact_verification   # existing users -> verified
venv\Scripts\python.exe manage.py seed_platform_demo      # demo accounts (now pre-verified)
```

`backfill_contact_verification` is essential: email verification is a login gate,
so without it every pre-existing account is locked out. `--dry-run` /
`--created-before <date>` / `--email-only` options are available.

### 15.6 New endpoints (summary)

```
POST /api/auth/verify/request/               send / resend an email|phone code
POST /api/auth/verify/confirm/               confirm a code -> session | pending
POST /api/auth/password-reset/request/       send a reset code
POST /api/auth/password-reset/confirm/       set a new password, kill old sessions
GET  /api/auth/registration-documents/<t>/   fetch a signup document (access-checked)
```

### 15.7 Files added / changed (pass 2)

**Backend — added**
- `backend/verification/` — `__init__.py`, `apps.py`, `otp.py`, `delivery.py`, `auth.py`, `documents.py`, `views.py`, `urls.py`
- `backend/verification/management/commands/backfill_contact_verification.py`
- `backend/verification_extension.sql`
- `backend/users/migrations/0003_contact_verification.py`
- `backend/scripts/test_verification_flows.py`

**Backend — changed**
- `backend/users/models.py` — `email_verified_at` / `phone_verified_at` fields + `email_verified` / `phone_verified` / `mark_*` helpers
- `backend/users/views.py` — email-OTP gate in `register` + `login`; `resume_response()` helper; `registration_upload` now writes to private storage and returns a signed URL; token minting via `tokens_for`
- `backend/users/urls.py` — includes `verification.urls`
- `backend/users/serializers.py` — `_create_delivery` stores `vehicle_photo_url`; `_create_researcher` stores `ethics_certificate_url` (unchanged registration semantics)
- `backend/featherflow_backend/settings.py` — `verification` app; `VersionedJWTAuthentication`; `OTP_EXPOSE_CODES`, `SIGNUP_REQUIRE_*`, `SMS_BACKEND`, `PRIVATE_MEDIA_ROOT`; four new throttle rates
- `backend/api/throttling.py` — `OTPRequestRateThrottle`, `OTPConfirmRateThrottle`, `PasswordResetRateThrottle`, `DocumentFetchRateThrottle`
- `backend/users/management/commands/seed_platform_demo.py` — demo accounts created pre-verified
- `backend/scripts/test_signup_flows.py` — updated for the OTP step (80 → 88 assertions)
- `.gitignore` — `backend/private_media/`

**Frontend — added**
- `lib/features/auth/presentation/screens/otp_verification_screen.dart`
- `lib/features/auth/presentation/screens/password_reset_screen.dart`
- `test/verification_flow_test.dart`

**Frontend — changed**
- `lib/core/network/auth_service.dart` — `RegistrationResult` gains `verificationRequired` / `email` / `channel` / `debugCode`; `AuthException` gains `next` / `data`; new `requestVerificationCode` / `confirmVerificationCode` / `requestPasswordReset` / `confirmPasswordReset`; `_registrationOutcome` interprets the `next` hint
- `lib/core/router/app_router.dart` — `/verify` and `/reset-password` public routes
- `lib/features/auth/presentation/widgets/signup_widgets.dart` — `routeAfterRegistration()` helper
- `lib/features/auth/presentation/screens/{farmer,doctor,delivery,pharmacy,researcher,admin}_signup_screen.dart` — success path delegates to `routeAfterRegistration()`
- `lib/features/auth/presentation/screens/login_screen.dart` — "Forgot password?" opens `/reset-password`; a `verify_email` login response routes to `/verify`
- `lib/features/auth/presentation/screens/signup_screen.dart` — profile-photo upload wired to `file_picker` + the private upload endpoint

---

# Addendum — signup file uploads persisted to the database (2026-09-10)

## The gap

`/api/auth/registration-upload/` stored files under `private_media/` and returned
a signed URL, but **only some** of those URLs were written to the database on
`register`, and there was no explicit record linking a file to the account that
uploaded it. Access control relied on a fragile reverse lookup that scanned
profile URL columns — so files that live only in a JSON column (delivery vehicle
photo) or in no column at all (pharmacy business-registration / responsible-
pharmacist certificates, admin CV) became **unreachable by their owner** once the
2-hour signup grace window closed, and orphaned files had no DB row at all.

Empirically, before the fix (probe across all six roles):

| Role | persisted | dropped |
|---|---|---|
| farmer | profile photo, farm photos | — |
| doctor | profile photo, council proof, CV | — |
| pharmacy | profile photo, trade license | **business-registration cert, responsible-pharmacist cert** |
| delivery | profile photo, license photo, vehicle photo (JSON) | — |
| researcher | profile photo, CV, ethics cert | — |
| admin | profile photo | **CV** |

## Approach chosen — Option B: a normalized `signup_documents` table

A dedicated table (not extra columns on each schema-owned profile) because it
gives an explicit claim/ownership record, fixes access control uniformly, and
captures every document — including the ones that had nowhere to go.

### Table: `signup_documents`  (Django model `verification.SignupDocument`)

`verification` is not a schema-owned app, so this is an ordinary migration
(`backend/verification/migrations/0001_initial.py`) — nothing in
`featherflow_schema.sql` is touched.

| Column | Type | Notes |
|---|---|---|
| `id` | UUID PK | |
| `user_id` | FK to `users` (nullable) | NULL = unclaimed (upload happened, signup not finished) |
| `document_type` | varchar(40) | profile_photo, farm_photo, council_proof, cv, trade_license, business_registration_cert, responsible_pharmacist_cert, license_photo, vehicle_photo, proof_of_work, ethics_certificate, publications, id_document, certificate, other |
| `file_path` | varchar(255) | path relative to `private_media/` (e.g. `registration/cv/9f3a....pdf`) — files never move |
| `token` | text, unique | the `django.core.signing` blob; also embedded in the served URL |
| `content_type` | varchar(100) | |
| `original_filename` | varchar(255) | |
| `uploaded_at` | datetime | from the token payload |
| `claimed_at` | datetime, null | set when the account is created |
| `is_verified` / `verified_by_id` / `verified_at` | bool / FK / datetime | for a future admin document-review step |
| `created_at` | datetime | |

Index on `(user_id, document_type)`.

## Code changes

**`backend/verification/models.py`** — new file, the `SignupDocument` model.

**`backend/verification/documents.py`**
- `store()` now also writes an unclaimed `SignupDocument` row for every upload, so
  a file is tracked from the moment it lands (fixes "orphaned on disk, referenced
  by nothing"). A row-write failure never breaks the upload.
- New `claim(url_or_token, user, document_type)` — links a file to an account.
  Idempotent; accepts the bare token or the full `/registration-documents/<token>/`
  URL; a bad/expired token is skipped (returns None, does not raise); a real DB
  error propagates so the signup transaction rolls back.
- New `token_from(url_or_token)` helper.
- `document_owner(token)` now checks `signup_documents` first (fast, indexed,
  covers JSON-only and column-less documents); the old profile-column reverse
  lookup remains as a fallback for pre-migration accounts.
- `can_access()` is unchanged — same rules, better ownership resolution.

**`backend/users/serializers.py`**
- `_ROLE_DOCUMENT_FIELDS` maps each role to its `(document_type, role_data key)`
  pairs; `_claim_signup_documents(user, role, role_data)` claims every one (plus
  the `farm_photos` list) inside the `@transaction.atomic` `create()`, right
  after the profile is built.
- `_create_admin` now also writes `AdminProfile.cv_url` (column existed, was
  never populated).
- `UserSerializer` gains a `documents` field — the account's `signup_documents`
  as `{id, document_type, filename, content_type, url, is_verified, uploaded_at}`.
  Skipped in list responses (N+1 guard); computed for login / register / me /
  detail.

**`backend/verification/management/commands/purge_orphan_signup_documents.py`** —
new. `python manage.py purge_orphan_signup_documents [--hours 24] [--dry-run]`
deletes unclaimed rows (and their files) older than the cutoff. Claimed documents
are never touched. Cron-safe.

**No frontend changes.** The signup screens already upload every document and send
the URL under the right `role_data` key (including the two pharmacy certs and the
admin CV, which the backend was simply ignoring). The upload flow, rate limits
and type/size validation are unchanged.

## File path format

- On disk: `backend/private_media/registration/<kind>/<uuid>.<ext>`
- In `signup_documents.file_path`: `registration/<kind>/<uuid>.<ext>` (relative)
- Served only via `GET /api/auth/registration-documents/<token>/` — never on
  `MEDIA_URL`, never guessable.

## Access control behaviour (after the fix)

| Requester | Unclaimed file < 2 h old | Claimed file, owner active | Claimed file, owner pending |
|---|---|---|---|
| Anonymous with the signed link | 200 | 401 | 401 |
| The owner (authenticated) | 200 | 200 | n/a — a pending account cannot obtain a session |
| Another user | 403 | 403 | 403 |
| Admin (`is_staff` = holds an admin-panel role) | 200 | 200 | 200 |

So during the pending-review window a professional's documents are reachable by
admins only (plus the signed link for the first 2 h) — which is what the
verification workflow needs. After approval the account is active and the owner
can see their own documents.

## Transaction flow

1. Form + file selection.
2. Frontend `POST /api/auth/registration-upload/` per file to get a signed URL.
   Each upload also creates an unclaimed `signup_documents` row.
3. Frontend `POST /api/auth/register/` with the URLs in `role_data`.
4. `UserRegistrationSerializer.create()` (atomic): create user, create profile,
   `_claim_signup_documents()` sets `user_id` + `claimed_at` on each row.
   - user creation fails: nothing is written; the uploaded files stay as unclaimed
     rows and are purged later by the cron command.
   - claim fails (DB error): the whole signup rolls back, no orphan account.

## Test results

`backend/scripts/test_signup_documents.py` — 42 checks, 0 failed:
- all six roles: every uploaded file (profile photo, role documents, farm photos)
  produces a claimed `signup_documents` row whose token matches the upload, with
  `file_path` + `document_type` set;
- access control: owner 200, other user 403, anonymous 401 (after claim), admin 200;
- unclaimed grace: a fresh upload is readable via the signed link; an aged
  unclaimed upload is not;
- atomic rollback: a forced failure in `_claim_signup_documents` leaves no user
  row and no claimed documents.

Regression: `test_signup_flows.py` 88/0, `test_verification_flows.py` 36/0,
`test_farmer_panel.py` 35/0, `test_admin_panel.py` 65/0. `manage.py check` clean.
`flutter analyze` unchanged (no frontend edits).

## Follow-up — auth-aware image loading (2026-09-10)

The private document endpoint requires a JWT, but the farmer profile screen
loaded `profile_photo_url` / farm photos with a plain `NetworkImage` (no header),
so an active farmer's own photo only rendered during the 2 h grace window.

**Fixed:**
- **`lib/core/network/authed_image.dart`** *(new)* — `AuthedNetworkImage`, an
  `ImageProvider` that fetches the bytes itself with `Authorization: Bearer <jwt>`
  (from `AuthService`), then feeds Flutter's normal decode + cache pipeline
  (keyed on the URL). Falls back to an unauthenticated request when there is no
  session (signup preview, still in grace). Works on web too, unlike
  `Image.network(headers:)`.
- **`lib/features/farmer/presentation/screens/farmer_profile_screen.dart`** — the
  avatar `CircleAvatar.backgroundImage` and the farm-photo thumbnails now use
  `AuthedNetworkImage`; the avatar got an `onBackgroundImageError` guard.
- **`backend/verification/documents.py`** — `can_access` now lets **any
  signed-in user** fetch a document whose kind is `profile_photo`
  (`_PUBLIC_TO_AUTHED`) — a low-sensitivity avatar. Everything else (CV,
  licences, ID, certificates, farm photos) stays owner + admin only. Anonymous
  requests for a claimed profile photo are still refused.

Access matrix for a **profile photo** after this change: owner 200 · any other
signed-in user 200 · anonymous 401 (once claimed) · admin 200. `_doc_kind()`
resolves the kind from the token payload, or from the claimed `signup_documents`
row for older tokens.

Tests: `test_signup_documents.py` now **46 checks** (added: another signed-in
user *can* fetch a profile photo but *not* a private document; owner can fetch
their own photo; anonymous still refused). `test/authed_image_test.dart` (3) —
`AuthedNetworkImage` is an `ImageProvider` and keys correctly for the image
cache. Verified end-to-end against the running app (headless-Chrome CDP): the
profile screen's image request carries the `Authorization` header and returns
200, and the avatar renders.

## Limitations / follow-ups

- Admin document verification (`is_verified` / `verified_by` / `verified_at`) is
  modelled but not yet wired into the admin approval screen — a future "review
  documents" action can flip those fields.
- Pharmacy business-registration and responsible-pharmacist certificates now
  persist in `signup_documents` only (no profile column) — visible to admins via
  the `documents` array on the user payload and the document endpoint.
