import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/network/auth_service.dart';

class AdminApiException implements Exception {
  final String message;
  const AdminApiException(this.message);

  @override
  String toString() => message;
}

class AdminApiService {
  AdminApiService._();

  static final AdminApiService instance = AdminApiService._();

  Future<Map<String, dynamic>> dashboard() => _request('dashboard/');

  Future<List<Map<String, dynamic>>> list(String module) async {
    final data = await _request('$module/');
    return (data['results'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<Map<String, dynamic>> create(
          String module, Map<String, dynamic> data) =>
      _request('$module/', method: 'POST', body: data);

  Future<Map<String, dynamic>> update(
          String module, String id, Map<String, dynamic> data) =>
      _request('$module/$id/', method: 'PATCH', body: data);

  Future<Map<String, dynamic>> profile() => _request('profile/');

  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> data) =>
      _request('profile/', method: 'PATCH', body: data);

  Future<Map<String, dynamic>> changePassword(
          String currentPassword, String password) =>
      _request('profile/', method: 'POST', body: {
        'current_password': currentPassword,
        'password': password,
      });

  Future<Map<String, dynamic>> _request(String path,
      {String method = 'GET', Map<String, dynamic>? body}) async {
    final auth = AuthService.instance;
    final session = auth.currentSession ?? await auth.getStoredSession();
    if (session == null || session.accessToken.isEmpty) {
      throw const AdminApiException('Admin authentication is required.');
    }
    final uri = Uri.parse('${auth.baseUrl}/api/admin-panel/$path');
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${session.accessToken}',
    };
    late http.Response response;
    switch (method) {
      case 'POST':
        response = await http.post(uri,
            headers: headers, body: jsonEncode(body ?? const {}));
      case 'PATCH':
        response = await http.patch(uri,
            headers: headers, body: jsonEncode(body ?? const {}));
      default:
        response = await http.get(uri, headers: headers);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'Admin request failed (${response.statusCode}).';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['detail'] != null) {
          message = decoded['detail'].toString();
        }
      } catch (_) {}
      throw AdminApiException(message);
    }
    if (response.body.isEmpty) return {};
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }
}
