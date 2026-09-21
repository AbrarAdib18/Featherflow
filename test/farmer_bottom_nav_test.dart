// Farmer bottom navigation regression test.
//
// Community used to sit at bottom-nav index 3 (Home | Cost | Detect |
// Community | Profile). It was removed — Community is reached from the
// dashboard's quick-action grid tile and the /community route instead — and
// Profile moved from index 4 to index 3. This locks in: exactly 4 destinations,
// no "Community" label in the bar, and that tapping each item navigates to the
// correct route with no index mismatch or blank tab.
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
    // Otherwise FarmerDashboardScreen.initState shows the blocking initial
    // language dialog (dismissible: false), which intercepts every tap in
    // these tests with an AbsorbPointer.
    LanguageNotifier.instance.markInitialDialogShown();
  });

  Future<GoRouter> pumpDashboard(WidgetTester t) async {
    final router = GoRouter(
      initialLocation: '/farmer',
      routes: [
        GoRoute(
            path: '/farmer', builder: (_, __) => const FarmerDashboardScreen()),
        GoRoute(
            path: '/farmer/cost-management', builder: (_, __) => const SizedBox()),
        GoRoute(
            path: '/farmer/disease-detection', builder: (_, __) => const SizedBox()),
        GoRoute(path: '/farmer/profile', builder: (_, __) => const SizedBox()),
        GoRoute(path: '/community', builder: (_, __) => const SizedBox()),
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

  testWidgets('bottom nav has exactly 4 destinations and no Community entry',
      (t) async {
    await pumpDashboard(t);
    final bar = t.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
    expect(bar.items, hasLength(4));
    expect(find.descendant(
        of: find.byType(BottomNavigationBar), matching: find.text('Community')),
        findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('tapping Profile (now index 3) navigates to /farmer/profile',
      (t) async {
    final router = await pumpDashboard(t);
    await t.tap(find.descendant(
        of: find.byType(BottomNavigationBar), matching: find.byIcon(Icons.person)));
    await t.pump(const Duration(milliseconds: 100));
    expect(router.routerDelegate.currentConfiguration.uri.path,
        '/farmer/profile');
  });

  testWidgets('tapping Cost navigates to /farmer/cost-management', (t) async {
    final router = await pumpDashboard(t);
    await t.tap(find.descendant(
        of: find.byType(BottomNavigationBar),
        matching: find.byIcon(Icons.attach_money)));
    await t.pump(const Duration(milliseconds: 100));
    expect(router.routerDelegate.currentConfiguration.uri.path,
        '/farmer/cost-management');
  });

  testWidgets('Community is still reachable from the quick-action grid',
      (t) async {
    // The Community tile sits below the fold on the default test viewport —
    // use a tall surface so the whole dashboard body renders without needing
    // to scroll.
    t.view.physicalSize = const Size(800, 3600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final router = await pumpDashboard(t);
    // The dashboard's first load is a real (unmocked) HTTP call that fails
    // with no session — let it actually fail before asserting, the same
    // pattern find_vet_screen_test.dart uses for its own real network calls.
    await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await t.pump(const Duration(milliseconds: 100));
    final communityTile = find.text('Community');
    expect(communityTile, findsOneWidget);
    await t.tap(communityTile);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(t.takeException(), isNull);
    expect(
        router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
        '/community');
  });
}
