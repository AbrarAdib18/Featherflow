"""Provider-agnostic delivery of one-time codes.

Email goes through Django's configured ``EMAIL_BACKEND`` (set ``EMAIL_*`` in
backend/.env for real SMTP; the dev default is console/locmem).

SMS goes through ``settings.SMS_BACKEND``:
  * 'console' (default) — logs that a code was sent (never the code) and keeps
    the last few messages in the in-memory ``sms_outbox`` for the test suite.

A one-time code is never written to the application log
(OTP_VERIFICATION_SECURITY_AUDIT.md).
  * anything else       — wire your provider in ``send_sms_code`` below
    (Twilio / Vonage / local aggregator). It currently raises so a
    mis-configuration is loud rather than silent.
"""
import logging
from collections import deque
from datetime import datetime, timezone

from django.conf import settings
from django.core.mail import send_mail

logger = logging.getLogger('verification')

# In-memory record of SMS "sent" by the console backend, for the test suite.
# Bounded, so a long-running server without an SMS provider can't accumulate
# codes in memory.
sms_outbox = deque(maxlen=50)


def _now_iso():
    return datetime.now(timezone.utc).isoformat(timespec='seconds')

_SUBJECTS = {
    'email_verify': 'Verify your Featherflow email address',
    'password_reset': 'Reset your Featherflow password',
    'phone_verify': 'Verify your Featherflow phone number',
}


def _body(code, purpose):
    what = 'reset your password' if purpose == 'password_reset' else 'verify your account'
    return (f'Your Featherflow code to {what} is: {code}\n\n'
            f'It expires in 10 minutes. If you did not request this, ignore this message.')


def send_email_code(email, code, purpose):
    subject = _SUBJECTS.get(purpose, 'Your Featherflow code')
    backend = settings.EMAIL_BACKEND.rsplit('.', 1)[-1]
    try:
        send_mail(subject, _body(code, purpose),
                  settings.DEFAULT_FROM_EMAIL, [email], fail_silently=False)
        logger.info(
            'OTP email sent: to=%s purpose=%s subject=%r backend=%s at=%s',
            email, purpose, subject, backend, _now_iso())
        return True
    except Exception as exc:  # never break the flow on a mail outage
        logger.warning(
            'OTP email delivery FAILED: to=%s purpose=%s backend=%s at=%s :: %s',
            email, purpose, backend, _now_iso(), exc)
        return False


def send_sms_code(phone, code, purpose):
    backend = getattr(settings, 'SMS_BACKEND', 'console')
    message = _body(code, purpose)

    if backend == 'console':
        # No SMS provider wired yet: record that a code was "sent", never the
        # code itself, so live codes can't end up in aggregated server logs.
        logger.info(
            'OTP SMS (console stub): to=%s purpose=%s at=%s (no SMS provider configured)',
            phone, purpose, _now_iso())
        sms_outbox.append({'to': phone, 'purpose': purpose, 'code': code, 'message': message})
        return True

    # ── Plug a real SMS provider here ───────────────────────────────────────
    # Example (Twilio):
    #   from twilio.rest import Client
    #   client = Client(settings.TWILIO_ACCOUNT_SID, settings.TWILIO_AUTH_TOKEN)
    #   client.messages.create(to=phone, from_=settings.TWILIO_FROM_NUMBER, body=message)
    #   return True
    raise NotImplementedError(
        f'SMS_BACKEND={backend!r} has no implementation. '
        f'Add it in verification/delivery.py::send_sms_code.')


def send_code(channel, destination, code, purpose):
    if channel == 'phone':
        return send_sms_code(destination, code, purpose)
    return send_email_code(destination, code, purpose)
