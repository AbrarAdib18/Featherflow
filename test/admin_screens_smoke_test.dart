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
}
