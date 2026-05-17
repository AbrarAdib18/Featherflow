import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:featherflow/core/theme/theme.dart';

class FeedManagementScreen extends StatelessWidget {
  const FeedManagementScreen({super.key});

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
          'Feed Management',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.home, color: Colors.white),
            onPressed: () => context.go('/farmer'),
            tooltip: 'Home',
          ),
        ],
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SummaryRow(),
            SizedBox(height: AppSpacing.md),
            _StockSection(),
            SizedBox(height: AppSpacing.md),
            _AddFeedButton(),
            SizedBox(height: AppSpacing.md),
            _FeedScheduleSection(),
            SizedBox(height: AppSpacing.md),
            _SupplierSection(),
            SizedBox(height: AppSpacing.md),
            _FeedHistorySection(),
            SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow();

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: AppSpacing.sm,
      mainAxisSpacing: AppSpacing.sm,
      childAspectRatio: 1.7,
      children: const [
        _SummaryCard(
          icon: Icons.inventory_2_outlined,
          label: 'Total Feed Stock',
          value: '2,450 kg',
          valueColor: Colors.black87,
        ),
        _SummaryCard(
          icon: Icons.local_dining_outlined,
          label: 'Daily Consumption',
          value: '180 kg',
          valueColor: Colors.black87,
        ),
        _SummaryCard(
          icon: Icons.hourglass_bottom_outlined,
          label: 'Days Remaining',
          value: '13 days',
          valueColor: Colors.orange,
          badge: 'Low Stock',
          badgeColor: Colors.orange,
        ),
        _SummaryCard(
          icon: Icons.payments_outlined,
          label: 'Monthly Cost',
          value: '৳3.2M',
          valueColor: AppColors.primary,
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color valueColor;
  final String? badge;
  final Color? badgeColor;

  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.valueColor,
    this.badge,
    this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: AppColors.primary, size: 18),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeColor!.withValues(alpha: 0.12),
                    borderRadius: AppRadius.smAll,
                  ),
                  child: Text(
                    badge!,
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: badgeColor),
                  ),
                ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: valueColor),
              ),
              Text(
                label,
                style: const TextStyle(fontSize: 10, color: Colors.black54),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StockSection extends StatelessWidget {
  const _StockSection();

  static const _rows = [
    _StockRow(type: 'Starter Feed', qty: '800 kg', unitCost: '৳45/kg', total: '৳36,000', status: 'Good', isLow: false),
    _StockRow(type: 'Grower Feed', qty: '1,200 kg', unitCost: '৳42/kg', total: '৳50,400', status: 'Good', isLow: false),
    _StockRow(type: 'Finisher Feed', qty: '450 kg', unitCost: '৳40/kg', total: '৳18,000', status: 'Low', isLow: true),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Current Stock',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black87),
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
              const _StockTableHeader(),
              const Divider(height: 1, color: Color(0xFFDEEAE5)),
              ...List.generate(
                _rows.length,
                (i) => Column(
                  children: [
                    _rows[i],
                    if (i < _rows.length - 1) const Divider(height: 1, color: Color(0xFFDEEAE5)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StockTableHeader extends StatelessWidget {
  const _StockTableHeader();

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
          Expanded(flex: 3, child: _HCell('Feed Type')),
          Expanded(flex: 2, child: _HCell('Qty')),
          Expanded(flex: 2, child: _HCell('Unit Cost')),
          Expanded(flex: 2, child: _HCell('Total')),
          Expanded(flex: 2, child: _HCell('Status')),
        ],
      ),
    );
  }
}

class _HCell extends StatelessWidget {
  final String text;

  const _HCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary),
    );
  }
}

class _StockRow extends StatelessWidget {
  final String type;
  final String qty;
  final String unitCost;
  final String total;
  final String status;
  final bool isLow;

