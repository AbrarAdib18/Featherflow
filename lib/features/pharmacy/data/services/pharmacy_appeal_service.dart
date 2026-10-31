import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/network/auth_service.dart';
import 'pharmacy_permissions_service.dart' show PharmacyApiException;

/// Suspension appeal reasons — mirrors the same enumerated list the backend
/// (pharmacy.services.SUSPENSION_REASONS) uses for both suspension and appeal
/// reasons, per spec §9.
const kSuspensionReasons = <String>[
  'expired_or_invalid_license',
  'missing_business_documentation',
  'unsafe_or_unauthorized_medicine',
  'repeated_policy_violations',
  'fraudulent_activity',
  'payment_settlement_issue',
  'customer_safety_issue',
  'other',
];

String suspensionReasonLabel(String code) => switch (code) {
      'expired_or_invalid_license' => 'Expired or invalid license',
      'missing_business_documentation' => 'Missing business documentation',
      'unsafe_or_unauthorized_medicine' => 'Unsafe or unauthorized medicine',
      'repeated_policy_violations' => 'Repeated policy violations',
      'fraudulent_activity' => 'Fraudulent activity',
      'payment_settlement_issue' => 'Payment/settlement issue',
      'customer_safety_issue' => 'Customer safety issue',
      _ => 'Other',
    };

class PharmacyAppealService {
  PharmacyAppealService._();
  static final instance = PharmacyAppealService._();

  Future<List<Map<String, dynamic>>> list() async {
    final data = await _get('appeals/');
    return (data['results'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, dynamic>> submit({
    required String reason,
    required String explanation,
    List<String> attachments = const [],
  }) =>
      _send('appeals/', 'POST', {
        'reason': reason,
        'explanation': explanation,
        'attachments': attachments,
      });

  Future<Map<String, String>> _headers() async {
    final auth = AuthService.instance;
    final session = auth.currentSession ?? await auth.getStoredSession();
    if (session == null || session.accessToken.isEmpty) {
      throw const PharmacyApiException('Pharmacy authentication is required.');
    }
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${session.accessToken}',
    };
  }

  Uri _uri(String path) => Uri.parse('${AuthService.instance.baseUrl}/api/pharmacy/$path');

  Future<Map<String, dynamic>> _get(String path) async {
    final r = await http.get(_uri(path), headers: await _headers());
    return _decode(r);
  }

  Future<Map<String, dynamic>> _send(String path, String method, Map<String, dynamic> body) async {
    final headers = await _headers();
    final payload = jsonEncode(body);
    final r = method == 'POST'
        ? await http.post(_uri(path), headers: headers, body: payload)
        : await http.patch(_uri(path), headers: headers, body: payload);
    return _decode(r);
  }

  Map<String, dynamic> _decode(http.Response r) {
    if (r.statusCode < 200 || r.statusCode >= 300) {
      var message = 'Pharmacy request failed (${r.statusCode}).';
      try {
        message = (jsonDecode(r.body) as Map)['detail']?.toString() ?? message;
      } catch (_) {}
      throw PharmacyApiException(message);
    }
    if (r.body.isEmpty) return {};
    final decoded = jsonDecode(r.body);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : {'results': decoded};
  }
}
