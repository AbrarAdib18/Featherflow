import uuid
from datetime import date, timedelta

from django.contrib.auth import update_session_auth_hash
from django.db import transaction
from django.utils import timezone
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import BasePermission
from rest_framework.response import Response

from audit.models import ActivityLog, AdminPanelRecord
from consultations.models import Consultation
from notifications.models import Notification
from profiles.models import DoctorProfile
from users.models import Role, User, UserRole


SEEDS = {
    'subscription-plans': [
        {'id': 'PLAN-FREE', 'name': 'Free', 'price': 0, 'currency': 'BDT', 'duration_days': None, 'scan_limit': 3, 'status': 'Active'},
        {'id': 'PLAN-BASIC', 'name': 'Monthly Basic', 'price': 299, 'currency': 'BDT', 'duration_days': 30, 'scan_limit': 50, 'status': 'Active'},
        {'id': 'PLAN-PREMIUM', 'name': 'Monthly Premium', 'price': 599, 'currency': 'BDT', 'duration_days': 30, 'scan_limit': None, 'status': 'Active'},
        {'id': 'PLAN-YEARLY', 'name': 'Yearly', 'price': 4999, 'currency': 'BDT', 'duration_days': 365, 'scan_limit': None, 'status': 'Active'},
    ],
    'diseases': [
        {'id': 'DIS-NEWCASTLE', 'name': 'Newcastle Disease', 'severity': 'Critical', 'requires_immediate_vet': True, 'status': 'Active', 'symptoms': ['Sudden death', 'Twisted neck', 'Breathing difficulty', 'Green diarrhea']},
        {'id': 'DIS-FOWL-POX', 'name': 'Fowl Pox', 'severity': 'Medium', 'requires_immediate_vet': False, 'status': 'Active', 'symptoms': ['Wart-like lesions', 'Reduced feed intake']},
        {'id': 'DIS-COCCIDIOSIS', 'name': 'Coccidiosis', 'severity': 'High', 'requires_immediate_vet': True, 'status': 'Active', 'symptoms': ['Bloody diarrhea', 'Lethargy', 'Weight loss']},
        {'id': 'DIS-AVIAN-FLU', 'name': 'Avian Influenza', 'severity': 'Critical', 'requires_immediate_vet': True, 'status': 'Active', 'symptoms': ['High mortality', 'Respiratory distress', 'Swollen head']},
        {'id': 'DIS-MAREK', 'name': "Marek Disease", 'severity': 'High', 'requires_immediate_vet': False, 'status': 'Active', 'symptoms': ['Progressive paralysis', 'Weight loss', 'Eye lesions']},
    ],
    'delivery-orders': [
        {'id': 'DO-1024', 'customer': 'Karim Hossain', 'destination': 'Dhanmondi, Dhaka', 'items': '3 medicines', 'status': 'In Transit', 'eta': '25 min', 'assigned_rider': 'Rahim Uddin'},
        {'id': 'DO-1025', 'customer': 'Jamal Mia', 'destination': 'Uttara, Dhaka', 'items': '2 vaccines', 'status': 'Pending', 'eta': '45 min', 'assigned_rider': None},
        {'id': 'DO-1026', 'customer': 'Green Valley Farm', 'destination': 'Gazipur', 'items': '1 supplement', 'status': 'Delayed', 'eta': '1 hr ago', 'assigned_rider': 'Belal Ahmed'},
        {'id': 'DO-1027', 'customer': 'Comilla Poultry Co.', 'destination': 'Comilla', 'items': '4 medicines', 'status': 'Failed', 'eta': 'Yesterday', 'assigned_rider': 'Hasan Ali'},
    ],
    'riders': [
        {'id': 'R001', 'name': 'Rahim Uddin', 'zone': 'Dhaka North', 'status': 'Online', 'rating': 4.8, 'active_orders': 2, 'completed_orders': 324},
        {'id': 'R002', 'name': 'Hasan Ali', 'zone': 'Dhaka South', 'status': 'Online', 'rating': 4.7, 'active_orders': 1, 'completed_orders': 287},
        {'id': 'R003', 'name': 'Imran Khan', 'zone': 'Narayanganj', 'status': 'Offline', 'rating': 4.5, 'active_orders': 0, 'completed_orders': 213},
        {'id': 'R004', 'name': 'Belal Ahmed', 'zone': 'Gazipur', 'status': 'Online', 'rating': 4.6, 'active_orders': 1, 'completed_orders': 155},
    ],
    'pharmacies': [
        {'id': 'P001', 'name': 'MedPlus Veterinary Rx', 'location': 'Rajshahi', 'status': 'Verified', 'product_count': 142, 'monthly_orders': 380, 'rating': 4.7},
        {'id': 'P002', 'name': 'AgroVet Supplies', 'location': 'Dhaka', 'status': 'Pending', 'product_count': 78, 'monthly_orders': 0, 'rating': 0.0},
        {'id': 'P003', 'name': 'PoultryMed Store', 'location': 'Chittagong', 'status': 'Verified', 'product_count': 94, 'monthly_orders': 210, 'rating': 4.4},
    ],
    'medicines': [
        {'id': 'M001', 'name': 'Oxytetracycline 20%', 'pharmacy': 'MedPlus Veterinary Rx', 'status': 'Approved', 'price': 420, 'expires_in_days': 90},
        {'id': 'M002', 'name': 'Newcastle Vaccine', 'pharmacy': 'MedPlus Veterinary Rx', 'status': 'Pending', 'price': 680, 'expires_in_days': 25},
        {'id': 'M003', 'name': 'Vitamin AD3E Supplement', 'pharmacy': 'PoultryMed Store', 'status': 'Approved', 'price': 290, 'expires_in_days': 180},
        {'id': 'M004', 'name': 'Coccidiostat Premix', 'pharmacy': 'PoultryMed Store', 'status': 'Approved', 'price': 550, 'expires_in_days': 18},
    ],
    'articles': [
        {'id': 'A001', 'title': 'Newcastle Disease Prevention in Commercial Flocks', 'author': 'Dr. Kamrul Islam', 'type': 'Research', 'status': 'Published', 'date': 'Jun 10, 2024', 'summary': 'Evidence-based prevention and vaccination guidance for commercial poultry farms.', 'featured': True},
        {'id': 'A002', 'title': 'Feed Prices Expected to Stabilize This Quarter', 'author': 'Sumaiya Islam', 'type': 'News', 'status': 'Pending', 'date': 'Jun 11, 2024', 'summary': 'A market review of feed supply and projected prices for the coming quarter.', 'featured': False},
        {'id': 'A003', 'title': 'Improving FCR Through Precision Nutrition', 'author': 'Dr. Rina Begum', 'type': 'Article', 'status': 'Pending', 'date': 'Jun 12, 2024', 'summary': 'Practical nutrition adjustments that can improve flock feed conversion ratios.', 'featured': False},
        {'id': 'A004', 'title': 'Biosecurity Checklist for Small Farms', 'author': 'Team Featherflow', 'type': 'Article', 'status': 'Published', 'date': 'Jun 8, 2024', 'summary': 'A concise daily and weekly biosecurity checklist for small poultry operations.', 'featured': False},
    ],
    'payments': [
        {'id': 'TXN-2041', 'user': 'Karim Hossain', 'type': 'Subscription', 'amount': 599, 'method': 'bKash', 'status': 'Completed', 'date': 'Jun 12, 2024'},
        {'id': 'TXN-2042', 'user': 'MedPlus Veterinary Rx', 'type': 'Medicine Order', 'amount': 2450, 'method': 'Card', 'status': 'Completed', 'date': 'Jun 12, 2024'},
        {'id': 'TXN-2043', 'user': 'Rahim Uddin', 'type': 'Cashout', 'amount': 2400, 'method': 'Nagad', 'status': 'Pending', 'date': 'Jun 11, 2024'},
        {'id': 'TXN-2044', 'user': 'Jamal Mia', 'type': 'Subscription', 'amount': 299, 'method': 'bKash', 'status': 'Failed', 'date': 'Jun 10, 2024'},
    ],
    'community-reports': [
        {'id': 'REP001', 'post_title': 'Cheap medicine available, contact me', 'author': 'Spam Account #42', 'excerpt': 'Bulk poultry medicine at the lowest price...', 'type': 'Spam', 'status': 'Open', 'report_count': 7, 'date': 'Jun 12, 2024'},
        {'id': 'REP002', 'post_title': 'This treatment always cures Newcastle', 'author': 'Farmer Alam', 'excerpt': 'Ignore vaccination and use this home remedy...', 'type': 'Misinformation', 'status': 'Open', 'report_count': 4, 'date': 'Jun 11, 2024'},
        {'id': 'REP003', 'post_title': 'Personal attack in discussion', 'author': 'User 103', 'excerpt': 'Reported abusive language directed at another member.', 'type': 'Harassment', 'status': 'Open', 'report_count': 3, 'date': 'Jun 10, 2024'},
    ],
    'community-users': [
        {'id': 'CU001', 'name': 'Karim Hossain', 'role': 'Farmer', 'posts': 84, 'helpful': 312, 'muted': False, 'verified': True},
        {'id': 'CU002', 'name': 'Sumaiya Islam', 'role': 'Researcher', 'posts': 42, 'helpful': 208, 'muted': False, 'verified': False},
        {'id': 'CU003', 'name': 'Spam Account #42', 'role': 'Farmer', 'posts': 15, 'helpful': 0, 'muted': False, 'verified': False},
    ],
    'team': [
        {'id': 'S001', 'name': 'Nusrat Jahan', 'email': 'nusrat@featherflow.com', 'role': 'Operations Admin', 'department': 'Operations', 'status': 'Active', 'joined_date': 'Jan 2024', 'last_active': '10 min ago', 'pending_approval': False},
        {'id': 'S002', 'name': 'Tanvir Hasan', 'email': 'tanvir@featherflow.com', 'role': 'Finance Admin', 'department': 'Finance', 'status': 'Active', 'joined_date': 'Feb 2024', 'last_active': '1 hour ago', 'pending_approval': False},
        {'id': 'S003', 'name': 'Raisa Ahmed', 'email': 'raisa@featherflow.com', 'role': 'Support Agent', 'department': 'Support', 'status': 'Active', 'joined_date': 'Mar 2024', 'last_active': 'Online', 'pending_approval': False},
    ],
    'support-tickets': [
        {'id': 'SUP-041', 'user': 'Karim Hossain', 'subject': 'Cannot login after password reset', 'type': 'Login Issue', 'priority': 'High', 'status': 'Open', 'date': 'Jun 12, 2024 09:15 AM', 'description': 'User reset the password via email but still receives an invalid credentials error.'},
        {'id': 'SUP-042', 'user': 'MedPlus Pharmacy', 'subject': 'Account suspended without notice', 'type': 'Account Issue', 'priority': 'High', 'status': 'Open', 'date': 'Jun 11, 2024 02:30 PM', 'description': 'Pharmacy owner requests review of an unexpected suspension.'},
        {'id': 'SUP-043', 'user': 'Rahim Uddin', 'subject': 'Delivery earnings not credited', 'type': 'Payment Issue', 'priority': 'Medium', 'status': 'Escalated', 'date': 'Jun 10, 2024 11:00 AM', 'description': 'Delivery rider reports ৳2,400 from last week was not credited.'},
        {'id': 'SUP-044', 'user': 'Sumaiya Islam', 'subject': 'Cannot access account — 2FA not working', 'type': 'Account Recovery', 'priority': 'Medium', 'status': 'Open', 'date': 'Jun 9, 2024 04:45 PM', 'description': 'Researcher lost access to 2FA after replacing her phone.'},
    ],
    'security-flags': [
        {'id': 'SF001', 'user': 'Unknown IP 192.168.45.12', 'type': 'Brute Force', 'severity': 'Critical', 'description': '47 failed login attempts in 10 minutes targeting admin panel', 'date': 'Jun 12, 2024', 'cleared': False},
        {'id': 'SF002', 'user': 'Farmer Alam', 'type': 'Suspicious Activity', 'severity': 'High', 'description': 'Account accessed from 3 countries within 2 hours', 'date': 'Jun 11, 2024', 'cleared': False},
        {'id': 'SF003', 'user': 'Spam Account #42', 'type': 'Content Abuse', 'severity': 'Medium', 'description': 'Posted 15 identical spam messages in 5 minutes', 'date': 'Jun 10, 2024', 'cleared': False},
    ],
}


