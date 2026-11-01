"""One serializer for every notification feed.

Used by `/api/notifications/` (the inbox), `/api/me/updates/` (the app-wide
poller behind toasts) and `/api/community/notifications/`. See
NOTIFICATION_TIMING_AND_NAVIGATION_AUDIT.md.

Timing
------
`notifications.created_at` is `timestamp without time zone` holding the UTC
wall-clock (`auto_now_add` writes `timezone.now()`, the column default writes
`now()` in a UTC session), so Django reads it back naive. Every feed used to
hand that naive value to `timesince()`, which then compares it with naive
`datetime.now()` — the server's *local* time (Asia/Dhaka, UTC+6) — so a
notification created this second came back as "6 hours ago". Here the naive
value is labelled UTC (the same convention as `api/admin_shifts._aware` and
`community.views._aware`), returned as ISO 8601 *with* an offset, and the
label is computed from that aware value.

Navigation
----------
The backend owns the tap destination. It is resolved from the recipient's own
role(s) and the notification's `reference_type`, because the same type goes to
different people (a `pharmacy_order` notification goes to the farmer *and* the
pharmacy; `delivery_order` to the rider *and* admins). Admin destinations are
only returned when the recipient's role can actually view that module, and
object-specific destinations are only returned when the object still exists
and the recipient is one of its participants.
"""
from datetime import timezone as dt_timezone

from django.utils import timezone

PANEL_PRIORITY = ('admin', 'doctor', 'pharmacy', 'delivery', 'research', 'farmer')


# ── time ───────────────────────────────────────────────────────────────────

def aware_created_at(notification):
    dt = notification.created_at
    if dt is not None and timezone.is_naive(dt):
        dt = dt.replace(tzinfo=dt_timezone.utc)
    return dt


def relative_time(created_at, now=None):
    """Just now / 1 min ago / N mins ago / 1 hour ago / N hours ago / 1 day ago /
    N days ago / 'Sep 22, 2026' (7+ days). A timestamp in the future (clock
    skew) reads as "Just now", never as a negative or nonsensical value."""
    if created_at is None:
        return ''
    now = now or timezone.now()
    seconds = int((now - created_at).total_seconds())
    if seconds < 60:
        return 'Just now'
    minutes = seconds // 60
    if minutes < 60:
        return '1 min ago' if minutes == 1 else f'{minutes} mins ago'
    hours = minutes // 60
    if hours < 24:
        return '1 hour ago' if hours == 1 else f'{hours} hours ago'
    days = hours // 24
    if days < 7:
        return '1 day ago' if days == 1 else f'{days} days ago'
    return timezone.localtime(created_at).strftime('%b %d, %Y')


# ── role / panel resolution ───────────────────────────────────────────────

def user_panels(user):
    names = {r.name for r in user.roles.all()}
    panels = set()
    for name in names:
        if name == 'admin' or name.startswith('admin_') or name == 'feed_admin':
            panels.add('admin')
        elif name == 'researcher':
            panels.add('research')
        elif name in ('farmer', 'doctor', 'pharmacy', 'delivery'):
            panels.add(name)
    return [p for p in PANEL_PRIORITY if p in panels]


# panel -> reference_type -> (route, target_type, admin_permission_module)
# A route containing "{id}" is object-specific and needs a reference_id.
_ROUTES = {
    'farmer': {
        'consultation': ('/farmer/find-vet/consultations', 'consultation', None),
        'consultation_payment': ('/farmer/find-vet/consultations', 'consultation', None),
        'consultation_dispute': ('/farmer/find-vet/consultations', 'consultation', None),
        'prescription': ('/farmer/find-vet/consultations', 'consultation', None),
        'follow_up': ('/farmer/find-vet/consultations', 'consultation', None),
        'conversation': ('/farmer/find-vet/chats', 'conversation', None),
        'loan': ('/farmer/cost-management/loans', 'loan', None),
        'expense': ('/farmer/cost-management/expenses', 'expense', None),
        'cashout': ('/farmer/cost-management', 'cashout', None),
        'feed_order': ('/farmer/feed-management/marketplace', 'feed_order', None),
        'feed_stock': ('/farmer/feed-management', 'feed_stock', None),
        'feed_low_stock': ('/farmer/feed-management', 'feed_stock', None),
        'feed_daily_reminder': ('/farmer/feed-management', 'feed', None),
        'feed_stage_upcoming': ('/farmer/feed-management', 'feed', None),
        'feed': ('/farmer/feed-management', 'feed', None),
        'pharmacy_order': ('/farmer/pharmacy', 'pharmacy_order', None),
        'worker': ('/farmer/labor', 'worker', None),
        'subscription_plan': ('/subscription', 'subscription', None),
        'community_post': ('/community/post/{id}', 'community_post', None),
    },
    'doctor': {
        'consultation': ('/doctor/appointments', 'consultation', None),
        'consultation_dispute': ('/doctor/appointments', 'consultation', None),
        'consultation_payment': ('/doctor/earnings', 'consultation', None),
        'consultation_rating': ('/doctor/earnings', 'consultation_rating', None),
        'follow_up': ('/doctor/followups', 'consultation', None),
        'conversation': ('/doctor/messenger', 'conversation', None),
        'community_post': ('/community/post/{id}', 'community_post', None),
    },
    'pharmacy': {
        'pharmacy_order': ('/pharmacy/orders', 'pharmacy_order', None),
        'pharmacy_medicine': ('/pharmacy/catalogue', 'pharmacy_medicine', None),
        'admin_pharmacy': ('/pharmacy/profile', 'pharmacy', None),
        'community_post': ('/community/post/{id}', 'community_post', None),
    },
    'delivery': {
        'delivery_order': ('/delivery/orders', 'delivery_order', None),
        'delivery_nearby': ('/delivery/orders', 'delivery_order', None),
        'delivery_payout': ('/delivery/earnings', 'delivery_payout', None),
        'community_post': ('/community/post/{id}', 'community_post', None),
    },
    'research': {
        'article': ('/research/papers', 'article', None),
        'profile_change_application': ('/research/profile', 'profile_change_application', None),
        'community_post': ('/community/post/{id}', 'community_post', None),
    },
    'admin': {
        'admin_approval_queue': ('/admin/approvals', 'approval', 'approvals'),
        'admin_escalation': ('/admin/oversight', 'escalation', 'oversight'),
        'support_ticket': ('/admin/support', 'support_ticket', 'support'),
        'consultation_dispute': ('/admin/doctors', 'consultation_dispute', 'doctors'),
        'delivery_order': ('/admin/delivery', 'delivery_order', 'delivery'),
        'delivery_payout': ('/admin/delivery', 'delivery_payout', 'delivery'),
        'pharmacy_order': ('/admin/pharmacy', 'pharmacy_order', 'pharmacy'),
        'pharmacy_medicine': ('/admin/pharmacy', 'pharmacy_medicine', 'pharmacy'),
        'admin_pharmacy': ('/admin/pharmacy', 'pharmacy', 'pharmacy'),
        'article': ('/admin/content', 'article', 'articles'),
        'profile_change_application': ('/admin/content', 'profile_change_application', 'research'),
        'community_moderation': ('/admin/community', 'community_report', 'community'),
        'cashout': ('/admin/cashouts/pending', 'cashout', 'cashouts'),
        'feed_order': ('/admin/feed', 'feed_order', 'feed-orders'),
        # special-cased below (not module-permission based)
        'admin_shift': ('/admin/payroll', 'admin_shift', '__super__'),
        'admin_payment': ('/admin/earnings', 'admin_payment', '__hourly__'),
    },
}

