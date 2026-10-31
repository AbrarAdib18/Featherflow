// Renders each new admin screen (inside a minimal GoRouter, which the admin
// scaffold needs) and asserts the widget tree builds without throwing. The API
// calls in initState fail with no session and the screens fall back to their
// error/empty state — that path must not crash.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:featherflow/features/admin/presentation/screens/admin_admins_screen.dart';
import 'package:featherflow/features/admin/presentation/screens/admin_approvals_screen.dart';
import 'package:featherflow/features/admin/presentation/screens/admin_audit_screen.dart';
import 'package:featherflow/features/admin/presentation/screens/admin_oversight_screen.dart';
import 'package:featherflow/features/admin/presentation/screens/admin_dashboard_screen.dart';
import 'package:featherflow/features/admin/presentation/screens/admin_payroll_screen.dart';
import 'package:featherflow/features/admin/presentation/screens/admin_pharmacy_screen.dart';

Future<void> _pump(WidgetTester tester, Widget screen) async {
  final router = GoRouter(
    initialLocation: '/admin/x',
    routes: [
      GoRoute(path: '/admin/x', builder: (_, __) => screen),
      GoRoute(path: '/admin', builder: (_, __) => const SizedBox()),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('AdminApprovalsScreen builds', (t) async {
    await _pump(t, const AdminApprovalsScreen());
    expect(t.takeException(), isNull);
    expect(find.text('Approval Queue'), findsWidgets);
  });

  testWidgets('AdminAuditScreen builds', (t) async {
    await _pump(t, const AdminAuditScreen());
    expect(t.takeException(), isNull);
    expect(find.text('Audit Trail'), findsWidgets);
  });

  testWidgets('AdminAdminsScreen builds', (t) async {
    await _pump(t, const AdminAdminsScreen());
    expect(t.takeException(), isNull);
    expect(find.text('Admin Management'), findsWidgets);
  });

  testWidgets('AdminOversightScreen builds', (t) async {
    await _pump(t, const AdminOversightScreen());
    expect(t.takeException(), isNull);
    expect(find.text('Oversight'), findsWidgets);
  });

  testWidgets('AdminDashboardScreen builds', (t) async {
    await _pump(t, const AdminDashboardScreen());
    expect(t.takeException(), isNull);
    expect(find.text('Dashboard'), findsWidgets);
  });

  testWidgets('AdminPayrollScreen builds', (t) async {
    await _pump(t, const AdminPayrollScreen());
    expect(t.takeException(), isNull);
    expect(find.text('Team & Payroll'), findsWidgets);
  });

  testWidgets('AdminPharmacyScreen builds with all 7 tabs and no overflow', (t) async {
    await _pump(t, const AdminPharmacyScreen());
    expect(t.takeException(), isNull);
    expect(find.text('Pharmacy Management'), findsWidgets);
    for (final tab in const [
      'Pharmacies', 'Medicine Approvals', 'Expiry Monitoring', 'Orders & Delivery',
      'Chat & Appeals', 'Sales & Settlements', 'Reports & Audit',
    ]) {
      expect(find.text(tab), findsOneWidget, reason: '"$tab" tab should be present');
    }
  });

  testWidgets('AdminPharmacyScreen renders at 320px without overflow', (t) async {
    t.view.physicalSize = const Size(320, 700);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await _pump(t, const AdminPharmacyScreen());
    expect(t.takeException(), isNull);
  });

  testWidgets('AdminPharmacyScreen: Reports & Audit tab is selectable without crashing', (t) async {
    // With no live admin session (as in every other test in this file), the
    // screen's own top-level data load fails and the whole body falls back
    // to its shared error+Retry view regardless of which tab is selected —
    // this asserts that fallback path survives tapping the new 7th tab and
    // its Retry action, not the (session-gated) report content itself.
    await _pump(t, const AdminPharmacyScreen());
    final tab = find.text('Reports & Audit');
    await t.ensureVisible(tab);
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(tab, warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(seconds: 1));
    expect(t.takeException(), isNull);
  });
}
