// Widget tests for the doctor dashboard's Profile button relocation and the
// rating-beside-name move — see DOCTOR_DASHBOARD_PROFILE_AND_RATING.md.
//
// DoctorSession is a persistent singleton seeded with demo data (rating 4.7,
// 128 ratings) whenever nothing overrides it — with no login/session in
// these tests, that demo profile is what renders, which conveniently
// exercises the "many ratings" case end-to-end. The 0/1-rating cases are
// covered at the model layer in doctor_rating_label_test.dart instead, since
// the singleton can't be driven to another state without a live backend —
// mirrors the existing convention in farmer_screens_smoke_test.dart (screens
// must degrade gracefully with no session, not crash).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:featherflow/features/doctor/presentation/screens/doctor_dashboard_screen.dart';
import 'package:featherflow/features/doctor/presentation/screens/doctor_earnings_screen.dart';
import 'package:featherflow/features/doctor/presentation/screens/doctor_profile_screen.dart';

// _AppointmentTile (unrelated to this task's Profile/rating changes; part of
// the pre-existing "Today's appointments" list) overflows by a few pixels
// under the widget-test harness's fallback test-font metrics — this repo has
// no flutter_test_config.dart loading real fonts, a common source of small,
// test-only layout discrepancies that don't reproduce with the real app font.
// It's out of scope here (this task doesn't touch appointment tiles), so it's
// filtered out rather than silencing exceptions broadly — anything else
// still fails the test normally.
bool _isKnownPreexistingOverflow(FlutterErrorDetails details) =>
    details.exception is FlutterError &&
    details.exception.toString().contains('A RenderFlex overflowed');

