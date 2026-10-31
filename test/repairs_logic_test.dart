import 'package:flutter_test/flutter_test.dart';
import 'package:featherflow/core/location/delivery_location.dart';
import 'package:featherflow/core/router/app_router.dart';

void main() {
  group('NF-3 delivery location validation', () {
    test('missing, partial and non-numeric input is rejected', () {
      expect(validateDeliveryLocation(null, null), isNotNull);
      expect(validateDeliveryLocation(23.8, null), isNotNull);
      expect(parseManualLocation('abc', '90.4').error, isNotNull);
      expect(parseManualLocation('', '').error, isNotNull);
    });
    test('out of range and outside Bangladesh are rejected', () {
      expect(validateDeliveryLocation(95, 90), isNotNull);
      expect(validateDeliveryLocation(51.5, -0.12), contains('outside'));
      expect(validateDeliveryLocation(double.nan, 90), isNotNull);
    });
    test('Dhaka is accepted', () {
      expect(validateDeliveryLocation(23.81, 90.41), isNull);
      final p = parseManualLocation(' 23.81 ', '90.41');
      expect(p.error, isNull);
      expect(p.lat, 23.81);
    });
  });

  group('F-007 panel guard', () {
    test('each panel only admits its role', () {
      expect(panelGuardFor('/doctor/dashboard')!(['farmer']), isFalse);
      expect(panelGuardFor('/doctor/dashboard')!(['doctor']), isTrue);
      expect(panelGuardFor('/admin/users')!(['admin_content']), isTrue);
      expect(panelGuardFor('/admin/users')!(['farmer']), isFalse);
      expect(panelGuardFor('/delivery/home')!(['pharmacy']), isFalse);
    });
    test('shared routes have no guard', () {
      expect(panelGuardFor('/community'), isNull);
    });
  });
}
