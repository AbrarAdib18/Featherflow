// Widget tests for FARMER_FEED_MANAGEMENT_AND_DASHBOARD_FIXES.md:
// 1. Farmer dashboard header — farm name renders in white (navigation
//    foreground token), not the near-black-on-green AppColors.onSecondaryContainer
//    it used before. The "(from profile)" suffix is gone from the bird-count
//    line.
// 2. Feed Management screen still builds/loads/errors/retries correctly
//    (this screen requires a live data fetch to reach its loaded body —
//    Supplier-UI-removal and Add Feed dialog changes are verified by code
//    review + the backend test suite + manual verification, documented as a
//    limitation in FARMER_FEED_MANAGEMENT_AND_DASHBOARD_FIXES.md, since
//    there is no injectable test seam to populate this screen's data
//    without a live backend — same constraint noted for other screens
//    gated behind a populated load, see farmer_screens_smoke_test.dart).
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:featherflow/core/l10n/app_localizations.dart';
import 'package:featherflow/core/l10n/language_notifier.dart';
import 'package:featherflow/core/theme/theme.dart';
import 'package:featherflow/features/farmer/presentation/screens/farmer_dashboard_screen.dart';
import 'package:featherflow/features/farmer/presentation/screens/feed_management_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LanguageNotifier.instance.markInitialDialogShown();
  });

  Future<void> settle(WidgetTester t) async {
    await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await t.pump(const Duration(milliseconds: 100));
  }

  group('Farmer dashboard header text fixes', () {
    Future<GoRouter> pumpDashboard(WidgetTester t) async {
      final router = GoRouter(
        initialLocation: '/farmer',
        routes: [
          GoRoute(
              path: '/farmer', builder: (_, __) => const FarmerDashboardScreen()),
          GoRoute(path: '/farmer/profile', builder: (_, __) => const SizedBox()),
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

    testWidgets('farm name text is white (navigation foreground token), not '
        'the illegible dark-green literal', (t) async {
      await pumpDashboard(t);
      await settle(t);
      expect(t.takeException(), isNull);
      // No session -> farmName is empty -> falls back to 'Your farm', per
      // _WelcomeCard's own `farmName.isEmpty ? 'Your farm' : farmName`.
      final finder = find.text('Your farm');
      expect(finder, findsOneWidget);
      final style = t.widget<Text>(finder).style;
      expect(style?.color, AppColors.navigationForegroundColor,
          reason: 'farm name must use the shared white nav-foreground token, '
              'not AppColors.onSecondaryContainer (near-black-on-green)');
      expect(style?.color, isNot(AppColors.onSecondaryContainer));
    });

    testWidgets('the bird-count line never shows "(from profile)" anymore',
        (t) async {
      await pumpDashboard(t);
      await settle(t);
      expect(t.takeException(), isNull);
      expect(find.textContaining('(from profile)'), findsNothing);
      expect(find.textContaining('(প্রোফাইল)'), findsNothing);
      // The rest of the line (birds count + active batches) still renders —
      // only the suffix was removed, not the whole label.
      expect(find.textContaining('Birds'), findsOneWidget);
    });
  });

  group('Feed Management screen — still loads/errors/retries correctly '
      'after the Supplier-removal and Add Feed changes', () {
    Future<void> pumpFeedManagement(WidgetTester t) async {
      final router = GoRouter(
        initialLocation: '/farmer/feed-management',
        routes: [
          GoRoute(
              path: '/farmer/feed-management',
              builder: (_, __) => const FeedManagementScreen()),
          GoRoute(path: '/farmer', builder: (_, __) => const SizedBox()),
        ],
      );
      await t.pumpWidget(MaterialApp.router(routerConfig: router));
      await t.pump(const Duration(milliseconds: 100));
    }

    testWidgets('shows a loading spinner before the first load resolves',
        (t) async {
      await pumpFeedManagement(t);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows an error + Retry state when the load fails (no '
        'session in this test environment), no crash', (t) async {
      await pumpFeedManagement(t);
      await settle(t);
      expect(t.takeException(), isNull);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('tapping Retry re-attempts the load without throwing',
        (t) async {
      await pumpFeedManagement(t);
      await settle(t);
      await t.tap(find.text('Retry'));
      await settle(t);
      expect(t.takeException(), isNull);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('app bar title is "Feed Management"', (t) async {
      await pumpFeedManagement(t);
      expect(find.text('Feed Management'), findsOneWidget);
    });
  });
}
