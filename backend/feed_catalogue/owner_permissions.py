"""Feed Inventory Owner account-wide permission class.

Mirrors pharmacy/permissions.py::IsPharmacyAccount exactly — a plain role
check with no active-status gate, so profile/chat stay reachable at every
lifecycle stage. Feed Inventory Owner is deliberately NOT panel_type='admin'
(feed_owner_extension.sql), so it never satisfies api.admin_rbac.IsAdminUser
on any admin-panel endpoint — every "must not access other admin panels"
restriction in the spec is therefore enforced by construction, not by an
extra check that could be forgotten on a new admin endpoint.
"""
from rest_framework.permissions import BasePermission


class IsFeedOwnerAccount(BasePermission):
    def has_permission(self, request, view):
        user = request.user
        return bool(user and user.is_authenticated and (
            user.is_superuser or user.roles.filter(name='feed_owner').exists()
        ))
