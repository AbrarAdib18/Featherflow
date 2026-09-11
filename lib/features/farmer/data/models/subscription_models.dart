/// Models for the subscription checkout flow (backend `billing` app).
library;

class SubPlan {
  final int id;
  final String code;
  final String name;
  final String interval; // month / year / one_time
  final String tagline;
  final double price;
  final String currency;
  final String priceDisplay;
  final int? diseaseScanLimit;
  final List<String> features;
  final bool recommended;
  final bool isActive;

  const SubPlan({
    required this.id,
    required this.code,
    required this.name,
    required this.interval,
    required this.tagline,
    required this.price,
    required this.currency,
    required this.priceDisplay,
    required this.diseaseScanLimit,
    required this.features,
    required this.recommended,
    required this.isActive,
  });

  factory SubPlan.fromJson(Map<String, dynamic> j) => SubPlan(
        id: (j['id'] as num?)?.toInt() ?? 0,
        code: j['code']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        interval: j['interval']?.toString() ?? 'month',
        tagline: j['tagline']?.toString() ?? '',
        price: (j['price'] as num?)?.toDouble() ?? 0,
        currency: j['currency']?.toString() ?? 'BDT',
        priceDisplay: j['price_display']?.toString() ?? '',
        diseaseScanLimit: (j['disease_scan_limit'] as num?)?.toInt(),
        features: ((j['features'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        recommended: j['recommended'] == true,
        isActive: j['is_active'] != false,
      );

  String get intervalLabel => switch (interval) {
        'year' => 'per year',
        'one_time' => 'one-time',
        _ => 'per month',
      };
}

class CurrentSubscription {
  final String id;
  final SubPlan plan;
  final String status;
  final DateTime? startedAt;
  final DateTime? expiresAt;
  final bool autoRenew;

  const CurrentSubscription({
    required this.id,
    required this.plan,
    required this.status,
    required this.startedAt,
    required this.expiresAt,
    required this.autoRenew,
  });

  factory CurrentSubscription.fromJson(Map<String, dynamic> j) =>
      CurrentSubscription(
        id: j['id']?.toString() ?? '',
        plan: SubPlan.fromJson(Map<String, dynamic>.from(j['plan'] as Map)),
        status: j['status']?.toString() ?? '',
        startedAt: DateTime.tryParse(j['started_at']?.toString() ?? ''),
        expiresAt: DateTime.tryParse(j['expires_at']?.toString() ?? ''),
        autoRenew: j['auto_renew'] == true,
      );
}

class PlansResponse {
  final String mode; // 'dev' | 'live'
  final SubPlan? freePlan;
  final List<SubPlan> plans;
  final CurrentSubscription? current;

  const PlansResponse({
    required this.mode,
    required this.freePlan,
    required this.plans,
    required this.current,
  });

  bool get isDevMode => mode == 'dev';

  factory PlansResponse.fromJson(Map<String, dynamic> j) => PlansResponse(
        mode: j['mode']?.toString() ?? 'dev',
        freePlan: j['free_plan'] is Map
            ? SubPlan.fromJson(Map<String, dynamic>.from(j['free_plan'] as Map))
            : null,
        plans: ((j['plans'] as List?) ?? const [])
            .map((e) => SubPlan.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        current: j['current'] is Map
            ? CurrentSubscription.fromJson(
                Map<String, dynamic>.from(j['current'] as Map))
            : null,
      );
}

class PaymentIntent {
  final String id;
  final String status; // created/pending/succeeded/failed/cancelled/refunded
  final String planName;
  final String planCode;
  final String interval;
  final double amount;
  final String currency;
  final String amountDisplay;
  final String? paymentMethod;
  final String provider;
  final String mode;
  final String? failureReason;
  final String? subscriptionId;
  final String? next;

  const PaymentIntent({
    required this.id,
    required this.status,
    required this.planName,
    required this.planCode,
    required this.interval,
    required this.amount,
    required this.currency,
    required this.amountDisplay,
    required this.paymentMethod,
    required this.provider,
    required this.mode,
    required this.failureReason,
    required this.subscriptionId,
    required this.next,
  });

  bool get isDevMode => mode == 'dev';
  bool get succeeded => status == 'succeeded';
  bool get failed => status == 'failed';
  bool get cancelled => status == 'cancelled';
  bool get isTerminal =>
      const {'succeeded', 'failed', 'cancelled', 'refunded'}.contains(status);

  factory PaymentIntent.fromJson(Map<String, dynamic> j) {
    final plan = (j['plan'] as Map?) ?? const {};
    return PaymentIntent(
      id: j['id']?.toString() ?? '',
      status: j['status']?.toString() ?? 'created',
      planName: plan['name']?.toString() ?? '',
      planCode: plan['code']?.toString() ?? '',
      interval: plan['interval']?.toString() ?? 'month',
      amount: (j['amount'] as num?)?.toDouble() ?? 0,
      currency: j['currency']?.toString() ?? 'BDT',
      amountDisplay: j['amount_display']?.toString() ?? '',
      paymentMethod: j['payment_method']?.toString(),
      provider: j['provider']?.toString() ?? 'dev',
      mode: j['mode']?.toString() ?? 'dev',
      failureReason: j['failure_reason']?.toString(),
      subscriptionId: j['subscription_id']?.toString(),
      next: j['next']?.toString(),
    );
  }
}

enum PayMethod { card, bkash, nagad }

extension PayMethodX on PayMethod {
  String get wire => switch (this) {
        PayMethod.card => 'card',
        PayMethod.bkash => 'bkash',
        PayMethod.nagad => 'nagad',
      };
  String get label => switch (this) {
        PayMethod.card => 'Card',
        PayMethod.bkash => 'bKash',
        PayMethod.nagad => 'Nagad',
      };
}
