import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:featherflow/core/format/currency.dart' show taka;
import 'package:featherflow/core/theme/theme.dart';

/// Chart set for Cost Management — Phase 3 of the farmer-panel fix pass.
/// Every value plotted here comes straight from `GET /api/farmers/costs/
/// dashboard/`'s `charts` object (`farmers/cost_views.py`), which computes
/// them with SQL-level `Sum`/`TruncMonth` aggregation. Nothing here is
/// hardcoded or sample data — an empty series renders the onboarding card
/// below instead of a chart with invented numbers.

const List<Color> _categoryPalette = [
  Color(0xFF2E7D32), Color(0xFF00695C), Color(0xFF6A1B9A),
  Color(0xFFC62828), Color(0xFFE65100), Color(0xFF283593),
  Color(0xFF4527A0), Color(0xFF00838F), Color(0xFF9E9D24),
];

/// A card with a title, an optional legend row and a fixed-height chart body.
/// Shared shell so every chart looks consistent and the empty/loaded switch
/// lives in one place.
class _ChartCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool isEmpty;
  final String emptyMessage;
  final Widget Function(BuildContext) chartBuilder;
  final Widget? legend;

  const _ChartCard({
    required this.title,
    this.subtitle,
    required this.isEmpty,
    required this.emptyMessage,
    required this.chartBuilder,
    this.legend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: const Color(0xFFDEEAE5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800, color: Colors.black87)),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(subtitle!,
              style: const TextStyle(fontSize: 11, color: Colors.black45)),
        ],
        const SizedBox(height: AppSpacing.sm),
        if (isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(children: [
              const Icon(Icons.insert_chart_outlined,
                  size: 36, color: Colors.black26),
              const SizedBox(height: 8),
              Text(emptyMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.black45)),
            ]),
          )
        else ...[
          SizedBox(
            // Fixed height keeps the card usable at both phone and desktop
            // widths — fl_chart fills whatever box it's given.
            height: 220,
            child: LayoutBuilder(builder: (context, _) => chartBuilder(context)),
          ),
          if (legend != null) ...[
            const SizedBox(height: AppSpacing.sm),
            legend!,
          ],
        ],
      ]),
    );
  }
}

Widget _legendDot(Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
      ],
    );

/// Revenue vs expense grouped bars, one pair per month.
class MonthlyRevenueExpenseChart extends StatelessWidget {
  final List monthly;
  const MonthlyRevenueExpenseChart({super.key, required this.monthly});

  @override
  Widget build(BuildContext context) {
    final rows = List<Map<String, dynamic>>.from(monthly.map((e) => Map<String, dynamic>.from(e as Map)));
    final isEmpty = rows.every((r) =>
        ((r['revenue'] as num?) ?? 0) == 0 && ((r['expense'] as num?) ?? 0) == 0);
    final maxY = isEmpty
        ? 10.0
        : rows
            .expand((r) => [((r['revenue'] as num?) ?? 0).toDouble(), ((r['expense'] as num?) ?? 0).toDouble()])
            .fold(0.0, (a, b) => a > b ? a : b) *
            1.2;

    return _ChartCard(
      title: 'Revenue vs Expenses',
      subtitle: 'Last ${rows.length} months',
      isEmpty: isEmpty,
      emptyMessage:
          'No revenue or expenses recorded yet. Add one to see your monthly trend here.',
      legend: Wrap(spacing: 16, children: [
        _legendDot(AppColors.secondaryContainer, 'Revenue'),
        _legendDot(AppColors.error, 'Expense'),
      ]),
      chartBuilder: (context) => BarChart(BarChartData(
        maxY: maxY <= 0 ? 10 : maxY,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final row = rows[group.x.toInt()];
              final isRevenue = rodIndex == 0;
              return BarTooltipItem(
                '${row['label']}\n${isRevenue ? 'Revenue' : 'Expense'}: ${taka(rod.toY)}',
                const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) => Text(
                  value >= 1000 ? '${(value / 1000).toStringAsFixed(0)}k' : value.toStringAsFixed(0),
                  style: const TextStyle(fontSize: 9, color: Colors.black45)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= rows.length) return const SizedBox.shrink();
                final label = rows[i]['label']?.toString() ?? '';
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(label.split(' ').first,
                      style: const TextStyle(fontSize: 9, color: Colors.black45)),
                );
              },
            ),
          ),
        ),
        gridData: const FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (var i = 0; i < rows.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                  toY: ((rows[i]['revenue'] as num?) ?? 0).toDouble(),
                  color: AppColors.secondaryContainer,
                  width: 8,
                  borderRadius: BorderRadius.circular(2)),
              BarChartRodData(
                  toY: ((rows[i]['expense'] as num?) ?? 0).toDouble(),
                  color: AppColors.error,
                  width: 8,
                  borderRadius: BorderRadius.circular(2)),
            ]),
        ],
      )),
    );
  }
}

