// Shared chat message state for every chat UI (doctor messenger, farmer chat
// dialog). See CHAT_MESSAGE_STATE_FIX.md.
//
// Two bugs lived here, duplicated in each screen:
//
// * Duplicate sender bubble. The server broadcasts the Socket.IO
//   `message_created` echo *while handling* the REST send, so the echo can
//   arrive before the HTTP response. The optimistic bubble still had its
//   local id, so the echo (server id) was appended; the response then renamed
//   the optimistic bubble to the same server id -> two bubbles, one DB row.
//   Every outgoing message now carries a `client_message_id` that the server
//   stores and echoes back, and [ChatTimeline.upsert] matches on either id.
//
// * Wrong times. List rows came back as naive ISO (UTC wall clock, no
//   offset), which `DateTime.parse` reads as *local* time; echo/send
//   responses carried `+00:00` but were formatted without `toLocal()`. Both
//   showed UTC — 6 h early in Dhaka. [ChatTime.parseServer] always yields
//   the instant in the viewer's local zone.
import 'dart:math';

import 'package:intl/intl.dart';

enum ChatSendStatus { sending, sent, failed }

/// What [ChatTimeline] needs from a message, whatever the screen's model.
abstract interface class ChatTimelineItem {
  /// Server id once confirmed; the client id while unconfirmed.
  String get id;
  String? get clientMessageId;
  DateTime get sentAt;
  ChatSendStatus get sendStatus;
}

class ChatTime {
  const ChatTime._();

  /// Parses a server timestamp into the viewer's local time.
  ///
  /// The API sends ISO 8601 with an offset. A value *without* one is UTC wall
  /// clock (that is how `messages.sent_at` is stored), never local time.
  static DateTime? parseServer(Object? raw) {
    if (raw == null) return null;
    final text = raw.toString().trim();
    if (text.isEmpty || text == 'null') return null;
    final hasZone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(text);
    final parsed = DateTime.tryParse(hasZone ? text : '${text}Z');
    return parsed?.toLocal();
  }

  /// Today: `4:52 PM` · Yesterday: `Yesterday, 4:52 PM` · last 7 days:
  /// `Mon, 4:52 PM` · older: `12 Oct 2026, 4:52 PM`.
  ///
  /// A time slightly ahead of this device's clock (server/device skew) is
  /// shown as "now" rather than as a future time; the stored value is untouched.
  static String format(DateTime time, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final local = time.toLocal();
    final shown = local.isAfter(current) ? current : local;
    final clock = DateFormat('h:mm a').format(shown);
    final today = DateTime(current.year, current.month, current.day);
    final day = DateTime(shown.year, shown.month, shown.day);
    final daysAgo = today.difference(day).inDays;
    if (daysAgo <= 0) return clock;
    if (daysAgo == 1) return 'Yesterday, $clock';
    if (daysAgo < 7) return '${DateFormat('EEE').format(shown)}, $clock';
    return '${DateFormat('d MMM yyyy').format(shown)}, $clock';
  }
}

final _random = Random.secure();

