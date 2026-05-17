import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:featherflow/core/theme/theme.dart';

class CostManagementScreen extends StatefulWidget {
  const CostManagementScreen({super.key});

  @override
  State<CostManagementScreen> createState() => _CostManagementScreenState();
}

class _CostManagementScreenState extends State<CostManagementScreen> {
  int _selectedFilter = 0;

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
        title: const Text(
          'Featherflow Cost Management',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.home, color: Colors.white),
            onPressed: () => context.go('/farmer'),
            tooltip: 'Home',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TopSection(
              selectedFilter: _selectedFilter,
              onFilterChanged: (i) => setState(() => _selectedFilter = i),
            ),
            const _ExpenseSection(),
            const _IncomeLoansSection(),
            const _RecentTransactions(),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _TopSection extends StatelessWidget {
  final int selectedFilter;
  final ValueChanged<int> onFilterChanged;

  const _TopSection({required this.selectedFilter, required this.onFilterChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primary,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FilterTabs(selected: selectedFilter, onChanged: onFilterChanged),
          const SizedBox(height: AppSpacing.lg),
          const Text(
            'Total Revenue',
            style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            '৳ 12,450,000',
            style: TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _SummaryGrid(),
        ],
      ),
    );
  }
}

class _FilterTabs extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;

  const _FilterTabs({required this.selected, required this.onChanged});

  static const _tabs = ['Monthly', 'Yearly', 'Lifetime'];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: AppRadius.smAll,
      ),
      padding: const EdgeInsets.all(AppSpacing.xxs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(_tabs.length, (i) {
          final active = i == selected;
          return GestureDetector(
            onTap: () => onChanged(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: active ? AppColors.secondary : Colors.transparent,
                borderRadius: AppRadius.smAll,
              ),
              child: Text(
                _tabs[i],
                style: TextStyle(
                  color: active ? Colors.black : Colors.white70,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                  fontSize: 13,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                label: 'Total Earning',
                amount: '৳13.8M',
                badge: '↑18%',
                badgeColor: AppColors.secondary,
              ),
            ),
            SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _SummaryCard(
                label: 'Total Expense',
                amount: '৳8.6M',
                badge: '↑6%',
                badgeColor: AppColors.error,
              ),
            ),
          ],
        ),
        SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                label: 'Due Tax',
                amount: '৳420K',
                badge: '● live',
                badgeColor: AppColors.error,
              ),
            ),
            SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _SummaryCard(
                label: 'Current Loan',
                amount: '৳1.2M',
                badge: null,
                badgeColor: null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String amount;
  final String? badge;
  final Color? badgeColor;

  const _SummaryCard({
    required this.label,
    required this.amount,
    required this.badge,
    required this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            amount,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
          ),
          if (badge != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: badgeColor!.withValues(alpha: 0.2),
                borderRadius: AppRadius.smAll,
              ),
              child: Text(
                badge!,
                style: TextStyle(color: badgeColor, fontSize: 10, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExpenseSection extends StatelessWidget {
  const _ExpenseSection();

  static const _items = [
    _ExpenseItem(icon: Icons.grass_outlined, name: 'Feed', amount: '৳3.2M'),
    _ExpenseItem(icon: Icons.medical_services_outlined, name: 'Medicines', amount: '৳1.1M'),
    _ExpenseItem(icon: Icons.people_outline, name: 'Labor', amount: '৳2.0M'),
    _ExpenseItem(icon: Icons.bolt_outlined, name: 'Utilities', amount: '৳900K'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Running Expense Sections',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: AppSpacing.sm,
            mainAxisSpacing: AppSpacing.sm,
            childAspectRatio: 0.88,
            children: _items.map((item) => _ExpenseCard(item: item)).toList(),
          ),
        ],
      ),
    );
  }
}

class _ExpenseItem {
  final IconData icon;
  final String name;
  final String amount;

  const _ExpenseItem({required this.icon, required this.name, required this.amount});
}

class _ExpenseCard extends StatelessWidget {
  final _ExpenseItem item;

  const _ExpenseCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: const Color(0xFFDEEAE5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: AppRadius.smAll,
                ),
                child: Icon(item.icon, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  item.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            item.amount,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: AppColors.primary,
            ),
          ),
          const Text(
            'Lifetime',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
                    minimumSize: const Size(0, 30),
                    textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Manage'),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
                    minimumSize: const Size(0, 30),
                    textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Payment'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IncomeLoansSection extends StatelessWidget {
  const _IncomeLoansSection();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(color: Color(0xFFDEEAE5)),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Income, Loans & Tax',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _ActionCard(
            icon: Icons.account_balance_wallet_outlined,
            iconColor: AppColors.primary,
            title: 'Total Revenue',
            subtitle: '৳12,450,000',
            subtitleColor: AppColors.primary,
            subtitleSize: 16,
            actions: [_FilledBtn(label: 'Cashout', onTap: () {})],
          ),
          const SizedBox(height: AppSpacing.sm),
          _ActionCard(
            icon: Icons.savings_outlined,
            iconColor: AppColors.primary,
            title: 'Current Loan',
            subtitle: '৳1.2M',
            subtitleColor: Colors.black87,
            subtitleSize: 18,
            actions: [
              _OutlineBtn(label: 'Get Loan', onTap: () {}),
              const SizedBox(width: AppSpacing.sm),
              _FilledBtn(label: 'Repay', onTap: () {}),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const _TaxCard(),
          const SizedBox(height: AppSpacing.sm),
          _ActionCard(
            icon: Icons.bar_chart_outlined,
            iconColor: AppColors.primary,
            title: 'Reports',
            subtitle: 'Financial summary & insights',
            subtitleColor: Colors.grey,
            subtitleSize: 13,
            actions: [
              _OutlineBtn(label: 'View Reports', onTap: () {}),
              const SizedBox(width: AppSpacing.sm),
              _FilledBtn(label: 'Download', onTap: () {}),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Color subtitleColor;
  final double subtitleSize;
  final List<Widget> actions;

  const _ActionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.subtitleColor,
    required this.subtitleSize,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: const Color(0xFFDEEAE5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: AppRadius.smAll,
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: subtitleSize,
                    color: subtitleColor,
                  ),
                ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class _TaxCard extends StatelessWidget {
  const _TaxCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: const Color(0xFFDEEAE5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: AppRadius.smAll,
                ),
                child: const Icon(Icons.receipt_long_outlined, color: AppColors.error, size: 22),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Text(
                'Tax Calculator',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black87),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            '৳420K',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: AppColors.error),
          ),
          const Text(
            'Due Tax',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(child: _OutlineBtn(label: 'Calculate My Tax', onTap: () {})),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Pay Tax'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilledBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _FilledBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}

class _OutlineBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _OutlineBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}

class _RecentTransactions extends StatelessWidget {
  const _RecentTransactions();

  static const _transactions = [
    _TxData(
      date: '12 May 2026',
      section: 'Feed',
      description: 'Feed stock payment',
      status: 'Paid',
      amount: '৳85,000',
      statusType: _TxStatus.paid,
    ),
    _TxData(
      date: '11 May 2026',
      section: 'Medicines',
      description: 'Emergency treatment',
      status: 'Pending',
      amount: '৳24,500',
      statusType: _TxStatus.pending,
    ),
    _TxData(
      date: '10 May 2026',
      section: 'Loan',
      description: 'Weekly installment',
      status: 'Due',
      amount: '৳30,000',
      statusType: _TxStatus.due,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent Transactions',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: AppRadius.lgAll,
              border: Border.all(color: const Color(0xFFDEEAE5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                const _TxHeader(),
                const Divider(height: 1, color: Color(0xFFDEEAE5)),
                ...List.generate(_transactions.length, (i) => Column(
                  children: [
                    _TxRow(data: _transactions[i]),
                    if (i < _transactions.length - 1)
                      const Divider(height: 1, color: Color(0xFFDEEAE5)),
                  ],
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _TxStatus { paid, pending, due }

class _TxData {
  final String date;
  final String section;
  final String description;
  final String status;
  final String amount;
  final _TxStatus statusType;

  const _TxData({
    required this.date,
    required this.section,
    required this.description,
    required this.status,
    required this.amount,
    required this.statusType,
  });
}

class _TxHeader extends StatelessWidget {
  const _TxHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: const BoxDecoration(
        color: Color(0xFFF0F7F4),
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      child: const Row(
        children: [
          Expanded(flex: 2, child: _TxHeaderCell('Date')),
          Expanded(flex: 2, child: _TxHeaderCell('Section')),
          Expanded(flex: 3, child: _TxHeaderCell('Description')),
          Expanded(flex: 2, child: _TxHeaderCell('Status')),
          Expanded(flex: 2, child: _TxHeaderCell('Amount')),
        ],
      ),
    );
  }
}

class _TxHeaderCell extends StatelessWidget {
  final String text;

  const _TxHeaderCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.primary,
      ),
    );
  }
}

class _TxRow extends StatelessWidget {
  final _TxData data;

  const _TxRow({required this.data});

  Color get _statusColor {
    switch (data.statusType) {
      case _TxStatus.paid:
        return AppColors.secondary;
      case _TxStatus.pending:
        return Colors.orange;
      case _TxStatus.due:
        return AppColors.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              data.date,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              data.section,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              data.description,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: AppRadius.smAll,
              ),
              child: Text(
                data.status,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              data.amount,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
