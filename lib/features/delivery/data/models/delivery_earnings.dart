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
    required this.avgRating,
    required this.bonusAmount,
    required this.recentRatings,
  });
}