class IsAdminUser(BasePermission):
    def has_permission(self, request, view):
        user = request.user
        return bool(user and user.is_authenticated and (
            user.is_superuser or user.is_staff or
            user.roles.filter(name__in=['admin', 'admin_super']).exists()
        ))


def _client_ip(request):
    forwarded = request.META.get('HTTP_X_FORWARDED_FOR')
    return (forwarded.split(',')[0].strip() if forwarded else request.META.get('REMOTE_ADDR'))


def _uuid_or_none(value):
    try:
        return uuid.UUID(str(value))
    except (TypeError, ValueError, AttributeError):
        return None


def _log(request, module, action, record_id='', old=None, new=None):
    ActivityLog.objects.create(
        user=request.user,
        module=module,
        action=action,
        entity_type=module,
        entity_id=_uuid_or_none(record_id),
        old_values=old,
        new_values=new,
        ip_address=_client_ip(request),
    )


def _seed(module):
    if module not in SEEDS:
        return
    with transaction.atomic():
        for item in SEEDS[module]:
            record, created = AdminPanelRecord.objects.get_or_create(
                module=module, record_id=item['id'], defaults={'payload': item}
            )
            if not created:
                merged = {**item, **record.payload}
                if merged != record.payload:
                    record.payload = merged
                    record.save(update_fields=['payload', 'updated_at'])


