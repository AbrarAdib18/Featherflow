import 'farm_management_service.dart';
import 'models/subscription_models.dart';

/// Typed wrapper over the billing / subscription checkout endpoints. Goes
/// through [FarmManagementService] so auth, the trailing slash and error
/// surfacing are handled in one place.
class SubscriptionService {
  static Future<PlansResponse> plans() async =>
      PlansResponse.fromJson(await FarmManagementService.get('subscriptions/plans'));

  static Future<CurrentSubscription?> current() async {
    final res = await FarmManagementService.get('subscriptions/current');
    final cur = res['current'];
    return cur is Map
        ? CurrentSubscription.fromJson(Map<String, dynamic>.from(cur))
        : null;
  }

  /// Create (or reuse, via [idempotencyKey]) a payment intent for [planId].
  /// The server computes the amount — nothing about price is sent from here.
  static Future<PaymentIntent> checkout(
          {required int planId, required String idempotencyKey}) async =>
      PaymentIntent.fromJson(await FarmManagementService.post(
          'subscriptions/checkout',
          {'plan_id': planId, 'idempotency_key': idempotencyKey}));

  static Future<PaymentIntent> selectMethod(String intentId, PayMethod method) async =>
      PaymentIntent.fromJson(await FarmManagementService.post(
          'payments/$intentId/method', {'payment_method': method.wire}));

  static Future<PaymentIntent> intent(String intentId) async =>
      PaymentIntent.fromJson(
          await FarmManagementService.get('payments/$intentId'));

  /// Development-mode only: tell the simulated provider the outcome.
  /// [outcome] is 'success' | 'failure' | 'cancel'.
  static Future<PaymentIntent> devConfirm(String intentId, String outcome) async =>
      PaymentIntent.fromJson(await FarmManagementService.post(
          'payments/$intentId/confirm', {'outcome': outcome}));

  static Future<PaymentIntent> cancel(String intentId) async =>
      PaymentIntent.fromJson(
          await FarmManagementService.post('payments/$intentId/cancel', const {}));
}
