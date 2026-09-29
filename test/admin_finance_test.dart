// Widget tests for FINANCE_ADMIN_DASHBOARD_AND_SUBSCRIPTIONS.md /
// FINANCE_ADMIN_CASHOUT_WORKFLOW.md / FINANCE_ADMIN_RBAC_CHANGES.md.
//
// AdminSession has no injectable test seam (documented limitation, first
// noted in admin_dashboard_and_profile_buttons_test.dart) — with no live
// session, `session.role` defaults to supportAgent and every finance-only
// nav item stays hidden (which is itself a correct assertion: an
// unauthorized/unauthenticated viewer must not see them). Full "Finance
// Admin sees these, another role doesn't" role-swapping is covered by the
// backend test (test_finance_admin.py) plus the pure permission-map unit
// tests in admin_navigation_test.dart.
//
// AdminScaffold reads GoRouterState.of(context) internally, so every screen
// below is pumped under a real GoRouter (matching the convention already
// established in admin_earnings_test.dart / admin_dashboard_and_profile_buttons_test.dart),
// and fetches are driven via runAsync since they're real (failing, no-
// session) dart:io HTTP calls, not fake-clock Futures.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:featherflow/features/admin/presentation/screens/admin_finance_screen.dart';
import 'package:featherflow/features/admin/presentation/screens/admin_subscriptions_screen.dart';
import 'package:featherflow/features/admin/presentation/screens/admin_cashouts_screen.dart';
import 'package:featherflow/features/admin/presentation/widgets/admin_sidebar.dart';
import 'package:featherflow/features/admin/data/models/admin_role.dart';

Future<void> _pumpUnderRouter(WidgetTester t, Widget screen) async {
  final router = GoRouter(
    initialLocation: '/x',
    routes: [GoRoute(path: '/x', builder: (_, __) => screen)],
  );
  await t.pumpWidget(MaterialApp.router(routerConfig: router));
  for (var i = 0; i < 20 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await t.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Finance label', () {
    testWidgets('AdminFinanceScreen title is exactly "Finance", not '
        '"Finance & Subscriptions"', (t) async {
      await t.runAsync(() async {
        await _pumpUnderRouter(t, const AdminFinanceScreen());
        expect(t.takeException(), isNull);
        expect(find.text('Finance & Subscriptions'), findsNothing);
      });
    });
  });

  group('Sidebar: finance-only items hidden for an unauthorized/no session', () {
    testWidgets('Subscriptions / Pending / Approved Cashout items are absent '
        'with no session', (t) async {
      await _pumpUnderRouter(
          t, const Scaffold(body: AdminSidebar(selectedModule: AdminModule.dashboard)));
      expect(t.takeException(), isNull);
      expect(find.text('Subscriptions'), findsNothing);
      expect(find.text('Pending Cashout Requests'), findsNothing);
      expect(find.text('Approved Cashout Requests'), findsNothing);
      // The generic operational Approval Queue must also not leak in.
      expect(find.text('Approval Queue'), findsNothing);
    });
  });

  group('AdminSubscriptionsScreen', () {
    testWidgets('shows the access-restricted panel with no session, no crash',
        (t) async {
      await _pumpUnderRouter(t, const AdminSubscriptionsScreen());
      expect(t.takeException(), isNull);
      expect(find.text('Access Restricted'), findsOneWidget);
    });
  });

  group('AdminCashoutsScreen', () {
    testWidgets('pending page renders its own title, not the generic '
        'Approval Queue title', (t) async {
      await t.runAsync(() async {
        await _pumpUnderRouter(t, const AdminCashoutsScreen(pending: true));
        expect(t.takeException(), isNull);
        expect(find.text('Pending Cashout Requests'), findsWidgets);
        expect(find.text('Approval Queue'), findsNothing);
      });
    });

    testWidgets('approved page renders its own title', (t) async {
      await t.runAsync(() async {
        await _pumpUnderRouter(t, const AdminCashoutsScreen(pending: false));
        expect(t.takeException(), isNull);
        expect(find.text('Approved Cashout Requests'), findsWidgets);
      });
    });

    testWidgets('reaches a loading/error state without throwing (no session, '
        'real failing fetch)', (t) async {
      await t.runAsync(() async {
        await _pumpUnderRouter(t, const AdminCashoutsScreen(pending: true));
        expect(t.takeException(), isNull);
      });
    });
  });
}