def _records(module):
    _seed(module)
    return [record.payload for record in AdminPanelRecord.objects.filter(module=module)]


def _user_json(user):
    roles = list(user.roles.values_list('name', flat=True))
    role = roles[0].replace('_', ' ').title() if roles else ('Staff' if user.is_staff else 'Farmer')
    if role.startswith('Admin'):
        role = 'Staff'
    status = {'active': 'Approved', 'pending': 'Pending', 'suspended': 'Suspended'}.get(user.account_status.lower(), user.account_status.title())
    return {
        'id': str(user.id), 'name': user.full_name or user.email.split('@')[0],
        'email': user.email, 'phone': user.phone or '', 'role': role,
        'status': status, 'location': user.present_address or user.location_service_area or 'Bangladesh',
        'joined': user.date_joined.strftime('%b %d, %Y'),
        'last_active': user.last_login.strftime('%b %d, %Y %H:%M') if user.last_login else 'Never',
        'verified': user.is_verified, 'bio': user.profile_data.get('bio', '') if isinstance(user.profile_data, dict) else '',
        'two_factor_enabled': user.two_factor_enabled,
    }


def _doctor_json(profile):
    status = (
        profile.user.account_status.title()
        if profile.user.account_status in ['suspended', 'rejected']
        else ('Verified' if profile.is_verified else 'Pending')
    )
    return {
        'id': str(profile.id), 'name': profile.user.full_name or profile.user.email,
        'specialty': profile.specialty, 'status': status,
        'rating': float(profile.rating), 'consultations': profile.user.doctor_consultations.count(),
        'response_time': '~15 min' if profile.is_available else 'Unavailable',
        'license_doc': profile.license_number,
        'clinic_name': profile.clinic_hospital_name,
        'practice_address': profile.practice_address,
        'district': profile.practice_address,
        'degree': profile.veterinary_degree,
        'university': profile.university_name,
        'graduation_year': profile.graduation_year,
        'license_authority': profile.license_issuing_authority,
        'license_expiry': profile.license_expiry_date.isoformat(),
        'focus_area': profile.poultry_focus_area,
        'years_experience': profile.years_of_experience,
        'consultation_mode': profile.consultation_mode,
        'service_fee': float(profile.service_fee or 0),
    }


