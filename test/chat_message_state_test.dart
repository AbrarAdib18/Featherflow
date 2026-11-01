// Chat duplicate-bubble + timestamp regressions (CHAT_MESSAGE_STATE_FIX.md).
//
// Reported (doctor -> farmer.rashed, conversation 8f906e79-…): one tap on Send
// rendered "hello 4:48 PM" AND "hello 10:48 AM" — one DB row (4ff3d38e-…,
// sent_at 10:48:20 UTC). The Socket.IO echo beat the REST response and was
// appended next to the optimistic bubble, and server times were displayed as
// UTC wall clock (6 h early in Dhaka).
//
// Network tests run the real send code against a fake server
// (`http.runWithClient` + MockClient) — no mock data in the app.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:featherflow/core/chat/chat_core.dart';
import 'package:featherflow/core/network/auth_service.dart';
import 'package:featherflow/core/network/realtime_chat_service.dart';
import 'package:featherflow/features/doctor/data/models/doctor_models.dart';
import 'package:featherflow/features/doctor/data/services/doctor_session.dart';
import 'package:featherflow/features/doctor/presentation/screens/doctor_messenger_screen.dart';
import 'package:featherflow/features/farmer/presentation/screens/farmer_consultations_screen.dart';

const _sentUtc = '2026-10-30T10:48:20.203851+00:00';
final _sentInstant = DateTime.utc(2026, 10, 30, 10, 48, 20, 203, 851);

AuthSession _session(String userId) => AuthSession(
      accessToken: 'a',
      refreshToken: 'r',
      user: AuthUser(
        id: userId,
        email: '$userId@featherflow.dev',
        fullName: 'Chat Fixture',
        // Not 'doctor': a doctor session would start DoctorSession's own
        // login refresh + notification timer, which these tests don't need.
        roles: const ['tester'],
        accountStatus: 'active',
        phone: '+8801000000000',
        presentAddress: 'Dhaka',
        dateOfBirth: '1990-01-01',
        profileData: const {},
      ),
    );

/// A server message as the API returns it.
Map<String, dynamic> _server(String id, String content,
        {String? clientId, String sender = 'doc-user', String sentAt = _sentUtc}) =>
    {
      'id': id,
      'client_message_id': clientId,
      'conversation_id': 't1',
      'sender_id': sender,
      'content': content,
      'message_type': 'text',
      'type': 'text',
      'file_url': null,
      'is_read': false,
      'sent_at': sentAt,
    };

ChatEntry _entry(String id, {String? clientId, DateTime? at,
        ChatSendStatus status = ChatSendStatus.sent}) =>
    ChatEntry(
        id: id,
        clientMessageId: clientId,
        mine: true,
        content: id,
        sentAt: at ?? _sentInstant.toLocal(),
        sendStatus: status);

