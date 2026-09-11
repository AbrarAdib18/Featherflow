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
    dynamic decoded;
    try {
      decoded = response.body.isEmpty ? const {} : jsonDecode(response.body);
    } catch (_) {
      decoded = const {};
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map ? decoded['detail']?.toString() : null;
      throw AuthException(detail ??
          (response.statusCode >= 500
              ? 'The server could not accept this upload. Please try again.'
              : 'Upload failed (${response.statusCode}).'));
    }
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
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
    // The body is normally JSON, but a 5xx (or a proxy/timeout page) can be
    // HTML or plain text — decode defensively so callers get a clean message
    // instead of a raw FormatException surfacing as "error in code".
    dynamic decoded;
    try {
      decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
    } catch (_) {
      decoded = <String, dynamic>{};
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var message = response.statusCode >= 500
          ? 'The server ran into a problem. Please try again in a moment.'
          : 'Request failed (${response.statusCode}).';
      if (decoded is Map && decoded.isNotEmpty) {
        message = decoded['detail']?.toString() ?? message;
        if (decoded['detail'] == null) {
          final value = decoded.values.first;
          message = value is List && value.isNotEmpty
              ? value.first.toString()
              : value.toString();
        }
      }
      throw AuthException(message);
    }
    if (decoded is! Map) {
      throw AuthException('The server sent an unexpected response.');
    }
    final result = Map<String, dynamic>.from(decoded);
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
