import re
from datetime import timedelta

from django.core.validators import URLValidator
from django.core.exceptions import ValidationError as DjangoValidationError
from django.utils import timezone

from subscriptions.models import FeatureUsage

LENGTH_LIMITS = {
    'title': (5, 300),
    'abstract': (20, 5000),
    'body': (50, 20000),
}

# Minimal seed wordlist for the soft profanity/abuse filter. Extend as needed —
# this never blocks a submission, it only flags it for admin review.
FLAGGED_TERMS = {
    'scam', 'fraud', 'quack', 'miracle cure', 'guaranteed cure',
    'fuck', 'shit', 'bitch', 'asshole', 'kill yourself',
}

MAX_TAGS_PER_ARTICLE = 8
DAILY_SUBMISSION_LIMIT = 5
_URL_VALIDATOR = URLValidator(schemes=['http', 'https'])


def check_length(field, value):
    lo, hi = LENGTH_LIMITS.get(field, (0, 100000))
    length = len(str(value or '').strip())
    if length < lo:
        return f'{field} must be at least {lo} characters.'
    if length > hi:
        return f'{field} must be at most {hi} characters.'
    return None


def check_url(field, value):
    if not value:
        return None
    try:
        _URL_VALIDATOR(str(value))
    except DjangoValidationError:
        return f'{field} must be a valid http(s) URL.'
    return None


def flagged_terms(*texts):
    combined = ' '.join(str(t or '') for t in texts).lower()
    combined = re.sub(r'[^a-z0-9 ]', ' ', combined)
    return sorted({term for term in FLAGGED_TERMS if term in combined})


def check_and_increment_daily_submission(user):
    """Returns True if the researcher is still within their daily
    submit-for-review quota (and increments usage), False if exhausted.

    Only writes reset_at when actually resetting the window — the column is
    a naive TIMESTAMP (no tz) while USE_TZ=True, so re-saving an
    already-read value on every call would re-interpret it under the
    project's local TIME_ZONE each round trip and drift it further every
    save. Reading it back is always treated as UTC, matching how it was
    written (timezone.now() is UTC-based)."""
    now = timezone.now()
    usage, created = FeatureUsage.objects.get_or_create(
        user=user, feature_name='research_submission_daily',
        defaults={'usage_count': 0, 'limit_count': DAILY_SUBMISSION_LIMIT, 'reset_at': now + timedelta(days=1)},
    )
    if not created:
        reset_at = usage.reset_at
        if reset_at is not None and timezone.is_naive(reset_at):
            reset_at = timezone.make_aware(reset_at, timezone.UTC)
        if reset_at is None or now >= reset_at:
            usage.usage_count = 0
            usage.reset_at = now + timedelta(days=1)
            usage.save(update_fields=['usage_count', 'reset_at'])
    if usage.usage_count >= (usage.limit_count or DAILY_SUBMISSION_LIMIT):
        return False
    usage.usage_count += 1
    usage.last_used_at = now
    usage.save(update_fields=['usage_count', 'last_used_at'])
    return True
