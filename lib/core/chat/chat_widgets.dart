import 'package:flutter/material.dart';

import 'chat_core.dart';

/// The line under a chat bubble: send time, or the send state while the
/// server hasn't confirmed it. Shared by every chat screen so times and
/// failed/retry states look and behave the same everywhere.
class ChatMessageMeta extends StatelessWidget {
  const ChatMessageMeta({
    super.key,
    required this.sentAt,
    required this.status,
    this.onRetry,
    this.color = const Color(0xFF8A8A8A),
  });

  final DateTime sentAt;
  final ChatSendStatus status;
  final VoidCallback? onRetry;
  final Color color;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case ChatSendStatus.sending:
        return Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.schedule, size: 11, color: color),
          const SizedBox(width: 3),
          // Provisional device time until the server's time replaces it.
          Text('Sending… ${ChatTime.format(sentAt)}',
              key: const Key('chatMessageSending'),
              style: TextStyle(color: color, fontSize: 10)),
        ]);
      case ChatSendStatus.failed:
        return InkWell(
          key: const Key('chatMessageRetry'),
          onTap: onRetry,
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline, size: 12, color: Color(0xFFD32F2F)),
            SizedBox(width: 3),
            Text('Not sent · Tap to retry',
                style: TextStyle(
                    color: Color(0xFFD32F2F),
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ]),
        );
      case ChatSendStatus.sent:
        return Text(ChatTime.format(sentAt),
            key: const Key('chatMessageTime'),
            style: TextStyle(color: color, fontSize: 10));
    }
  }
}