NAVIGABLE_TYPES = sorted({t for routes in _ROUTES.values() for t in routes})


def _admin_allowed(user, module):
    from api.admin_rbac import admin_tier, can_perform_action, is_super_admin
    if module is None:
        return True
    if module == '__super__':
        return is_super_admin(user)
    if module == '__hourly__':
        tier = admin_tier(user)
        return tier is not None and tier > 1
    return can_perform_action(user, module, 'view')


# ── object availability (bulk, one query per type per page) ───────────────

def _available_targets(user, notifications):
    """{(reference_type, reference_id): bool} for the object-checked types —
    exists *and* the recipient is a participant. Anything not checked here is a
    list destination scoped to the user server-side, so it needs no check."""
    by_type = {}
    for n in notifications:
        if n.reference_id and n.reference_type in ('consultation', 'conversation', 'community_post'):
            by_type.setdefault(n.reference_type, set()).add(n.reference_id)
    result = {}
    if 'consultation' in by_type:
        from django.db.models import Q
        from consultations.models import Consultation
        ok = set(Consultation.objects.filter(pk__in=by_type['consultation']).filter(
            Q(farmer_id=user.id) | Q(doctor_id=user.id)).values_list('id', flat=True))
        result.update({('consultation', i): i in ok for i in by_type['consultation']})
    if 'conversation' in by_type:
        from django.db.models import Q
        from doctor.models import Conversation
        ok = set(Conversation.objects.filter(pk__in=by_type['conversation']).filter(
            Q(participant_one_id=user.id) | Q(participant_two_id=user.id)).values_list('id', flat=True))
        result.update({('conversation', i): i in ok for i in by_type['conversation']})
    if 'community_post' in by_type:
        from community.models import Post as CommunityPost
        ok = set(CommunityPost.objects.filter(
            pk__in=by_type['community_post'], status='active').values_list('id', flat=True))
        result.update({('community_post', i): i in ok for i in by_type['community_post']})
    return result


def navigation_for(notification, user, panels, availability):
    """`{"route", "target_type", "target_id", "available"}`, or None when this
    notification has no meaningful destination for this recipient."""
    ref_type = notification.reference_type or ''
    for panel in panels:
        spec = _ROUTES.get(panel, {}).get(ref_type)
        if spec is None:
            continue
        route, target_type, admin_module = spec
        if panel == 'admin' and not _admin_allowed(user, admin_module):
            continue
        target_id = str(notification.reference_id) if notification.reference_id else None
        available = availability.get((ref_type, notification.reference_id), True)
        if '{id}' in route:
            if not target_id:
                continue  # object route but nothing to open
            route = route.replace('{id}', target_id) if available else None
        return {
            'route': route if available else None,
            'target_type': target_type,
            'target_id': target_id,
            'available': available,
        }
    return None


# ── public ─────────────────────────────────────────────────────────────────

def serialize_notifications(user, notifications, now=None):
    notifications = list(notifications)
    now = now or timezone.now()
    panels = user_panels(user)
    availability = _available_targets(user, notifications)
    rows = []
    for n in notifications:
        created = aware_created_at(n)
        rows.append({
            'id': str(n.id),
            'title': n.title,
            'body': n.body,
            'type': n.notification_type,
            'reference_id': str(n.reference_id) if n.reference_id else None,
            'reference_type': n.reference_type,
            'is_read': n.is_read,
            'created_at': created.isoformat() if created else None,
            # Kept for older clients; current Flutter recomputes it from
            # created_at so the label never goes stale on screen.
            'time': relative_time(created, now),
            'navigation': navigation_for(n, user, panels, availability),
        })
    return rows
