import 'farm_management_service.dart';
import 'models/labour_payment_models.dart';
import 'models/subscription_models.dart' show PayMethod, PayMethodX;

/// Wraps the labour-payment endpoints. "Pay"/"Pay All" only ever creates a
/// payment intent (`POST workers/payments`) — it never marks a worker paid
/// directly. The method/confirm/cancel calls reuse the exact same generic
/// `billing` endpoints the subscription flow uses (`SubscriptionService`),
/// since a `PaymentIntent` id is opaque to those routes regardless of what
/// it's paying for.
class LabourPaymentService {
  /// Opens intents for one worker ([workerId]) or several ([workerIds], the
  /// "Pay All" case). Workers with nothing due are silently skipped by the
  /// backend (returned in `skipped`, not surfaced as an error).
  static Future<List<LabourPaymentIntent>> openIntents({
    String? workerId,
    List<String>? workerIds,
  }) async {
    final body = workerIds != null
        ? {'worker_ids': workerIds}
        : {'worker_id': workerId};
    final res = await FarmManagementService.post('workers/payments', body);
    return ((res['intents'] as List?) ?? const [])
        .map((e) => LabourPaymentIntent.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<LabourPaymentIntent> selectMethod(String intentId, PayMethod method) async =>
      LabourPaymentIntent.fromJson(await FarmManagementService.post(
          'payments/$intentId/method', {'payment_method': method.wire}));

  /// Development-mode only: tell the simulated provider the outcome.
  static Future<LabourPaymentIntent> devConfirm(String intentId, String outcome) async =>
      LabourPaymentIntent.fromJson(await FarmManagementService.post(
          'payments/$intentId/confirm', {'outcome': outcome}));

  static Future<LabourPaymentIntent> cancel(String intentId) async =>
      LabourPaymentIntent.fromJson(
          await FarmManagementService.post('payments/$intentId/cancel', const {}));
}