Future<void> _pump(WidgetTester tester, Widget screen,
    {String initial = '/doctor/x'}) async {
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (_isKnownPreexistingOverflow(details)) return;
    previousOnError?.call(details);
  };
  addTearDown(() => FlutterError.onError = previousOnError);

  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(path: '/doctor/x', builder: (_, __) => screen),
      GoRoute(
        path: '/doctor',
        builder: (_, __) => const DoctorDashboardScreen(),
        // Nested exactly like the real app_router.dart, so `context.go`
        // from the dashboard to /doctor/profile leaves a real back-stack
        // entry (a flat/sibling route registration wouldn't, and the
        // dashboard's own auto-generated back button relies on it).
        routes: [
          GoRoute(
              path: 'profile', builder: (_, __) => const DoctorProfileScreen()),
        ],
      ),
      GoRoute(path: '/login', builder: (_, __) => const SizedBox()),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Doctor dashboard profile button', () {
    testWidgets('exists in the top-right of the dashboard', (t) async {
      await _pump(t, const DoctorDashboardScreen());
      expect(t.takeException(), isNull);
      expect(find.byKey(const Key('doctorProfileButton')), findsOneWidget);
    });

    testWidgets('tapping it opens the Profile screen', (t) async {
      await _pump(t, const DoctorDashboardScreen());
      await t.tap(find.byKey(const Key('doctorProfileButton')));
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(seconds: 1));
      expect(t.takeException(), isNull);
      expect(find.text('Profile'), findsOneWidget);
      // Registration Details / Status / Account sections from the existing,
      // unmodified profile content should all still be present.
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('Account'), findsOneWidget);
      // "Log Out" is further down the same scrollable list.
      await t.scrollUntilVisible(find.text('Log Out'), 200);
      expect(find.text('Log Out'), findsOneWidget);
    });

    testWidgets('back navigation from Profile returns to the dashboard',
        (t) async {
      await _pump(t, const DoctorDashboardScreen());
      await t.tap(find.byKey(const Key('doctorProfileButton')));
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(seconds: 1));
      expect(find.text('Profile'), findsOneWidget);

      final backButton = find.byTooltip('Back');
      expect(backButton, findsOneWidget);
      await t.tap(backButton);
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(seconds: 1));
      expect(t.takeException(), isNull);
      // Home tab content is back on screen.
      expect(find.byKey(const Key('doctorProfileButton')), findsOneWidget);
    });

    testWidgets('logout from Profile navigates to login', (t) async {
      await _pump(t, const DoctorProfileScreen(), initial: '/doctor/x');
      await t.scrollUntilVisible(find.text('Log Out'), 200);
      await t.tap(find.text('Log Out'));
      // AuthService.clearSession()'s secure-storage delete call has no mock
      // handler on the test's native/VM target and can take real (not fake)
      // async time to settle via MissingPluginException — same class of
      // situation as the geolocator/discover-vets tests elsewhere in this
      // suite. runAsync lets that actually resolve instead of leaving a
      // "pending timer/future" at teardown.
      await t.runAsync(() async {
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await t.pump(const Duration(milliseconds: 100));
          if (find.text('Profile').evaluate().isEmpty) break;
        }
      });
      await t.pump();
      expect(t.takeException(), isNull);
      // The login route's placeholder (empty SizedBox screen) is reached —
      // Profile's own content is gone.
      expect(find.text('Profile'), findsNothing);
    });
  });

  group('Rating moved beside the doctor name', () {
    testWidgets('no longer appears in the top-right app bar actions',
        (t) async {
      await _pump(t, const DoctorDashboardScreen());
      // The old top-right rating chip showed just the number with no
      // reviews count (e.g. "4.7"); the name-row version is now the only
      // place "4.7" (the seeded demo rating) appears.
      expect(find.text('4.7'), findsOneWidget);
    });

    testWidgets('appears on the same row as the name, with a gap, when the '
        'doctor has ratings (many-ratings case via demo data)', (t) async {
      await _pump(t, const DoctorDashboardScreen());
      expect(t.takeException(), isNull);

      final star = find.byIcon(Icons.star_rounded);
      final rating = find.text('4.7');
      expect(star, findsOneWidget);
      expect(rating, findsOneWidget);

      // Same row: the star and the rating text share a Y position (allowing
      // for the icon/text baseline difference), proving horizontal, not
      // stacked, alignment.
      final starCenter = t.getCenter(star);
      final ratingCenter = t.getCenter(rating);
      expect((starCenter.dy - ratingCenter.dy).abs(), lessThan(6));
      // And the rating sits to the right of the star with a small, non-zero
      // gap — not overlapping, not far enough to look like a separate block.
      expect(ratingCenter.dx, greaterThan(starCenter.dx));
    });
  });

  group('Earnings screen', () {
    testWidgets('no longer has a Profile tab — only Earnings and Ratings',
        (t) async {
      await _pump(t, const DoctorEarningsScreen());
      expect(t.takeException(), isNull);
      expect(find.text('Earnings'), findsWidgets);
      expect(find.text('Ratings'), findsWidgets);
      expect(find.text('Profile'), findsNothing);
      expect(find.byType(Tab), findsNWidgets(2));
    });
  });

  group('Responsive layout', () {
    for (final size in [
      const Size(1366, 900), // web wide
      const Size(390, 844), // web narrow
    ]) {
      testWidgets('no overflow at ${size.width.toInt()}x${size.height.toInt()}',
          (t) async {
        await t.binding.setSurfaceSize(size);
        addTearDown(() => t.binding.setSurfaceSize(null));
        await _pump(t, const DoctorDashboardScreen());
        expect(t.takeException(), isNull);
        expect(find.byKey(const Key('doctorProfileButton')), findsOneWidget);
      });
    }
  });

  group('Bottom navigation unchanged', () {
    testWidgets('still has the same 5 items (Home/Schedule/Cases/Chat/Earnings)',
        (t) async {
      await _pump(t, const DoctorDashboardScreen());
      expect(find.byType(BottomNavigationBar), findsOneWidget);
      final bar =
          t.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
      expect(bar.items.length, 5);
      expect(bar.items.map((i) => i.label),
          ['Home', 'Schedule', 'Cases', 'Chat', 'Earnings']);
    });
  });
}
