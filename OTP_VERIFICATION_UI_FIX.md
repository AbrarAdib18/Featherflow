# Account-Verification OTP — Fix

Root cause and security review: [OTP_VERIFICATION_SECURITY_AUDIT.md](OTP_VERIFICATION_SECURITY_AUDIT.md). In short: in DEBUG the API returned the live code (`debug_code`) and the app pre-filled it under a "Development mode" banner.

The code now reaches the user **only by email**. The page opens empty, the user types the code, and the server checks it.

## Files changed

| File | Change |
|---|---|
| `backend/featherflow_backend/settings.py` | **Removed** `OTP_EXPOSE_CODES` and `OTP_DEV_DELIVERY` (no switch can expose codes any more) |
| `backend/.env.example` | The `OTP_EXPOSE_CODES` entry removed; SMS note updated |
| `backend/users/views.py` | Signup and unverified-login responses: no `debug_code` / `dev_delivery`; safe metadata `email_masked`, `expires_in`, `resend_cooldown`, `delivered` (now true only if the provider accepted the email); honest detail text. A new account clears earlier probing of its address. `mask_email()` |
| `backend/verification/views.py` | No code or dev flag in any response. Unified `invalid_code` / `locked` errors; uniform handling of unknown, verified and pending emails for request, confirm and reset (no enumeration). Audit logging of confirm success and failure without the code |
| `backend/verification/otp.py` | HMAC-SHA256 storage, constant-time compare, every failure counts toward the lockout, an expired code is disarmed |
| `backend/verification/delivery.py` | No code in any log line; bounded SMS test outbox |
| `lib/core/network/auth_service.dart` | `RegistrationResult` / `CodeRequestResult`: `debugCode` and `devDelivery` removed; `emailMasked` and `retryAfter` added. The app no longer reads `debug_code` or `dev_delivery` at all |
| `lib/core/router/app_router.dart`, `lib/features/auth/presentation/widgets/signup_widgets.dart`, `lib/features/auth/presentation/screens/login_screen.dart` | Stop passing the code to the verification page; pass the masked email |
| `lib/features/auth/presentation/screens/otp_verification_screen.dart` | Empty field, no banner, *"We sent a 6-digit verification code to n***@example.com. It expires in 10 minutes."*; resend handles `retry_after` ("Please wait…") and says earlier codes no longer work |
| `lib/features/auth/presentation/screens/password_reset_screen.dart` | Same cleanup: no pre-fill, no Development-mode banner |
| Tests | New `backend/scripts/test_otp_verification_security.py` and `test/otp_verification_ui_test.dart`; updated `backend/scripts/test_verification_flows.py`, `backend/scripts/test_signup_flows.py`, `test/verification_flow_test.dart` (see below) |

No schema or migration change.

## API responses

| Endpoint | Removed | Now returns |
|---|---|---|
| `POST /api/auth/register/` (verification required) | `debug_code`, `dev_delivery`, "printed in the backend terminal (and filled in below)" | `detail` ("Account created. We sent a 6-digit verification code to u***@example.com."), `next: verify_email`, `channel`, `email`, `email_masked`, `expires_in` (600), `resend_cooldown` (60), `account_status`, `delivered` |
| `POST /api/auth/login/` (unverified, 403) | `debug_code`, `dev_delivery`, "code is in the backend terminal (dev mode)" | `detail`, `next`, `channel`, `email`, `email_masked`, `expires_in`, `resend_cooldown` |
| `POST /api/auth/verify/request/` | `debug_code`, `dev_delivery`, `delivered`; **429** inside the cooldown | Always 200 `{detail, channel, resend_cooldown, expires_in}` (+ `retry_after` when no new code was sent), identical for every email |
| `POST /api/auth/verify/confirm/` | `code: wrong` / `no_code` / `expired` | 400 `{detail: "That code is incorrect or has expired…", code: "invalid_code"}` or 429 `locked`; success unchanged (session / pending / next channel) |
| `POST /api/auth/password-reset/request/` | `debug_code`, `dev_delivery` | Generic 200 (+ `retry_after`), identical for every email |
| `POST /api/auth/password-reset/confirm/` | `debug_code` (weak-password re-issue); granular errors | Same unified errors; the re-issued code goes by email only |

None of `otp`, `code` (as an OTP value), `verification_code`, `email_otp`, `dev_otp`, `debug_otp` or `debug_code` appears in any response. `code` is only ever the error identifier `invalid_code` / `locked`.

## Developer-mode cleanup

Searched for `debug_code`, `debugCode`, `dev_delivery`, `devDelivery`, `OTP_EXPOSE_CODES`, `OTP_DEV_DELIVERY`, "Development mode", "backend terminal", "filled in", pre-fill and OTP logging.

* **All OTP instances removed:** from the backend, the verification page, and the password-reset page.
* **No development OTP tool kept:** for local work without SMTP, Django's console email backend prints the email itself, which is the real delivery channel and documented as such.
* **Untouched:** the "Development mode — no real money moved / no real charge" notices in the labour-payment and subscription screens are unrelated sandbox-payment notices.

## Tests and results

