// Widget tests for OPERATIONS_ADMIN_DASHBOARD_AUDIT.md:
// 1. Both profile-avatar buttons (navbar/top-bar and sidebar header) are
//    actionable and navigate to the shared /admin/profile route — they
//    previously had no onTap/GestureDetector at all, so tapping did nothing.
// 2. The dashboard shows a loading state before the first fetch resolves,
//    and an error state with a working Retry control after a failed load
//    (no session in this test environment) — not fabricated zero values.
//
// AdminSession/AdminApiService have no injectable test seam (real HTTP
// singletons, same constraint noted for FeedManagementScreen and
// DeliverySession's non-seamed siblings elsewhere in this codebase) — so
// this file cannot directly assert the corrected "Active Users" card shows
// a specific live value. That binding (stats['active_users'], not
// stats['total_users']) is covered instead by the backend test
// (test_admin_dashboard_metrics.py) and by code review; documented as a
// limitation in OPERATIONS_ADMIN_DASHBOARD_AUDIT.md.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:featherflow/features/admin/presentation/screens/admin_dashboard_screen.dart';
import 'package:featherflow/features/admin/presentation/screens/admin_profile_screen.dart';

Future<GoRouter> _pump(WidgetTester tester, {required Size size}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  final router = GoRouter(
    initialLocation: '/admin',
    routes: [
      GoRoute(
          path: '/admin', builder: (_, __) => const AdminDashboardScreen()),
      GoRoute(
          path: '/admin/profile',
          builder: (_, __) => const AdminProfileScreen()),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(seconds: 1));
  return router;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Both profile-avatar buttons navigate to /admin/profile', () {
    testWidgets('wide layout: top-bar avatar is actionable', (t) async {
      final router = await _pump(t, size: const Size(1400, 900));
      expect(t.takeException(), isNull);
      final avatar = find.byKey(const Key('adminProfileAvatarWide'));
      expect(avatar, findsOneWidget,
          reason: 'the top-bar avatar must exist on the wide layout');
      await t.tap(avatar);
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(seconds: 1));
      expect(t.takeException(), isNull);
      expect(router.routerDelegate.currentConfiguration.uri.path,
          '/admin/profile');
    });

    testWidgets('wide layout: sidebar header avatar is actionable', (t) async {
      final router = await _pump(t, size: const Size(1400, 900));
      final avatar = find.byKey(const Key('adminProfileAvatarSidebar'));
      expect(avatar, findsOneWidget,
          reason: 'the sidebar is persistently visible on the wide layout');
      await t.tap(avatar);
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(seconds: 1));
      expect(t.takeException(), isNull);
      expect(router.routerDelegate.currentConfiguration.uri.path,
          '/admin/profile');
    });

    testWidgets('narrow layout: app-bar avatar is actionable', (t) async {
      // Below kBreakpointWide (900) — exercises the narrow AppBar/drawer
      // layout, including the AdminProfileScreen this now navigates to
      // (whose _InfoRow overflow at narrow widths was found and fixed
      // alongside this test — see OPERATIONS_ADMIN_DASHBOARD_AUDIT.md).
      final router = await _pump(t, size: const Size(390, 844));
      final avatar = find.byKey(const Key('adminProfileAvatarNarrow'));
      expect(avatar, findsOneWidget,
          reason: 'the app-bar avatar must exist on the narrow layout');
      await t.tap(avatar);
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(seconds: 1));
      expect(t.takeException(), isNull);
      expect(router.routerDelegate.currentConfiguration.uri.path,
          '/admin/profile');
    });

    testWidgets('back navigation from the profile screen returns to the '
        'dashboard', (t) async {
      final router = await _pump(t, size: const Size(1400, 900));
      await t.tap(find.byKey(const Key('adminProfileAvatarWide')));
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(seconds: 1));
      expect(router.routerDelegate.currentConfiguration.uri.path,
          '/admin/profile');
      // AdminProfileScreen is wrapped in AdminScaffold, which renders its own
      // back control (_TopBar's IconButton with tooltip 'Back' on wide, or
      // the narrow AppBar's arrow_back_ios_new) — go through whichever the
      // current layout renders.
      final backButton = find.byTooltip('Back');
      expect(backButton, findsOneWidget);
      await t.tap(backButton);
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(seconds: 1));
      expect(t.takeException(), isNull);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/admin');
    });
  });

  group('Dashboard loading / error / retry states', () {
    testWidgets('shows a loading spinner before the first load resolves',
        (t) async {
      testerViewSize(t, const Size(1400, 900));
      final router = GoRouter(
        initialLocation: '/admin',
        routes: [
          GoRoute(
              path: '/admin', builder: (_, __) => const AdminDashboardScreen()),
        ],
      );
      await t.pumpWidget(MaterialApp.router(routerConfig: router));
      // Before the (failing, no-session) fetch has had time to resolve.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows an error banner with a working Retry control after '
        'the load fails, no crash', (t) async {
      // The failed fetch is a real dart:io HTTP call (no session/no
      // reachable backend in this harness) — that needs the real event
      // loop, not just the fake-async clock `pump()` advances, so drive it
      // via runAsync.
      await t.runAsync(() async {
        testerViewSize(t, const Size(1400, 900));
        final router = GoRouter(
          initialLocation: '/admin',
          routes: [
            GoRoute(
                path: '/admin',
                builder: (_, __) => const AdminDashboardScreen()),
          ],
        );
        await t.pumpWidget(MaterialApp.router(routerConfig: router));
        for (var i = 0; i < 20 && find.text('Retry').evaluate().isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          await t.pump();
        }
        expect(t.takeException(), isNull);
        expect(find.text('Retry'), findsOneWidget);
        await t.tap(find.text('Retry'));
        await t.pump();
        for (var i = 0; i < 20 && find.text('Retry').evaluate().isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          await t.pump();
        }
        expect(t.takeException(), isNull);
        // Still on the dashboard, still showing the error state — retrying
        // against a still-unreachable backend fails again cleanly, not a
        // crash.
        expect(find.text('Retry'), findsOneWidget);
      });
    });

    testWidgets('does not show fabricated stat values while unloaded — no '
        'Overview cards render before a successful load', (t) async {
      await _pump(t, size: const Size(1400, 900));
      expect(t.takeException(), isNull);
      // With no successful load, _OverviewGrid's cards are never built with
      // fake numbers — only the loading/error scaffolding is present.
      expect(find.text('Active Users'), findsNothing);
    });
  });
}

void testerViewSize(WidgetTester t, Size size) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
}