  const _StockRow({
    required this.type,
    required this.qty,
    required this.unitCost,
    required this.total,
    required this.status,
    required this.isLow,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = isLow ? AppColors.error : AppColors.secondary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              type,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(qty, style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ),
          Expanded(
            flex: 2,
            child: Text(unitCost, style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ),
          Expanded(
            flex: 2,
            child: Text(
              total,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87),
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
                status,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddFeedButton extends StatelessWidget {
  const _AddFeedButton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {},
        icon: const Icon(Icons.add, size: 20),
        label: const Text('Add Feed Purchase'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.secondary,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _FeedScheduleSection extends StatelessWidget {
  const _FeedScheduleSection();

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
          const Row(
            children: [
              Icon(Icons.schedule_outlined, color: AppColors.primary, size: 20),
              SizedBox(width: AppSpacing.sm),
              Text(
                'Feed Schedule',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.black87),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const _ScheduleItem(
            icon: Icons.wb_sunny_outlined,
            iconColor: Colors.orange,
            time: '6:00 AM',
            label: 'Morning Feeding',
            qty: '90 kg',
          ),
          const SizedBox(height: AppSpacing.sm),
          const Divider(color: Color(0xFFDEEAE5)),
          const SizedBox(height: AppSpacing.sm),
          const _ScheduleItem(
            icon: Icons.nights_stay_outlined,
            iconColor: AppColors.primary,
            time: '5:00 PM',
            label: 'Evening Feeding',
            qty: '90 kg',
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Edit Schedule'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String time;
  final String label;
  final String qty;

  const _ScheduleItem({
    required this.icon,
    required this.iconColor,
    required this.time,
    required this.label,
    required this.qty,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: AppRadius.smAll,
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black87),
              ),
              Text(
                time,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: AppRadius.smAll,
          ),
          child: Text(
            qty,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary),
          ),
        ),
      ],
    );
  }
}

class _SupplierSection extends StatelessWidget {
  const _SupplierSection();

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
          const Row(
            children: [
              Icon(Icons.storefront_outlined, color: AppColors.primary, size: 20),
              SizedBox(width: AppSpacing.sm),
              Text(
                'Supplier',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.black87),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const _SupplierInfoRow(icon: Icons.business_outlined, label: 'AgriFeeds Bangladesh Ltd.'),
          const SizedBox(height: AppSpacing.xs),
          const _SupplierInfoRow(icon: Icons.phone_outlined, label: '+880 1711-234567'),
          const SizedBox(height: AppSpacing.xs),
          const _SupplierInfoRow(icon: Icons.local_shipping_outlined, label: 'Last delivery: 5 May 2026'),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.shopping_cart_outlined, size: 16),
              label: const Text('Order Now'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SupplierInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SupplierInfoRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppColors.primary),
        const SizedBox(width: AppSpacing.sm),
        Text(label, style: const TextStyle(fontSize: 13, color: Colors.black87)),
      ],
    );
  }
}

class _FeedHistorySection extends StatelessWidget {
  const _FeedHistorySection();

  static const _history = [
    _HistoryData(date: '05 May 2026', type: 'Grower Feed', qty: '500 kg', cost: '৳21,000', supplier: 'AgriFeeds BD'),
    _HistoryData(date: '22 Apr 2026', type: 'Starter Feed', qty: '300 kg', cost: '৳13,500', supplier: 'AgriFeeds BD'),
    _HistoryData(date: '10 Apr 2026', type: 'Finisher Feed', qty: '200 kg', cost: '৳8,000', supplier: 'FeedMart Ltd.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Feed History',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black87),
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
              const _HistoryTableHeader(),
              const Divider(height: 1, color: Color(0xFFDEEAE5)),
              ...List.generate(
                _history.length,
                (i) => Column(
                  children: [
                    _HistoryRow(data: _history[i]),
                    if (i < _history.length - 1) const Divider(height: 1, color: Color(0xFFDEEAE5)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HistoryData {
  final String date;
  final String type;
  final String qty;
  final String cost;
  final String supplier;

  const _HistoryData({
    required this.date,
    required this.type,
    required this.qty,
    required this.cost,
    required this.supplier,
  });
}

class _HistoryTableHeader extends StatelessWidget {
  const _HistoryTableHeader();

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
          Expanded(flex: 2, child: _HCell('Date')),
          Expanded(flex: 3, child: _HCell('Type')),
          Expanded(flex: 2, child: _HCell('Qty')),
          Expanded(flex: 2, child: _HCell('Cost')),
          Expanded(flex: 3, child: _HCell('Supplier')),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final _HistoryData data;

  const _HistoryRow({required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(data.date, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ),
          Expanded(
            flex: 3,
            child: Text(
              data.type,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(data.qty, style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ),
          Expanded(
            flex: 2,
            child: Text(
              data.cost,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(data.supplier, style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ),
        ],
      ),
    );
  }
}
