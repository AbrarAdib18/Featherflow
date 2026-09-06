import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:featherflow/core/theme/theme.dart';
import '../../data/cost_management_service.dart';
import '../widgets/cost_dialogs.dart';

const _periods = ['lifetime', 'monthly', 'yearly'];

String taka(num v) {
  final s = v.abs().toStringAsFixed(0);
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return '${v < 0 ? '-' : ''}৳$buf';
}

class CostManagementScreen extends StatefulWidget {
  const CostManagementScreen({super.key});

  @override
  State<CostManagementScreen> createState() => _CostManagementScreenState();
}

class _CostManagementScreenState extends State<CostManagementScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  int _period = 0;
  Timer? _poll;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && !_loading) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final d =
          await CostManagementService.dashboard(period: _periods[_period]);
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Cost Management',
            style: TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart, color: Colors.white),
            tooltip: 'Reports',
            onPressed: () => context.push('/farmer/cost-management/reports'),
          ),
          IconButton(
            icon: const Icon(Icons.home, color: Colors.white),
            onPressed: () => context.go('/farmer'),
          ),
        ],
      ),
      body: _data == null
          ? Center(
              child: _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        TextButton(
                            onPressed: _load, child: const Text('Retry')),
                      ]),
                    )
                  : const CircularProgressIndicator(),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _TopCard(
                    data: _data!,
                    period: _period,
                    onPeriod: (i) {
                      setState(() => _period = i);
                      _load();
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _QuickActions(onDone: _load, dashboard: _data!),
                        const SizedBox(height: AppSpacing.lg),
                        _alerts(),
                        const _Header('Expense sections'),
                        const SizedBox(height: AppSpacing.sm),
                        _ExpenseGrid(
                            sections: (_data!['expense_sections'] as List?) ?? [],
                            onManage: (cat) => context.push(
                                '/farmer/cost-management/expenses',
                                extra: cat),
                            onAdd: (cat) async {
                              final ok = await showExpenseSheet(context,
                                  presetCategory: cat);
                              if (ok == true) {
                                _snack('Expense added');
                                _load();
                              }
                            }),
                        const SizedBox(height: AppSpacing.lg),
                        _Header('Revenue sections',
                            action: TextButton(
                              onPressed: () => context.push(
                                  '/farmer/cost-management/revenue'),
                              child: const Text('View all'),
                            )),
                        const SizedBox(height: AppSpacing.sm),
                        _RevenueList(
                            sections: (_data!['revenue_sections'] as List?) ?? []),
                        const SizedBox(height: AppSpacing.lg),
                        _LoansSection(
                            loans: (_data!['loans'] as List?) ?? [],
                            onDone: _load),
                        const SizedBox(height: AppSpacing.lg),
                        const _Header('Recent transactions'),
                        const SizedBox(height: AppSpacing.sm),
                        _Transactions(
                            rows: (_data!['transactions'] as List?) ?? []),
                        const SizedBox(height: AppSpacing.xl),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _alerts() {
    final alerts = (_data!['alerts'] as List?) ?? [];
    if (alerts.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Header('Alerts'),
        const SizedBox(height: AppSpacing.sm),
        for (final a in alerts.take(4))
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: (a['severity'] == 'error'
                      ? AppColors.error
                      : Colors.orange)
                  .withValues(alpha: 0.08),
              borderRadius: AppRadius.mdAll,
              border: Border.all(
                  color: (a['severity'] == 'error'
                          ? AppColors.error
                          : Colors.orange)
                      .withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              Icon(
                  a['severity'] == 'error'
                      ? Icons.error_outline
                      : Icons.warning_amber_rounded,
                  color: a['severity'] == 'error'
                      ? AppColors.error
                      : Colors.orange,
                  size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${a['title']}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: Colors.black87)),
                      Text('${a['body']}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54)),
                    ]),
              ),
            ]),
          ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  final Widget? action;
  const _Header(this.text, {this.action});
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Text(text,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87)),
          const Spacer(),
          if (action != null) action!,
        ],
      );
}

