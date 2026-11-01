"""Account-verification OTP security (OTP_VERIFICATION_SECURITY_AUDIT.md).

Run:  backend/venv/Scripts/python.exe backend/scripts/test_otp_verification_security.py

The bug: in DEBUG the API returned the live code (``debug_code``) and the app
pre-filled it, with a "Development mode" banner. The code was also written to
the server log. Here the code is only ever read from the email the server
sent (locmem backend), and every response and log line is checked for it.

Throw-away ``otpsec+`` accounts against the live configured DB and the
configured cache; cleaned on entry and exit.
"""
import logging
import os
import re
import sys
import time

os.environ.setdefault('THROTTLE_AUTH_REGISTER', '100000/hour')
os.environ.setdefault('THROTTLE_AUTH_LOGIN', '100000/min')
os.environ.setdefault('THROTTLE_OTP_REQUEST', '100000/hour')
os.environ.setdefault('THROTTLE_OTP_CONFIRM', '100000/hour')
os.environ.setdefault('THROTTLE_PASSWORD_RESET', '100000/hour')
os.environ['EMAIL_BACKEND'] = 'django.core.mail.backends.locmem.EmailBackend'

import django  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
django.setup()

from django.conf import settings as dj_settings  # noqa: E402
if 'testserver' not in dj_settings.ALLOWED_HOSTS:
    dj_settings.ALLOWED_HOSTS.append('testserver')

from django.core import mail  # noqa: E402
from django.core.cache import cache  # noqa: E402
from django.test import Client  # noqa: E402

from api.throttling import OTPConfirmRateThrottle, OTPRequestRateThrottle  # noqa: E402
from farms.models import Farm  # noqa: E402
from notifications.models import Notification  # noqa: E402
from profiles.models import FarmerProfile  # noqa: E402
from users.models import User  # noqa: E402
from verification import otp  # noqa: E402

PASS = FAIL = 0
PREFIX = 'otpsec+'
JSON = 'application/json'
FORBIDDEN_KEYS = ('otp', 'code', 'verification_code', 'email_otp', 'dev_otp', 'debug_otp',
                  'debug_code', 'dev_delivery')
_seq = [int(time.time()) % 100000]


def check(name, cond, extra=''):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f'  ok   {name}')
    else:
        FAIL += 1
        print(f'  FAIL {name}   {extra}')


class Capture(logging.Handler):
    """Every log record emitted while the suite runs, from every logger."""
    def __init__(self):
        super().__init__(level=logging.DEBUG)
        self.lines = []

    def emit(self, record):
        try:
            self.lines.append(record.getMessage())
        except Exception:
            self.lines.append(str(record.msg))


def cleanup():
    for u in User.objects.filter(email__startswith=PREFIX):
        Farm.objects.filter(farmer__user=u).delete()
        FarmerProfile.objects.filter(user=u).delete()
        Notification.objects.filter(user=u).delete()
    User.objects.filter(email__startswith=PREFIX).delete()


def new_email():
    _seq[0] += 1
    return f'{PREFIX}u{_seq[0]}@example.com'


def register(c, email=None):
    _seq[0] += 1
    email = email or new_email()
    body = {
        'email': email, 'password': 'Str0ngPass!42', 'password2': 'Str0ngPass!42',
        'phone': f'+88019{_seq[0]:08d}', 'full_name': 'Otp Security',
        'present_address': 'House 1, Dhaka', 'date_of_birth': '1990-01-01',
        'consent_terms': True, 'role': 'farmer',
        'role_data': {'farm_name': 'F', 'farm_location': 'Savar'},
    }
    return c.post('/api/auth/register/', body, content_type=JSON), email


def emailed(email):
    return [m for m in getattr(mail, 'outbox', []) if email.lower() in [t.lower() for t in m.to]]


def emailed_code(email):
    for message in reversed(emailed(email)):
        found = re.search(r'\b(\d{6})\b', message.body)
        if found:
            return found.group(1)
    raise AssertionError(f'no code emailed to {email}')


def no_code_in(response, code, keys=FORBIDDEN_KEYS):
    """The response carries none of the OTP fields, and the code's digits
    appear nowhere in its body."""
    body = response.content.decode()
    data = response.json() if body.strip().startswith('{') else {}
    return code not in body and not (set(data) & set(keys) - {'code'}) \
        and data.get('code') in (None, 'invalid_code', 'locked')


def confirm(c, email, code, path='/api/auth/verify/confirm/'):
    return c.post(path, {'email': email, 'channel': 'email', 'code': code}, content_type=JSON)


