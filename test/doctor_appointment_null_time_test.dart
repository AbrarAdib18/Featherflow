// Regression (retest finding): a farmer's "request any available time" consultation
// reaches the doctor app with scheduled_at == null. DateTime.parse('null') used to
// throw, DoctorSession.refresh() then failed as a whole and the panel silently kept
// its hard-coded demo data.
import 'package:flutter_test/flutter_test.dart';
import 'package:featherflow/features/doctor/data/models/doctor_models.dart';

Map<String, dynamic> _json({Object? scheduledAt}) => {
      'id': 'a1', 'farmer_name': 'Md. Rashed Karim', 'farm_name': 'Rashed Poultry Farm',
      'farmer_phone': '+880170', 'scheduled_at': scheduledAt, 'mode': 'online',
      'status': 'pending', 'is_urgent': false, 'fee': 900,
    };

void main() {
  test('null scheduled_at parses (no slot requested)', () {
    final a = DoctorAppointment.fromJson(_json());
    expect(a.hasSlot, isFalse);
    expect(a.farmerName, 'Md. Rashed Karim');
  });

  test('a real scheduled_at still parses', () {
    final a = DoctorAppointment.fromJson(_json(scheduledAt: '2026-10-05T09:00:00'));
    expect(a.hasSlot, isTrue);
    expect(a.scheduledAt, DateTime(2026, 10, 5, 9));
  });

  test('copyWith keeps hasSlot', () {
    final a = DoctorAppointment.fromJson(_json());
    expect(a.copyWith(status: AppointmentStatus.accepted).hasSlot, isFalse);
  });
}
