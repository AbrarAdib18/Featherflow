import 'package:flutter/material.dart';
import '../../data/models/delivery_earnings.dart';
import '../delivery_theme.dart';

class DeliveryPerformanceScreen extends StatelessWidget {
  const DeliveryPerformanceScreen({super.key});

  // TODO: replace with API call
  static const _mockScore = 87.0;
  static final _mockEarnings = DeliveryEarnings(
    totalBalance: 3240.0,
    todayEarnings: 450.0,
    weekEarnings: 2100.0,
    monthEarnings: 8400.0,
    totalEarnings: 42000.0,
    payoutHistory: const [],
    completionRate: 94.2,
    onTimeRate: 89.5,
    cancellationRate: 3.1,
    avgRating: 4.8,
    bonusAmount: 300.0,
    recentRatings: [
      RatingRecord(
        farmerName: 'Rahman Poultry Farm',
        stars: 5.0,
        comment: 'Very punctual and professional delivery.',
        date: DateTime(2024, 5, 22),
      ),
      RatingRecord(
        farmerName: 'Karim Farm',
        stars: 4.0,
        comment: 'Good service, slightly late.',
        date: DateTime(2024, 5, 21),
      ),
      RatingRecord(
        farmerName: 'Hasan Agro',
        stars: 5.0,
        comment: 'Handled medicine package carefully.',
        date: DateTime(2024, 5, 20),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
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
          _buildScoreCard(),
          const SizedBox(height: 14),
          _buildStatsGrid(),
          const SizedBox(height: 14),
          _buildRatingsSection(),
          const SizedBox(height: 14),
          _buildTipsSection(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildScoreCard() {
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
              const Text('Performance Score',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _mockScore.toStringAsFixed(0),
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
                        style: TextStyle(
                            color: Colors.white60, fontSize: 18)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('Good Standing',
                    style: TextStyle(
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
                  value: _mockScore / 100,
                  strokeWidth: 7,
                  backgroundColor:
                      Colors.white.withValues(alpha: 0.2),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.white),
                ),
                const Icon(Icons.star, color: Colors.white, size: 30),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Performance Metrics',
            style: TextStyle(
                color: DColors.primary,
                fontSize: 15,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _metricCard(
                label: 'Completion Rate',
                value:
                    '${_mockEarnings.completionRate.toStringAsFixed(1)}%',
                icon: Icons.check_circle_outline,
                color: DColors.accent,
                bgColor: DColors.accentLight,
                isGood: _mockEarnings.completionRate >= 90,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _metricCard(
                label: 'On-Time Rate',
                value:
                    '${_mockEarnings.onTimeRate.toStringAsFixed(1)}%',
                icon: Icons.timer_outlined,
                color: DColors.accentMid,
                bgColor: DColors.accentLight,
                isGood: _mockEarnings.onTimeRate >= 85,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _metricCard(
                label: 'Cancellation',
                value:
                    '${_mockEarnings.cancellationRate.toStringAsFixed(1)}%',
                icon: Icons.cancel_outlined,
                color: DColors.red,
                bgColor: DColors.redLight,
                isGood: _mockEarnings.cancellationRate <= 5,
                invertGood: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _metricCard(
                label: 'Avg Rating',
                value: _mockEarnings.avgRating.toStringAsFixed(1),
                icon: Icons.star_outline,
                color: const Color(0xFFFFB300),
                bgColor: const Color(0xFFFFF8E1),
                isGood: _mockEarnings.avgRating >= 4.5,
                suffix: '/ 5',
              ),
            ),
          ],
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
                      color: color,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
              if (suffix.isNotEmpty)
                Padding(
                  padding:
                      const EdgeInsets.only(bottom: 2, left: 3),
                  child: Text(suffix,
                      style: const TextStyle(
                          color: DColors.grey, fontSize: 11)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                  color: DColors.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildRatingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Recent Ratings',
                style: TextStyle(
                    color: DColors.primary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            Row(
              children: [
                const Icon(Icons.star,
                    color: Color(0xFFFFB300), size: 14),
                const SizedBox(width: 4),
                Text(
                  _mockEarnings.avgRating.toStringAsFixed(1),
                  style: const TextStyle(
                      color: DColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        ..._mockEarnings.recentRatings.map(_ratingItem),
      ],
    );
  }

  Widget _ratingItem(RatingRecord r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: dCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: DColors.accentLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person,
                    color: DColors.accent, size: 16),
              ),
              const SizedBox(width: 10),
              Text(r.farmerName,
                  style: const TextStyle(
                      color: DColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < r.stars ? Icons.star : Icons.star_outline,
                    color: const Color(0xFFFFB300),
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
          if (r.comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(r.comment,
                style: const TextStyle(
                    color: DColors.textSecondary,
                    fontSize: 12,
                    height: 1.4)),
          ],
        ],
      ),
    );
  }

  Widget _buildTipsSection() {
    const tips = [
      (Icons.access_time, 'Pick up orders within 5 min of acceptance'),
      (Icons.navigation, 'Use navigation for faster routes'),
      (Icons.phone_in_talk,
          'Call customer before arrival to confirm'),
      (Icons.thumb_up_outlined,
          'Greet customers professionally for better ratings'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Improve Your Score',
            style: TextStyle(
                color: DColors.primary,
                fontSize: 15,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: dCard(),
          child: Column(
            children: tips
                .map((t) => Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: DColors.accentLight,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(t.$1,
                                color: DColors.accent, size: 15),
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
