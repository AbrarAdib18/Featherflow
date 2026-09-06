from datetime import date, time
from decimal import Decimal
from unittest.mock import patch
from types import SimpleNamespace

from django.test import SimpleTestCase, override_settings
from rest_framework.test import APIRequestFactory, force_authenticate

from .permissions import IsDoctor
from consultations.serializers import FarmerBookingSerializer
from consultations.serializers import FarmerConsultationActionSerializer
from consultations.booking import initial_case_values
from messaging.realtime import room_name
from consultations.workflow import get_or_create_conversation
from consultations.payments import payment_breakdown
from consultations.permissions import IsFarmer
from .serializers import (AppointmentActionSerializer, CaseSerializer,
                          AvailabilitySlotSerializer,
                          FollowUpSerializer, PrescriptionSerializer,
                          ProfileSerializer)
from .prescription_pdf import build_prescription_pdf
from consultations.views import _distance, _doctor_row, _mode, clinical_results


class FakeRoles:
    def __init__(self, doctor=True): self.doctor = doctor
    def filter(self, **kwargs): return self
    def exists(self): return self.doctor


class FakeUser:
    is_authenticated = True
    account_status = 'active'
    roles = FakeRoles()
    id = '11111111-1111-1111-1111-111111111111'
    full_name = 'Test Farmer'
    email = 'farmer@example.com'


