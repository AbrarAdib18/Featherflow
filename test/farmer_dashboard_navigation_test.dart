// Farmer dashboard — dead-tap regression test (Phase 2 fix, Phase 4 coverage).
//
// The welcome card, finance mini-cells, alert cards and activity rows used to
// render real API values with no `onTap` at all. Navigation itself does not
// depend on the dashboard's data having loaded — every one of these taps
// fires a `context.go`/`push` to a fixed route regardless of what (if
// anything) the API returned — so this is testable without a session, unlike
// the screens gated behind a populated data load (see
// farmer_screens_smoke_test.dart's header comment for that convention).
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:featherflow/core/l10n/app_localizations.dart';
import 'package:featherflow/core/l10n/language_notifier.dart';
import 'package:featherflow/features/farmer/presentation/screens/farmer_dashboard_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LanguageNotifier.instance.markInitialDialogShown();
  });

  Future<GoRouter> pumpDashboard(WidgetTester t) async {
    final router = GoRouter(
      initialLocation: '/farmer',
      routes: [
        GoRoute(
            path: '/farmer', builder: (_, __) => const FarmerDashboardScreen()),
        GoRoute(
            path: '/farmer/profile', builder: (_, __) => const SizedBox()),
        GoRoute(
            path: '/farmer/cost-management', builder: (_, __) => const SizedBox()),
        GoRoute(
            path: '/farmer/cost-management/expenses',
            builder: (_, __) => const SizedBox()),
        GoRoute(
            path: '/farmer/cost-management/reports',
            builder: (_, __) => const SizedBox()),
      ],
    );
    await t.pumpWidget(MaterialApp.router(
      routerConfig: router,
      locale: const Locale('en'),
      supportedLocales: const [Locale('en'), Locale('bn')],
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
    ));
    await t.pump(const Duration(milliseconds: 100));
    return router;
  }

  /// The dashboard's first load is a real (unmocked) HTTP call that fails
  /// with no session — let it actually fail before asserting, same pattern as
  /// farmer_bottom_nav_test.dart's Community-tile test.
  Future<void> settle(WidgetTester t) async {
    await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await t.pump(const Duration(milliseconds: 100));
  }

  testWidgets('dashboard shows a loading spinner before first data, not '
      'zeroed cards', (t) async {
    final router = await pumpDashboard(t);
    // On the very first frame (before the failed load has even settled),
    // nothing claiming to be real data should be visible yet.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('Welcome'), findsNothing);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/farmer');
  });

  testWidgets('welcome card navigates to the farmer profile', (t) async {
    final router = await pumpDashboard(t);
    // Let the failed dashboard load settle so the (zero-default) body renders.
    await settle(t);
    await t.tap(find.textContaining('Welcome'));
    await t.pump(const Duration(milliseconds: 100));
    expect(router.routerDelegate.currentConfiguration.uri.path,
        '/farmer/profile');
  });

  testWidgets('finance overview card navigates to cost management', (t) async {
    final router = await pumpDashboard(t);
    await settle(t);
    await t.tap(find.text('Total Revenue'));
    await t.pump(const Duration(milliseconds: 100));
    expect(router.routerDelegate.currentConfiguration.uri.path,
        '/farmer/cost-management');
  });

  testWidgets('finance Expense mini-cell navigates to the expense list, not '
      'just the overview', (t) async {
    final router = await pumpDashboard(t);
    await settle(t);
    await t.tap(find.text('Expense'));
    await t.pump(const Duration(milliseconds: 100));
    expect(router.routerDelegate.currentConfiguration.uri.path,
        '/farmer/cost-management/expenses');
  });

  testWidgets('finance Net Profit mini-cell navigates to reports', (t) async {
    final router = await pumpDashboard(t);
    await settle(t);
    await t.tap(find.text('Net Profit'));
    await t.pump(const Duration(milliseconds: 100));
    expect(router.routerDelegate.currentConfiguration.uri.path,
        '/farmer/cost-management/reports');
  });

  testWidgets('no exceptions thrown across the dead-tap fix surface', (t) async {
    await pumpDashboard(t);
    await settle(t);
    expect(t.takeException(), isNull);
  });
}