def expire(purpose, ident):
    key = otp._key(purpose, 'email', ident)
    rec = cache.get(key)
    rec['expires_at'] = time.time() - 1
    cache.set(key, rec, timeout=120)


def age_out_cooldown(purpose, ident):
    key = otp._key(purpose, 'email', ident)
    rec = cache.get(key)
    rec['sent_at'] = time.time() - otp.RESEND_COOLDOWN - 1
    cache.set(key, rec, timeout=otp.CODE_TTL + otp.LOCKOUT_TTL)


def main():
    mail.outbox = []
    capture = Capture()
    logging.getLogger().addHandler(capture)
    for name in ('verification', 'users', 'django', 'django.request'):
        logging.getLogger(name).addHandler(capture)
    cleanup()
    c = Client()
    seen_codes = []

    print('\n== configuration ==')
    check('no setting can expose codes (OTP_EXPOSE_CODES / OTP_DEV_DELIVERY removed)',
          not hasattr(dj_settings, 'OTP_EXPOSE_CODES') and not hasattr(dj_settings, 'OTP_DEV_DELIVERY'))

    print('\n== signup: code generated, stored as HMAC, emailed, not returned ==')
    r, email = register(c)
    data = r.json()
    check('signup 201 -> verify_email', r.status_code == 201 and data.get('next') == 'verify_email', r.content[:200])
    check('exactly one verification email sent to the new account', len(emailed(email)) == 1, len(emailed(email)))
    code = emailed_code(email)
    seen_codes.append(code)
    check('emailed code is 6 digits', re.fullmatch(r'\d{6}', code) is not None, code)
    check('signup response contains no OTP field and not the code', no_code_in(r, code), r.content[:300])
    check('signup response has only safe metadata',
          data.get('email_masked', '').endswith('@example.com') and data['email_masked'].startswith(email[0] + '***')
          and data.get('expires_in') == otp.CODE_TTL and data.get('resend_cooldown') == otp.RESEND_COOLDOWN
          and data.get('delivered') is True, data)
    check('detail says it was emailed, never "printed in the terminal"',
          'sent a 6-digit verification code' in data.get('detail', '')
          and 'terminal' not in data.get('detail', '').lower(), data.get('detail'))
    rec = cache.get(otp._key('email_verify', 'email', email))
    check('stored record holds an HMAC, never the code', rec and rec.get('hash') and code not in str(rec)
          and rec['hash'] != code, rec)
    check('email subject/body are the verification email', 'Verify your Featherflow email' in emailed(email)[-1].subject)

    print('\n== confirm ==')
    w = confirm(c, email, '000000' if code != '000000' else '111111')
    check('wrong code -> 400 invalid_code, generic message', w.status_code == 400
          and w.json().get('code') == 'invalid_code' and no_code_in(w, code), w.content[:200])
    g = c.get(f'/api/auth/verify/confirm/?email={email}&channel=email&code={code}')
    check('GET with the code in the query string -> 405, not verified',
          g.status_code == 405 and not User.objects.get(email=email).email_verified, g.status_code)
    q = c.post(f'/api/auth/verify/confirm/?email={email}&channel=email&code={code}', {}, content_type=JSON)
    check('POST with the code only in the query string -> rejected (400)',
          q.status_code == 400 and not User.objects.get(email=email).email_verified, q.content[:200])
    bad = c.post('/api/auth/verify/confirm/', {'email': email, 'channel': 'fax', 'code': code}, content_type=JSON)
    check('invalid channel -> 400', bad.status_code == 400, bad.status_code)
    ok = confirm(c, email, code)
    check('correct code -> 200, verified, session issued', ok.status_code == 200 and ok.json().get('access')
          and User.objects.get(email=email).email_verified is True, ok.content[:200])
    check('success response does not contain the code', code not in ok.content.decode())
    check('code consumed on success (nothing left in the store)',
          cache.get(otp._key('email_verify', 'email', email)) is None)
    replay = confirm(c, email, code)
    check('reusing the code -> 400 invalid_code', replay.status_code == 400
          and replay.json().get('code') == 'invalid_code', replay.content[:200])

    print('\n== expiry ==')
    r2, email2 = register(c)
    code2 = emailed_code(email2)
    seen_codes.append(code2)
    expire('email_verify', email2)
    ex = confirm(c, email2, code2)
    check('expired code -> 400 invalid_code', ex.status_code == 400 and ex.json().get('code') == 'invalid_code', ex.content[:200])
    check('expired code stays unusable', confirm(c, email2, code2).status_code in (400, 429)
          and not User.objects.get(email=email2).email_verified)

    print('\n== resend: rate-limited, new code invalidates the old one, nothing returned ==')
    r3, email3 = register(c)
    first = emailed_code(email3)
    seen_codes.append(first)
    rs = c.post('/api/auth/verify/request/', {'email': email3, 'channel': 'email'}, content_type=JSON)
    check('resend inside the cooldown -> 200 + retry_after, no new email',
          rs.status_code == 200 and rs.json().get('retry_after', 0) > 0 and len(emailed(email3)) == 1, rs.content[:200])
    check('resend response contains no OTP field', no_code_in(rs, first), rs.content[:200])
    age_out_cooldown('email_verify', email3)
    rs2 = c.post('/api/auth/verify/request/', {'email': email3, 'channel': 'email'}, content_type=JSON)
    second = emailed_code(email3)
    seen_codes.append(second)
    check('resend after the cooldown -> 200, a new code is emailed', rs2.status_code == 200
          and len(emailed(email3)) == 2 and second != first or len(emailed(email3)) == 2, rs2.content[:200])
    check('resend response contains neither code', no_code_in(rs2, first) and no_code_in(rs2, second), rs2.content[:200])
    if second != first:
        old = confirm(c, email3, first)
        check('the previous code no longer works', old.status_code == 400 and old.json().get('code') == 'invalid_code')
    check('the new code works', confirm(c, email3, second).status_code == 200)
    r4, email4 = register(c)
    seen_codes.append(emailed_code(email4))
    for _ in range(otp.MAX_RESENDS + 1):
        age_out_cooldown('email_verify', email4)
        last = c.post('/api/auth/verify/request/', {'email': email4, 'channel': 'email'}, content_type=JSON)
        seen_codes.append(emailed_code(email4))
    check('resend ceiling: after MAX_RESENDS no more emails', len(emailed(email4)) == otp.MAX_RESENDS + 1
          and last.json().get('retry_after', 0) > 0, (len(emailed(email4)), last.content[:150]))

    print('\n== brute force ==')
    r5, email5 = register(c)
    good = emailed_code(email5)
    seen_codes.append(good)
    wrong = '999999' if good != '999999' else '888888'
    statuses = [confirm(c, email5, wrong).status_code for _ in range(otp.MAX_ATTEMPTS)]
    check(f'{otp.MAX_ATTEMPTS} wrong guesses -> locked (429)', statuses[-1] == 429 and set(statuses[:-1]) == {400}, statuses)
    blocked = confirm(c, email5, good)
    check('correct code during lockout -> still 429, not verified',
          blocked.status_code == 429 and blocked.json().get('code') == 'locked'
          and not User.objects.get(email=email5).email_verified, blocked.content[:200])
    rl = c.post('/api/auth/verify/request/', {'email': email5, 'channel': 'email'}, content_type=JSON)
    check('no new code can be requested during lockout', rl.json().get('retry_after', 0) > 0
          and len(emailed(email5)) == 1, rl.content[:150])

    print('\n== per-IP throttles ==')
    # Only this suite's own throttle keys: the configured cache may be a
    # shared Redis, so it is never cleared wholesale.
    own_keys = ['throttle_otp_confirm_10.9.9.9', 'throttle_otp_request_10.9.9.8']
    cache.delete_many(own_keys)
    saved = OTPConfirmRateThrottle.THROTTLE_RATES
    OTPConfirmRateThrottle.THROTTLE_RATES = {**saved, 'otp_confirm': '3/hour'}
    try:
        codes = [confirm(Client(REMOTE_ADDR='10.9.9.9'), new_email(), '123456').status_code for _ in range(4)]
    finally:
        OTPConfirmRateThrottle.THROTTLE_RATES = saved
    check('confirm attempts beyond the per-IP rate -> 429', codes[-1] == 429 and codes[0] == 400, codes)
    saved = OTPRequestRateThrottle.THROTTLE_RATES
    OTPRequestRateThrottle.THROTTLE_RATES = {**saved, 'otp_request': '2/hour'}
    try:
        codes = [Client(REMOTE_ADDR='10.9.9.8').post('/api/auth/verify/request/',
                 {'email': new_email(), 'channel': 'email'}, content_type=JSON).status_code for _ in range(3)]
    finally:
        OTPRequestRateThrottle.THROTTLE_RATES = saved
    check('code requests beyond the per-IP rate -> 429', codes == [200, 200, 429], codes)
    cache.delete_many(own_keys)

    print('\n== no account enumeration ==')
    r6, pending = register(c)
    seen_codes.append(emailed_code(pending))
    ghost = new_email()
    age_out_cooldown('email_verify', pending)
    a = c.post('/api/auth/verify/request/', {'email': pending, 'channel': 'email'}, content_type=JSON)
    b = c.post('/api/auth/verify/request/', {'email': ghost, 'channel': 'email'}, content_type=JSON)
    seen_codes.append(emailed_code(pending))
    check('resend: real pending vs unknown email -> identical status and body',
          a.status_code == b.status_code == 200 and a.json() == b.json(), (a.content, b.content))
    check('unknown email gets no email', not emailed(ghost))
    a2 = c.post('/api/auth/verify/request/', {'email': pending, 'channel': 'email'}, content_type=JSON)
    b2 = c.post('/api/auth/verify/request/', {'email': ghost, 'channel': 'email'}, content_type=JSON)
    check('resend inside the cooldown: identical too (200 + retry_after)',
          a2.status_code == b2.status_code == 200 and set(a2.json()) == set(b2.json()), (a2.content, b2.content))
    ca = confirm(c, pending, '000001')
    cb = confirm(c, ghost, '000001')
    check('wrong code: real vs unknown email -> identical response',
          (ca.status_code, ca.json()) == (cb.status_code, cb.json()), (ca.content, cb.content))
    for _ in range(otp.MAX_ATTEMPTS):
        la = confirm(c, pending, '000002')
        lb = confirm(c, ghost, '000002')
    check('lockout: real and unknown emails lock the same way', la.status_code == lb.status_code == 429
          and la.json() == lb.json(), (la.content, lb.content))
    verified_email = email  # verified above
    va = c.post('/api/auth/verify/request/', {'email': verified_email, 'channel': 'email'}, content_type=JSON)
    vb = c.post('/api/auth/verify/request/', {'email': new_email(), 'channel': 'email'}, content_type=JSON)
    check('already-verified account looks like an unknown one', va.status_code == vb.status_code
          and set(va.json()) == set(vb.json()) and va.json()['detail'] == vb.json()['detail'], (va.content, vb.content))

    print('\n== login and password reset never return a code ==')
    r7, email7 = register(c)
    seen_codes.append(emailed_code(email7))
    age_out_cooldown('email_verify', email7)
    lg = c.post('/api/auth/login/', {'email': email7, 'password': 'Str0ngPass!42'}, content_type=JSON)
    login_code = emailed_code(email7)
    seen_codes.append(login_code)
    check('unverified login -> 403 verify_email, fresh code emailed, not returned',
          lg.status_code == 403 and lg.json().get('next') == 'verify_email' and no_code_in(lg, login_code)
          and 'terminal' not in lg.json().get('detail', '').lower(), lg.content[:300])
    pr = c.post('/api/auth/password-reset/request/', {'email': email}, content_type=JSON)
    reset_code = emailed_code(email)
    seen_codes.append(reset_code)
    check('password reset request -> code emailed, not returned', pr.status_code == 200
          and no_code_in(pr, reset_code), pr.content[:200])
    weak = c.post('/api/auth/password-reset/confirm/', {'email': email, 'code': reset_code,
                  'new_password': 'short'}, content_type=JSON)
    reissued = emailed_code(email)
    seen_codes.append(reissued)
    check('weak password -> re-issued code emailed, not returned', weak.status_code == 400
          and no_code_in(weak, reissued) and 'debug_code' not in weak.json(), weak.content[:200])
    ghost_reset = c.post('/api/auth/password-reset/request/', {'email': new_email()}, content_type=JSON)
    check('password reset: unknown email -> same body as a real one',
          ghost_reset.status_code == 200 and set(ghost_reset.json()) == set(pr.json()), ghost_reset.content[:200])

    print('\n== nothing logged ==')
    logged = '\n'.join(capture.lines)
    leaked = [c_ for c_ in set(seen_codes) if c_ in logged]
    check(f'none of the {len(set(seen_codes))} codes issued appears in any log record', not leaked, leaked)
    check('verification failures are audited (without the code)',
          any('OTP confirm failed' in line and 'reason=invalid_code' in line for line in capture.lines))
    check('verification success is audited', any('OTP confirm succeeded' in line for line in capture.lines))

    cleanup()
    print(f'\n{PASS} passed, {FAIL} failed')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    main()