class _TopCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final int period;
  final ValueChanged<int> onPeriod;
  const _TopCard(
      {required this.data, required this.period, required this.onPeriod});

  @override
  Widget build(BuildContext context) {
    final s = (data['summary'] as Map?) ?? {};
    num n(String k) => (s[k] as num?) ?? 0;
    return Container(
      width: double.infinity,
      color: AppColors.primary,
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          decoration: const BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: AppRadius.smAll),
          padding: const EdgeInsets.all(3),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < _periods.length; i++)
              GestureDetector(
                onTap: () => onPeriod(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                      color: i == period
                          ? AppColors.secondary
                          : Colors.transparent,
                      borderRadius: AppRadius.smAll),
                  child: Text(
                    _periods[i][0].toUpperCase() + _periods[i].substring(1),
                    style: TextStyle(
                        color: i == period ? Colors.black : Colors.white70,
                        fontWeight:
                            i == period ? FontWeight.w700 : FontWeight.w400,
                        fontSize: 12),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: AppSpacing.lg),
        const Text('Total Revenue',
            style: TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 2),
        Text(taka(n('total_revenue')),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5)),
        const SizedBox(height: AppSpacing.md),
        Row(children: [
          _mini('Total Expense', taka(n('total_expense'))),
          const SizedBox(width: AppSpacing.sm),
          _mini('Net Profit', taka(n('net_profit')),
              accent: n('net_profit') >= 0
                  ? AppColors.secondary
                  : AppColors.error),
        ]),
        const SizedBox(height: AppSpacing.sm),
        Row(children: [
          _mini('Cash Balance', taka(n('cash_balance'))),
          const SizedBox(width: AppSpacing.sm),
          _mini('Due Tax', 'Coming soon', dim: true),
        ]),
      ]),
    );
  }

  Widget _mini(String label, String value,
          {Color? accent, bool dim = false}) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: AppRadius.mdAll,
              border: Border.all(color: Colors.white24)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: const TextStyle(color: Colors.white60, fontSize: 11)),
            const SizedBox(height: 3),
            Text(value,
                style: TextStyle(
                    color: dim
                        ? Colors.white38
                        : (accent ?? Colors.white),
                    fontSize: dim ? 13 : 17,
                    fontWeight: FontWeight.w700)),
          ]),
        ),
      );
}

class _QuickActions extends StatelessWidget {
  final VoidCallback onDone;
  final Map<String, dynamic> dashboard;
  const _QuickActions({required this.onDone, required this.dashboard});

  @override
  Widget build(BuildContext context) {
    Future<void> add(bool expense) async {
      final ok = expense
          ? await showExpenseSheet(context)
          : await showRevenueSheet(context);
      if (ok == true) onDone();
    }

    return Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
      _chip(Icons.remove_circle_outline, 'Add Expense', () => add(true)),
      _chip(Icons.add_circle_outline, 'Add Revenue', () => add(false)),
      _chip(Icons.account_balance, 'Request Loan', () async {
        final ok = await showLoanRequestSheet(context);
        if (ok == true) onDone();
      }),
      _chip(Icons.bar_chart, 'Reports',
          () => context.push('/farmer/cost-management/reports')),
      _chip(Icons.inventory_2_outlined, 'Inventory',
          () => context.push('/farmer/cost-management/inventory')),
    ]);
  }

  Widget _chip(IconData icon, String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: AppRadius.fullAll,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: AppRadius.fullAll,
              border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary)),
          ]),
        ),
      );
}

class _ExpenseGrid extends StatelessWidget {
  final List sections;
  final void Function(String category) onManage;
  final void Function(String category) onAdd;
  const _ExpenseGrid(
      {required this.sections, required this.onManage, required this.onAdd});

  static const _icons = {
    'Feed': Icons.grass_outlined,
    'Medicines': Icons.medical_services_outlined,
    'Labor': Icons.people_outline,
    'Utilities': Icons.bolt_outlined,
    'Chicks': Icons.egg_outlined,
    'Vaccines': Icons.vaccines_outlined,
    'Litter': Icons.layers_outlined,
    'Transport': Icons.local_shipping_outlined,
    'Repairs': Icons.build_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: AppSpacing.sm,
      mainAxisSpacing: AppSpacing.sm,
      childAspectRatio: 0.92,
      children: [
        for (final raw in sections)
          Builder(builder: (context) {
            final s = Map<String, dynamic>.from(raw as Map);
            final cat = s['category'].toString();
            return Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: AppRadius.mdAll,
                border: Border.all(color: const Color(0xFFDEEAE5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(_icons[cat] ?? Icons.category_outlined,
                        size: 18, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(cat,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: Colors.black87)),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text(taka((s['total_spent'] as num?) ?? 0),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppColors.primary)),
                  Text(
                      'Pending ${taka((s['pending_bills'] as num?) ?? 0)}',
                      style: const TextStyle(
                          fontSize: 10, color: Colors.orange)),
                  Text('Paid ${taka((s['paid_bills'] as num?) ?? 0)}',
                      style: const TextStyle(
                          fontSize: 10, color: Colors.black45)),
                  const Spacer(),
                  Row(children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => onManage(cat),
                        child: Container(
                          alignment: Alignment.center,
                          padding:
                              const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                              border: Border.all(
                                  color: AppColors.primary),
                              borderRadius: AppRadius.smAll),
                          child: const Text('Manage',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => onAdd(cat),
                        child: Container(
                          alignment: Alignment.center,
                          padding:
                              const EdgeInsets.symmetric(vertical: 6),
                          decoration: const BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: AppRadius.smAll),
                          child: const Text('Add',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ),
                      ),
                    ),
                  ]),
                ],
              ),
            );
          }),
      ],
    );
  }
}

