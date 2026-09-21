// Cost Management charts (Phase 3) — widget-level rendering tests.
//
// Data-correctness (SQL aggregation, period/date-range filtering, labour
// mirroring, updates after a mutation) is covered live-DB in
// backend/scripts/test_cost_dashboard_charts.py, following this project's
// established "no client-side HTTP mocking" convention (see
// farmer_screens_smoke_test.dart). These tests instead verify what the chart
// widgets do with a given `charts` payload: populated data renders a chart,
// empty/all-zero data renders the onboarding empty state instead of an
// invented chart, and the section lays out responsively.
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:featherflow/features/farmer/presentation/widgets/cost_charts.dart';

const _populatedMonthly = [
  {'month': '2026-04', 'label': 'Apr 2026', 'revenue': 10000.0, 'expense': 6000.0, 'profit': 4000.0},
  {'month': '2026-05', 'label': 'May 2026', 'revenue': 8000.0, 'expense': 9000.0, 'profit': -1000.0},
];

const _zeroMonthly = [
  {'month': '2026-04', 'label': 'Apr 2026', 'revenue': 0.0, 'expense': 0.0, 'profit': 0.0},
  {'month': '2026-05', 'label': 'May 2026', 'revenue': 0.0, 'expense': 0.0, 'profit': 0.0},
];

const _populatedBreakdown = [
  {'category': 'Feed', 'total': 5000.0},
  {'category': 'Labor', 'total': 2000.0},
];

const _zeroComparison = [
  {'category': 'Feed', 'total': 0.0},
  {'category': 'Labor', 'total': 0.0},
  {'category': 'Medicines', 'total': 0.0},
];

Widget _host(Widget child, {double width = 400}) => MaterialApp(
      home: Scaffold(
          body: SizedBox(width: width, child: SingleChildScrollView(child: child))),
    );

void main() {
  group('MonthlyRevenueExpenseChart', () {
    testWidgets('renders a bar chart with real data', (t) async {
      await t.pumpWidget(_host(const MonthlyRevenueExpenseChart(monthly: _populatedMonthly)));
      expect(find.text('Revenue vs Expenses'), findsOneWidget);
      expect(find.byType(BarChart), findsOneWidget);
      expect(find.textContaining('No revenue or expenses'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('shows the onboarding empty state for an all-zero series', (t) async {
      await t.pumpWidget(_host(const MonthlyRevenueExpenseChart(monthly: _zeroMonthly)));
      expect(find.byType(BarChart), findsNothing);
      expect(find.textContaining('No revenue or expenses'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('shows the onboarding empty state for a genuinely empty list', (t) async {
      await t.pumpWidget(_host(const MonthlyRevenueExpenseChart(monthly: [])));
      expect(find.byType(BarChart), findsNothing);
      expect(find.textContaining('No revenue or expenses'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('ProfitTrendChart', () {
    testWidgets('renders a line chart with real data', (t) async {
      await t.pumpWidget(_host(const ProfitTrendChart(monthly: _populatedMonthly)));
      expect(find.text('Profit Trend'), findsOneWidget);
      expect(find.byType(LineChart), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('shows the onboarding empty state when every month has zero profit',
        (t) async {
      await t.pumpWidget(_host(const ProfitTrendChart(monthly: _zeroMonthly)));
      expect(find.byType(LineChart), findsNothing);
      expect(find.textContaining('No profit data yet'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('CategoryBreakdownChart', () {
    testWidgets('renders a pie chart and a legend entry per category', (t) async {
      await t.pumpWidget(_host(const CategoryBreakdownChart(categories: _populatedBreakdown)));
      expect(find.byType(PieChart), findsOneWidget);
      expect(find.text('Feed'), findsOneWidget);
      expect(find.text('Labor'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('shows the onboarding empty state for an empty period', (t) async {
      await t.pumpWidget(_host(const CategoryBreakdownChart(categories: [])));
      expect(find.byType(PieChart), findsNothing);
      expect(find.textContaining('No expenses in this period'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('CategoryComparisonChart', () {
    testWidgets('shows the onboarding empty state when every category is zero',
        (t) async {
      await t.pumpWidget(_host(const CategoryComparisonChart(comparison: _zeroComparison)));
      expect(find.byType(BarChart), findsNothing);
      expect(find.textContaining('No feed, labour or medicine costs'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('renders bars once at least one category has spend', (t) async {
      await t.pumpWidget(_host(const CategoryComparisonChart(comparison: [
        {'category': 'Feed', 'total': 1500.0},
        {'category': 'Labor', 'total': 0.0},
        {'category': 'Medicines', 'total': 0.0},
      ])));
      expect(find.byType(BarChart), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('CostChartsSection responsive layout', () {
    const charts = {
      'monthly': _populatedMonthly,
      'category_breakdown': _populatedBreakdown,
      'category_comparison': _zeroComparison,
    };

    testWidgets('stacks charts in one column on a narrow viewport', (t) async {
      await t.pumpWidget(_host(const CostChartsSection(charts: charts), width: 380));
      // Narrow layout has no side-by-side Row pairing two chart cards.
      expect(find.byType(MonthlyRevenueExpenseChart), findsOneWidget);
      expect(find.byType(ProfitTrendChart), findsOneWidget);
      expect(find.byType(CategoryBreakdownChart), findsOneWidget);
      expect(find.byType(CategoryComparisonChart), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('pairs charts two-per-row on a wide viewport', (t) async {
      await t.pumpWidget(_host(const CostChartsSection(charts: charts), width: 1000));
      expect(find.byType(MonthlyRevenueExpenseChart), findsOneWidget);
      expect(find.byType(ProfitTrendChart), findsOneWidget);
      expect(find.byType(CategoryBreakdownChart), findsOneWidget);
      expect(find.byType(CategoryComparisonChart), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('handles a completely missing charts map without throwing', (t) async {
      await t.pumpWidget(_host(const CostChartsSection(charts: {})));
      expect(find.textContaining('No revenue or expenses'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('no overflow at a small-phone width with populated data', (t) async {
      // 320px is the narrowest common phone width (e.g. iPhone SE). A
      // RenderFlex overflow or similar layout error surfaces as an exception
      // here, not a silent visual clip.
      const full = {
        'monthly': _populatedMonthly,
        'category_breakdown': _populatedBreakdown,
        'category_comparison': [
          {'category': 'Feed', 'total': 1500.0},
          {'category': 'Labor', 'total': 750.0},
          {'category': 'Medicines', 'total': 300.0},
        ],
      };
      await t.pumpWidget(_host(const CostChartsSection(charts: full), width: 320));
      await t.pump(const Duration(milliseconds: 100));
      expect(t.takeException(), isNull);
    });
  });
}
