// Tax feature: model parsing (pure) + screen smoke tests.
// The screens' initState API calls fail with no session; each must fall back to
// its loading / error state without throwing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:featherflow/features/farmer/data/models/tax_calculation_result.dart';
import 'package:featherflow/features/farmer/data/models/tax_payment.dart';
import 'package:featherflow/features/farmer/data/models/tax_profile.dart';
import 'package:featherflow/features/farmer/data/models/tax_summary.dart';
import 'package:featherflow/features/farmer/presentation/screens/tax_calculation_screen.dart';
import 'package:featherflow/features/farmer/presentation/screens/tax_payment_screen.dart';
import 'package:featherflow/features/farmer/presentation/screens/tax_profile_screen.dart';
import 'package:featherflow/features/farmer/presentation/screens/tax_summary_screen.dart';

Future<void> _pump(WidgetTester tester, Widget screen) async {
  final router = GoRouter(
    initialLocation: '/farmer/x',
    routes: [
      GoRoute(path: '/farmer/x', builder: (_, __) => screen),
      GoRoute(path: '/farmer', builder: (_, __) => const SizedBox()),
      GoRoute(path: '/farmer/tax', builder: (_, __) => const SizedBox()),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('models', () {
    test('TaxProfile parses and round-trips vehicles', () {
      // DRF DecimalField serialises to a JSON string ("50.00") — must tolerate it.
      final p = TaxProfile.fromJson({
        'land_area': '50.00',
        'land_unit': 'katha',
        'land_use': 'agricultural',
        'location': 'rural',
        'income_type': 'agricultural',
        'exemptions': '0.00',
        'rebates': '1500.50',
        'is_senior': false,
        'vehicles': [
          {'type': 'motorcycle', 'count': 1},
          {'type': 'van', 'count': 2},
        ],
      });
      expect(p.landArea, 50);
      expect(p.rebates, 1500.5);
      expect(p.exemptions, 0);
      expect(p.vehicles.length, 2);
      expect(p.vehicles[1].type, 'van');
      expect(p.vehicles[1].count, 2);
      final json = p.toUpdateJson(landArea: 60);
      expect(json['land_area'], 60);
      expect((json['vehicles'] as List).length, 2);
    });

    test('TaxCalculationResult exposes totals + breakdown', () {
      final r = TaxCalculationResult.fromJson({
        'tax_year': '2024-25',
        'income_tax': 20000.0,
        'land_tax': 0.0,
        'vehicle_tax': 4000.0,
        'total': 24000.0,
        'total_revenue': 1200000.0,
        'net_income': 800000.0,
        'breakdown': ['INCOME TAX', '  Gross annual income: BDT 800,000'],
        'income': {
          'breakdown': ['Gross annual income: BDT 800,000', 'Income tax payable: BDT 20,000']
        },
      });
      expect(r.total, 24000.0);
      expect(r.incomeTax, 20000.0);
      expect(r.breakdown, isNotEmpty);
      expect(r.incomeBreakdown.length, 2);
    });

    test('TaxSummary parses lines', () {
      final s = TaxSummary.fromJson({
        'year': 2026,
        'tax_year': '2024-25',
        'estimated_total': 4000.0,
        'total_paid': 7000.0,
        'pending': 0.0,
        'lines': [
          {'tax_type': 'income', 'label': 'Income / business tax', 'estimated': 0.0, 'paid': 0.0, 'pending': 0.0},
          {'tax_type': 'vehicle', 'label': 'Vehicle tax', 'estimated': 4000.0, 'paid': 2000.0, 'pending': 2000.0},
        ],
        'estimate': {'total': 4000.0},
        'disclaimer': 'This is an estimate.',
      });
      expect(s.year, 2026);
      expect(s.lines.length, 2);
      expect(s.lines[1].pending, 2000.0);
      expect(s.estimate.total, 4000.0);
    });

    test('TaxPayment create json + string amount parse', () {
      final j = TaxPayment.toCreateJson(
        taxType: 'land',
        amount: 5000,
        paymentDate: '2026-02-15',
        referenceNumber: 'CH-1',
        logAsExpense: true,
      );
      expect(j['tax_type'], 'land');
      expect(j['amount'], 5000);
      expect(j['log_as_expense'], true);
      expect(TaxPayment.typeLabel('vehicle'), 'Vehicle tax');
      // DRF returns amount as a string
      expect(TaxPayment.fromJson({'amount': '5000.00'}).amount, 5000);
    });
  });

  group('screens build without a session', () {
    testWidgets('TaxSummaryScreen', (t) async {
      await _pump(t, const TaxSummaryScreen());
      expect(t.takeException(), isNull);
      expect(find.text('Tax'), findsWidgets);
    });

    testWidgets('TaxCalculationScreen', (t) async {
      await _pump(t, const TaxCalculationScreen());
      expect(t.takeException(), isNull);
      expect(find.text('Tax estimate'), findsWidgets);
    });

    testWidgets('TaxProfileScreen', (t) async {
      await _pump(t, const TaxProfileScreen());
      expect(t.takeException(), isNull);
      expect(find.text('My tax details'), findsWidgets);
    });

    testWidgets('TaxPaymentScreen', (t) async {
      await _pump(t, const TaxPaymentScreen());
      expect(t.takeException(), isNull);
      expect(find.text('Tax payments'), findsWidgets);
    });
  });
}