/// Net-profit line across the same trailing months.
class ProfitTrendChart extends StatelessWidget {
  final List monthly;
  const ProfitTrendChart({super.key, required this.monthly});

  @override
  Widget build(BuildContext context) {
    final rows = List<Map<String, dynamic>>.from(monthly.map((e) => Map<String, dynamic>.from(e as Map)));
    final isEmpty = rows.every((r) => ((r['profit'] as num?) ?? 0) == 0);
    final profits = rows.map((r) => ((r['profit'] as num?) ?? 0).toDouble()).toList();
    final minY = (profits.isEmpty ? 0.0 : profits.reduce((a, b) => a < b ? a : b));
    final maxY = (profits.isEmpty ? 0.0 : profits.reduce((a, b) => a > b ? a : b));
    final pad = ((maxY - minY).abs() * 0.2).clamp(10.0, double.infinity);

    return _ChartCard(
      title: 'Profit Trend',
      subtitle: 'Net profit by month (revenue − expense)',
      isEmpty: isEmpty,
      emptyMessage: 'No profit data yet — record revenue and expenses to see the trend.',
      chartBuilder: (context) => LineChart(LineChartData(
        minY: minY - pad,
        maxY: maxY + pad,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots.map((s) {
              final row = rows[s.x.toInt()];
              return LineTooltipItem(
                '${row['label']}\n${taka(s.y)}',
                const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
              );
            }).toList(),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) => Text(
                  value.abs() >= 1000 ? '${(value / 1000).toStringAsFixed(0)}k' : value.toStringAsFixed(0),
                  style: const TextStyle(fontSize: 9, color: Colors.black45)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= rows.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(rows[i]['label'].toString().split(' ').first,
                      style: const TextStyle(fontSize: 9, color: Colors.black45)),
                );
              },
            ),
          ),
        ),
        gridData: const FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: [for (var i = 0; i < rows.length; i++) FlSpot(i.toDouble(), profits[i])],
            isCurved: true,
            color: AppColors.primary,
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
                show: true, color: AppColors.primary.withValues(alpha: 0.08)),
          ),
        ],
      )),
    );
  }
}

/// Donut breakdown of expense categories for the selected period.
class CategoryBreakdownChart extends StatelessWidget {
  final List categories;
  const CategoryBreakdownChart({super.key, required this.categories});

