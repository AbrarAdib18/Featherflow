import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/network/auth_service.dart';

/// One turn of the conversation (what the server accepts as `history`).
class ChatTurn {
  const ChatTurn({required this.fromUser, required this.text});
  final bool fromUser;
  final String text;
}

class ChatReply {
  const ChatReply({required this.text, required this.inScope});
  final String text;

  /// False when the assistant refused because the question was not about
  /// poultry farming or Featherflow.
  final bool inScope;
}

/// A failed assistant call, already phrased for the user. Never carries a raw
/// exception, URL, token or provider detail.
class ChatbotException implements Exception {
  const ChatbotException(this.message,
      {this.code = 'unknown', this.offline = false, this.retryable = true});
  final String message;
  final String code;
  final bool offline;
  final bool retryable;

  @override
  String toString() => message;
}

typedef ChatTransport = Future<ChatReply> Function(
    String message, List<ChatTurn> history);

/// Talks to the Featherflow backend (`POST /api/chatbot/chat/`). The Gemini
/// key lives only on the server; the app sends the user's own JWT and never
/// holds any provider credential.
class ChatbotService {
  ChatbotService._();
  static final ChatbotService instance = ChatbotService._();

  static const maxMessageChars = 1000;
  static const maxHistoryTurns = 6;

  /// Tests inject a fake transport here; null means the real HTTP call.
  ChatTransport? transportOverride;

  http.Client Function() clientFactory = http.Client.new;

  Future<ChatReply> send(String message, List<ChatTurn> history) {
    final override = transportOverride;
    if (override != null) return override(message, history);
    return _sendHttp(message, history);
  }

  Future<ChatReply> _sendHttp(String message, List<ChatTurn> history) async {
    final session = AuthService.instance.currentSession;
    if (session == null || session.accessToken.isEmpty) {
      throw const ChatbotException('Please sign in again to use the assistant.',
          code: 'signed_out', retryable: false);
    }
    final trimmed = history.length > maxHistoryTurns
        ? history.sublist(history.length - maxHistoryTurns)
        : history;
    final client = clientFactory();
    try {
      final response = await client
          .post(
            Uri.parse('${AuthService.instance.baseUrl}/api/chatbot/chat/'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer ${session.accessToken}',
            },
            body: jsonEncode({
              'message': message,
              'history': [
                for (final t in trimmed)
                  {'role': t.fromUser ? 'user' : 'assistant', 'text': t.text},
              ],
            }),
          )
          .timeout(const Duration(seconds: 40));
      return _parse(response);
    } on TimeoutException {
      throw const ChatbotException(
          'The assistant took too long to answer. Please try again.',
          code: 'timeout');
    } on ChatbotException {
      rethrow;
    } catch (_) {
      // SocketException / ClientException / browser fetch failure.
      throw const ChatbotException(
          'You appear to be offline. Check your connection and try again.',
          code: 'offline',
          offline: true);
    } finally {
      client.close();
    }
  }

  ChatReply _parse(http.Response response) {
    Map<String, dynamic> body = const {};
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {}
    final status = response.statusCode;
    if (status == 200 && body['reply'] is String) {
      return ChatReply(
          text: body['reply'] as String, inScope: body['in_scope'] != false);
    }
    if (status == 401 || status == 403) {
      throw const ChatbotException('Please sign in again to use the assistant.',
          code: 'signed_out', retryable: false);
    }
    if (status == 429) {
      throw const ChatbotException(
          'You are sending messages too quickly. Please wait a minute and try again.',
          code: 'rate_limited');
    }
    final error = body['error'];
    if (error is Map && error['message'] is String) {
      final code = (error['code'] ?? 'unknown').toString();
      throw ChatbotException(error['message'] as String,
          code: code, retryable: code != 'not_configured');
    }
    throw const ChatbotException(
        'The assistant is unavailable right now. Please try again.',
        code: 'server');
  }
}
