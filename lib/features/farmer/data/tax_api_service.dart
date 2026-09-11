import 'farm_management_service.dart';
import 'models/tax_calculation_result.dart';
import 'models/tax_payment.dart';
import 'models/tax_profile.dart';
import 'models/tax_summary.dart';

/// Typed wrapper over the /api/farmers/tax/ endpoints. Calls go through
/// [FarmManagementService] so auth, the trailing slash and error surfacing are
/// handled in one place.
class TaxApiService {
  // ── estimate ───────────────────────────────────────────────────────────
  /// Estimate tax. Any field left out falls back to the saved profile and this
  /// year's cost-management revenue on the backend.
  static Future<TaxCalculationResult> calculateTax({
    Map<String, double>? revenueBreakdown,
    double? expenses,
    String? incomeType,
    double? exemptions,
    double? rebates,
    bool? isSenior,
    Map<String, dynamic>? assets,
  }) async {
    final body = <String, dynamic>{};
    if (revenueBreakdown != null) body['revenue_breakdown'] = revenueBreakdown;
    if (expenses != null) body['expenses'] = expenses;
    if (incomeType != null) body['income_type'] = incomeType;
    if (exemptions != null) body['exemptions'] = exemptions;
    if (rebates != null) body['rebates'] = rebates;
    if (isSenior != null) body['is_senior'] = isSenior;
    if (assets != null) body['assets'] = assets;
    final res = await FarmManagementService.post('farmers/tax/calculate', body);
    return TaxCalculationResult.fromJson(res);
  }

  // ── profile ────────────────────────────────────────────────────────────
  static Future<TaxProfile> getTaxProfile() async =>
      TaxProfile.fromJson(await FarmManagementService.get('farmers/tax/profile'));

  static Future<TaxProfile> updateTaxProfile(Map<String, dynamic> body) async =>
      TaxProfile.fromJson(
          await FarmManagementService.patch('farmers/tax/profile', body));

  // ── payments ───────────────────────────────────────────────────────────
  static Future<TaxPayment> recordTaxPayment(Map<String, dynamic> body) async =>
      TaxPayment.fromJson(
          await FarmManagementService.post('farmers/tax/payment', body));

  static Future<List<TaxPayment>> getTaxPayments({String? taxType, int? year}) async {
    final params = <String, String>{};
    if (taxType != null && taxType.isNotEmpty) params['tax_type'] = taxType;
    if (year != null) params['year'] = '$year';
    final qs = params.isEmpty
        ? ''
        : '?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}';
    final res = await FarmManagementService.get('farmers/tax/payments$qs');
    return ((res['results'] as List?) ?? const [])
        .map((e) => TaxPayment.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<String> uploadReceipt(List<int> bytes, String filename) async {
    final res = await FarmManagementService.upload(
        'farmers/tax/payment/upload-receipt', bytes, filename);
    return res['image_url']?.toString() ?? '';
  }

  // ── summary ────────────────────────────────────────────────────────────
  static Future<TaxSummary> getTaxSummary() async =>
      TaxSummary.fromJson(await FarmManagementService.get('farmers/tax/summary'));
}