  @override
  Widget build(BuildContext context) {
    final rows = List<Map<String, dynamic>>.from(categories.map((e) => Map<String, dynamic>.from(e as Map)));
    final total = rows.fold<double>(0, (sum, r) => sum + ((r['total'] as num?) ?? 0));
    final isEmpty = rows.isEmpty || total <= 0;

    return _ChartCard(
      title: 'Expense Breakdown',
      subtitle: 'By category, this period',
      isEmpty: isEmpty,
      emptyMessage: 'No expenses in this period yet.',
      legend: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          for (var i = 0; i < rows.length; i++)
            _legendDot(_categoryPalette[i % _categoryPalette.length], '${rows[i]['category']}'),
        ],
      ),
      chartBuilder: (context) => PieChart(PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 40,
        sections: [
          for (var i = 0; i < rows.length; i++)
            PieChartSectionData(
              value: ((rows[i]['total'] as num?) ?? 0).toDouble(),
              color: _categoryPalette[i % _categoryPalette.length],
              radius: 50,
              title: total > 0
                  ? '${(((rows[i]['total'] as num?) ?? 0) / total * 100).toStringAsFixed(0)}%'
                  : '',
              titleStyle: const TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
            ),
        ],
      )),
    );
  }
}

/// Feed / Labour / Medicines cost comparison for the selected period.
class CategoryComparisonChart extends StatelessWidget {
  final List comparison;
  const CategoryComparisonChart({super.key, required this.comparison});

  @override
  Widget build(BuildContext context) {
    final rows = List<Map<String, dynamic>>.from(comparison.map((e) => Map<String, dynamic>.from(e as Map)));
    final isEmpty = rows.every((r) => ((r['total'] as num?) ?? 0) == 0);
    final maxY = isEmpty
        ? 10.0
        : rows.map((r) => ((r['total'] as num?) ?? 0).toDouble()).fold(0.0, (a, b) => a > b ? a : b) * 1.3;
    const colors = {
      'Feed': Color(0xFF00695C),
      'Labor': Color(0xFF283593),
      'Medicines': Color(0xFFC62828),
    };

    return _ChartCard(
      title: 'Feed · Labour · Medicine Costs',
      subtitle: 'This period',
      isEmpty: isEmpty,
      emptyMessage: 'No feed, labour or medicine costs recorded in this period yet.',
      chartBuilder: (context) => BarChart(BarChartData(
        maxY: maxY <= 0 ? 10 : maxY,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
              '${rows[group.x.toInt()]['category']}\n${taka(rod.toY)}',
              const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) => Text(
                  value >= 1000 ? '${(value / 1000).toStringAsFixed(0)}k' : value.toStringAsFixed(0),
                  style: const TextStyle(fontSize: 9, color: Colors.black45)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= rows.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${rows[i]['category']}',
                      style: const TextStyle(fontSize: 9, color: Colors.black45)),
                );
              },
            ),
          ),
        ),
        gridData: const FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (var i = 0; i < rows.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: ((rows[i]['total'] as num?) ?? 0).toDouble(),
                color: colors[rows[i]['category']] ?? AppColors.primary,
                width: 26,
                borderRadius: BorderRadius.circular(4),
              ),
            ]),
        ],
      )),
    );
  }
}

/// Lays the four charts out responsively: two columns on wide (desktop/tablet
/// web) viewports, one column stacked on narrow ones.
class CostChartsSection extends StatelessWidget {
  final Map<String, dynamic> charts;
  const CostChartsSection({super.key, required this.charts});

  @override
  Widget build(BuildContext context) {
    final monthly = (charts['monthly'] as List?) ?? const [];
    final breakdown = (charts['category_breakdown'] as List?) ?? const [];
    final comparison = (charts['category_comparison'] as List?) ?? const [];

    final cards = [
      MonthlyRevenueExpenseChart(monthly: monthly),
      ProfitTrendChart(monthly: monthly),
      CategoryBreakdownChart(categories: breakdown),
      CategoryComparisonChart(comparison: comparison),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 720;
      if (!wide) {
        return Column(children: [
          for (final c in cards) ...[c, const SizedBox(height: AppSpacing.md)],
        ]);
      }
      return Column(children: [
        for (var i = 0; i < cards.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: cards[i]),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                  child: i + 1 < cards.length ? cards[i + 1] : const SizedBox.shrink()),
            ]),
          ),
      ]);
    });
  }
}