| Gate | Result |
|---|---|
| `backend/scripts/test_otp_verification_security.py` *(new)* | **44/44** |
| `test/otp_verification_ui_test.dart` *(new)* | **11/11** |
| `backend/scripts/test_verification_flows.py` *(updated)* | 36/36 |
| `backend/scripts/test_signup_flows.py` *(updated)* | 96/96 |
| `test/verification_flow_test.dart` *(updated)* | 8/8 |
| signup_documents / verification_status / profile_photo / finance_admin | 46/46 · 24/24 · 58/58 · 35/35 |
| admin_panel | 62/63: the known pre-existing "admin login 200" failure (the test admin account is unverified; the response now correctly carries no code) |
| `manage.py check` / `migrate --check` | clean / exit 0 |
| `flutter analyze lib test` | only the 6 known infos in `farmer_feed_marketplace_screen.dart` |
| `flutter test` (one process per file, for machine memory) | all files pass except the 2 known pre-existing navbar-photo tests in `doctor_dashboard_fixes_test.dart` |
| `flutter build web --release` | built |

**Backend security suite: what it covers**
* **Signup:** sends exactly one email with a 6-digit code; the response has no OTP field and not the code; only safe metadata; no "terminal" wording; the stored record is an HMAC, never the code.
* **Confirm:** a wrong code gives a generic 400; GET with the code in the query string gives 405; a POST with the code only in the query string is rejected; the correct code verifies and issues a session, without the code in the response; the code is consumed; reuse is refused.
* **Expiry:** an expired code is refused, and it stays refused.
* **Resend:**
  * Inside the cooldown it returns 200 + `retry_after` and sends no new email.
  * After the cooldown a new code is emailed, the old code stops working and the new one works.
  * No more than 5 resends per code.
* **Brute force:** 5 wrong guesses lock the identity (429). The correct code is refused while locked, and no new code can be requested.
* **Per-IP throttles:** confirm and request both answer 429 beyond the rate.
* **No enumeration:** for a real pending account vs an unknown email, resend (inside and outside the cooldown), wrong code and lockout all respond identically; an already-verified account looks like an unknown one.
* **Login and password reset:** the unverified login, the reset request and the weak-password re-issue all email the code and never return it; an unknown email gets the same reset body.
* **Logging:** every log record during the run was captured, and none of the **19 codes issued** appears in any of them. Failures and successes are audited without the code.

**Flutter: what it covers**
* **Opening the page:** the field is empty; no Development-mode, "backend terminal" or "filled in" text and no terminal icon; it shows "We sent a 6-digit verification code to n***@example.com…"; the full email is not shown.
* **Submitting:** the code the user enters is posted (email, channel, code), and the user lands on the farmer dashboard. An awaiting-review account goes to the pending page.
* **Errors:** a wrong or expired code shows the generic error, never the correct code, and the button works again; retrying with the right code succeeds. A short code is caught locally with no request.
* **Duplicates:** a loading spinner shows, and a second tap sends no second request.
* **Resend:** after the cooldown, even a *legacy* server that still leaks `debug_code` leaves the field empty with no banner; the confirmation names the masked email and the cooldown restarts. When the server says wait (`retry_after`) there is no "sent" claim and the cooldown follows the server.
* **Password-reset code step:** empty, with no banner, even if the legacy leak is present.
* **Layout:** 360px and 1400px.
* **Flutter log:** `debugPrint` is captured in every test and never contains a code.

**Existing tests changed (requirement-driven, not weakened)**
* `test_verification_flows.py` and `test_signup_flows.py`:
  * They read the code from the response's `debug_code`; they now read it **from the email the server sent**, which is the real channel.
  * The assertion "signup returns debug_code" became "the code is in the email, not the response".
  * The granular `wrong` / `no_code` / `expired` codes became `invalid_code`.
  * The 429 resend became 200 + `retry_after`.
* `verification_flow_test.dart`: one test asserted that `debugCode` pre-fills the field. It now asserts the field starts **empty** and types the code.

**Negative controls**
* **`debug_code` restored in the signup response:** the security suite fails (43/44).
* **The field pre-filled again:** 2 UI tests fail.

Both files were restored byte-for-byte afterwards.

## Manual verification (to do by hand)

There is no browser or desktop automation in this environment, so these steps are for you. Run `.\run_backend.bat` (your `.env` has SMTP configured), then `flutter run -d chrome` or `-d windows`.

1. Sign up with a real test inbox. The verification page opens with an **empty** field and **no** Development-mode banner, and it says "We sent a 6-digit verification code to x***@domain".
2. The email "Verify your Featherflow email address" arrives. Type the code. You land on the dashboard (or on the pending page for professional roles).
3. Log out and log back in. No verification is asked again.
4. Sign up another account and enter a wrong code. You see "That code is incorrect or has expired…" and no code is shown.
5. Wait 60 s, then press Resend. A new email arrives, the old code fails, the new one works.
6. In the browser DevTools Network tab, the register, resend and confirm responses contain no code. In the backend terminal no code is logged (the SMTP backend doesn't print emails).

## Limitations

See §6 of the audit: a shared cache is needed in production, lockout can be abused as denial of service, signup still reveals registered emails, there is no SMS provider, and codes in flight at deploy become invalid.
