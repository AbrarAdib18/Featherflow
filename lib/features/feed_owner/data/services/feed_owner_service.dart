import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/network/auth_service.dart';

class FeedOwnerApiException implements Exception {
  const FeedOwnerApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// REST wrapper for the Feed Inventory Owner's own profile and the private
/// Feed Owner<->Feed Marketplace Admin chat (`/api/feed-owner/...`). Mirrors
/// PharmacyChatService's shape exactly — this role reuses the same
/// doctor.Conversation/Message backend, just a different owner-side prefix.
class FeedOwnerService {
  FeedOwnerService._();
  static final instance = FeedOwnerService._();

  Future<Map<String, dynamic>> profile() => _get('profile/');

  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> fields) =>
      _send('profile/', 'PATCH', fields);

  Future<Map<String, dynamic>> getOrCreateChat() => _send('chat/', 'POST', const {});

  Future<Map<String, dynamic>> fetchChat() => _get('chat/');

  Future<Map<String, dynamic>> sendMessage(String conversationId, String content) =>
      _send('chat/$conversationId/', 'POST', {'content': content});

  Future<void> markRead(String conversationId) =>
      _send('chat/$conversationId/', 'PATCH', const {});

  Future<Map<String, String>> _headers() async {
    final auth = AuthService.instance;
    final session = auth.currentSession ?? await auth.getStoredSession();
    if (session == null || session.accessToken.isEmpty) {
      throw const FeedOwnerApiException('You need to sign in again.');
    }
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${session.accessToken}',
    };
  }

  Uri _uri(String path) => Uri.parse('${AuthService.instance.baseUrl}/api/feed-owner/$path');

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
      var message = 'Request failed (${r.statusCode}).';
      try {
        message = (jsonDecode(r.body) as Map)['detail']?.toString() ?? message;
      } catch (_) {}
      throw FeedOwnerApiException(message);
    }
    if (r.body.isEmpty) return {};
    final decoded = jsonDecode(r.body);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : {'results': decoded};
  }
}
