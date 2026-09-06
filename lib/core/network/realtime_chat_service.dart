import 'package:socket_io_client/socket_io_client.dart' as io;

import 'auth_service.dart';

class RealtimeChatService {
  io.Socket? _socket;
  void Function(Map<String, dynamic>)? onMessage;
  void Function(String)? onError;

  Future<void> connect(String conversationId) async {
    final auth = AuthService.instance;
    final session = auth.currentSession ?? await auth.getStoredSession();
    if (session == null) throw AuthException('Please sign in again.');
    disconnect();
    _socket = io.io(
        auth.baseUrl,
        io.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .setAuth({'token': session.accessToken})
            .enableReconnection()
            .build());
    _socket!
      ..onConnect((_) => _socket!.emitWithAck(
              'join_conversation', {'conversation_id': conversationId},
              ack: (data) {
            if (data is Map && data['ok'] != true) {
              onError?.call('${data['error']}');
            }
          }))
      ..on('message_created', (data) {
        if (data is Map) onMessage?.call(Map<String, dynamic>.from(data));
      })
      ..onConnectError(
          (error) => onError?.call('Chat connection failed: $error'))
      ..onError((error) => onError?.call('Chat error: $error'))
      ..connect();
  }

  void send(String conversationId, String content) {
    _socket?.emitWithAck('send_message', {
      'conversation_id': conversationId,
      'content': content,
      'message_type': 'text',
    }, ack: (data) {
      if (data is Map && data['ok'] != true) onError?.call('${data['error']}');
    });
  }

  void markRead(String conversationId) =>
      _socket?.emit('mark_read', {'conversation_id': conversationId});

  void disconnect() {
    _socket?.dispose();
    _socket = null;
  }
}
