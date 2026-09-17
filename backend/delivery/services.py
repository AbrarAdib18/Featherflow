"""Shared rider-capacity / active-order logic for the delivery module.

Used by `delivery/views.py` (the rider's own dashboard) and by every admin
surface that assigns a `DeliveryOrder` to a rider — pharmacy's
`api/admin_views.py::_assign_from_queue`/`_reassign_order` and feed's
`feed_catalogue/order_admin_views.py::order_assign`. Previously each of
those three call sites had its own inline status-list literal and no shared
concept of "how many orders can one rider carry at once" — this module gives
them one definition instead of three that could silently drift apart.

See FEED_AND_DATA_INTEGRITY_AUDIT.md and OPERATIONS_RUNBOOK.md §11 for the
bug this fixes: a rider with two concurrent in-progress deliveries used to
have the older one become invisible in both the API and the UI.
"""
from .models import DeliveryOrder

# Statuses where the rider has committed to the delivery (accepted the offer)
# and it is still in progress — used for the rider's "Active" list/dashboard.
ACTIVE_ORDER_STATUSES = ('accepted', 'picked_up', 'on_the_way')

# ACTIVE_ORDER_STATUSES plus 'pending' (offered to the rider, awaiting their
# accept/reject) — everything currently occupying a rider's capacity whether
# or not they've responded yet. 'pending' offers are intentionally excluded
# from ACTIVE_ORDER_STATUSES (they're already surfaced separately via the
# rider's "New requests" queue / `requests_view`) but must still count
# against the capacity limit below, otherwise an admin could flood a rider
# with unanswered offers even while their *active* count looks fine.
OPEN_ORDER_STATUSES = ('pending',) + ACTIVE_ORDER_STATUSES

# Soft operational cap on how many orders (pending + active, combined) one
# rider can hold at once. Multiple concurrent ACTIVE deliveries are
# intentionally supported by this platform (a rider finishing one drop-off
# while already carrying the next is normal, not a bug) — this cap only
# stops runaway over-assignment, it does not limit a rider to one at a time.
# Not currently configurable per-rider or per-deployment; a single constant
# is enough for the current operational scale. See OPERATIONS_RUNBOOK.md §11.
MAX_CONCURRENT_ORDERS_PER_RIDER = 3

# Lower number sorts first — closer to completion is shown/prioritized first
# so a rider's next action is always at the top of their active list.
_STATUS_PRIORITY = {'on_the_way': 0, 'picked_up': 1, 'accepted': 2}

# Defensive cap on how many active orders the dashboard response will ever
# list, independent of MAX_CONCURRENT_ORDERS_PER_RIDER (which should already
# make this unreachable) — protects the response size if the cap is ever
# raised or bypassed by a direct DB write (e.g. demo-data seeding).
MAX_ACTIVE_ORDERS_IN_RESPONSE = 20


def open_order_count(rider):
    """How many orders (pending + active) currently occupy this rider's
    capacity. Scoped to `delivery_person=rider` only — never counts or
    exposes another rider's orders."""
    return DeliveryOrder.objects.filter(
        delivery_person=rider, status__in=OPEN_ORDER_STATUSES).count()


def capacity_error(rider):
    """None if `rider` has room for one more order; otherwise a human-
    readable 409 message. Callers must still create the order themselves —
    this only answers "is there room", it takes no action itself."""
    count = open_order_count(rider)
    if count >= MAX_CONCURRENT_ORDERS_PER_RIDER:
        name = rider.user.full_name or rider.user.email
        return (f'{name} already has {count} open deliveries '
                f'(limit {MAX_CONCURRENT_ORDERS_PER_RIDER} per rider). '
                'Choose another rider or wait for one of theirs to finish.')
    return None


def active_orders_for(rider):
    """All in-progress orders for `rider`, ordered deterministically:
    status priority (closest to completion first), then oldest-assigned
    first within the same status. Bounded by MAX_ACTIVE_ORDERS_IN_RESPONSE.
    Scoped to `delivery_person=rider` only — never exposes another rider's
    orders, satisfying the same least-privilege guarantee `requests_view`/
    `orders_view` already provide."""
    orders = list(DeliveryOrder.objects.filter(
        delivery_person=rider, status__in=ACTIVE_ORDER_STATUSES,
    ).order_by('assigned_at'))
    orders.sort(key=lambda o: _STATUS_PRIORITY.get(o.status, 99))
    return orders[:MAX_ACTIVE_ORDERS_IN_RESPONSE]