Map<String, dynamic> _bodyOf(http.Request r) =>
    r.body.isEmpty ? {} : Map<String, dynamic>.from(jsonDecode(r.body) as Map);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() async {
    await TestWidgetsFlutterBinding.instance
        .runAsync(() => AuthService.instance.clearSession());
  });

  group('Server time parsing + display', () {
    test('UTC ISO with offset parses to the same instant, in local time', () {
      final t = ChatTime.parseServer(_sentUtc)!;
      expect(t.isUtc, isFalse, reason: 'displayed in the viewer zone');
      expect(t.isAtSameMomentAs(_sentInstant), isTrue);
    });

    test('a naive server value is UTC wall clock, not local time (the bug)', () {
      final naive = ChatTime.parseServer('2026-10-30T10:48:20.203851')!;
      expect(naive.isAtSameMomentAs(_sentInstant), isTrue);
      expect(ChatTime.parseServer('2026-10-30T10:48:20Z')!
          .isAtSameMomentAs(DateTime.utc(2026, 10, 30, 10, 48, 20)), isTrue);
      expect(ChatTime.parseServer(null), isNull);
      expect(ChatTime.parseServer('null'), isNull);
    });

    test('the screenshot message shows its real local send time', () {
      final local = _sentInstant.toLocal();
      final shown = ChatTime.format(ChatTime.parseServer(_sentUtc)!, now: local);
      expect(shown, DateFormat('h:mm a').format(local),
          reason: 'e.g. 4:48 PM in Dhaka, not the UTC 10:48 AM');
      final naiveShown = ChatTime.format(
          ChatTime.parseServer('2026-10-30T10:48:20.203851')!, now: local);
      expect(naiveShown, shown, reason: 'list rows and echoes agree');
    });

    test('today / yesterday / weekday / older formats', () {
      final now = DateTime(2026, 10, 30, 17, 0);
      expect(ChatTime.format(DateTime(2026, 10, 30, 16, 52), now: now), '4:52 PM');
      expect(ChatTime.format(DateTime(2026, 10, 29, 19, 29), now: now),
          'Yesterday, 7:29 PM');
      expect(ChatTime.format(DateTime(2026, 10, 26, 9, 5), now: now), 'Mon, 9:05 AM');
      expect(ChatTime.format(DateTime(2026, 9, 29, 22, 37), now: now),
          '29 Sep 2026, 10:37 PM');
    });

    test('a just-sent message is never shown in the future (clock skew)', () {
      final now = DateTime(2026, 10, 30, 16, 52);
      expect(ChatTime.format(now.add(const Duration(minutes: 2)), now: now),
          '4:52 PM');
    });

    test('client message ids are unique RFC 4122 v4 UUIDs', () {
      final ids = List.generate(500, (_) => newClientMessageId());
      expect(ids.toSet().length, 500);
      final v4 = RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
      expect(ids.every(v4.hasMatch), isTrue);
    });
  });

  group('ChatTimeline (shared by every chat screen)', () {
    test('echo BEFORE response: one bubble (the reported race)', () {
      final pending = ChatEntry.pending('hello', clientMessageId: 'c1');
      var list = ChatTimeline.upsert(<ChatEntry>[], pending);
      final server = ChatEntry.fromServer(
          _server('s1', 'hello', clientId: 'c1'), myUserId: 'doc-user');
      list = ChatTimeline.upsert(list, server); // socket echo
      expect(list.map((m) => m.id), ['s1'],
          reason: 'the echo replaces the optimistic bubble at once — no '
              'double bubble while the REST response is still in flight');
      list = ChatTimeline.upsert(list, server, replacingClientId: 'c1'); // REST
      expect(list.map((m) => m.id), ['s1']);
      expect(list.single.sendStatus, ChatSendStatus.sent);
    });

    test('response BEFORE echo, then a poll: still one bubble', () {
      var list = ChatTimeline.upsert(
          <ChatEntry>[], ChatEntry.pending('hello', clientMessageId: 'c1'));
      final server = ChatEntry.fromServer(_server('s1', 'hello', clientId: 'c1'));
      list = ChatTimeline.upsert(list, server, replacingClientId: 'c1');
      list = ChatTimeline.upsert(list, server);
      list = ChatTimeline.reconcile([server], list);
      expect(list.map((m) => m.id), ['s1']);
    });

    test('confirmation replaces the provisional time with the server time', () {
      final pending = ChatEntry.pending('hello', clientMessageId: 'c1');
      final list = ChatTimeline.upsert([pending],
          ChatEntry.fromServer(_server('s1', 'hello', clientId: 'c1')),
          replacingClientId: 'c1');
      expect(list.single.sentAt.isAtSameMomentAs(_sentInstant), isTrue);
    });

    test('an older server without client ids is matched via replacingClientId',
        () {
      final list = ChatTimeline.upsert(
          [ChatEntry.pending('hello', clientMessageId: 'c1')],
          ChatEntry.fromServer(_server('s1', 'hello')),
          replacingClientId: 'c1');
      expect(list.map((m) => m.id), ['s1']);
    });

    test('overlapping pages merge by id, in time order', () {
      final t0 = DateTime(2026, 10, 30, 10);
      final a = _entry('a', at: t0);
      final b = _entry('b', at: t0.add(const Duration(minutes: 1)));
      final c = _entry('c', at: t0.add(const Duration(minutes: 2)));
      final merged = ChatTimeline.mergePage(
          ChatTimeline.mergePage(<ChatEntry>[], [b, c]), [a, b]);
      expect(merged.map((m) => m.id), ['a', 'b', 'c']);
    });

    test('refresh keeps unsent local messages, drops nothing, duplicates nothing',
        () {
      final t0 = DateTime(2026, 10, 30, 10);
      final sent = _entry('s1', clientId: 'c1', at: t0);
      final failed = _entry('c2', clientId: 'c2',
          at: t0.add(const Duration(minutes: 1)), status: ChatSendStatus.failed);
      final sending = _entry('c3', clientId: 'c3',
          at: t0.add(const Duration(minutes: 2)), status: ChatSendStatus.sending);
      final stale = _entry('s0', at: t0.subtract(const Duration(minutes: 1)));
      final result = ChatTimeline.reconcile([sent], [stale, sent, failed, sending]);
      expect(result.map((m) => m.id), ['s1', 'c2', 'c3'],
          reason: 'server list wins; only unconfirmed local entries are kept');
    });

    test('refresh never changes a persisted timestamp', () {
      final server = ChatEntry.fromServer(_server('s1', 'hello'));
      final again = ChatTimeline.reconcile(
          [ChatEntry.fromServer(_server('s1', 'hello'))], [server]);
      expect(again.single.sentAt, server.sentAt);
    });

    test('ties in time keep a stable order', () {
      final t = DateTime(2026, 10, 30, 10);
      expect(ChatTimeline.sorted([_entry('b', at: t), _entry('a', at: t)])
          .map((m) => m.id), ['a', 'b']);
    });
  });

  group('Doctor messenger', () {
    late List<http.Request> posts;
    late Completer<void>? gate;
    late bool echoFirst;
    late int failuresLeft;
    late List<int> helloCountAfterEcho;

    MockClient server() => MockClient((request) async {
          if (request.method == 'POST' && request.url.path.contains('/conversations/t1')) {
            posts.add(request);
            final body = _bodyOf(request);
            if (gate != null) await gate!.future;
            if (failuresLeft > 0) {
              failuresLeft--;
              return http.Response(jsonEncode({'detail': 'Server unavailable.'}), 503);
            }
            final msg = _server('s-${posts.length}', '${body['content']}',
                clientId: '${body['client_message_id']}');
            // The server broadcasts while handling the POST, so the echo can
            // land before the response — exactly what duplicated the bubble.
            if (echoFirst) {
              DoctorSession.instance.debugReceiveRealtime('t1', msg);
              helloCountAfterEcho.add(DoctorSession.instance.chatThreads
                  .firstWhere((x) => x.id == 't1')
                  .messages
                  .where((m) => m.content == body['content'])
                  .length);
            }
            return http.Response(jsonEncode({...msg, 'from_me': true, 'from_doctor': true}), 201);
          }
          return http.Response('{}', 404);
        });

    Future<void> pump(WidgetTester t) async {
      await t.runAsync(() => AuthService.instance.saveSession(_session('doc-user')));
      DoctorSession.instance.debugLoadConversationsPayload({
        'conversations': [
          {
            'id': 't1', 'farmer_name': 'Md. Rashed Karim', 'farm_name': 'Rashed Poultry Farm',
            'case_id': null, 'last_message': 'hi', 'last_message_at': '2026-10-29T19:29:24+00:00',
            'unread_count': 0,
            'messages': [
              {..._server('f1', 'hi', sender: 'farmer-user', sentAt: '2026-10-29T19:29:24+00:00'),
                'from_doctor': false, 'from_me': false},
            ],
          }
        ]
      });
      await t.pumpWidget(const MaterialApp(home: DoctorChatScreen(threadId: 't1')));
    }

    List<ChatMessage> messages() =>
        DoctorSession.instance.chatThreads.firstWhere((x) => x.id == 't1').messages;

    setUp(() {
      posts = [];
      gate = null;
      echoFirst = false;
      failuresLeft = 0;
      helloCountAfterEcho = [];
    });

    testWidgets('one tap -> one API call -> one bubble, even when the echo '
        'beats the response', (t) async {
      echoFirst = true;
      await http.runWithClient(() async {
        await pump(t);
        await t.enterText(find.byType(TextField), 'hello');
        await t.tap(find.byKey(const Key('doctorChatSend')));
        await t.pumpAndSettle();
      }, server);
      expect(posts, hasLength(1));
      expect(helloCountAfterEcho, [1],
          reason: 'one bubble even before the REST response arrives');
      expect(find.text('hello'), findsOneWidget);
      expect(messages().where((m) => m.content == 'hello'), hasLength(1));
      final sent = messages().firstWhere((m) => m.content == 'hello');
      expect(sent.status, ChatSendStatus.sent);
      expect(sent.sentAt.isAtSameMomentAs(_sentInstant), isTrue,
          reason: 'server time replaced the provisional one');
      expect(find.text(ChatTime.format(sent.sentAt)), findsWidgets);
      expect(_bodyOf(posts.single)['client_message_id'], sent.clientMessageId);
    });

    testWidgets('double tap while in flight sends once', (t) async {
      gate = Completer<void>();
      await http.runWithClient(() async {
        await pump(t);
        await t.enterText(find.byType(TextField), 'hello');
        await t.tap(find.byKey(const Key('doctorChatSend')));
        await t.pump();
        expect(find.byKey(const Key('chatMessageSending')), findsOneWidget);
        await t.enterText(find.byType(TextField), 'hello');
        await t.tap(find.byKey(const Key('doctorChatSend')), warnIfMissed: false);
        await t.pump();
        gate!.complete();
        await t.pumpAndSettle();
      }, server);
      expect(posts, hasLength(1), reason: 'Send is disabled while in flight');
      expect(messages().where((m) => m.content == 'hello'), hasLength(1));
    });

    testWidgets('failed send stays visible with Retry; retry reuses the '
        'client id and yields one message', (t) async {
      failuresLeft = 1;
      await http.runWithClient(() async {
        await pump(t);
        await t.enterText(find.byType(TextField), 'hello');
        await t.tap(find.byKey(const Key('doctorChatSend')));
        await t.pumpAndSettle();
        expect(find.text('Not sent · Tap to retry'), findsOneWidget);
        expect(find.text('hello'), findsOneWidget,
            reason: 'a failed message never silently disappears');
        await t.tap(find.byKey(const Key('chatMessageRetry')));
        await t.pumpAndSettle();
      }, server);
      expect(posts, hasLength(2));
      expect(_bodyOf(posts[1])['client_message_id'],
          _bodyOf(posts[0])['client_message_id'],
          reason: 'the retry is idempotent server-side');
      expect(find.text('hello'), findsOneWidget);
      expect(find.text('Not sent · Tap to retry'), findsNothing);
    });

    testWidgets('a later echo and a refresh do not duplicate or re-time it',
        (t) async {
      await http.runWithClient(() async {
        await pump(t);
        await t.enterText(find.byType(TextField), 'hello');
        await t.tap(find.byKey(const Key('doctorChatSend')));
        await t.pumpAndSettle();
      }, server);
      final sent = messages().firstWhere((m) => m.content == 'hello');
      DoctorSession.instance.debugReceiveRealtime('t1',
          _server(sent.id, 'hello', clientId: sent.clientMessageId));
      await t.pump();
      expect(find.text('hello'), findsOneWidget);
      expect(messages().firstWhere((m) => m.content == 'hello').sentAt,
          sent.sentAt);
    });

    test('list rows parse with server time in local zone and in order', () {
      final thread = ChatThread.fromJson({
        'id': 't9', 'farmer_name': 'F', 'farm_name': 'Farm', 'unread_count': 0,
        'last_message_at': '2026-10-30T10:48:20.203851+00:00',
        'messages': [
          {..._server('b', 'second'), 'from_doctor': true},
          {..._server('a', 'first', sentAt: '2026-10-30T10:48:04.361344'), 'from_doctor': true},
        ],
      });
      expect(thread.messages.map((m) => m.id), ['a', 'b']);
      expect(thread.messages.last.sentAt.isAtSameMomentAs(_sentInstant), isTrue);
      expect(thread.lastMessageAt.isAtSameMomentAs(_sentInstant), isTrue);
    });
  });

  group('Farmer chat dialog', () {
    late List<http.Request> posts;
    late List<Map<String, dynamic>> serverRows;
    late _FakeRealtime realtime;
    late bool echoFirst;
    late int failuresLeft;

    MockClient server() => MockClient((request) async {
          if (request.method == 'POST' && request.url.path.contains('/consultations/chats/t1')) {
            posts.add(request);
            if (failuresLeft > 0) {
              failuresLeft--;
              return http.Response(jsonEncode({'detail': 'Server unavailable.'}), 503);
            }
            final body = _bodyOf(request);
            final existing = serverRows.where(
                (m) => m['client_message_id'] == body['client_message_id']);
            final msg = existing.isNotEmpty
                ? existing.first
                : _server('s-${serverRows.length + 1}', '${body['content']}',
                    clientId: '${body['client_message_id']}', sender: 'farm-user');
            if (existing.isEmpty) serverRows.add(msg);
            if (echoFirst) realtime.onMessage?.call(msg);
            return http.Response(jsonEncode({...msg, 'from_me': true}), 201);
          }
          if (request.method == 'GET' && request.url.path.contains('/consultations/chats')) {
            return http.Response(jsonEncode({
              'conversations': [
                {'id': 't1', 'messages': [
                  for (final m in serverRows) {...m, 'from_me': m['sender_id'] == 'farm-user'}
                ]}
              ]
            }), 200);
          }
          return http.Response('{}', 404);
        });

    Future<void> pump(WidgetTester t) async {
      await t.runAsync(() => AuthService.instance.saveSession(_session('farm-user')));
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FarmerChatDialog(
            realtime: realtime,
            chat: {
              'id': 't1',
              'participant_name': 'Dr. Samira Rahman',
              'messages': [for (final m in serverRows) {...m, 'from_me': false}],
            },
          ),
        ),
      ));
    }

    setUp(() {
      posts = [];
      serverRows = [_server('d1', 'hello farmer', sender: 'doc-user')];
      realtime = _FakeRealtime();
      echoFirst = false;
      failuresLeft = 0;
    });

    Future<void> close(WidgetTester t) async {
      await t.pumpWidget(const SizedBox()); // cancels the 4s poll
    }

    testWidgets('one tap -> one bubble with echo first, then a poll',
        (t) async {
      echoFirst = true;
      await http.runWithClient(() async {
        await pump(t);
        await t.enterText(find.byType(TextField), 'hi doctor');
        await t.tap(find.byKey(const Key('farmerChatSend')));
        await t.pumpAndSettle();
        expect(find.text('hi doctor'), findsOneWidget);
        await t.pump(const Duration(seconds: 4)); // poll tick
        await t.pumpAndSettle();
        expect(find.text('hi doctor'), findsOneWidget);
        expect(find.text('hello farmer'), findsOneWidget);
        await close(t);
      }, server);
      expect(posts, hasLength(1));
    });

    testWidgets('times are shown from the server timestamp', (t) async {
      await http.runWithClient(() async {
        await pump(t);
        await t.pump();
        final local = _sentInstant.toLocal();
        expect(find.text(ChatTime.format(local)), findsOneWidget);
        await close(t);
      }, server);
    });

    testWidgets('double tap sends once', (t) async {
      await http.runWithClient(() async {
        await pump(t);
        await t.enterText(find.byType(TextField), 'once');
        await t.tap(find.byKey(const Key('farmerChatSend')));
        await t.tap(find.byKey(const Key('farmerChatSend')), warnIfMissed: false);
        await t.pumpAndSettle();
        expect(find.text('once'), findsOneWidget);
        await close(t);
      }, server);
      expect(posts, hasLength(1));
    });

    testWidgets('failed send -> Retry with the same client id -> one message',
        (t) async {
      failuresLeft = 1;
      await http.runWithClient(() async {
        await pump(t);
        await t.enterText(find.byType(TextField), 'retry me');
        await t.tap(find.byKey(const Key('farmerChatSend')));
        await t.pumpAndSettle();
        expect(find.text('Not sent · Tap to retry'), findsOneWidget);
        expect(find.text('retry me'), findsOneWidget);
        await t.tap(find.byKey(const Key('chatMessageRetry')));
        await t.pumpAndSettle();
        expect(find.text('retry me'), findsOneWidget);
        expect(find.text('Not sent · Tap to retry'), findsNothing);
        await close(t);
      }, server);
      expect(posts, hasLength(2));
      expect(_bodyOf(posts[1])['client_message_id'],
          _bodyOf(posts[0])['client_message_id']);
    });

    testWidgets('a real-time message from the vet appears once', (t) async {
      await http.runWithClient(() async {
        await pump(t);
        final msg = _server('d2', 'take photos', sender: 'doc-user');
        serverRows.add(msg);
        realtime.onMessage?.call(msg);
        realtime.onMessage?.call(msg); // duplicate delivery
        await t.pump();
        await t.pump(const Duration(seconds: 4)); // and the poll
        await t.pumpAndSettle();
        expect(find.text('take photos'), findsOneWidget);
        await close(t);
      }, server);
    });
  });
}

class _FakeRealtime extends RealtimeChatService {
  @override
  Future<void> connect(String conversationId) async {}
  @override
  void markRead(String conversationId) {}
  @override
  void disconnect() {}
}
