"""Pharmacy-account-wide permission classes.

`IsPharmacyUser` (pharmacy/views.py) requires `account_status == 'active'` and
therefore 403s a pending/suspended pharmacy on EVERY endpoint it guards —
correct for catalogue/order/supplier mutations (those must stay locked until
approval), but wrong for profile/dashboard/chat/appeal, which the spec
explicitly requires to stay reachable at every lifecycle stage. `IsPharmacyAccount`
is the same role check without the active-only gate.
"""
from rest_framework.permissions import BasePermission


class IsPharmacyAccount(BasePermission):
    def has_permission(self, request, view):
        user = request.user
        return bool(user and user.is_authenticated and (
            user.is_superuser or user.roles.filter(name='pharmacy').exists()
        ))
