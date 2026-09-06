import 'package:flutter/material.dart';
import '../../data/models/delivery_earnings.dart';
import '../../data/services/delivery_session.dart';
import '../delivery_theme.dart';

class DeliveryPerformanceScreen extends StatelessWidget {
  const DeliveryPerformanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DeliverySession.instance,
      builder: (context, _) {
        final earnings = DeliverySession.instance.earnings;
        return Scaffold(
          backgroundColor: DColors.bg,
          appBar: AppBar(
            backgroundColor: DColors.appBar,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              'Performance',
              style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildScoreCard(earnings),
              const SizedBox(height: 14),
              _buildStatsGrid(earnings),
              const SizedBox(height: 14),
              _buildTipsSection(),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _buildScoreCard(DeliveryEarnings earnings) {
    final score = earnings.completionRate;
    final standing = score >= 90
        ? 'Good Standing'
        : score >= 70
            ? 'Fair Standing'
            : 'Needs Improvement';
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [DColors.primary, DColors.secondaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: DColors.primary.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Completion Score',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    score.toStringAsFixed(0),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 56,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8, left: 4),
                    child: Text('/100',
                        style: TextStyle(color: Colors.white60, fontSize: 18)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(standing,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const Spacer(),
          SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: score / 100,
                  strokeWidth: 7,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
                const Icon(Icons.star, color: Colors.white, size: 30),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(DeliveryEarnings earnings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Performance Metrics',
            style: TextStyle(
                color: DColors.primary, fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _metricCard(
                label: 'Completion Rate',
                value: '${earnings.completionRate.toStringAsFixed(1)}%',
                icon: Icons.check_circle_outline,
                color: DColors.accent,
                bgColor: DColors.accentLight,
                isGood: earnings.completionRate >= 90,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _metricCard(
                label: 'Cancellation Rate',
                value: '${earnings.cancellationRate.toStringAsFixed(1)}%',
                icon: Icons.cancel_outlined,
                color: DColors.red,
                bgColor: DColors.redLight,
                isGood: earnings.cancellationRate <= 5,
                invertGood: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _metricCard(
                label: 'Avg Rating',
                value:
                    earnings.avgRating > 0 ? earnings.avgRating.toStringAsFixed(1) : '—',
                icon: Icons.star_outline,
                color: const Color(0xFFFFB300),
                bgColor: const Color(0xFFFFF8E1),
                isGood: earnings.avgRating >= 4.5,
                suffix: earnings.avgRating > 0 ? '/ 5' : '',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _metricCard(
                label: 'Pending Payout',
                value: '৳${earnings.totalBalance.toStringAsFixed(0)}',
                icon: Icons.account_balance_wallet_outlined,
                color: DColors.accentMid,
                bgColor: DColors.accentLight,
                isGood: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _metricCard(
                label: 'Acceptance Rate',
                value: '${earnings.acceptanceRate.toStringAsFixed(1)}%',
                icon: Icons.thumb_up_alt_outlined,
                color: DColors.primary,
                bgColor: DColors.accentLight,
                isGood: earnings.acceptanceRate >= 80,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _metricCard(
                label: 'On-Time Rate',
                value: '${earnings.onTimeRate.toStringAsFixed(1)}%',
                icon: Icons.schedule,
                color: DColors.accentMid,
                bgColor: DColors.accentLight,
                isGood: earnings.onTimeRate >= 80,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _metricCard(
          label: 'Avg Distance per Delivery',
          value:
              earnings.avgDistanceKm > 0 ? '${earnings.avgDistanceKm.toStringAsFixed(1)} km' : '—',
          icon: Icons.straighten,
          color: DColors.grey,
          bgColor: DColors.surface2,
          isGood: true,
        ),
      ],
    );
  }

  Widget _metricCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required Color bgColor,
    required bool isGood,
    bool invertGood = false,
    String suffix = '',
  }) {
    final good = invertGood ? !isGood : isGood;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: dCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const Spacer(),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: good ? DColors.accentMid : DColors.orange,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value,
                  style: TextStyle(
                      color: color, fontSize: 22, fontWeight: FontWeight.w800)),
              if (suffix.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2, left: 3),
                  child: Text(suffix,
                      style: const TextStyle(color: DColors.grey, fontSize: 11)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(color: DColors.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildTipsSection() {
    const tips = [
      (Icons.access_time, 'Pick up orders within 5 min of acceptance'),
      (Icons.navigation, 'Use navigation for faster routes'),
      (Icons.phone_in_talk, 'Call customer before arrival to confirm'),
      (Icons.thumb_up_outlined, 'Greet customers professionally for better ratings'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Improve Your Score',
            style: TextStyle(
                color: DColors.primary, fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: dCard(),
          child: Column(
            children: tips
                .map((t) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: const BoxDecoration(
                              color: DColors.accentLight,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(t.$1, color: DColors.accent, size: 15),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(t.$2,
                                style: const TextStyle(
                                    color: DColors.textSecondary,
                                    fontSize: 12,
                                    height: 1.4)),
                          ),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }
}
