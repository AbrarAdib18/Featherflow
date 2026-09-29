// Widget + unit tests for OPERATIONS_ADMIN_EARNINGS.md:
// 1. formatDuration()/formatBdt() — the display-formatting rules the
//    Earnings screen uses to render server-computed seconds/BDT strings.
// 2. The sidebar's "Earnings" item is gated on AdminSession.tracksShifts —
//    with no session (the only state directly reachable in this harness,
//    same constraint as admin_dashboard_and_profile_buttons_test.dart)
//    tracksShifts defaults to false, so the item must not render. This is
//    the same mechanism that keeps it off Super Admin and non-admin roles
//    (feed_admin has no AdminProfile row at all, so tracks_shifts is false
//    for it server-side too — see OPERATIONS_ADMIN_EARNINGS_AUDIT.md).
// 3. AdminEarningsScreen renders its loading/error/retry states without
//    throwing, on both wide and narrow layouts, and its back control works.
//
// AdminApiService/AdminSession have no injectable test seam (documented
// limitation, first noted in admin_dashboard_and_profile_buttons_test.dart)
// — so a *populated* Today/This Week/This Month/Total Income render, the
// ৳450/hour rate display, and the no-duplicate-API-calls behavior of the
// live ticker cannot be asserted end-to-end in this harness. Those are
// covered instead by the backend test (test_admin_earnings.py) plus code
// review of the binding itself.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:featherflow/features/admin/presentation/screens/admin_earnings_screen.dart';
import 'package:featherflow/features/admin/presentation/widgets/admin_sidebar.dart';
import 'package:featherflow/features/admin/data/models/admin_role.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('formatDuration', () {
    test('zero seconds', () {
      expect(formatDuration(0), '0h 0m');
    });

    test('exactly one hour', () {
      expect(formatDuration(3600), '1h 0m');
    });

    test('6h 30m (23400s), matching the spec example', () {
      expect(formatDuration(23400), '6h 30m');
    });

    test('30 minutes only', () {
      expect(formatDuration(1800), '0h 30m');
    });

    test('negative input clamps to zero, never crashes', () {
      expect(formatDuration(-5), '0h 0m');
    });
  });

  group('formatBdt', () {
    test('zero', () {
      expect(formatBdt(0), '৳0.00');
    });

    test('one hour at 450/h', () {
      expect(formatBdt(450.0), '৳450.00');
    });

    test('30 minutes at 450/h = 225.00', () {
      expect(formatBdt(225.0), '৳225.00');
    });

    test('always renders exactly two decimal places', () {
      // formatBdt only formats an already-rounded server value (the backend
      // does all monetary rounding with Decimal — see OPERATIONS_ADMIN_EARNINGS.md)
      // so these inputs are deliberately clean two-decimal values, not
      // borderline-rounding cases that would make this a float-rounding test.
      expect(formatBdt(32.7), '৳32.70');
      expect(formatBdt(32.75), '৳32.75');
    });
  });

  group('Earnings sidebar visibility', () {
    testWidgets('does not render for an unauthorized session (no session — '
        'tracksShifts false, same gate that keeps it off Super Admin and '
        'feed_admin)', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(body: AdminSidebar(selectedModule: AdminModule.dashboard)),
      ));
      await t.pump(const Duration(milliseconds: 100));
      expect(t.takeException(), isNull);
      expect(find.text('Earnings'), findsNothing);
    });
  });

  group('AdminEarningsScreen', () {
    Future<GoRouter> pump(WidgetTester t, Size size) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.resetPhysicalSize);
      final router = GoRouter(
        initialLocation: '/admin',
        routes: [
          // A lightweight placeholder — not the real dashboard screen, which
          // performs its own real (failing, in this no-session harness)
          // fetch and would race the earnings screen's own "Retry" text,
          // making findsOneWidget flaky. Matches admin_screens_smoke_test.dart's
          // established '/admin' placeholder convention.
          GoRoute(path: '/admin', builder: (_, __) => const SizedBox()),
          GoRoute(path: '/admin/earnings', builder: (_, __) => const AdminEarningsScreen()),
        ],
      );
      await t.pumpWidget(MaterialApp.router(routerConfig: router));
      await t.pump(const Duration(milliseconds: 100));
      return router;
    }

    testWidgets('shows a loading spinner on the first frame, wide layout',
        (t) async {
      final router = await pump(t, const Size(1400, 900));
      router.go('/admin/earnings');
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(t.takeException(), isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('reaches an error/retry state without throwing, no crash, '
        'wide layout', (t) async {
      await t.runAsync(() async {
        final router = await pump(t, const Size(1400, 900));
        router.go('/admin/earnings');
        await t.pump();
        for (var i = 0; i < 20 && find.text('Retry').evaluate().isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          await t.pump();
        }
        expect(t.takeException(), isNull);
        expect(find.text('Retry'), findsOneWidget);
      });
    });

    testWidgets('renders without overflow on a narrow layout', (t) async {
      await t.runAsync(() async {
        final router = await pump(t, const Size(390, 844));
        router.go('/admin/earnings');
        await t.pump();
        for (var i = 0; i < 20 && find.text('Retry').evaluate().isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          await t.pump();
        }
        expect(t.takeException(), isNull);
      });
    });

    testWidgets('back navigation from Earnings returns to the dashboard',
        (t) async {
      final router = await pump(t, const Size(1400, 900));
      router.go('/admin/earnings');
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      final backButton = find.byTooltip('Back');
      expect(backButton, findsOneWidget);
      await t.tap(backButton);
      await t.pump(const Duration(milliseconds: 100));
      expect(t.takeException(), isNull);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/admin');
    });
  });
}
