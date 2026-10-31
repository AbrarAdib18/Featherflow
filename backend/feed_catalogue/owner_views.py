"""Feed Inventory Owner — own profile.

Reachable at every lifecycle stage (no suspend/appeal flow exists for this
role today — see FEED_MARKETPLACE_ADMIN_AUDIT.md). Photo upload reuses the
platform-wide ``POST/DELETE /api/auth/profile-photo/`` endpoint
(``verification.views.profile_photo`` writes ``User.profile_photo_url``,
which works for every role) rather than a feed-specific upload endpoint.
"""
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from profiles.models import FeedOwnerProfile

from .owner_permissions import IsFeedOwnerAccount


def _profile_json(user, profile):
    return {
        'id': str(user.id),
        'full_name': user.full_name or '',
        'email': user.email,
        'phone': user.phone or '',
        'role': 'feed_owner',
        'role_label': 'Feed Inventory Owner',
        'business_name': profile.business_name,
        'inventory_location': profile.inventory_location,
        'assigned_categories': profile.assigned_categories or [],
        'profile_photo_url': user.profile_photo_url or profile.profile_photo_url or '',
        'status': profile.status,
        'created_at': profile.created_at.isoformat() if profile.created_at else None,
        'updated_at': profile.updated_at.isoformat() if profile.updated_at else None,
    }


@api_view(['GET', 'PATCH'])
@permission_classes([IsFeedOwnerAccount])
def profile(request):
    profile_obj, _created = FeedOwnerProfile.objects.get_or_create(user=request.user)
    if request.method == 'GET':
        return Response(_profile_json(request.user, profile_obj))

    data = request.data
    user_fields = []
    if 'full_name' in data:
        request.user.full_name = str(data['full_name']).strip()
        user_fields.append('full_name')
    if 'phone' in data:
        request.user.phone = str(data['phone']).strip()
        user_fields.append('phone')
    if user_fields:
        request.user.save(update_fields=user_fields)

    # Business/org fields are self-service; account status stays admin-only.
    editable = {'business_name', 'inventory_location', 'assigned_categories'}
    profile_fields = []
    for field in editable & set(data.keys()):
        setattr(profile_obj, field, data[field])
        profile_fields.append(field)
    if profile_fields:
        profile_obj.save(update_fields=profile_fields)
    return Response(_profile_json(request.user, profile_obj))
