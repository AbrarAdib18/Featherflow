from datetime import date, datetime, timedelta
from math import asin, cos, radians, sin, sqrt

from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework.decorators import api_view
from rest_framework.response import Response
from rest_framework import status

from notifications.models import Notification
from profiles.models import DoctorProfile
from .models import Consultation


def _distance(lat1, lon1, lat2, lon2):
    if None in (lat1, lon1, lat2, lon2):
        return None
    dlat, dlon = radians(float(lat2) - float(lat1)), radians(float(lon2) - float(lon1))
    a = sin(dlat / 2) ** 2 + cos(radians(float(lat1))) * cos(radians(float(lat2))) * sin(dlon / 2) ** 2
    return 6371 * 2 * asin(sqrt(a))


def _doctor_row(profile, latitude=None, longitude=None):
    distance = _distance(latitude, longitude, profile.latitude, profile.longitude)
    return {
        'id': str(profile.id),
        'user_id': str(profile.user_id),
        'name': profile.user.full_name or profile.user.email,
        'photo_url': profile.user.profile_photo_url,
        'clinic': profile.clinic_hospital_name,
        'address': profile.practice_address,
        'district': profile.practice_address,
        'latitude': float(profile.latitude) if profile.latitude is not None else None,
        'longitude': float(profile.longitude) if profile.longitude is not None else None,
        'degree': profile.veterinary_degree,
        'specialty': profile.specialty,
        'focus_area': profile.poultry_focus_area,
        'experience_years': profile.years_of_experience,
        'mode': profile.consultation_mode,
        'emergency': profile.emergency_on_call_availability,
        'available': profile.is_available,
        'verified': profile.is_verified,
        'fee': float(profile.service_fee or 0),
        'rating': float(profile.rating),
        'distance_km': round(distance, 1) if distance is not None else None,
    }


@api_view(['GET'])
def vets(request):
    try:
        latitude = float(request.query_params.get('latitude')) if request.query_params.get('latitude') else None
        longitude = float(request.query_params.get('longitude')) if request.query_params.get('longitude') else None
    except ValueError:
        return Response({'detail': 'Invalid coordinates.'}, status=400)
    qs = DoctorProfile.objects.select_related('user').filter(
        user__account_status='active',
        user__user_roles__role__name='doctor',
    ).distinct()
    rows = [_doctor_row(x, latitude, longitude) for x in qs]
    rows.sort(key=lambda x: (x['distance_km'] is None, x['distance_km'] or 0, -x['rating']))
    active_clinics = len({x['clinic'] for x in rows if x['available']})
    return Response({
        'doctors': rows,
        'summary': {
            'nearby_doctors': len(rows),
            'active_clinics': active_clinics,
            'available_now': sum(1 for x in rows if x['available']),
        },
    })


@api_view(['GET', 'POST', 'PATCH'])
def consultations(request):
    if request.method == 'GET':
        qs = Consultation.objects.filter(farmer=request.user).select_related('doctor').order_by('-created_at')
        return Response({'consultations': [{
            'id': str(x.id), 'doctor_name': x.doctor.full_name or x.doctor.email,
            'mode': x.mode, 'status': x.status, 'urgency': x.urgency_level,
            'date': x.appointment_date.isoformat(), 'time': x.appointment_time.strftime('%H:%M'),
            'fee': float(x.consultation_fee or 0),
        } for x in qs]})
    if request.method == 'PATCH':
        item = get_object_or_404(Consultation, id=request.data.get('id'), farmer=request.user)
        if item.status not in ('requested', 'accepted'):
            return Response({'detail': 'This request can no longer be cancelled.'}, status=400)
        item.status = 'cancelled'
        item.save(update_fields=['status', 'updated_at'])
        Notification.objects.create(
            user=item.doctor, title='Consultation cancelled',
            body=f'{request.user.full_name or request.user.email} cancelled a consultation request.',
            notification_type='reminder', reference_id=item.id, reference_type='consultation',
        )
        return Response({'status': item.status})

    profile = get_object_or_404(
        DoctorProfile.objects.select_related('user'), id=request.data.get('doctor_id'),
    )
    mode = request.data.get('mode', 'online')
    if profile.consultation_mode not in ('both', mode):
        return Response({'detail': f'This vet does not offer {mode} consultations.'}, status=400)
    urgency = request.data.get('urgency', 'routine')
    appointment_date = request.data.get('appointment_date') or date.today().isoformat()
    appointment_time = request.data.get('appointment_time') or (datetime.now() + timedelta(hours=1)).strftime('%H:%M')
    item = Consultation.objects.create(
        farmer=request.user, doctor=profile.user, mode=mode,
        urgency_level=urgency, appointment_date=appointment_date,
        appointment_time=appointment_time, consultation_fee=profile.service_fee,
    )
    farmer_name = request.user.full_name or request.user.email
    Notification.objects.create(
        user=profile.user, title='New consultation request',
        body=f'{farmer_name} requested an {urgency} {mode} consultation.',
        notification_type='reminder', reference_id=item.id, reference_type='consultation',
    )
    Notification.objects.create(
        user=request.user, title='Consultation requested',
        body=f'Your request with {profile.user.full_name or profile.user.email} was submitted.',
        notification_type='reminder', reference_id=item.id, reference_type='consultation',
    )
    return Response({'id': str(item.id), 'status': item.status}, status=status.HTTP_201_CREATED)
