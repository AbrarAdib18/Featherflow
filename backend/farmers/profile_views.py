"""Farmer profile — read/update the FarmerProfile + primary Farm, upload farm
photos. Signup captures these once; this is the only place a farmer can edit
them afterwards.
"""
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from farms.models import Farm
from profiles.models import FarmerProfile

from .services import IsFarmer, farm_for, notify, store_image

FARM_TYPES = {'broiler', 'layer', 'breeder', 'hatchery', 'mixed', 'backyard'}
EXPERIENCE_LEVELS = {'beginner', 'intermediate', 'expert'}

# FarmerProfile text/number fields the farmer may edit.
PROFILE_FIELDS = {
    'farm_name': str, 'owner_name': str, 'farm_location': str, 'farm_address': str,
    'farm_registration_number': str, 'primary_diseases_faced': str, 'feed_type': str,
    'feed_sourcing_method': str, 'existing_vet_consultant': str,
    'number_of_birds': int, 'years_in_farming': int, 'number_of_active_workers': int,
}


def _profile_json(profile, farm):
    user = profile.user
    return {
        'id': str(profile.id),
        'farm_name': profile.farm_name,
        'owner_name': profile.owner_name,
        'farm_location': profile.farm_location,
        'farm_address': profile.farm_address,
        'farm_type': profile.farm_type or 'mixed',
        'number_of_birds': profile.number_of_birds or 0,
        'farm_registration_number': profile.farm_registration_number or '',
        'years_in_farming': profile.years_in_farming or 0,
        'experience_level': profile.experience_level or '',
        'primary_diseases_faced': profile.primary_diseases_faced or '',
        'feed_type': profile.feed_type or '',
        'feed_sourcing_method': profile.feed_sourcing_method or '',
        'existing_vet_consultant': profile.existing_vet_consultant or '',
        'number_of_active_workers': profile.number_of_active_workers or 0,
        'consent_data_collection': bool(profile.consent_data_collection),
        'farm_photos': profile.farm_photos or [],
        'is_verified': profile.approved_by_admin_id is not None,
        'verification_status': 'verified' if profile.approved_by_admin_id else 'pending',
        'farm_id': str(farm.id),
        'total_sheds': farm.total_sheds or 0,
        'account': {
            'full_name': user.full_name,
            'email': user.email,
            'phone': user.phone,
            'profile_photo_url': user.profile_photo_url or '',
            'preferred_language': user.preferred_language or 'en',
            'emergency_contact_name': user.emergency_contact_name or '',
            'emergency_contact_phone': user.emergency_contact_phone or '',
            'present_address': user.present_address,
            'account_status': user.account_status,
            'is_verified': bool(user.is_verified),
            'bank_mobile_payment_details': user.bank_mobile_payment_details or {},
        },
    }


@api_view(['GET', 'PUT', 'PATCH'])
@permission_classes([IsFarmer])
def profile(request):
    farm = farm_for(request.user)
    fp = FarmerProfile.objects.get(user=request.user)
    if request.method == 'GET':
        return Response(_profile_json(fp, farm))

    data = request.data
    try:
        for field, caster in PROFILE_FIELDS.items():
            if field in data and data[field] not in (None, ''):
                value = caster(data[field]) if caster is int else str(data[field]).strip()
                setattr(fp, field, value)
        if data.get('farm_type'):
            ft = str(data['farm_type']).lower()
            if ft not in FARM_TYPES:
                return Response({'detail': f'farm_type must be one of {sorted(FARM_TYPES)}.'}, status=400)
            fp.farm_type = ft
        if data.get('experience_level'):
            el = str(data['experience_level']).lower()
            if el not in EXPERIENCE_LEVELS:
                return Response({'detail': f'experience_level must be one of {sorted(EXPERIENCE_LEVELS)}.'}, status=400)
            fp.experience_level = el
        if 'consent_data_collection' in data:
            fp.consent_data_collection = bool(data['consent_data_collection'])
        fp.save()
    except (ValueError, TypeError) as exc:
        return Response({'detail': str(exc)}, status=status.HTTP_400_BAD_REQUEST)

    # Keep the farm-management row (used by consultation booking + cost mgmt) in step.
    Farm.objects.filter(pk=farm.id).update(
        farm_name=fp.farm_name, farm_type=fp.farm_type or 'mixed',
        location=fp.farm_location, address=fp.farm_address,
        registration_number=fp.farm_registration_number)

    # Account-level fields live on users.
    user = request.user
    for src, attr in (('emergency_contact_name', 'emergency_contact_name'),
                      ('emergency_contact_phone', 'emergency_contact_phone'),
                      ('preferred_language', 'preferred_language'),
                      ('present_address', 'present_address')):
        if data.get(src):
            setattr(user, attr, str(data[src]).strip())
    if isinstance(data.get('bank_mobile_payment_details'), dict):
        user.bank_mobile_payment_details = data['bank_mobile_payment_details']
    user.save()

    farm.refresh_from_db()
    return Response(_profile_json(FarmerProfile.objects.get(user=request.user), farm))


@api_view(['POST', 'DELETE'])
@permission_classes([IsFarmer])
def upload_photo(request):
    fp = FarmerProfile.objects.get(user=request.user)
    photos = list(fp.farm_photos or [])
    if request.method == 'DELETE':
        url = request.data.get('image_url')
        photos = [p for p in photos if p != url]
        fp.farm_photos = photos
        fp.save(update_fields=['farm_photos', 'updated_at'])
        return Response({'farm_photos': photos})

    if len(photos) >= 12:
        return Response({'detail': 'A farm can keep up to 12 photos.'}, status=400)
    url, error = store_image(request, 'farm-photos')
    if error:
        return Response({'detail': error}, status=status.HTTP_400_BAD_REQUEST)
    photos.append(url)
    fp.farm_photos = photos
    fp.save(update_fields=['farm_photos', 'updated_at'])
    return Response({'image_url': url, 'farm_photos': photos}, status=status.HTTP_201_CREATED)
