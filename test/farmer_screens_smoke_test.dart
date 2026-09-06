// Renders each new/rewired farmer Cost-Management screen inside a minimal
// GoRouter and asserts the tree builds without throwing. initState API calls
// fail with no session; the screens must fall back to their loading/error
// state without crashing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:featherflow/features/farmer/presentation/screens/cost_management_screen.dart';
import 'package:featherflow/features/farmer/presentation/screens/expense_list_screen.dart';
import 'package:featherflow/features/farmer/presentation/screens/revenue_list_screen.dart';
import 'package:featherflow/features/farmer/presentation/screens/loan_screen.dart';
import 'package:featherflow/features/farmer/presentation/screens/inventory_screen.dart';
import 'package:featherflow/features/farmer/presentation/screens/reports_screen.dart';
import 'package:featherflow/features/farmer/presentation/screens/farmer_profile_screen.dart';

Future<void> _pump(WidgetTester tester, Widget screen) async {
  final router = GoRouter(
    initialLocation: '/farmer/x',
    routes: [
      GoRoute(path: '/farmer/x', builder: (_, __) => screen),
      GoRoute(path: '/farmer', builder: (_, __) => const SizedBox()),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('CostManagementScreen builds', (t) async {
    await _pump(t, const CostManagementScreen());
    expect(t.takeException(), isNull);
    expect(find.text('Cost Management'), findsWidgets);
  });

  testWidgets('ExpenseListScreen builds', (t) async {
    await _pump(t, const ExpenseListScreen(category: 'Feed'));
    expect(t.takeException(), isNull);
    expect(find.textContaining('expenses'), findsWidgets);
  });

  testWidgets('RevenueListScreen builds', (t) async {
    await _pump(t, const RevenueListScreen());
    expect(t.takeException(), isNull);
    expect(find.text('Revenue'), findsWidgets);
  });

  testWidgets('LoanScreen builds', (t) async {
    await _pump(t, const LoanScreen());
    expect(t.takeException(), isNull);
    expect(find.text('Loans'), findsWidgets);
  });

  testWidgets('InventoryScreen builds', (t) async {
    await _pump(t, const InventoryScreen());
    expect(t.takeException(), isNull);
    expect(find.text('Inventory & Batches'), findsWidgets);
  });

  testWidgets('ReportsScreen builds', (t) async {
    await _pump(t, const ReportsScreen());
    expect(t.takeException(), isNull);
    expect(find.text('Reports'), findsWidgets);
  });

  testWidgets('FarmerProfileScreen builds', (t) async {
    await _pump(t, const FarmerProfileScreen());
    expect(t.takeException(), isNull);
  });
}