class DoctorValidationTests(SimpleTestCase):
    def test_discovery_distance_is_calculated_in_kilometres(self):
        self.assertAlmostEqual(_distance(23.8103, 90.4125, 23.8103, 90.4125), 0)

    def test_discovery_row_exposes_farmer_facing_fields(self):
        profile = SimpleNamespace(
            id='profile', user_id='user', user=SimpleNamespace(full_name='Dr Test', email='vet@example.com', profile_photo_url=None),
            clinic_hospital_name='Clinic', practice_address='Dhaka', latitude=None, longitude=None,
            veterinary_degree='DVM', specialty='Poultry', poultry_focus_area='Broilers', years_of_experience=5,
            consultation_mode='both', emergency_on_call_availability=True, is_available=True,
            availability_status='available', is_verified=True, service_fee=500, rating=4.5,
        )
        row = _doctor_row(profile)
        self.assertEqual(row['name'], 'Dr Test')
        self.assertEqual(row['availability_status'], 'available')
        self.assertTrue(row['emergency'])

    def test_doctor_permission_requires_active_doctor(self):
        request = APIRequestFactory().get('/api/doctor/dashboard/')
        request.user = FakeUser()
        self.assertTrue(IsDoctor().has_permission(request, None))
        request.user.account_status = 'suspended'
        self.assertFalse(IsDoctor().has_permission(request, None))

    def test_farmer_discovery_permission_requires_farmer_role(self):
        request = APIRequestFactory().get('/api/consultations/vets/')
        request.user = FakeUser()
        self.assertTrue(IsFarmer().has_permission(request, None))
        request.user.roles = FakeRoles(False)
        self.assertFalse(IsFarmer().has_permission(request, None))

    def test_reschedule_requires_date_and_time(self):
        serializer = AppointmentActionSerializer(data={'action': 'reschedule'})
        self.assertFalse(serializer.is_valid())
        serializer = AppointmentActionSerializer(data={'action': 'reschedule', 'appointment_date': date.today(), 'appointment_time': time(10)})
        self.assertTrue(serializer.is_valid(), serializer.errors)

    def test_availability_requires_a_complete_consultation_slot(self):
        serializer = AvailabilitySlotSerializer(data={
            'weekday': 0,
            'start_time': '09:00',
            'end_time': '09:20',
            'mode': 'online',
        })
        self.assertFalse(serializer.is_valid())

        serializer = AvailabilitySlotSerializer(data={
            'weekday': 0,
            'start_time': '09:00',
            'end_time': '09:30',
            'mode': 'in-person',
        })
        self.assertTrue(serializer.is_valid(), serializer.errors)
        self.assertEqual(serializer.validated_data['mode'], 'offline')

    def test_case_rejects_negative_poultry_counts(self):
        serializer = CaseSerializer(data={'consultation_id': '11111111-1111-1111-1111-111111111111', 'flock_count': -1})
        self.assertFalse(serializer.is_valid())

    def test_prescription_requires_complete_medicine_items(self):
        serializer = PrescriptionSerializer(data={'consultation_id': '11111111-1111-1111-1111-111111111111', 'medicines': [{'name': 'Medicine'}]})
        self.assertFalse(serializer.is_valid())

    def test_prescription_requires_case_advice(self):
        serializer = PrescriptionSerializer(data={
            'consultation_id': '11111111-1111-1111-1111-111111111111',
            'medicines': [{'name': 'Medicine', 'dosage': '1 ml', 'duration': '3 days'}],
        })
        self.assertFalse(serializer.is_valid())
        self.assertIn('case_advice', serializer.errors)

    def test_follow_up_requires_an_exact_time(self):
        missing_time = FollowUpSerializer(data={
            'consultation_id': '11111111-1111-1111-1111-111111111111',
            'scheduled_date': date.today(),
        })
        self.assertFalse(missing_time.is_valid())
        self.assertIn('scheduled_time', missing_time.errors)
        complete = FollowUpSerializer(data={
            'consultation_id': '11111111-1111-1111-1111-111111111111',
            'scheduled_date': date.today(), 'scheduled_time': time(10),
        })
        self.assertTrue(complete.is_valid(), complete.errors)

    def test_prescription_pdf_is_generated(self):
        medicine = SimpleNamespace(
            medicine_name='Medicine', dosage='1 ml', duration='3 days',
            instructions='After feed')
        prescription = SimpleNamespace(
            id='rx-1', doctor=SimpleNamespace(full_name='Dr Test', email='vet@example.com'),
            consultation=SimpleNamespace(
                farmer=SimpleNamespace(full_name='Farmer Test', email='farmer@example.com'),
                appointment_date=date(2026, 8, 14), appointment_time=time(10),
                case_detail=None),
            items=SimpleNamespace(all=lambda: [medicine]), dosage_notes='Shake well',
            case_advice='Keep the flock warm.', follow_up_instructions='Review in 3 days',
            referred_to=None)
        pdf = build_prescription_pdf(prescription)
        self.assertTrue(pdf.startswith(b'%PDF-'))

    def test_farmer_booking_requires_farm_slot_and_symptoms(self):
        serializer = FarmerBookingSerializer(data={
            'doctor_id': '11111111-1111-1111-1111-111111111111',
            'mode': 'online', 'appointment_date': date.today(), 'appointment_time': time(10),
        })
        self.assertFalse(serializer.is_valid())
        self.assertIn('farm_id', serializer.errors)
        self.assertIn('symptoms', serializer.errors)

    def test_in_person_aliases_normalize_to_offline(self):
        base = {
            'doctor_id': '11111111-1111-1111-1111-111111111111',
            'farm_id': '22222222-2222-2222-2222-222222222222',
            'flock_id': '33333333-3333-3333-3333-333333333333',
            'appointment_date': date.today(), 'appointment_time': time(23, 59),
            'symptoms': ['Routine review'],
        }
        for alias in ('offline', 'in-person', 'in_person', 'in person'):
            serializer = FarmerBookingSerializer(data={**base, 'mode': alias})
            self.assertTrue(serializer.is_valid(), serializer.errors)
            self.assertEqual(serializer.validated_data['mode'], 'offline')
        self.assertEqual(_mode('clinic visit'), 'offline')
        self.assertEqual(_mode('online'), 'online')
        profile = ProfileSerializer(data={'consultation_mode': 'in-person'})
        self.assertTrue(profile.is_valid(), profile.errors)
        self.assertEqual(profile.validated_data['consultation_mode'], 'offline')
        both = ProfileSerializer(data={'consultation_mode': 'both'})
        self.assertTrue(both.is_valid(), both.errors)

    def test_initial_case_uses_selected_flock_facts_and_farmer_history(self):
        farm = SimpleNamespace(farm_name='Sunrise Farm')
        flock = SimpleNamespace(start_date=date(2026, 7, 1), breed='Cobb 500', bird_type='broiler', current_quantity=950)
        farmer = SimpleNamespace(full_name='Rahim Uddin', email='rahim@example.com')
        values = initial_case_values(farmer, farm, flock, {
            'appointment_date': date(2026, 8, 12), 'symptoms': ['Sneezing', 'Low appetite'],
            'mortality_count': 4, 'feed_notes': 'Reduced intake', 'vaccine_history': 'ND vaccine',
            'biosecurity_notes': 'New visitors', 'farmer_notes': 'Started yesterday',
        })
        self.assertEqual(values['farm_name'], 'Sunrise Farm')
        self.assertEqual(values['farmer_name'], 'Rahim Uddin')
        self.assertEqual(values['bird_age'], '6 weeks')
        self.assertEqual(values['flock_count'], 950)
        self.assertEqual(values['symptoms_description'], 'Sneezing\nLow appetite')

    def test_manual_case_fields_required_without_a_flock(self):
        serializer = FarmerBookingSerializer(data={
            'doctor_id': '11111111-1111-1111-1111-111111111111',
            'farm_id': '22222222-2222-2222-2222-222222222222',
            'mode': 'online', 'appointment_date': date.today(),
            'appointment_time': time(23, 59), 'symptoms': ['Sneezing'],
        })
        self.assertFalse(serializer.is_valid())
        self.assertIn('bird_age_weeks', serializer.errors)

    def test_non_critical_routine_booking_is_valid(self):
        serializer = FarmerBookingSerializer(data={
            'doctor_id': '11111111-1111-1111-1111-111111111111',
            'farm_id': '22222222-2222-2222-2222-222222222222',
            'flock_id': '33333333-3333-3333-3333-333333333333',
            'mode': 'online', 'urgency': 'routine',
            'appointment_date': date.today(), 'appointment_time': time(23, 59),
            'symptoms': ['Mild sneezing'], 'mortality_count': 0,
            'farmer_name': 'Spoofed Name',
        })
        self.assertTrue(serializer.is_valid(), serializer.errors)
        self.assertEqual(serializer.validated_data['urgency'], 'routine')
        self.assertNotIn('farmer_name', serializer.validated_data)

    def test_farmer_reschedule_and_rating_actions_validate(self):
        self.assertTrue(FarmerConsultationActionSerializer(
            data={'action': 'accept_reschedule'}).is_valid())
        rating = FarmerConsultationActionSerializer(data={'action': 'rate'})
        self.assertFalse(rating.is_valid())
        self.assertIn('rating', rating.errors)

    def test_socket_rooms_are_isolated_by_conversation(self):
        self.assertEqual(room_name('abc'), 'conversation:abc')
        self.assertNotEqual(room_name('abc'), room_name('xyz'))

    @patch('consultations.views.get_object_or_404')
    def test_farmer_results_are_withheld_until_completion(self, get_object):
        get_object.return_value = SimpleNamespace(status='accepted')
        request = APIRequestFactory().get('/api/consultations/test/clinical-results/')
        force_authenticate(request, user=FakeUser())
        response = clinical_results(
            request, '22222222-2222-2222-2222-222222222222')
        self.assertEqual(response.status_code, 409)
        self.assertEqual(get_object.call_args.kwargs['farmer'].id, FakeUser.id)

    @patch('consultations.views._clinical_result_row')
    @patch('consultations.views.get_object_or_404')
    def test_completed_results_are_returned_to_owning_farmer(
            self, get_object, result_row):
        get_object.return_value = SimpleNamespace(status='completed')
        result_row.return_value = {'status': 'completed', 'clinical_note': {}}
        request = APIRequestFactory().get('/api/consultations/test/clinical-results/')
        force_authenticate(request, user=FakeUser())
        response = clinical_results(
            request, '22222222-2222-2222-2222-222222222222')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['status'], 'completed')

    @override_settings(
        CONSULTATION_PLATFORM_THRESHOLD='1500.00',
        CONSULTATION_PLATFORM_RATE='5.00')
    def test_platform_charge_only_applies_above_threshold(self):
        at_threshold = SimpleNamespace(consultation_fee=Decimal('1500.00'))
        above_threshold = SimpleNamespace(consultation_fee=Decimal('2000.00'))
        self.assertEqual(payment_breakdown(at_threshold), (
            Decimal('1500.00'), Decimal('0.00'), Decimal('1500.00')))
        self.assertEqual(payment_breakdown(above_threshold), (
            Decimal('2000.00'), Decimal('25.00'), Decimal('1975.00')))

    @patch('consultations.workflow.Conversation.objects')
    def test_acceptance_reuses_existing_farmer_doctor_conversation(self, objects):
        existing = SimpleNamespace(consultation_id='old', consultation=None, save=lambda **kwargs: None)
        objects.filter.return_value.first.return_value = existing
        farmer = SimpleNamespace(id='11111111-1111-1111-1111-111111111111')
        doctor = SimpleNamespace(id='22222222-2222-2222-2222-222222222222')
        consultation = SimpleNamespace(id='new', farmer=farmer, doctor=doctor)
        conversation, created = get_or_create_conversation(consultation)
        self.assertIs(conversation, existing)
        self.assertFalse(created)
        self.assertEqual(existing.consultation, consultation)
        objects.create.assert_not_called()