def _team_json(user):
    role = user.roles.filter(name__startswith='admin_').first()
    profile = user.profile_data if isinstance(user.profile_data, dict) else {}
    return {
        'id': str(user.id),
        'name': user.full_name or user.email,
        'email': user.email,
        'role': (role.display_name or role.name.replace('_', ' ').title()) if role else 'Support Agent',
        'department': profile.get('department', 'Operations'),
        'status': 'Active' if user.account_status == 'active' else 'Inactive',
        'joined_date': user.date_joined.strftime('%b %Y'),
        'last_active': user.last_login.strftime('%b %d, %H:%M') if user.last_login else 'Never',
        'pending_approval': profile.get('pending_approval', False),
    }


def _pharmacy_json(user):
    profile = user.profile_data if isinstance(user.profile_data, dict) else {}
    owner = str(user.id)
    products = AdminPanelRecord.objects.filter(module='pharmacy-products', payload__owner_id=owner).count()
    orders = AdminPanelRecord.objects.filter(module='pharmacy-orders', payload__owner_id=owner).count()
    status = {'active': 'Verified', 'pending': 'Pending', 'suspended': 'Suspended'}.get(user.account_status, user.account_status.title())
    return {
        'id': owner,
        'name': profile.get('business_name') or profile.get('organization_name') or user.full_name or user.email,
        'location': profile.get('business_address') or profile.get('service_area') or user.present_address or 'Bangladesh',
        'status': status, 'product_count': products, 'monthly_orders': orders,
        'rating': float(profile.get('rating', 0)),
    }


