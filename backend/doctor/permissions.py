from rest_framework.permissions import BasePermission


class IsDoctor(BasePermission):
    message = 'A doctor account is required.'

    def has_permission(self, request, view):
        return bool(
            request.user
            and request.user.is_authenticated
            and request.user.roles.filter(name='doctor').exists()
            and request.user.account_status == 'active'
        )

