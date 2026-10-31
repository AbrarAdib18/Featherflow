// Floating "Poultry & Featherflow assistant": bubble on every authenticated
// page, drag + persisted position, chat flow, loading / error / retry /
// offline / refusal states, and phone layout. The real backend and Gemini are
// never called: ChatbotService.transportOverride swaps in a fake.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:featherflow/core/network/auth_service.dart';
import 'package:featherflow/features/chatbot/data/chatbot_service.dart';
import 'package:featherflow/features/chatbot/presentation/chatbot_overlay.dart';

final _bubble = find.byKey(const Key('chatbot-bubble'));
final _panel = find.byKey(const Key('chatbot-panel'));
final _input = find.byKey(const Key('chatbot-input'));
final _send = find.byKey(const Key('chatbot-send'));

Future<void> _signIn(WidgetTester t) async {
  await t.runAsync(() => AuthService.instance.saveSession(AuthSession(
        accessToken: 'test-token',
        refreshToken: 'r',
        user: AuthUser(
          id: 'f1',
          email: 'farmer@test',
          fullName: 'Test Farmer',
          roles: const ['farmer'],
          accountStatus: 'active',
          phone: '+8801000000000',
          presentAddress: 'Dhaka',
          dateOfBirth: '1990-01-01',
          profileData: const {},
          profilePhotoUrl: '',
        ),
      )));
}

Future<void> _type(WidgetTester t, String text) async {
  await t.enterText(_input, text);
  await t.pump(); // let onChanged's setState enable the send button
}

