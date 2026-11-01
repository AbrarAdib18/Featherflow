"""One-time code lifecycle for email/phone verification and password reset.

Codes live in Django's cache, never the database — a code is short-lived (10
min) and single-use. For a multi-process deployment configure a shared cache
(Redis) so the code issued by one worker can be confirmed by another; the
default LocMemCache is per-process and fine for a single ``runserver`` /
``uvicorn`` worker or the test suite.

Protections:
  * expiry              — CODE_TTL seconds
  * resend cooldown     — RESEND_COOLDOWN seconds between sends
  * resend ceiling      — MAX_RESENDS sends per code lifecycle
  * brute-force lockout  — MAX_ATTEMPTS failed checks -> LOCKOUT_TTL freeze
  * single use / replay  — the code is deleted from the cache on success
  * stored as an HMAC    — only HMAC-SHA256(SECRET_KEY, code) is kept, and it is
                           compared in constant time
  * no enumeration       — a wrong, expired, used or never-issued code is the
                           same 'invalid' failure, and every failure counts
                           toward the lockout, whether or not the identity is a
                           real account (OTP_VERIFICATION_SECURITY_AUDIT.md)

The code itself never leaves this module except to the email/SMS sender.
"""
import hashlib
import hmac
import secrets
import time

from django.conf import settings
from django.core.cache import cache

CODE_TTL = 10 * 60          # a code is valid for 10 minutes
RESEND_COOLDOWN = 60        # seconds a caller must wait between sends
MAX_RESENDS = 5             # sends allowed within one code lifecycle
MAX_ATTEMPTS = 5            # wrong guesses before the identity is frozen
LOCKOUT_TTL = 15 * 60       # freeze duration after too many wrong guesses

PURPOSES = ('email_verify', 'phone_verify', 'password_reset')
CHANNELS = ('email', 'phone')


def _key(purpose, channel, ident):
    return f'ff:otp:{purpose}:{channel}:{str(ident).strip().lower()}'


def _hash(code):
    return hmac.new(settings.SECRET_KEY.encode(), str(code).encode(),
                    hashlib.sha256).hexdigest()


def generate_code():
    return f'{secrets.randbelow(1_000_000):06d}'


def issue(purpose, channel, ident):
    """Create + store a fresh code.

    Returns ``(code, retry_after, error)``. When ``error`` is set the caller must
    NOT send anything: 'cooldown' / 'max_resends' / 'locked' (``retry_after`` is
    the seconds to wait, best-effort).
    """
    key = _key(purpose, channel, ident)
    now = time.time()
    rec = cache.get(key)

    if rec and rec.get('locked_until', 0) > now:
        return None, int(rec['locked_until'] - now), 'locked'
    if rec:
        waited = now - rec.get('sent_at', 0)
        if waited < RESEND_COOLDOWN:
            return None, int(RESEND_COOLDOWN - waited) or 1, 'cooldown'
        if rec.get('resends', 0) >= MAX_RESENDS:
            return None, int(rec.get('expires_at', now) - now), 'max_resends'

    code = generate_code()
    cache.set(key, {
        'hash': _hash(code),
        'sent_at': now,
        'expires_at': now + CODE_TTL,
        'attempts': 0,
        'resends': (rec.get('resends', 0) + 1) if rec else 0,
    }, timeout=CODE_TTL + LOCKOUT_TTL)
    return code, 0, None


def peek_active(purpose, channel, ident):
    """True if a live (unconsumed, unexpired) code exists — used to answer
    'resend' politely without leaking whether the account exists."""
    rec = cache.get(_key(purpose, channel, ident))
    return bool(rec and rec.get('expires_at', 0) > time.time()
               and not rec.get('locked_until', 0) > time.time())


def verify(purpose, channel, ident, code):
    """Check a code. Returns ``(ok, error)`` where error is ``'invalid'`` (wrong,
    expired, already used or never issued: deliberately indistinguishable) or
    ``'locked'``. On success the code is consumed.

    Every failure counts toward the lockout for this identity, even when no
    code (or no account) exists, so a caller can't tell a real pending account
    from an unknown email by how it fails.
    """
    key = _key(purpose, channel, ident)
    now = time.time()
    rec = cache.get(key) or {}

    if rec.get('locked_until', 0) > now:
        return False, 'locked'
    live = bool(rec.get('hash')) and now <= rec.get('expires_at', 0)
    candidate = str(code).strip()
    if live and candidate.isdigit() and len(candidate) == 6 \
            and hmac.compare_digest(_hash(candidate), rec['hash']):
        cache.delete(key)          # single use: a replay is 'invalid'
        return True, None

    failed = {**rec, 'attempts': rec.get('attempts', 0) + 1}
    if not live:
        failed.pop('hash', None)   # an expired code can never be used again
    if failed['attempts'] >= MAX_ATTEMPTS:
        failed['locked_until'] = now + LOCKOUT_TTL
        cache.set(key, failed, timeout=LOCKOUT_TTL + 60)
        return False, 'locked'
    cache.set(key, failed, timeout=CODE_TTL + LOCKOUT_TTL)
    return False, 'invalid'


def clear(purpose, channel, ident):
    cache.delete(_key(purpose, channel, ident))
