import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/network/auth_service.dart';

class DoctorApiService {
  static Future<Map<String, dynamic>> get(String path) => _request('GET', path);
  static Future<Map<String, dynamic>> post(
          String path, Map<String, dynamic> body) =>
      _request('POST', path, body);
  static Future<Map<String, dynamic>> patch(
          String path, Map<String, dynamic> body) =>
      _request('PATCH', path, body);
  static Future<Map<String, dynamic>> delete(
          String path, Map<String, dynamic> body) =>
      _request('DELETE', path, body);
  static Future<Map<String, dynamic>> notifications() =>
      _rootRequest('GET', 'notifications');
  static Future<Map<String, dynamic>> markNotificationsRead() =>
      _rootRequest('PATCH', 'notifications');

  static Future<Map<String, dynamic>> _rootRequest(
      String method, String path) async {
    final auth = AuthService.instance;
    final session = auth.currentSession ?? await auth.getStoredSession();
    if (session == null) throw AuthException('Please sign in again.');
    final uri = Uri.parse('${auth.baseUrl}/api/$path/');
    final headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${session.accessToken}'
    };
    final response = method == 'PATCH'
        ? await http.patch(uri, headers: headers, body: '{}')
        : await http.get(uri, headers: headers);
    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException(
          decoded['detail']?.toString() ?? 'Notification request failed.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  static Future<Map<String, dynamic>> _request(String method, String path,
      [Map<String, dynamic>? body]) async {
    final auth = AuthService.instance;
    final session = auth.currentSession ?? await auth.getStoredSession();
    if (session == null) throw AuthException('Please sign in again.');
    final uri = Uri.parse('${auth.baseUrl}/api/doctor/$path/');
    final headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${session.accessToken}'
    };
    final response = switch (method) {
      'POST' => await http.post(uri, headers: headers, body: jsonEncode(body)),
      'PATCH' =>
        await http.patch(uri, headers: headers, body: jsonEncode(body)),
      'DELETE' =>
        await http.delete(uri, headers: headers, body: jsonEncode(body)),
      _ => await http.get(uri, headers: headers),
    };
    final decoded =
        response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'Doctor request failed.';
      if (decoded is Map) {
        if (decoded['detail'] != null) {
          message = decoded['detail'].toString();
        } else {
          // DRF field errors: {"diagnosis": ["Ensure this field has no more than ..."]}
          final first = decoded.entries.firstOrNull;
          if (first != null) {
            final v = first.value;
            message = '${first.key}: ${v is List && v.isNotEmpty ? v.first : v}';
          }
        }
      }
      throw AuthException(message,
          statusCode: response.statusCode,
          data: decoded is Map ? Map<String, dynamic>.from(decoded) : const {});
    }
    return Map<String, dynamic>.from(decoded as Map);
  }
}