/// RFC 4122 v4 UUID — the per-message idempotency key. Generated once per
/// outgoing message and reused for every retry of that message.
String newClientMessageId() {
  final b = List<int>.generate(16, (_) => _random.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String hex(int from, int to) =>
      b.sublist(from, to).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

/// Pure list operations; every chat screen keeps its messages through these.
class ChatTimeline {
  const ChatTimeline._();

  static bool _same(ChatTimelineItem a, ChatTimelineItem b) =>
      a.id == b.id ||
      (a.clientMessageId != null && a.clientMessageId == b.clientMessageId);

  /// Chronological by the server time; unconfirmed messages use their
  /// provisional local time. Ties keep a stable order by id.
  static List<T> sorted<T extends ChatTimelineItem>(Iterable<T> items) =>
      items.toList()
        ..sort((a, b) {
          final byTime = a.sentAt.compareTo(b.sentAt);
          return byTime != 0 ? byTime : a.id.compareTo(b.id);
        });

  /// Inserts a server-confirmed message, or replaces the entry it confirms —
  /// the optimistic bubble (matched by client id) and/or an earlier copy of
  /// the same server message (matched by id). Never yields two entries for
  /// one message, whichever of the send response, Socket.IO echo or poll
  /// arrives first.
  static List<T> upsert<T extends ChatTimelineItem>(List<T> items, T incoming,
      {String? replacingClientId}) {
    bool matches(T m) =>
        _same(m, incoming) ||
        (replacingClientId != null &&
            (m.clientMessageId == replacingClientId || m.id == replacingClientId));
    return sorted([...items.where((m) => !matches(m)), incoming]);
  }

  /// Merges a page of server messages (poll, refresh, pagination) into what
  /// is on screen. Overlapping pages and repeated rows collapse by id.
  static List<T> mergePage<T extends ChatTimelineItem>(List<T> items, Iterable<T> page) =>
      page.fold(items, (list, m) => upsert(list, m));

  /// Rebuilds from an authoritative server list (refresh / reopen): server
  /// rows win, and only *unconfirmed* local messages (sending or failed) that
  /// the server hasn't stored yet are kept, so nothing is duplicated and an
  /// unsent message never silently disappears.
  static List<T> reconcile<T extends ChatTimelineItem>(
      Iterable<T> server, Iterable<T> local) {
    final merged = mergePage(<T>[], server);
    final unconfirmed = local.where((m) =>
        m.sendStatus != ChatSendStatus.sent && !merged.any((s) => _same(s, m)));
    return sorted([...merged, ...unconfirmed]);
  }
}

/// Generic message model for chat screens that work on raw API maps
/// (the farmer chat dialog). The doctor messenger uses its own `ChatMessage`,
/// which implements the same [ChatTimelineItem] contract.
class ChatEntry implements ChatTimelineItem {
  const ChatEntry({
    required this.id,
    required this.mine,
    required this.content,
    required this.sentAt,
    this.clientMessageId,
    this.senderId,
    this.messageType = 'text',
    this.fileUrl,
    this.isRead = false,
    this.sendStatus = ChatSendStatus.sent,
  });

  @override
  final String id;
  @override
  final String? clientMessageId;
  final String? senderId;
  final bool mine;
  final String content;
  final String messageType;
  final String? fileUrl;
  final bool isRead;
  @override
  final DateTime sentAt;
  @override
  final ChatSendStatus sendStatus;

  /// [myUserId] decides `mine` for broadcast payloads, which carry no
  /// viewer-relative `from_me`.
  factory ChatEntry.fromServer(Map<String, dynamic> j, {String? myUserId}) {
    final sender = j['sender_id']?.toString();
    return ChatEntry(
      id: '${j['id']}',
      clientMessageId: j['client_message_id']?.toString(),
      senderId: sender,
      mine: j['from_me'] is bool
          ? j['from_me'] as bool
          : (myUserId != null && sender == myUserId),
      content: '${j['content'] ?? ''}',
      messageType: '${j['message_type'] ?? j['type'] ?? 'text'}',
      fileUrl: j['file_url']?.toString(),
      isRead: j['is_read'] == true,
      // Epoch only for a malformed row (the API always sends sent_at): it
      // sorts first rather than crashing the whole conversation.
      sentAt: ChatTime.parseServer(j['sent_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// The optimistic bubble: provisional local time until the server answers.
  factory ChatEntry.pending(String content, {required String clientMessageId}) =>
      ChatEntry(
        id: clientMessageId,
        clientMessageId: clientMessageId,
        mine: true,
        content: content,
        sentAt: DateTime.now(),
        sendStatus: ChatSendStatus.sending,
      );

  ChatEntry withStatus(ChatSendStatus status) => ChatEntry(
        id: id,
        clientMessageId: clientMessageId,
        senderId: senderId,
        mine: mine,
        content: content,
        messageType: messageType,
        fileUrl: fileUrl,
        isRead: isRead,
        sentAt: sentAt,
        sendStatus: status,
      );
}
