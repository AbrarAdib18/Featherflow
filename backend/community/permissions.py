"""Shared community rules: verified badges, anonymity, mutes, and poll quota.

Design decisions (requirements §H): every role may post (not premium-gated),
anonymous posting is allowed but stays traceable to the real user for
moderation, verified badges are auto-applied from the author's role, polls are
capped at 2 per user per rolling week, and a report threshold auto-hides a post
pending admin review.
"""

from datetime import timedelta

from django.utils import timezone

from api.admin_rbac import can_perform_action, is_admin

MAX_POST_LENGTH = 2000
MAX_COMMENT_LENGTH = 1000
MAX_POLL_OPTIONS = 6
MIN_POLL_OPTIONS = 2
POLL_WEEKLY_LIMIT = 2
# A post with this many distinct pending reports is auto-hidden ('flagged')
# until an admin reviews it.
REPORT_AUTOHIDE_THRESHOLD = 5

ANONYMOUS_NAME = 'Anonymous Farmer'

# role name -> (badge key, human label). First match wins, in this order.
_BADGE_ROLES = [
    ('researcher', ('researcher', 'Verified Researcher')),
    ('doctor', ('doctor', 'Verified Vet')),
    ('pharmacy', ('pharmacy', 'Verified Pharmacy')),
]


def verified_badge(user):
    """The badge to show next to a non-anonymous author, or None. Team
    Featherflow staff (any admin-panel role) get the official badge."""
    if user is None:
        return None
    roles = set(user.role_names)
    if is_admin(user):
        return {'type': 'team', 'label': 'Team Featherflow'}
    for role_name, (key, label) in _BADGE_ROLES:
        if role_name in roles:
            # doctors/pharmacies only earn the badge once the account is verified
            if key in ('doctor', 'pharmacy') and not user.is_verified:
                continue
            if key == 'researcher':
                profile = getattr(user, 'researcher_profile', None)
                if not (profile and profile.is_verified):
                    continue
            return {'type': key, 'label': label}
    return None


def is_moderator(user, action='view'):
    """True if the user may run ``action`` on the community module in the admin
    panel (view / edit / suspend / delete per the RBAC matrix)."""
    return can_perform_action(user, 'community', action)


def active_mute(user):
    """The user's live community mute, or None. Lazily deactivates one that has
    passed its ``expires_at`` so callers can treat the result as authoritative."""
    from community.models import CommunityMute

    mute = CommunityMute.objects.filter(user=user, is_active=True).order_by('-created_at').first()
    if mute is None:
        return None
    if mute.expires_at and mute.expires_at <= timezone.now():
        mute.is_active = False
        mute.save(update_fields=['is_active', 'updated_at'])
        return None
    return mute


def poll_quota_ok(user):
    from community.models import Post

    since = timezone.now() - timedelta(days=7)
    used = Post.objects.filter(
        author=user, post_type='poll', created_at__gte=since,
    ).exclude(status='removed').count()
    return used < POLL_WEEKLY_LIMIT


def display_author(user, is_anonymous):
    """The author block the feed renders. Anonymous posts hide identity from
    other users; ``real_author_id`` is always included for admin tooling and is
    filtered out before the payload reaches a non-moderator (see views)."""
    if is_anonymous:
        return {
            'id': None, 'name': ANONYMOUS_NAME, 'initial': 'A',
            'role': 'Community member', 'badge': None, 'anonymous': True,
            'real_author_id': str(user.id),
        }
    name = user.full_name or user.email
    roles = user.role_names
    return {
        'id': str(user.id), 'name': name, 'initial': (name or '?')[0].upper(),
        'role': roles[0].replace('_', ' ').title() if roles else 'Community member',
        'badge': verified_badge(user), 'anonymous': False,
        'real_author_id': str(user.id),
    }