@api_view(['GET'])
@permission_classes([IsAdminUser])
def admin_dashboard(request):
    pending_users = User.objects.filter(account_status='pending').count()
    pending_doctors = DoctorProfile.objects.filter(is_verified=False).count()
    return Response({
        'stats': {
            'total_users': User.objects.count(),
            'active_doctors': DoctorProfile.objects.filter(is_verified=True).count(),
            'pending_approvals': pending_users + pending_doctors,
            'open_tickets': sum(1 for x in _records('support-tickets') if x['status'] == 'Open'),
            'monthly_revenue': sum(x['amount'] for x in _records('payments') if x['status'] == 'Completed'),
            'flagged_content': sum(1 for x in _records('community-reports') if x['status'] == 'Open'),
            'deliveries_in_progress': sum(1 for x in _records('delivery-orders') if x['status'] in ['In Transit', 'Assigned']),
            'active_pharmacies': sum(1 for x in _records('pharmacies') if x['status'] == 'Verified'),
            'pending_pharmacies': sum(1 for x in _records('pharmacies') if x['status'] == 'Pending'),
            'urgent_consultations': Consultation.objects.filter(urgency_level__in=['urgent', 'emergency']).exclude(status__in=['completed', 'cancelled']).count(),
        },
        'tasks': [
            {'title': 'User approvals', 'count': pending_users, 'module': 'User Management'},
            {'title': 'Doctor verification', 'count': pending_doctors, 'module': 'Doctor & Patient'},
            {'title': 'Open support tickets', 'count': sum(1 for x in _records('support-tickets') if x['status'] == 'Open'), 'module': 'Support & Safety'},
        ],
        'activity': list(ActivityLog.objects.values('module', 'action', 'entity_id', 'created_at')[:8]),
    })


@api_view(['GET', 'POST'])
@permission_classes([IsAdminUser])
def admin_collection(request, module):
    if request.method == 'GET':
        if module == 'users':
            return Response({'results': [_user_json(u) for u in User.objects.prefetch_related('roles').all()]})
        if module == 'doctors':
            return Response({'results': [_doctor_json(p) for p in DoctorProfile.objects.select_related('user').all()]})
        if module == 'team':
            members = User.objects.filter(roles__name__startswith='admin_').prefetch_related('roles').distinct()
            return Response({'results': [_team_json(user) for user in members]})
        if module == 'pharmacies':
            pharmacies = User.objects.filter(roles__name='pharmacy').distinct()
            return Response({'results': [_pharmacy_json(user) for user in pharmacies]})
        if module == 'consultations':
            results = [{
                'id': str(c.id), 'patient': c.farmer.full_name or c.farmer.email,
                'doctor': c.doctor.full_name or c.doctor.email,
                'topic': c.review_text or c.urgency_level.title(),
                'time': f'{c.appointment_date} {c.appointment_time:%H:%M}',
                'urgent': c.urgency_level in ['urgent', 'emergency'], 'status': c.status,
            } for c in Consultation.objects.select_related('farmer', 'doctor')]
            return Response({'results': results})
        if module == 'access-logs':
            return Response({'results': list(ActivityLog.objects.values(
                'id', 'module', 'action', 'entity_id', 'created_at')[:100])})
        return Response({'results': _records(module)})

    if module == 'team':
        email = request.data.get('email', '').strip().lower()
        if not email:
            return Response({'detail': 'Email is required.'}, status=400)
        role_label = request.data.get('role', 'Support Agent')
        role_name = 'admin_' + role_label.lower().replace(' admin', '').replace(' agent', '').replace(' ', '_')
        role, _ = Role.objects.get_or_create(
            name=role_name, defaults={'panel_type': 'admin'})
        user, created = User.objects.get_or_create(
            email=email,
            defaults={
                'full_name': request.data.get('name', ''),
                'phone': request.data.get('phone') or f'pending-{uuid.uuid4().hex[:12]}',
                'date_of_birth': request.data.get('date_of_birth') or date(1970, 1, 1),
                'present_address': request.data.get('present_address') or 'Not provided',
                'consent_terms': True,
                'account_status': 'active',
                'profile_data': {'department': request.data.get('department', 'Operations')},
            },
        )
        if not created:
            return Response({'detail': 'A user with this email already exists.'}, status=400)
        user.set_password(request.data.get('temporary_password', 'FeatherflowTeam@2026'))
        user.save()
        UserRole.objects.create(user=user, role=role)
        result = _team_json(user)
        _log(request, module, 'Create', str(user.id), new=result)
        return Response(result, status=201)

    payload = dict(request.data)
    record_id = str(payload.get('id') or f'{module[:3].upper()}-{AdminPanelRecord.objects.filter(module=module).count() + 1:03d}')
    payload['id'] = record_id
    record = AdminPanelRecord.objects.create(module=module, record_id=record_id, payload=payload)
    _log(request, module, 'Create', record_id, new=record.payload)
    return Response(record.payload, status=201)


