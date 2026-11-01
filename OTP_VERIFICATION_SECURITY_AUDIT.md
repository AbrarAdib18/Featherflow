# Account-Verification OTP — Security Audit

**Date:** 2026-11-01
**Reported:** right after signup, the "Verify your email" page showed the 6-digit code already filled in, under an orange banner: *"Development mode: no email/SMS provider is configured, so nothing was actually sent. The code is printed in the backend terminal — and has been filled in below for you."* The code is meant to prove control of the inbox, and this defeated that.

The fix is in [OTP_VERIFICATION_UI_FIX.md](OTP_VERIFICATION_UI_FIX.md).

## 1. How the code travelled

```
Signup (POST /api/auth/register/)
 → otp.issue(): secrets.randbelow → 6 digits, cache stores hash + TTL      ✔
 → delivery.send_email_code(): email via EMAIL_BACKEND                     ✔
     + if OTP_DEV_DELIVERY: logger.info("[dev] … OTP for <email> is <CODE>")   ✘ code in the log
 → users/views.py: if OTP_EXPOSE_CODES: body['debug_code'] = <CODE>        ✘ code in the API
                   body['dev_delivery'] = OTP_DEV_DELIVERY                  ✘ drives the banner
 → Flutter AuthService: RegistrationResult.debugCode / devDelivery
 → routeAfterRegistration → /verify (extra: debug_code, dev_delivery)
 → OtpVerificationScreen.initState: _codeCtrl.text = widget.debugCode      ✘ pre-filled
                                    _devDelivery → orange banner           ✘
```

The same leak existed on four more paths:

* The **unverified-login** 403 (`debug_code`, plus a "code is in the backend terminal" detail).
* The **resend** endpoint (`POST /api/auth/verify/request/`).
* The **password-reset request**.
* The **password-reset "weak password" re-issue**.

On the Flutter side, the **password-reset screen** pre-filled the code and showed its own Development-mode banner too.

## 2. Root cause

Two settings, both on by default in this dev setup (`DJANGO_DEBUG=True`):

| Setting | Default | Effect |
|---|---|---|
| `OTP_EXPOSE_CODES` | `True` whenever `DEBUG` | Every code-issuing response included the live code as `debug_code` |
| `OTP_DEV_DELIVERY` | True if `EMAIL_BACKEND` is console/locmem **or `SMS_BACKEND == 'console'`** | Sent `dev_delivery: true` (the banner) and logged the code. Because `SMS_BACKEND` defaults to `console`, it was **true even with real SMTP configured**, which is why the banner appeared although email delivery works |

Flutter trusted those fields: it copied `debug_code` into the input and showed the banner whenever `dev_delivery` was true.

**Classification:** the code was exposed through the **backend API response** (primary), carried into **Flutter state** (pre-fill), shown because of **developer-mode configuration**, and also written to the **server log**. It was not seed data, and not local storage: `SignupFormCache` logs only field names, never values, and the code was never persisted.

## 3. OTP mechanics (`verification/otp.py`)

| Control | Before | After |
|---|---|---|
| Generation | `secrets.randbelow(10**6)`, 6 digits (cryptographically secure) | unchanged |
| Storage | Django cache; `sha256(SECRET_KEY:code)` (no plaintext) | **HMAC-SHA256(SECRET_KEY, code)**, compared with **`hmac.compare_digest`** (was `!=`) |
| Expiry | 10 min | unchanged; a failed check on an expired code also drops its hash |
| One-time use | deleted on success | unchanged |
| Attempt limit | 5 wrong guesses → 15 min lock (only while a code existed) | 5 failures of **any** kind (wrong / expired / used / none issued) → 15 min lock |
| Resend | 60 s cooldown, 5 resends per code lifecycle | unchanged |
| New code invalidates the old | yes (the record is overwritten) | unchanged (tested) |
| Per-IP throttles | `otp_request` 15/h, `otp_confirm` 30/h, `password_reset` | unchanged (tested) |
| Methods | POST only (`@api_view(['POST'])`) | unchanged; GET → 405, and a code only in the query string is ignored (tested) |
| CSRF | DRF enforces CSRF for session-authenticated requests; these endpoints are unauthenticated JSON POSTs, and the app authenticates with JWT bearer tokens, not cookies | unchanged (no cookie session to forge) |

## 4. Account enumeration (found and fixed)

| Probe | Before | After |
|---|---|---|
| `verify/confirm` with an unknown email | "That code is not correct." | Same response as a real email with a wrong code: 400 `invalid_code` |
| … a real email with no code issued | "Request a code first." (`no_code`) | 400 `invalid_code` |
| … a real email, wrong / expired / used code | `wrong` / `expired` / `no_code` | 400 `invalid_code` |
| … 5 failures | Locked only for real accounts | Locked the same way for unknown emails |
| `verify/request` inside the cooldown | **429** for real accounts, 200 for unknown | 200 + `retry_after` for both |
| `verify/request` success | Real accounts got extra keys (`delivered`, `dev_delivery`, `debug_code`) | Identical body for unknown, verified and pending accounts |
| `password-reset/request` | `retry_after` only for real accounts | Same bookkeeping and body for all |

Unknown and already-verified emails now go through the same cooldown and lockout bookkeeping under an identity no code is ever sent to (`nosend:<email>`). Signing up clears any earlier probing of the new address, so an attacker can't pre-lock it.

## 5. Logging

* **Removed:** the `[dev] … OTP for <email> is <code>` line, and the SMS console stub's `code=` log line.
* **Bounded:** the SMS console stub's in-memory test outbox (`deque(maxlen=50)`).
* **Added:** audit lines `OTP confirm failed: purpose=… email=… reason=invalid_code|locked` and `OTP confirm succeeded: …`, with no code.
* **Tested:** the new suite captures every log record during a full run and asserts none of the 19 codes it issued appears.

## 6. Remaining recommendations

1. **Production cache:** OTPs live in Django's cache. Run a **shared cache (Redis, `REDIS_URL`)** with more than one worker; per-process LocMem would make codes issued by one worker unknown to another.
2. **Lockout as denial of service:** anyone can lock an email's verification for 15 minutes with 5 wrong guesses (now true for unknown emails too, by design for uniformity). Consider a per-IP + per-identity combination or a CAPTCHA after the lock.
3. **Signup enumeration:** signup itself reveals registered emails ("email already exists"). This is outside the OTP flow; it needs a product decision (e.g. "check your inbox" for existing addresses).
4. **Console email backend:** with no SMTP configured, the email, including the code, is printed by the console backend. That is the email channel itself in local dev, not an app log, but production must set `EMAIL_BACKEND` to SMTP (it is in your `.env`).
5. **Deployment note:** the HMAC change invalidates codes issued in the 10 minutes before deploy; affected users press Resend.
6. **SMS:** no SMS provider is wired (`SMS_BACKEND=console`). Phone verification stays opt-in (`SIGNUP_REQUIRE_PHONE_VERIFICATION=False`).