/// Two routes, each with a "core control" button at the top-left and a scroll
/// list, hosted the same way main.dart hosts the overlay (MaterialApp builder).
Future<GoRouter> _pump(WidgetTester t,
    {Size size = const Size(1000, 800), Map<String, Object>? prefs}) async {
  SharedPreferences.setMockInitialValues(prefs ?? {});
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  late GoRouter router;
  router = GoRouter(routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => Scaffold(
        appBar: AppBar(title: const Text('Page A')),
        body: Column(children: [
          ElevatedButton(
              key: const Key('go-b'),
              onPressed: () => router.go('/b'),
              child: const Text('Go B')),
          Expanded(
              child: ListView(
                  children: [for (var i = 0; i < 60; i++) Text('row $i')])),
        ]),
      ),
    ),
    GoRoute(
      path: '/b',
      builder: (_, __) => const Scaffold(body: Center(child: Text('Page B'))),
    ),
  ]);
  await t.pumpWidget(MaterialApp.router(
    routerConfig: router,
    builder: (_, child) => ChatbotOverlay(child: child!),
  ));
  await t.pumpAndSettle();
  return router;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ChatbotService.instance.transportOverride = (m, h) async =>
        ChatReply(text: 'Echo: $m (history ${h.length})', inScope: true);
  });
  tearDown(() async {
    ChatbotService.instance.transportOverride = null;
    await AuthService.instance.clearSession();
  });

  testWidgets('hidden while signed out, shown once authenticated',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    await t.runAsync(() => AuthService.instance.clearSession());
    await _pump(t);
    expect(_bubble, findsNothing);
    await _signIn(t);
    await t.pumpAndSettle();
    expect(_bubble, findsOneWidget);
  });

  testWidgets('bubble renders on every page and defaults to the right side',
      (t) async {
    await _signIn(t);
    await _pump(t);
    expect(_bubble, findsOneWidget);
    final c = t.getCenter(_bubble);
    expect(c.dx, greaterThan(1000 / 2));
    await t.tap(find.byKey(const Key('go-b')));
    await t.pumpAndSettle();
    expect(find.text('Page B'), findsOneWidget);
    expect(_bubble, findsOneWidget);
  });

  testWidgets('does not block page controls or scrolling', (t) async {
    await _signIn(t);
    await _pump(t);
    await t.drag(find.byType(ListView).first, const Offset(0, -300));
    await t.pump();
    expect(find.text('row 0'), findsNothing); // scrolled
    await t.tap(find.byKey(const Key('go-b')));
    await t.pumpAndSettle();
    expect(find.text('Page B'), findsOneWidget);
  });

  testWidgets('drag moves the bubble, clamps to the viewport and persists',
      (t) async {
    await _signIn(t);
    await _pump(t);
    final start = t.getCenter(_bubble);
    await t.drag(_bubble, const Offset(-300, -200));
    await t.pumpAndSettle();
    final moved = t.getCenter(_bubble);
    expect(moved.dx, closeTo(start.dx - 300, 25));
    expect(moved.dy, closeTo(start.dy - 200, 25));

    // Far off-screen drag stays fully inside the viewport.
    await t.drag(_bubble, const Offset(-5000, -5000));
    await t.pumpAndSettle();
    var r = t.getRect(_bubble);
    expect(r.left, greaterThanOrEqualTo(0));
    expect(r.top, greaterThanOrEqualTo(0));
    await t.drag(_bubble, const Offset(5000, 5000));
    await t.pumpAndSettle();
    r = t.getRect(_bubble);
    expect(r.right, lessThanOrEqualTo(1000));
    expect(r.bottom, lessThanOrEqualTo(800));

    // Position is saved…
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(chatbotPositionPrefsKey), isNotNull);

    // …and restored after a fresh start.
    await t.drag(_bubble, const Offset(-400, -300));
    await t.pumpAndSettle();
    final placed = t.getCenter(_bubble);
    final saved = prefs.getStringList(chatbotPositionPrefsKey)!;
    await t.pumpWidget(const SizedBox());
    await _pump(t, prefs: {chatbotPositionPrefsKey: saved});
    expect(t.getCenter(_bubble).dx, closeTo(placed.dx, 2));
    expect(t.getCenter(_bubble).dy, closeTo(placed.dy, 2));
  });

  testWidgets('a tap does not move the bubble; it opens and closes the chat',
      (t) async {
    await _signIn(t);
    await _pump(t);
    final before = t.getCenter(_bubble);
    await t.tap(_bubble);
    await t.pumpAndSettle();
    expect(_panel, findsOneWidget);
    expect(find.text('Poultry & Featherflow assistant'), findsOneWidget);
    expect(find.byKey(const Key('chatbot-empty')), findsOneWidget);
    expect(t.getCenter(_bubble), before);

    await t.tap(find.byKey(const Key('chatbot-close')));
    await t.pumpAndSettle();
    expect(_panel, findsNothing);

    await t.tap(_bubble);
    await t.pumpAndSettle();
    expect(_panel, findsOneWidget);
    await t.tapAt(const Offset(20, 400)); // outside the panel
    await t.pumpAndSettle();
    expect(_panel, findsNothing);

    await t.tap(_bubble);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(_panel, findsNothing);
  });

  testWidgets('message send / receive keeps a short history', (t) async {
    await _signIn(t);
    await _pump(t);
    await t.tap(_bubble);
    await t.pumpAndSettle();
    await _type(t, 'How warm for chicks?');
    await t.tap(_send);
    await t.pumpAndSettle();
    expect(find.text('How warm for chicks?'), findsOneWidget);
    expect(find.textContaining('Echo: How warm for chicks?'), findsOneWidget);

    await _type(t, 'And in week two?');
    await t.tap(_send);
    await t.pumpAndSettle();
    expect(find.textContaining('(history 2)'), findsOneWidget);
  });

  testWidgets('loading state shows once and blocks duplicate requests',
      (t) async {
    final gate = Completer<ChatReply>();
    var calls = 0;
    ChatbotService.instance.transportOverride = (m, h) {
      calls++;
      return gate.future;
    };
    await _signIn(t);
    await _pump(t);
    await t.tap(_bubble);
    await t.pumpAndSettle();
    await _type(t, 'chicken feed?');
    await t.tap(_send);
    await t.pump();
    expect(find.byKey(const Key('chatbot-loading')), findsOneWidget);

    // Send is disabled mid-flight; submitting from the keyboard is ignored.
    await _type(t, 'second');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await t.pump();
    expect(calls, 1);

    gate.complete(const ChatReply(text: 'done', inScope: true));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('chatbot-loading')), findsNothing);
    expect(find.text('done'), findsOneWidget);
  });

  testWidgets('error state offers Retry which resends and recovers',
      (t) async {
    var attempt = 0;
    ChatbotService.instance.transportOverride = (m, h) async {
      attempt++;
      if (attempt == 1) {
        throw const ChatbotException('The assistant is unavailable right now.',
            code: 'server');
      }
      return ChatReply(text: 'ok: $m', inScope: true);
    };
    await _signIn(t);
    await _pump(t);
    await t.tap(_bubble);
    await t.pumpAndSettle();
    await _type(t, 'vaccination plan?');
    await t.tap(_send);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('chatbot-error')), findsOneWidget);
    expect(find.text('The assistant is unavailable right now.'), findsOneWidget);

    await t.tap(find.byKey(const Key('chatbot-retry')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('chatbot-error')), findsNothing);
    expect(find.text('ok: vaccination plan?'), findsOneWidget);
    // The user's message was not duplicated by the retry.
    expect(find.text('vaccination plan?'), findsOneWidget);
  });

  testWidgets('offline error is explained and retryable', (t) async {
    ChatbotService.instance.transportOverride = (m, h) async =>
        throw const ChatbotException(
            'You appear to be offline. Check your connection and try again.',
            code: 'offline',
            offline: true);
    await _signIn(t);
    await _pump(t);
    await t.tap(_bubble);
    await t.pumpAndSettle();
    await _type(t, 'hello chicken');
    await t.tap(_send);
    await t.pumpAndSettle();
    expect(find.textContaining('offline'), findsOneWidget);
    expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
    expect(find.byKey(const Key('chatbot-retry')), findsOneWidget);
  });

  testWidgets('missing server configuration shows an error without Retry',
      (t) async {
    ChatbotService.instance.transportOverride = (m, h) async =>
        throw const ChatbotException(
            'The AI assistant is not configured on this server.',
            code: 'not_configured',
            retryable: false);
    await _signIn(t);
    await _pump(t);
    await t.tap(_bubble);
    await t.pumpAndSettle();
    await _type(t, 'chicken');
    await t.tap(_send);
    await t.pumpAndSettle();
    expect(find.textContaining('not configured'), findsOneWidget);
    expect(find.byKey(const Key('chatbot-retry')), findsNothing);
    expect(t.takeException(), isNull); // app still alive
  });

  testWidgets('off-topic refusal is shown as a refusal message', (t) async {
    ChatbotService.instance.transportOverride = (m, h) async =>
        const ChatReply(
            text: 'I can only help with poultry farming and Featherflow.',
            inScope: false);
    await _signIn(t);
    await _pump(t);
    await t.tap(_bubble);
    await t.pumpAndSettle();
    await _type(t, 'Who won the match?');
    await t.tap(_send);
    await t.pumpAndSettle();
    expect(find.textContaining('only help with poultry'), findsOneWidget);
  });

  testWidgets('empty or whitespace input cannot be sent', (t) async {
    var calls = 0;
    ChatbotService.instance.transportOverride = (m, h) async {
      calls++;
      return const ChatReply(text: 'x', inScope: true);
    };
    await _signIn(t);
    await _pump(t);
    await t.tap(_bubble);
    await t.pumpAndSettle();
    expect(t.widget<IconButton>(_send).onPressed, isNull);
    await _type(t, '   ');
    await t.pump();
    expect(t.widget<IconButton>(_send).onPressed, isNull);
    expect(calls, 0);
  });

  testWidgets('phone layout: panel fits, leaves the top of the page usable',
      (t) async {
    await _signIn(t);
    await _pump(t, size: const Size(360, 640));
    await t.tap(_bubble);
    await t.pumpAndSettle();
    final p = t.getRect(_panel);
    expect(p.left, greaterThanOrEqualTo(0));
    expect(p.right, lessThanOrEqualTo(360));
    expect(p.bottom, lessThanOrEqualTo(640));
    expect(p.height, lessThanOrEqualTo(640 * 0.6 + 1));
    // The app bar and the "Go B" control stay uncovered and tappable.
    expect(p.top, greaterThan(150));
    await t.tap(find.byKey(const Key('chatbot-close')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('go-b')));
    await t.pumpAndSettle();
    expect(find.text('Page B'), findsOneWidget);
  });

  testWidgets('semantics: bubble is a labelled button', (t) async {
    final handle = t.ensureSemantics();
    await _signIn(t);
    await _pump(t);
    expect(find.bySemanticsLabel(RegExp('Open Poultry and Featherflow')),
        findsOneWidget);
    handle.dispose();
  });

  group('ChatbotService over HTTP', () {
    Future<Object?> run(http.Response Function(http.Request) handler,
        {bool signedIn = true}) async {
      final svc = ChatbotService.instance;
      svc.transportOverride = null;
      svc.clientFactory = () => MockClient((r) async => handler(r));
      addTearDown(() => svc.clientFactory = http.Client.new);
      try {
        return await svc.send('chicken feed?', const []);
      } on ChatbotException catch (e) {
        return e;
      }
    }

    testWidgets('sends bearer token + JSON body, returns reply', (t) async {
      await _signIn(t);
      late http.Request seen;
      final r = await t.runAsync(() => run((req) {
            seen = req;
            return http.Response(
                '{"reply":"hi","in_scope":true,"error":null}', 200);
          }));
      expect((r as ChatReply).text, 'hi');
      expect(seen.url.path, '/api/chatbot/chat/');
      expect(seen.headers['Authorization'], 'Bearer test-token');
      expect(seen.body, contains('"message":"chicken feed?"'));
      expect(seen.body.toLowerCase(), isNot(contains('gemini')));
    });

    testWidgets('maps 429, not_configured, 5xx and network failure',
        (t) async {
      await _signIn(t);
      final rate = await t.runAsync(() => run((_) => http.Response('{}', 429)));
      expect((rate as ChatbotException).code, 'rate_limited');
      final cfg = await t.runAsync(() => run((_) => http.Response(
          '{"reply":"","in_scope":false,"error":{"code":"not_configured","message":"Not configured."}}',
          503)));
      expect((cfg as ChatbotException).retryable, isFalse);
      expect(cfg.message, 'Not configured.');
      final html = await t.runAsync(
          () => run((_) => http.Response('<html>500</html>', 500)));
      expect((html as ChatbotException).message, isNot(contains('<html')));
      final off = await t.runAsync(
          () => run((_) => throw http.ClientException('Failed to fetch')));
      expect((off as ChatbotException).offline, isTrue);
    });

    testWidgets('signed-out session never calls the network', (t) async {
      await t.runAsync(() => AuthService.instance.clearSession());
      var called = false;
      final r = await t.runAsync(() => run((_) {
            called = true;
            return http.Response('{}', 200);
          }));
      expect((r as ChatbotException).code, 'signed_out');
      expect(called, isFalse);
    });
  });
}
