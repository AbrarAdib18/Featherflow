import 'package:flutter/material.dart';
import '../../data/models/delivery_earnings.dart';
import '../../data/services/delivery_session.dart';
import '../delivery_theme.dart';
import '../widgets/earnings_card.dart';

class DeliveryEarningsScreen extends StatefulWidget {
  const DeliveryEarningsScreen({super.key});

  @override
  State<DeliveryEarningsScreen> createState() =>
      _DeliveryEarningsScreenState();
}

class _DeliveryEarningsScreenState extends State<DeliveryEarningsScreen> {
  DeliveryEarnings get _earnings => DeliverySession.instance.earnings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DeliverySession.instance,
      builder: (context, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: DColors.bg,
      appBar: AppBar(
        backgroundColor: DColors.appBar,
        elevation: 0,
        title: const Text(
          'Earnings',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          EarningsCard(
              label: 'Total Balance',
              amount: _earnings.totalBalance,
              isLarge: true),
          const SizedBox(height: 16),
          if (_earnings.bonusAmount > 0) ...[
            _buildBonus(),
            const SizedBox(height: 16),
          ],
          _buildStatsRow(),
          const SizedBox(height: 16),
          _buildPerformanceSummary(),
          const SizedBox(height: 16),
          _buildPayoutHistory(),
          const SizedBox(height: 16),
          _buildPayoutButton(context),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildBonus() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: DColors.accentLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DColors.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: DColors.accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.emoji_events_outlined,
                color: Color(0xFFFFB300), size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Weekly Bonus',
                  style: TextStyle(
                      color: DColors.textSecondary, fontSize: 12)),
              Text(
                '৳${_earnings.bonusAmount.toStringAsFixed(0)}',
                style: const TextStyle(
                    color: DColors.accent,
                    fontSize: 18,
                    fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: DColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: DColors.accent.withValues(alpha: 0.3)),
            ),
            child: const Text('Earned',
                style: TextStyle(
                    color: DColors.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Earnings Summary',
            style: TextStyle(
                color: DColors.primary,
                fontSize: 15,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: EarningsCard(
                  label: 'Today',
                  amount: _earnings.todayEarnings),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: EarningsCard(
                  label: 'This Week',
                  amount: _earnings.weekEarnings),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: EarningsCard(
                  label: 'This Month',
                  amount: _earnings.monthEarnings),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: EarningsCard(
                  label: 'All Time',
                  amount: _earnings.totalEarnings),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPerformanceSummary() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Performance',
            style: TextStyle(
                color: DColors.primary,
                fontSize: 15,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: dCard(),
          child: Column(
            children: [
              _perfRow(
                  'Completion Rate',
                  '${_earnings.completionRate.toStringAsFixed(1)}%',
                  _earnings.completionRate / 100,
                  DColors.accent),
              const SizedBox(height: 12),
              _perfRow(
                  'On-Time Rate',
                  '${_earnings.onTimeRate.toStringAsFixed(1)}%',
                  _earnings.onTimeRate / 100,
                  DColors.accentMid),
              const SizedBox(height: 12),
              _perfRow(
                  'Cancellation Rate',
                  '${_earnings.cancellationRate.toStringAsFixed(1)}%',
                  _earnings.cancellationRate / 100,
                  DColors.red),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Avg Rating',
                      style: TextStyle(
                          color: DColors.textSecondary, fontSize: 12)),
                  const Spacer(),
                  Row(
                    children: List.generate(
                      5,
                      (i) => Icon(
                        i < _earnings.avgRating.floor()
                            ? Icons.star
                            : Icons.star_outline,
                        color: const Color(0xFFFFB300),
                        size: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(_earnings.avgRating.toStringAsFixed(1),
                      style: const TextStyle(
                          color: DColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _perfRow(
      String label, String value, double progress, Color color) {
    return Column(
      children: [
        Row(
          children: [
            Text(label,
                style: const TextStyle(
                    color: DColors.textSecondary, fontSize: 12)),
            const Spacer(),
            Text(value,
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            backgroundColor: DColors.surface2,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 5,
          ),
        ),
      ],
    );
  }

  Widget _buildPayoutHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Payout History',
            style: TextStyle(
                color: DColors.primary,
                fontSize: 15,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        if (_earnings.payoutHistory.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: dCard(),
            child: const Center(
              child: Text('No completed deliveries yet',
                  style: TextStyle(color: DColors.textSecondary, fontSize: 13)),
            ),
          )
        else
          ..._earnings.payoutHistory.map(_payoutRow),
      ],
    );
  }

  Widget _payoutRow(PayoutRecord p) {
    const months = [
      '',
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final dateStr =
        '${p.date.day} ${months[p.date.month]} ${p.date.year}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: dCard(),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: DColors.accentLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.account_balance_wallet_outlined,
                color: DColors.accent, size: 18),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(dateStr,
                  style: const TextStyle(
                      color: DColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              Text('${p.trips} trips',
                  style: const TextStyle(
                      color: DColors.textSecondary, fontSize: 11)),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('৳${p.amount.toStringAsFixed(0)}',
                  style: const TextStyle(
                      color: DColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: p.isPaid ? DColors.accentLight : DColors.orangeLight,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: p.isPaid
                        ? DColors.accent.withValues(alpha: 0.4)
                        : DColors.orange.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  p.isPaid ? 'Paid' : 'Pending',
                  style: TextStyle(
                    color: p.isPaid ? DColors.accent : DColors.orange,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPayoutButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => _showPayoutSheet(context),
        icon: const Icon(Icons.send, size: 18),
        label: const Text('Request Payout',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        style: ElevatedButton.styleFrom(
          backgroundColor: DColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  void _showPayoutSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: DColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: DColors.greyDark,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Request Payout',
                style: TextStyle(
                    color: DColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'Available: ৳${_earnings.totalBalance.toStringAsFixed(2)}',
              style: const TextStyle(
                  color: DColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            _payoutOption(context,
                logo: '৳',
                name: 'bKash',
                subtitle: 'Send to bKash number',
                color: const Color(0xFFE2136E)),
            const SizedBox(height: 10),
            _payoutOption(context,
                logo: 'N',
                name: 'Nagad',
                subtitle: 'Send to Nagad number',
                color: const Color(0xFFF7941D)),
          ],
        ),
      ),
    );
  }

  Widget _payoutOption(
    BuildContext context, {
    required String logo,
    required String name,
    required String subtitle,
    required Color color,
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$name payout requested (mock)'),
            backgroundColor: DColors.secondary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: dCard(),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                    color: color.withValues(alpha: 0.3)),
              ),
              child: Center(
                child: Text(logo,
                    style: TextStyle(
                        color: color,
                        fontSize: 18,
                        fontWeight: FontWeight.w900)),
              ),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        color: DColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style: const TextStyle(
                        color: DColors.textSecondary, fontSize: 11)),
              ],
            ),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios,
                color: DColors.grey, size: 14),
          ],
        ),
      ),
    );
  }
}
