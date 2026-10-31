import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/network/auth_service.dart';

class PharmacyApiException implements Exception {
  final String message;
  const PharmacyApiException(this.message);
  @override
  String toString() => message;
}

/// The one place every pharmacy screen should check for lock state instead of
/// reading `account_status` itself — wraps `GET /api/pharmacy/permissions/`
/// (backend: `pharmacy.services.pharmacy_permission_snapshot`).
class PharmacyPermissions {
  final String status; // PENDING_REVIEW | NEEDS_MORE_INFORMATION | ACTIVE | SUSPENDED | APPEAL_PENDING | REJECTED | CLOSED
  final String accountStatus;
  final String? reviewState;
  final bool isVerified;
  final Map<String, bool> can;
  final String? lockedReason;
  final String? rejectionReason;
  final String? moreInformationReason;
  final String? openAppealId;

  const PharmacyPermissions({
    required this.status,
    required this.accountStatus,
    required this.reviewState,
    required this.isVerified,
    required this.can,
    required this.lockedReason,
    required this.rejectionReason,
    required this.moreInformationReason,
    required this.openAppealId,
  });

  bool get isActive => status == 'ACTIVE';
  bool get isLocked => !isActive;
  bool canDo(String feature) => can[feature] ?? false;

  factory PharmacyPermissions.fromJson(Map<String, dynamic> json) => PharmacyPermissions(
        status: json['status']?.toString() ?? 'PENDING_REVIEW',
        accountStatus: json['account_status']?.toString() ?? 'pending',
        reviewState: json['review_state']?.toString(),
        isVerified: json['is_verified'] == true,
        can: (json['can'] as Map? ?? const {})
            .map((k, v) => MapEntry(k.toString(), v == true)),
        lockedReason: json['locked_reason']?.toString(),
        rejectionReason: json['rejection_reason']?.toString(),
        moreInformationReason: json['more_information_reason']?.toString(),
        openAppealId: json['open_appeal_id']?.toString(),
      );
}

class PharmacyPermissionsService {
  PharmacyPermissionsService._();
  static final instance = PharmacyPermissionsService._();

  Future<PharmacyPermissions> fetch() async {
    final data = await _get('permissions/');
    return PharmacyPermissions.fromJson(data);
  }

  /// Real lifetime earnings — reachable at every lifecycle stage (spec §1).
  Future<Map<String, dynamic>> earnings() => _get('earnings/');

  Future<Map<String, String>> _headers() async {
    final auth = AuthService.instance;
    final session = auth.currentSession ?? await auth.getStoredSession();
    if (session == null || session.accessToken.isEmpty) {
      throw const PharmacyApiException('Pharmacy authentication is required.');
    }
    return {
      'Accept': 'application/json',
      'Authorization': 'Bearer ${session.accessToken}',
    };
  }

  Uri _uri(String path) => Uri.parse('${AuthService.instance.baseUrl}/api/pharmacy/$path');

  Future<Map<String, dynamic>> _get(String path) async {
    final r = await http.get(_uri(path), headers: await _headers());
    if (r.statusCode < 200 || r.statusCode >= 300) {
      var message = 'Pharmacy request failed (${r.statusCode}).';
      try {
        message = (jsonDecode(r.body) as Map)['detail']?.toString() ?? message;
      } catch (_) {}
      throw PharmacyApiException(message);
    }
    final decoded = jsonDecode(r.body);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
  }
}