@api_view(['PATCH', 'DELETE'])
@permission_classes([IsAdminUser])
def admin_record(request, module, record_id):
    if module == 'pharmacies':
        try:
            user = User.objects.get(pk=record_id, roles__name='pharmacy')
        except (User.DoesNotExist, ValueError):
            return Response({'detail': 'Pharmacy not found.'}, status=404)
        old = _pharmacy_json(user)
        status_value = request.data.get('status')
        if request.method == 'DELETE' or status_value == 'Suspended':
            user.account_status = 'suspended'
            user.is_verified = False
        elif status_value == 'Verified':
            user.account_status = 'active'
            user.is_verified = True
        user.save(update_fields=['account_status', 'is_verified', 'updated_at'])
        result = _pharmacy_json(user)
        _log(request, module, 'Update', record_id, old=old, new=result)
        return Response(result)

    if module == 'users':
        try:
            user = User.objects.get(pk=record_id)
        except (User.DoesNotExist, ValueError):
            return Response({'detail': 'User not found.'}, status=404)
        old = _user_json(user)
        if request.method == 'DELETE':
            user.account_status = 'suspended'
        else:
            status_value = request.data.get('status')
            if status_value:
                user.account_status = {'Approved': 'active', 'Pending': 'pending', 'Suspended': 'suspended'}.get(status_value, status_value.lower())
                user.is_verified = status_value == 'Approved'
                try:
                    doctor_profile = user.doctor_profile
                except DoctorProfile.DoesNotExist:
                    doctor_profile = None
                if doctor_profile is not None:
                    doctor_profile.is_verified = status_value == 'Approved'
                    doctor_profile.is_available = status_value == 'Approved'
                    doctor_profile.save(update_fields=['is_verified', 'is_available', 'updated_at'])
            for field in ['full_name', 'phone', 'present_address', 'two_factor_enabled']:
                if field in request.data:
                    setattr(user, field, request.data[field])
            if 'bio' in request.data:
                profile_data = dict(user.profile_data or {})
                profile_data['bio'] = request.data['bio']
                user.profile_data = profile_data
        user.save()
        result = _user_json(user)
        _log(request, module, 'Update', record_id, old=old, new=result)
        return Response(result)

    if module == 'doctors':
        try:
            profile = DoctorProfile.objects.get(pk=record_id)
        except (DoctorProfile.DoesNotExist, ValueError):
            return Response({'detail': 'Doctor not found.'}, status=404)
        old = _doctor_json(profile)
        status_value = request.data.get('status')
        if status_value:
            profile.is_verified = status_value == 'Verified'
            profile.is_available = status_value == 'Verified'
            profile.save()
            profile.user.account_status = {
                'Suspended': 'suspended',
                'Rejected': 'suspended',
                'Verified': 'active',
            }.get(status_value, 'pending')
            profile.user.save(update_fields=['account_status'])
        profile_fields = {
            'specialty': 'specialty',
            'clinic_name': 'clinic_hospital_name',
            'practice_address': 'practice_address',
            'district': 'practice_address',
            'degree': 'veterinary_degree',
            'university': 'university_name',
            'license_doc': 'license_number',
            'license_authority': 'license_issuing_authority',
            'focus_area': 'poultry_focus_area',
            'consultation_mode': 'consultation_mode',
            'service_fee': 'service_fee',
            'years_experience': 'years_of_experience',
        }
        changed = []
        for api_field, model_field in profile_fields.items():
            if api_field in request.data:
                setattr(profile, model_field, request.data[api_field])
                changed.append(model_field)
        if changed:
            profile.save(update_fields=changed + ['updated_at'])
        result = _doctor_json(profile)
        _log(request, module, 'Update', record_id, old=old, new=result)
        return Response(result)

    if module == 'team':
        try:
            user = User.objects.prefetch_related('roles').get(pk=record_id)
        except (User.DoesNotExist, ValueError):
            return Response({'detail': 'Team member not found.'}, status=404)
        old = _team_json(user)
        if 'status' in request.data:
            user.account_status = 'active' if request.data['status'] == 'Active' else 'suspended'
        if 'name' in request.data:
            user.full_name = request.data['name']
        if 'email' in request.data:
            user.email = request.data['email']
        profile = dict(user.profile_data or {})
        for key in ['department', 'pending_approval']:
            if key in request.data:
                profile[key] = request.data[key]
        user.profile_data = profile
        if 'role' in request.data:
            role_label = request.data['role']
            role_name = 'admin_' + role_label.lower().replace(' admin', '').replace(' agent', '').replace(' ', '_')
            role, _ = Role.objects.get_or_create(
                name=role_name, defaults={'panel_type': 'admin'})
            user.roles.remove(*user.roles.filter(name__startswith='admin_'))
            user.roles.add(role)
        user.save()
        result = _team_json(user)
        _log(request, module, 'Update', record_id, old=old, new=result)
        return Response(result)

    _seed(module)
    try:
        record = AdminPanelRecord.objects.get(module=module, record_id=record_id)
    except AdminPanelRecord.DoesNotExist:
        return Response({'detail': 'Record not found.'}, status=404)
    old = dict(record.payload)
    if request.method == 'DELETE':
        record.delete()
        _log(request, module, 'Delete', record_id, old=old)
        return Response(status=204)
    updated = {**old, **dict(request.data)}
    record.payload = updated
    record.save(update_fields=['payload', 'updated_at'])
    if module == 'medicines' and updated.get('pharmacy_user_id'):
        try:
            pharmacy_user = User.objects.get(pk=updated['pharmacy_user_id'])
            Notification.objects.create(
                user=pharmacy_user,
                title=f'Medicine {updated.get("status", "updated").lower()}',
                body=f'{updated.get("name", "Your medicine")} was {updated.get("status", "updated").lower()} by an administrator.',
                notification_type='approval', reference_type='pharmacy_medicine',
            )
        except (User.DoesNotExist, ValueError, TypeError):
            pass
    _log(request, module, 'Update', record_id, old=old, new=updated)
    return Response(updated)


