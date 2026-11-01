import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/network/auth_service.dart';
import 'pharmacy_permissions_service.dart' show PharmacyApiException;

/// REST wrapper for the pharmacy<->Pharmacy-Admin support conversation
/// (`/api/pharmacy/support-conversation/...`). Live delivery reuses the
/// existing, role-agnostic `RealtimeChatService` (lib/core/network) exactly
/// like the doctor messenger does — this class only needs to get-or-create
/// the thread and provide a REST fallback for sending/reading.
class PharmacyChatService {
  PharmacyChatService._();
  static final instance = PharmacyChatService._();

  Future<Map<String, dynamic>> getOrCreate() => _send('support-conversation/', 'POST', const {});

  Future<Map<String, dynamic>> fetch() => _get('support-conversation/');

  Future<Map<String, dynamic>> sendMessage(String conversationId, String content) =>
      _send('support-conversation/$conversationId/', 'POST', {'content': content});

  Future<void> markRead(String conversationId) =>
      _send('support-conversation/$conversationId/', 'PATCH', const {});

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