class _RevenueList extends StatelessWidget {
  final List sections;
  const _RevenueList({required this.sections});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: const Color(0xFFDEEAE5)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < sections.length; i++)
            Builder(builder: (_) {
              final s = Map<String, dynamic>.from(sections[i] as Map);
              return Column(children: [
                ListTile(
                  dense: true,
                  title: Text(s['source'].toString(),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Colors.black87)),
                  subtitle: Text('${s['entries']} entries',
                      style: const TextStyle(fontSize: 11)),
                  trailing: Text(taka((s['total'] as num?) ?? 0),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.secondaryContainer)),
                ),
                if (i < sections.length - 1)
                  const Divider(height: 1, color: Color(0xFFF0F7F4)),
              ]);
            }),
        ],
      ),
    );
  }
}

class _LoansSection extends StatelessWidget {
  final List loans;
  final VoidCallback onDone;
  const _LoansSection({required this.loans, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header('Loans',
            action: TextButton(
              onPressed: () =>
                  context.push('/farmer/cost-management/loans').then((_) => onDone()),
              child: const Text('Manage'),
            )),
        const SizedBox(height: AppSpacing.sm),
        if (loans.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: AppRadius.mdAll,
                border: Border.all(color: const Color(0xFFDEEAE5))),
            child: Row(children: [
              const Expanded(
                  child: Text('No active loans.',
                      style: TextStyle(color: Colors.black54, fontSize: 13))),
              TextButton(
                  onPressed: () async {
                    final ok = await showLoanRequestSheet(context);
                    if (ok == true) onDone();
                  },
                  child: const Text('Get Loan')),
            ]),
          )
        else
          for (final raw in loans)
            Builder(builder: (_) {
              final l = Map<String, dynamic>.from(raw as Map);
              return Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: AppRadius.mdAll,
                    border: Border.all(color: const Color(0xFFDEEAE5))),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(l['lender_name'].toString(),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87)),
                        ),
                        _statusPill(l['status'].toString()),
                      ]),
                      const SizedBox(height: 4),
                      Text('Balance ${taka((l['remaining_balance'] as num?) ?? 0)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: AppColors.primary)),
                      if ((l['next_payment_date'] ?? '')
                          .toString()
                          .isNotEmpty)
                        Text(
                            'Next ${taka((l['next_payment_amount'] as num?) ?? 0)} on ${l['next_payment_date']}',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.black54)),
                      if (((l['overdue_amount'] as num?) ?? 0) > 0)
                        Text('Overdue ${taka((l['overdue_amount'] as num?) ?? 0)}',
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.error,
                                fontWeight: FontWeight.w700)),
                    ]),
              );
            }),
      ],
    );
  }

  Widget _statusPill(String s) {
    final c = switch (s) {
      'active' => AppColors.secondaryContainer,
      'pending' => Colors.orange,
      'overdue' => AppColors.error,
      'rejected' => AppColors.error,
      _ => Colors.black45,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12), borderRadius: AppRadius.smAll),
      child: Text(s.toUpperCase(),
          style: TextStyle(
              fontSize: 9, fontWeight: FontWeight.w800, color: c)),
    );
  }
}

class _Transactions extends StatelessWidget {
  final List rows;
  const _Transactions({required this.rows});
  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('No transactions yet.',
            style: TextStyle(color: Colors.black54)),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: const Color(0xFFDEEAE5)),
      ),
      child: Column(children: [
        for (var i = 0; i < rows.length; i++)
          Builder(builder: (_) {
            final t = Map<String, dynamic>.from(rows[i] as Map);
            final isRevenue = t['kind'] == 'revenue';
            return Column(children: [
              ListTile(
                dense: true,
                leading: Icon(
                    isRevenue
                        ? Icons.south_west
                        : Icons.north_east,
                    size: 18,
                    color: isRevenue
                        ? AppColors.secondaryContainer
                        : AppColors.error),
                title: Text('${t['description']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87)),
                subtitle: Text('${t['section']} • ${t['date']}',
                    style: const TextStyle(fontSize: 11)),
                trailing: Text(
                    '${isRevenue ? '+' : '-'}${taka((t['amount'] as num?) ?? 0)}',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: isRevenue
                            ? AppColors.secondaryContainer
                            : Colors.black87)),
              ),
              if (i < rows.length - 1)
                const Divider(height: 1, color: Color(0xFFF0F7F4)),
            ]);
          }),
      ]),
    );
  }
}