@api_view(['GET', 'PATCH', 'POST'])
@permission_classes([IsAdminUser])
def admin_profile(request):
    user = request.user
    if request.method == 'GET':
        return Response(_user_json(user) | {
            'department': user.profile_data.get('department', 'IT & Operations'),
            'notification_preferences': user.profile_data.get('notification_preferences', {
                'user_activity': True, 'system_alerts': True, 'weekly_report': False,
            }),
        })
    if request.method == 'POST':
        current_password = request.data.get('current_password')
        password = request.data.get('password')
        if not password:
            return Response({'detail': 'Password is required.'}, status=400)
        if not current_password or not user.check_password(current_password):
            return Response({'detail': 'Current password is incorrect.'}, status=400)
        user.set_password(password)
        user.save(update_fields=['password'])
        update_session_auth_hash(request, user)
        _log(request, 'Profile', 'Change Password', str(user.id))
        return Response({'detail': 'Password updated.'})
    old = _user_json(user)
    for field in ['full_name', 'phone', 'present_address', 'two_factor_enabled']:
        if field in request.data:
            setattr(user, field, request.data[field])
    profile_data = dict(user.profile_data or {})
    for field in ['department', 'bio', 'notification_preferences']:
        if field in request.data:
            profile_data[field] = request.data[field]
    user.profile_data = profile_data
    user.save()
    result = _user_json(user) | {'department': profile_data.get('department', 'IT & Operations'), 'notification_preferences': profile_data.get('notification_preferences', {})}
    _log(request, 'Profile', 'Update', str(user.id), old=old, new=result)
    return Response(result)
