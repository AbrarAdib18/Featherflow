import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../core/network/auth_service.dart';
import 'farm_management_service.dart';

/// Thin typed wrapper over the /api/farmers/costs/ endpoints. All calls go
/// through [FarmManagementService] so auth, error surfacing and the trailing
/// slash are handled in one place.
class CostManagementService {
  static String _qs(Map<String, String?> params) {
    final entries = params.entries
        .where((e) => e.value != null && e.value!.isNotEmpty)
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value!)}');
    return entries.isEmpty ? '' : '?${entries.join('&')}';
  }

  // ── dashboard ──────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> dashboard({String period = 'lifetime'}) =>
      FarmManagementService.get('farmers/costs/dashboard${_qs({'period': period})}');

  // ── expenses ───────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> expenses({
    String? category,
    String? status,
    String? flock,
    String? from,
    String? to,
  }) =>
      FarmManagementService.get('farmers/costs/expenses${_qs({
            'category': category,
            'status': status,
            'flock': flock,
            'from': from,
            'to': to,
          })}');

  static Future<Map<String, dynamic>> addExpense(Map<String, dynamic> body) =>
      FarmManagementService.post('farmers/costs/expenses', body);

  static Future<Map<String, dynamic>> updateExpense(
          String id, Map<String, dynamic> body) =>
      FarmManagementService.patch('farmers/costs/expenses/$id', body);

  static Future<void> deleteExpense(String id) =>
      FarmManagementService.delete('farmers/costs/expenses/$id', const {});

  static Future<Map<String, dynamic>> payExpense(String id, String method) =>
      FarmManagementService.post(
          'farmers/costs/expenses/$id/pay', {'payment_method': method});

  // ── revenue ────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> revenue({String? source, String? flock}) =>
      FarmManagementService.get(
          'farmers/costs/revenue${_qs({'source': source, 'flock': flock})}');

  static Future<Map<String, dynamic>> addRevenue(Map<String, dynamic> body) =>
      FarmManagementService.post('farmers/costs/revenue', body);

  static Future<Map<String, dynamic>> updateRevenue(
          String id, Map<String, dynamic> body) =>
      FarmManagementService.patch('farmers/costs/revenue/$id', body);

  static Future<void> deleteRevenue(String id) =>
      FarmManagementService.delete('farmers/costs/revenue/$id', const {});

  // ── loans ──────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> loans() =>
      FarmManagementService.get('farmers/costs/loans');

  static Future<Map<String, dynamic>> requestLoan(Map<String, dynamic> body) =>
      FarmManagementService.post('farmers/costs/loans', body);

  static Future<Map<String, dynamic>> repayLoan(
          String id, double amount, String method) =>
      FarmManagementService.post('farmers/costs/loans/$id',
          {'amount': amount, 'payment_method': method});

  // ── inventory / batches ────────────────────────────────────────────────
  static Future<Map<String, dynamic>> inventory() =>
      FarmManagementService.get('farmers/costs/inventory');

  static Future<Map<String, dynamic>> batches() =>
      FarmManagementService.get('farmers/costs/batches');

  // ── cashout ────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> cashoutHistory() =>
      FarmManagementService.get('farmers/costs/cashout');

  static Future<Map<String, dynamic>> cashout(double amount, String method,
          {String accountDetails = ''}) =>
      FarmManagementService.post('farmers/costs/cashout', {
        'amount': amount,
        'payment_method': method,
        'account_details': accountDetails,
      });

  // ── receipts (returns { image_url }) ──────────────────────────────────
  static Future<String> uploadReceipt(List<int> bytes, String filename) async {
    final res = await FarmManagementService.upload(
        'farmers/costs/expenses/upload-receipt', bytes, filename);
    return res['image_url']?.toString() ?? '';
  }

  // ── reports — authed fetch of the generated CSV / PDF ────────────────
  static Future<({Uint8List bytes, bool isPdf})> report({
    required String type,
    String period = 'lifetime',
    String export = 'csv',
    String? from,
    String? to,
  }) async {
    final auth = AuthService.instance;
    final session = auth.currentSession ?? await auth.getStoredSession();
    if (session == null) throw AuthException('Please sign in again.');
    final q = _qs({
      'type': type,
      'period': period,
      'export': export,
      'from': from,
      'to': to,
    });
    final uri = Uri.parse('${auth.baseUrl}/api/farmers/costs/reports/$q');
    final response = await http.get(uri, headers: {
      'Authorization': 'Bearer ${session.accessToken}',
    });
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException('Unable to generate this report.');
    }
    final isPdf =
        (response.headers['content-type'] ?? '').contains('application/pdf');
    return (bytes: response.bodyBytes, isPdf: isPdf);
  }
}
