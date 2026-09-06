import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/network/auth_service.dart';

class AdminApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? code;
  const AdminApiException(this.message, {this.statusCode, this.code});

  bool get isAccessRevoked =>
      statusCode == 403 &&
      (code == 'account_suspended' ||
          message.toLowerCase().contains('suspended') ||
          message.toLowerCase().contains('awaiting approval'));

  @override
  String toString() => message;
}

/// A queued (202) response from a sensitive action that needs higher approval.
class AdminApprovalRequired implements Exception {
  final String approvalId;
  final int requiredTier;
  final String message;
  const AdminApprovalRequired(this.approvalId, this.requiredTier, this.message);

  @override
  String toString() => message;
}

class AdminApiService {
  AdminApiService._();
  static final AdminApiService instance = AdminApiService._();

  // ── generic module CRUD (unchanged contract) ─────────────────────────────
  Future<Map<String, dynamic>> dashboard() => _request('dashboard/');
  Future<Map<String, dynamic>> me() => _request('me/');

  Future<List<Map<String, dynamic>>> list(String module,
      {Map<String, String>? query}) async {
    final data = await _request('$module/', query: query);
    return (data['results'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<Map<String, dynamic>> create(String module, Map<String, dynamic> data) =>
      _request('$module/', method: 'POST', body: data);

  Future<Map<String, dynamic>> update(
          String module, String id, Map<String, dynamic> data) =>
      _request('$module/$id/', method: 'PATCH', body: data);

  Future<Map<String, dynamic>> delete(String module, String id) =>
      _request('$module/$id/', method: 'DELETE');

  Future<Map<String, dynamic>> profile() => _request('profile/');
  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> data) =>
      _request('profile/', method: 'PATCH', body: data);
  Future<Map<String, dynamic>> changePassword(String current, String next) =>
      _request('profile/', method: 'POST',
          body: {'current_password': current, 'password': next});

  // ── admin account management ─────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> admins({String? status}) =>
      list('admins', query: status == null ? null : {'status': status});
  Future<Map<String, dynamic>> createAdmin(Map<String, dynamic> data) =>
      _request('admins/', method: 'POST', body: data);
  Future<Map<String, dynamic>> updateAdmin(String id, Map<String, dynamic> data) =>
      _request('admins/$id/', method: 'PATCH', body: data);
  Future<Map<String, dynamic>> adminAction(String id, String action,
          {String reason = ''}) =>
      _request('admins/$id/action/', method: 'POST',
          body: {'action': action, 'reason': reason});
  Future<List<Map<String, dynamic>>> roles() => list('roles');
  Future<Map<String, dynamic>> updateRolePermissions(
          String name, Map<String, dynamic> permissions) =>
      _request('roles/', method: 'PATCH',
          body: {'name': name, 'permissions': permissions});

  // ── audit trail ─────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> auditLogs({Map<String, String>? filters}) =>
      _request('audit-logs/', query: filters);
  Future<Map<String, dynamic>> overrideLog(String id, String reason) =>
      _request('audit-logs/$id/override/', method: 'POST', body: {'reason': reason});

  // ── approval queue ──────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> approvalQueue({String status = 'pending'}) =>
      list('approval-queue', query: {'status': status});
  Future<Map<String, dynamic>> decideApproval(String id, String decision,
          {String rejectionReason = ''}) =>
      _request('approval-queue/$id/decide/', method: 'POST',
          body: {'decision': decision, 'rejection_reason': rejectionReason});

  // ── shift timer (own) ───────────────────────────────────────────────────
  Future<Map<String, dynamic>> shiftStatus() => _request('my-shift/status/');
  Future<Map<String, dynamic>> startShift() => _request('my-shift/start/', method: 'POST');
  Future<Map<String, dynamic>> endShift() => _request('my-shift/end/', method: 'POST');
  Future<Map<String, dynamic>> startBreak() => _request('my-shift/break-start/', method: 'POST');
  Future<Map<String, dynamic>> endBreak() => _request('my-shift/break-end/', method: 'POST');
  Future<Map<String, dynamic>> shiftHours() => _request('my-shift/hours/');
  Future<List<Map<String, dynamic>>> shiftHistory() => list('my-shift/history');
  Future<List<Map<String, dynamic>>> myPayments() => list('my-payments');

  // ── team & payroll (Super Admin) ────────────────────────────────────────
  Future<Map<String, dynamic>> allAdmins() => _request('all-admins/');
  Future<List<Map<String, dynamic>>> onlineAdmins() => list('online-admins');
  Future<List<Map<String, dynamic>>> offlineAdmins() => list('offline-admins');
  Future<List<Map<String, dynamic>>> adminShiftsList({String? adminId}) =>
      list('shifts', query: adminId == null ? null : {'admin_id': adminId});
  Future<Map<String, dynamic>> forceEndShift(String shiftId, {String reason = ''}) =>
      _request('shifts/force-end/', method: 'POST',
          body: {'shift_id': shiftId, 'reason': reason});
  Future<Map<String, dynamic>> setHourlyRate(String adminId, num rate) =>
      _request('admins/$adminId/hourly-rate/', method: 'PATCH',
          body: {'hourly_rate': rate});
  Future<Map<String, dynamic>> setMaxHours(String adminId, int? hours) =>
      _request('admins/$adminId/max-hours/', method: 'PATCH',
          body: {'max_hours_per_week': hours});
  Future<List<Map<String, dynamic>>> adminPayments({String? status}) =>
      list('admin-payments', query: status == null ? null : {'status': status});
  Future<Map<String, dynamic>> generatePayroll({String? periodStart}) =>
      _request('admin-payments/', method: 'POST',
          body: periodStart == null ? {} : {'period_start': periodStart});
  Future<Map<String, dynamic>> markPaymentPaid(String id,
          {required String method, String reference = '', String notes = ''}) =>
      _request('admin-payments/$id/', method: 'PATCH', body: {
        'action': 'mark_paid',
        'payment_method': method,
        'payment_reference': reference,
        'notes': notes,
      });
  Future<({String filename, String csv})> exportPayroll() async {
    final auth = AuthService.instance;
    final session = auth.currentSession ?? await auth.getStoredSession();
    if (session == null) throw const AdminApiException('Admin authentication is required.');
    final uri = Uri.parse('${auth.baseUrl}/api/admin-panel/admin-payments/export/');
    final response = await http.get(uri, headers: {
      'Accept': 'text/csv',
      'Authorization': 'Bearer ${session.accessToken}',
    });
    if (response.statusCode != 200) throw _errorFrom(response);
    final match = RegExp('filename="([^"]+)"')
        .firstMatch(response.headers['content-disposition'] ?? '');
    return (filename: match?.group(1) ?? 'admin-payroll.csv', csv: response.body);
  }

  // ── pharmacy oversight ──────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> pharmacyMedicines({Map<String, String>? filters}) async {
    final data = await _request('pharmacy/medicines/', query: filters);
    return (data['results'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, dynamic>> approvePharmacyMedicine(String id) =>
      _request('pharmacy/medicines/$id/approve/', method: 'PATCH');

  Future<Map<String, dynamic>> rejectPharmacyMedicine(String id, String reason) =>
      _request('pharmacy/medicines/$id/reject/', method: 'PATCH', body: {'reason': reason});

  Future<Map<String, dynamic>> pharmacyExpiryAlerts({Map<String, String>? filters}) =>
      _request('pharmacy/expiry-alerts/', query: filters);

  Future<List<Map<String, dynamic>>> pharmacyOrders({Map<String, String>? filters}) async {
    final data = await _request('pharmacy/orders/', query: filters);
    return (data['results'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, dynamic>> setPharmacyStatus(String id, String action, {String reason = ''}) =>
      _request('pharmacy/$id/suspend/', method: 'PATCH',
          body: {'action': action, 'reason': reason});

  Future<Map<String, dynamic>> pharmacyAnalytics(String id) =>
      _request('pharmacy/$id/analytics/');

  // ── finance ─────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> financeSummary() => _request('finance/summary/');

  // ── oversight / escalations ─────────────────────────────────────────────
  Future<Map<String, dynamic>> oversight() => _request('oversight/');
  Future<List<Map<String, dynamic>>> escalations({String status = 'active'}) =>
      list('escalations', query: {'status': status});
  Future<Map<String, dynamic>> raiseEscalation(Map<String, dynamic> data) =>
      _request('escalations/', method: 'POST', body: data);
  Future<Map<String, dynamic>> resolveEscalation(String id,
          {String action = 'resolve', String resolution = ''}) =>
      _request('escalations/$id/resolve/', method: 'POST',
          body: {'action': action, 'resolution': resolution});

  // ── CSV export ──────────────────────────────────────────────────────────
  Future<({String filename, String csv})> exportCsv(String module) async {
    final auth = AuthService.instance;
    final session = auth.currentSession ?? await auth.getStoredSession();
    if (session == null) throw const AdminApiException('Admin authentication is required.');
    final uri = Uri.parse('${auth.baseUrl}/api/admin-panel/$module/export/');
    final response = await http.get(uri, headers: {
      'Accept': 'text/csv',
      'Authorization': 'Bearer ${session.accessToken}',
    });
    if (response.statusCode != 200) {
      throw _errorFrom(response);
    }
    final disposition = response.headers['content-disposition'] ?? '';
    final match = RegExp('filename="([^"]+)"').firstMatch(disposition);
    return (filename: match?.group(1) ?? '$module.csv', csv: response.body);
  }

  // ── core request ────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> _request(String path,
      {String method = 'GET',
      Map<String, dynamic>? body,
      Map<String, String>? query}) async {
    final auth = AuthService.instance;
    final session = auth.currentSession ?? await auth.getStoredSession();
    if (session == null || session.accessToken.isEmpty) {
      throw const AdminApiException('Admin authentication is required.', statusCode: 401);
    }
    var uri = Uri.parse('${auth.baseUrl}/api/admin-panel/$path');
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: {...uri.queryParameters, ...query});
    }
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${session.accessToken}',
    };
    late http.Response response;
    switch (method) {
      case 'POST':
        response = await http.post(uri, headers: headers, body: jsonEncode(body ?? const {}));
      case 'PATCH':
        response = await http.patch(uri, headers: headers, body: jsonEncode(body ?? const {}));
      case 'DELETE':
        response = await http.delete(uri, headers: headers, body: jsonEncode(body ?? const {}));
      default:
        response = await http.get(uri, headers: headers);
    }

    if (response.statusCode == 202) {
      final decoded = _tryDecode(response.body);
      throw AdminApprovalRequired(
        decoded['approval_id']?.toString() ?? '',
        (decoded['required_tier'] as num?)?.toInt() ?? 2,
        decoded['detail']?.toString() ??
            'This action was queued for higher-tier approval.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _errorFrom(response);
    }
    if (response.body.isEmpty) return {};
    final decoded = jsonDecode(response.body);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return {'results': decoded};
  }

  AdminApiException _errorFrom(http.Response response) {
    String message = 'Admin request failed (${response.statusCode}).';
    String? code;
    final decoded = _tryDecode(response.body);
    if (decoded['detail'] != null) message = decoded['detail'].toString();
    if (decoded['code'] != null) code = decoded['code'].toString();
    return AdminApiException(message, statusCode: response.statusCode, code: code);
  }

  Map<String, dynamic> _tryDecode(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return {};
  }
}
