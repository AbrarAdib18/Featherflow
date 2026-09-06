class PayoutRecord {
  final DateTime date;
  final int trips;
  final double amount;
  final bool isPaid;

  const PayoutRecord({
    required this.date,
    required this.trips,
    required this.amount,
    required this.isPaid,
  });

  factory PayoutRecord.fromJson(Map<String, dynamic> json) => PayoutRecord(
        date: DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now(),
        trips: 1,
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        isPaid: json['is_paid'] == true,
      );
}

class RatingRecord {
  final String farmerName;
  final double stars;
  final String comment;
  final DateTime date;

  const RatingRecord({
    required this.farmerName,
    required this.stars,
    required this.comment,
    required this.date,
  });
}

class DeliveryEarnings {
  final double totalBalance;
  final double todayEarnings;
  final double weekEarnings;
  final double monthEarnings;
  final double totalEarnings;
  final List<PayoutRecord> payoutHistory;
  final double completionRate;
  final double onTimeRate;
  final double cancellationRate;
  final double acceptanceRate;
  final double avgDistanceKm;
  final double avgRating;
  final double bonusAmount;
  final List<RatingRecord> recentRatings;

  const DeliveryEarnings({
    required this.totalBalance,
    required this.todayEarnings,
    required this.weekEarnings,
    required this.monthEarnings,
    required this.totalEarnings,
    required this.payoutHistory,
    required this.completionRate,
    required this.onTimeRate,
    required this.cancellationRate,
    required this.acceptanceRate,
    required this.avgDistanceKm,
    required this.avgRating,
    required this.bonusAmount,
    required this.recentRatings,
  });

  static const empty = DeliveryEarnings(
    totalBalance: 0,
    todayEarnings: 0,
    weekEarnings: 0,
    monthEarnings: 0,
    totalEarnings: 0,
    payoutHistory: [],
    completionRate: 0,
    onTimeRate: 0,
    cancellationRate: 0,
    acceptanceRate: 0,
    avgDistanceKm: 0,
    avgRating: 0,
    bonusAmount: 0,
    recentRatings: [],
  );

  factory DeliveryEarnings.fromJson(Map<String, dynamic> json) {
    final history = json['payout_history'] is List
        ? json['payout_history'] as List
        : const [];
    return DeliveryEarnings(
      totalBalance: (json['pending_payout'] as num?)?.toDouble() ?? 0,
      todayEarnings: (json['today_earnings'] as num?)?.toDouble() ?? 0,
      weekEarnings: (json['week_earnings'] as num?)?.toDouble() ?? 0,
      monthEarnings: (json['month_earnings'] as num?)?.toDouble() ?? 0,
      totalEarnings: (json['total_earnings'] as num?)?.toDouble() ?? 0,
      payoutHistory: history
          .map((e) => PayoutRecord.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      completionRate: (json['completion_rate'] as num?)?.toDouble() ?? 0,
      onTimeRate: (json['on_time_rate'] as num?)?.toDouble() ?? 0,
      cancellationRate: (json['cancellation_rate'] as num?)?.toDouble() ?? 0,
      acceptanceRate: (json['acceptance_rate'] as num?)?.toDouble() ?? 0,
      avgDistanceKm: (json['avg_distance_km'] as num?)?.toDouble() ?? 0,
      avgRating: (json['avg_rating'] as num?)?.toDouble() ?? 0,
      bonusAmount: 0,
      recentRatings: const [],
    );
  }
}
