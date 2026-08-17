from rest_framework.permissions import BasePermission


class IsFarmer(BasePermission):
    message = 'A farmer account is required.'

    def has_permission(self, request, view):
        return bool(
            request.user and request.user.is_authenticated
            and request.user.account_status == 'active'
            and request.user.roles.filter(name='farmer').exists()
        )
