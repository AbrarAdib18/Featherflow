// F-004 regression (Flutter side): an empty pharmacy account must render the
// real empty states and zero totals — never fabricated medicines/orders.
//
// The session is driven through its real code path (`PharmacySession.refresh`)
// against a mock HTTP client that returns the *actual* JSON the fixed backend
// returns for an empty pharmacy (captured to
// audit_logs/data/f004_empty_pharmacy_responses.json). The backend half of the
// fix is backend/scripts/test_pharmacy_no_fabricated_data.py; real-browser
// evidence is in F-004_FIX_REPORT.md.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:featherflow/core/network/auth_service.dart';
import 'package:featherflow/features/pharmacy/data/services/pharmacy_session.dart';
import 'package:featherflow/features/pharmacy/presentation/screens/pharmacy_catalogue_screen.dart';
import 'package:featherflow/features/pharmacy/presentation/screens/pharmacy_orders_screen.dart';

const _empty = <String, Object>{
  'permissions': {
    'status': 'ACTIVE', 'account_status': 'active', 'review_state': null, 'is_verified': false,
    'can': {'catalogue': true, 'orders': true, 'suppliers': true, 'analytics': true,
            'employees': true, 'chat': true, 'appeal': false, 'profile': true},
    'locked_reason': null, 'rejection_reason': null, 'more_information_reason': null,
    'open_appeal_id': null,
  },
  'earnings': {'total_orders': 0, 'gross_sales': '0.00', 'featherflow_commission': '0.00', 'pharmacy_earnings': '0.00'},
  'medicines': {'results': []},
  'orders': {'results': []},
  'inventory/summary': {
    'total_products': 0, 'active_products': 0, 'low_stock_count': 0, 'out_of_stock_count': 0,
    'expiring_soon_count': 0, 'critical_expiry_count': 0, 'pending_approval_count': 0,
    'stock_value': 0, 'low_stock_threshold': 10,
  },
  'inventory/expiring-soon': {'results': [], 'grouped': {'critical': [], 'warning': [], 'info': []}},
  'suppliers': {'results': []},
};

http.Client _emptyPharmacyBackend() => MockClient((request) async {
      final path = request.url.path.replaceFirst('/api/pharmacy/', '').replaceAll(RegExp(r'/$'), '');
      final body = _empty[path];
      if (body == null) return http.Response('{"detail":"unexpected $path"}', 404);
      return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
    });

Future<void> _signedInEmptyPharmacy(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  await tester.runAsync(() => AuthService.instance.saveSession(AuthSession(
    accessToken: 'a',
    refreshToken: 'r',
    user: AuthUser(
      id: 'u-empty', email: 'empty@pharmacy.test', fullName: 'Empty Pharmacy',
      roles: const ['pharmacy'], accountStatus: 'active', phone: '+8801000000000',
      presentAddress: 'Dhaka', dateOfBirth: '1990-01-01', profileData: const {},
      profilePhotoUrl: '',
    ),
  )));
}

// runAsync leaves the fake-async zone, so the mock client must be installed
// inside it.
Future<void> _refresh(WidgetTester tester) => tester.runAsync(() async {
      final s = PharmacySession.instance;
      // The session auto-refreshes when AuthService notifies (real client in a
      // test binding => HTTP 400). Let that in-flight refresh finish, then run
      // ours against the mock backend.
      for (var i = 0; i < 100 && s.isLoading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await http.runWithClient(() => s.refresh(), _emptyPharmacyBackend);
    }).then((_) {});

// Signing out makes the session cancel its 4 s poll timer (no pending timers).
Future<void> _signOut(WidgetTester tester) async {
  await tester.runAsync(() => AuthService.instance.clearSession());
  await tester.pump();
}

const _demoNames = [
  'Oxytetracycline 20%', 'Newcastle Vaccine', 'Vitamin AD3E Supplement', 'Automatic Vaccinator',
  'Karim Hossain', 'Jamal Mia', 'Salma Akter', '#PH-1042',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Construct the singleton outside the fake-async zone so its constructor-time
  // timers/listeners are not created inside a test body.
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    PharmacySession.instance;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });

  testWidgets('empty pharmacy: session has zero medicines/orders/totals after a real refresh',
      (tester) async {
    await _signedInEmptyPharmacy(tester);
    {
      final s = PharmacySession.instance;
      await _refresh(tester);
      expect(s.ready, isTrue);
      expect(s.errorMessage, isNull);
      expect(s.medicines, isEmpty);
      expect(s.orders, isEmpty);
      expect(s.totalProducts, 0);
      expect(s.lowStockCount, 0);
      expect(s.outOfStockCount, 0);
      expect(s.expiringSoonCount, 0);
      expect(s.incomingOrderCount, 0);
      expect(s.activeDeliveryCount, 0);
      expect(s.recentOrders, isEmpty);
      expect(s.earnings?['total_orders'], 0);
      await _signOut(tester);
    }
  });

  testWidgets('catalogue shows the "No medicines yet" empty state and no demo names',
      (tester) async {
    await _signedInEmptyPharmacy(tester);
    {
      await _refresh(tester);
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: PharmacyCatalogueScreen(embedded: true)),
      ));
      await tester.pump();
      expect(find.text('No medicines yet'), findsOneWidget);
      expect(find.text('Tap Add to list your first medicine.'), findsOneWidget);
      for (final demo in _demoNames) {
        expect(find.textContaining(demo), findsNothing);
      }
      await tester.pumpWidget(const SizedBox());
      await _signOut(tester);
    }
  });

  testWidgets('orders screen shows the empty state in every tab and no demo orders',
      (tester) async {
    await _signedInEmptyPharmacy(tester);
    {
      await _refresh(tester);
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: PharmacyOrdersScreen(embedded: true)),
      ));
      await tester.pump();
      expect(find.text('No orders here'), findsWidgets);
      for (final demo in _demoNames) {
        expect(find.textContaining(demo), findsNothing);
      }
      for (final tab in ['Preparing', 'Delivery', 'Completed', 'Cancelled']) {
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
        expect(find.text('No orders here'), findsWidgets, reason: '$tab tab');
      }
      await tester.pumpWidget(const SizedBox());
      await _signOut(tester);
    }
  });
}
