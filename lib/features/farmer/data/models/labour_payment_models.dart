/// Models for the labour-payment flow (backend `billing` app,
/// `target_type='labour_payment'`) — see PAYMENT_INTEGRATION.md and
/// FEED_AND_DATA_INTEGRITY_AUDIT.md Priority 3.
library;

class LabourPaymentIntent {
  final String id;
  final String status; // created/pending/succeeded/failed/cancelled
  final String workerId;
  final String workerName;
  final String periodStart;
  final String periodEnd;
  final double amount;
  final String currency;
  final String amountDisplay;
  final String? paymentMethod;
  final String mode; // dev | live
  final String? failureReason;

  const LabourPaymentIntent({
    required this.id,
    required this.status,
    required this.workerId,
    required this.workerName,
    required this.periodStart,
    required this.periodEnd,
    required this.amount,
    required this.currency,
    required this.amountDisplay,
    required this.paymentMethod,
    required this.mode,
    required this.failureReason,
  });

  bool get isDevMode => mode == 'dev';
  bool get succeeded => status == 'succeeded';
  bool get failed => status == 'failed';
  bool get cancelled => status == 'cancelled';
  bool get isTerminal =>
      const {'succeeded', 'failed', 'cancelled', 'refunded'}.contains(status);

  LabourPaymentIntent copyWith({String? status, String? paymentMethod, String? failureReason}) =>
      LabourPaymentIntent(
        id: id,
        status: status ?? this.status,
        workerId: workerId,
        workerName: workerName,
        periodStart: periodStart,
        periodEnd: periodEnd,
        amount: amount,
        currency: currency,
        amountDisplay: amountDisplay,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        mode: mode,
        failureReason: failureReason ?? this.failureReason,
      );

  factory LabourPaymentIntent.fromJson(Map<String, dynamic> j) {
    final lp = (j['labour_payment'] as Map?) ?? const {};
    return LabourPaymentIntent(
      id: j['id']?.toString() ?? '',
      status: j['status']?.toString() ?? 'created',
      workerId: lp['worker_id']?.toString() ?? '',
      workerName: lp['worker_name']?.toString() ?? 'Worker',
      periodStart: lp['period_start']?.toString() ?? '',
      periodEnd: lp['period_end']?.toString() ?? '',
      amount: (j['amount'] as num?)?.toDouble() ?? 0,
      currency: j['currency']?.toString() ?? 'BDT',
      amountDisplay: j['amount_display']?.toString() ?? '',
      paymentMethod: j['payment_method']?.toString(),
      mode: j['mode']?.toString() ?? 'dev',
      failureReason: j['failure_reason']?.toString(),
    );
  }
}
