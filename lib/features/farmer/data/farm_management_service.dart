import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/network/auth_service.dart';

class FarmManagementService {
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
  static Future<Map<String, dynamic>> upload(
      String path, List<int> bytes, String filename) async {
    final auth = AuthService.instance;
    final session = auth.currentSession ?? await auth.getStoredSession();
    if (session == null) throw AuthException('Please sign in again.');
    final request = http.MultipartRequest(
        'POST', Uri.parse('${auth.baseUrl}/api/$path/'))
      ..headers['Authorization'] = 'Bearer ${session.accessToken}'
      ..files
          .add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final response = await http.Response.fromStream(await request.send());
    final decoded = jsonDecode(response.body) as Map;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException(decoded['detail']?.toString() ?? 'Upload failed');
    }
    return Map<String, dynamic>.from(decoded);
  }

  static Future<Map<String, dynamic>> _request(String method, String path,
      [Map<String, dynamic>? body]) async {
    final auth = AuthService.instance;
    final session = auth.currentSession ?? await auth.getStoredSession();
    if (session == null) throw AuthException('Please sign in again.');
    final rawUri = Uri.parse('${auth.baseUrl}/api/$path');
    final uri = rawUri.replace(path: '${rawUri.path}/');
    final headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${session.accessToken}',
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
      var message = 'Request failed';
      if (decoded is Map) {
        message = decoded['detail']?.toString() ?? message;
        if (decoded['detail'] == null && decoded.isNotEmpty) {
          final value = decoded.values.first;
          message = value is List && value.isNotEmpty
              ? value.first.toString()
              : value.toString();
        }
      }
      throw AuthException(message);
    }
    final result = Map<String, dynamic>.from(decoded as Map);
    if (path == 'feed') {
      result['stock'] ??= <dynamic>[];
      result['schedules'] ??= <dynamic>[];
      result['history'] ??= <dynamic>[];
      result['suppliers'] ??= <dynamic>[];
      final summary = Map<String, dynamic>.from(
          result['summary'] as Map? ?? const <String, dynamic>{});
      summary['total_stock'] ??= 0;
      summary['stock_value'] ??= 0;
      summary['feed_types'] ??= 0;
      summary['low_stock_items'] ??= 0;
      result['summary'] = summary;
    } else if (path == 'workers') {
      result['workers'] ??= <dynamic>[];
      final summary = Map<String, dynamic>.from(
          result['summary'] as Map? ?? const <String, dynamic>{});
      summary['total_workers'] ??= 0;
      summary['present_today'] ??= 0;
      summary['absent_today'] ??= 0;
      summary['monthly_payroll'] ??= 0;
      result['summary'] = summary;
    }
    return result;
  }
}
