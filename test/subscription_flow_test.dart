// Smoke + parsing tests for the rewritten subscription / payment flow.
// No backend in the harness — screens must build and fall back to their
// loading / error state without crashing, and the models must parse the
// billing API shapes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:featherflow/features/farmer/data/models/subscription_models.dart';
import 'package:featherflow/features/farmer/presentation/screens/subscription_screen.dart';
import 'package:featherflow/features/farmer/presentation/screens/subscription_flow_screens.dart';

Future<void> _pump(WidgetTester t, Widget screen) async {
  final router = GoRouter(
    initialLocation: '/x',
    routes: [
      GoRoute(path: '/x', builder: (_, __) => screen),
      GoRoute(path: '/subscription', builder: (_, __) => const SizedBox()),
      GoRoute(path: '/farmer', builder: (_, __) => const SizedBox()),
    ],
  );
  await t.pumpWidget(MaterialApp.router(routerConfig: router));
  await t.pump(const Duration(milliseconds: 100));
  await t.pump(const Duration(seconds: 1));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const planJson = {
    'id': 3,
    'code': 'monthly_premium',
    'name': 'Pro',
    'interval': 'month',
    'tagline': 'Everything to run the farm.',
    'price': 599.0,
    'currency': 'BDT',
    'price_display': 'BDT 599/mo',
    'disease_scan_limit': null,
    'features': ['Unlimited disease scans', 'Full cost management'],
    'recommended': true,
    'is_active': true,
  };

  test('SubPlan parses the billing plan shape', () {
    final p = SubPlan.fromJson(Map<String, dynamic>.from(planJson));
    expect(p.id, 3);
    expect(p.name, 'Pro');
    expect(p.price, 599.0);
    expect(p.recommended, isTrue);
    expect(p.intervalLabel, 'per month');
  });

  test('PlansResponse parses mode + current', () {
    final r = PlansResponse.fromJson({
      'mode': 'dev',
      'free_plan': {...planJson, 'code': 'free', 'name': 'Free', 'price': 0.0},
      'plans': [planJson],
      'current': {
        'id': 'abc',
        'plan': planJson,
        'status': 'active',
        'started_at': '2026-09-01T00:00:00Z',
        'expires_at': '2026-10-01T00:00:00Z',
        'auto_renew': true,
      },
    });
    expect(r.isDevMode, isTrue);
    expect(r.plans.single.code, 'monthly_premium');
    expect(r.current!.status, 'active');
  });

  test('PaymentIntent status helpers', () {
    PaymentIntent i(String s) => PaymentIntent.fromJson({
          'id': '00000000-0000-0000-0000-000000000000',
          'status': s,
          'plan': {'name': 'Pro', 'code': 'monthly_premium', 'interval': 'month'},
          'amount': 599.0,
          'currency': 'BDT',
          'amount_display': 'BDT 599',
          'mode': 'dev',
        });
    expect(i('succeeded').succeeded, isTrue);
    expect(i('failed').failed, isTrue);
    expect(i('cancelled').cancelled, isTrue);
    expect(i('pending').isTerminal, isFalse);
    expect(i('succeeded').isTerminal, isTrue);
  });

  testWidgets('SubscriptionScreen builds and shows a state (no backend)',
      (t) async {
    await _pump(t, const SubscriptionScreen());
    expect(t.takeException(), isNull);
    expect(find.text('Featherflow Plans'), findsWidgets);
  });

  testWidgets('PlanReviewScreen builds with a plan + dev banner', (t) async {
    final plan = SubPlan.fromJson(Map<String, dynamic>.from(planJson));
    await _pump(t, PlanReviewScreen(plan: plan, isDevMode: true));
    expect(t.takeException(), isNull);
    expect(find.textContaining('Development payment mode'), findsWidgets);
    expect(find.text('Continue to payment'), findsOneWidget);
  });

  testWidgets('PaymentMethodScreen shows Card / bKash / Nagad', (t) async {
    final intent = PaymentIntent.fromJson({
      'id': '00000000-0000-0000-0000-000000000000',
      'status': 'created',
      'plan': {'name': 'Pro', 'code': 'monthly_premium', 'interval': 'month'},
      'amount': 599.0,
      'currency': 'BDT',
      'amount_display': 'BDT 599',
      'mode': 'dev',
    });
    await _pump(t, PaymentMethodScreen(intent: intent));
    expect(t.takeException(), isNull);
    expect(find.text('Card'), findsOneWidget);
    expect(find.text('bKash'), findsWidgets);
    expect(find.text('Nagad'), findsWidgets);
    // Pay button is disabled until a method is chosen.
    expect(find.text('Select a method'), findsOneWidget);
  });

  testWidgets('PaymentResultScreen renders each outcome', (t) async {
    PaymentIntent i(String s) => PaymentIntent.fromJson({
          'id': '11111111-1111-1111-1111-111111111111',
          'status': s,
          'plan': {'name': 'Pro', 'code': 'monthly_premium', 'interval': 'month'},
          'amount': 599.0,
          'currency': 'BDT',
          'amount_display': 'BDT 599',
          'mode': 'dev',
          'failure_reason': 'The payment did not go through.',
        });
    await _pump(t, PaymentResultScreen(intent: i('succeeded')));
    expect(find.text('Payment successful'), findsOneWidget);
    await _pump(t, PaymentResultScreen(intent: i('failed')));
    expect(find.text('Payment failed'), findsOneWidget);
    await _pump(t, PaymentResultScreen(intent: i('cancelled')));
    expect(find.text('Payment cancelled'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
