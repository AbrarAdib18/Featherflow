// Account-verification OTP UI (OTP_VERIFICATION_UI_FIX.md).
//
// Reported: right after signup the verification page showed the 6-digit code
// already filled in, under a "Development mode" banner. The backend returned
// the live code (`debug_code`) and the app copied it into the field. Here the
// real screen and AuthService run against a fake server: the code only
// "arrives by email", the user types it, and it is never shown or logged.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:featherflow/core/network/auth_service.dart';
import 'package:featherflow/features/auth/presentation/screens/otp_verification_screen.dart';
import 'package:featherflow/features/auth/presentation/screens/password_reset_screen.dart';

const _email = 'new.farmer@example.com';
const _masked = 'n***@example.com';
const _emailedCode = '482915'; // what the email contained; the app never receives it

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, dynamic> _session() => {
      'access': 'access-token', 'refresh': 'refresh-token', 'next': 'dashboard',
      'user': {
        'id': 'u1', 'email': _email, 'full_name': 'New Farmer', 'roles': ['farmer'],
        'account_status': 'active', 'phone': '+8801711000000', 'present_address': 'Dhaka',
        'date_of_birth': '1990-01-01',
      },
    };

/// The verify/resend endpoints. A *legacy* server also leaked `debug_code`;
/// [legacyLeak] reproduces that, to prove the app ignores it.
class _Server {
  _Server({this.legacyLeak = false});
  final bool legacyLeak;
  final confirms = <Map<String, dynamic>>[];
  final resends = <Map<String, dynamic>>[];
  Completer<void>? gate;
  int retryAfter = 0;
  Map<String, dynamic> Function(String code)? confirmReply;

  MockClient get client => MockClient((r) async {
        final body = r.body.isEmpty ? <String, dynamic>{} : jsonDecode(r.body) as Map<String, dynamic>;
        if (r.url.path.endsWith('/auth/verify/confirm/')) {
          expect(r.method, 'POST');
          confirms.add(body);
          if (gate != null) await gate!.future;
          if (body['code'] == _emailedCode) {
            final reply = confirmReply?.call(body['code']);
            return _json(reply ?? _session(), reply?['__status'] ?? 200);
          }
          return _json({
            'detail': 'That code is incorrect or has expired. Check the latest email '
                'we sent, or request a new code.',
            'code': 'invalid_code',
          }, 400);
        }
        if (r.url.path.endsWith('/auth/verify/request/') ||
            r.url.path.endsWith('/auth/password-reset/request/')) {
          resends.add(body);
          return _json({
            'detail': 'If that account exists and is unverified, a code has been sent.',
            'channel': 'email', 'resend_cooldown': 60, 'expires_in': 600,
            if (retryAfter > 0) 'retry_after': retryAfter,
            if (legacyLeak) 'debug_code': '777777',
            if (legacyLeak) 'dev_delivery': true,
          });
        }
        return _json({'detail': 'unused'}, 404);
      });
}

Future<void> _pump(WidgetTester t, Widget screen, {Size size = const Size(800, 1200)}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final router = GoRouter(initialLocation: '/verify', routes: [
    GoRoute(path: '/verify', builder: (_, __) => screen),
    GoRoute(path: '/login', builder: (_, __) => const Scaffold(body: Text('login page'))),
    GoRoute(path: '/signup/pending', builder: (_, __) => const Scaffold(body: Text('pending page'))),
    GoRoute(path: '/farmer', builder: (_, __) => const Scaffold(body: Text('farmer dashboard'))),
  ]);
  await t.pumpWidget(MaterialApp.router(routerConfig: router));
  await t.pump(const Duration(milliseconds: 100));
}

const _screen = OtpVerificationScreen(
  email: _email,
  emailMasked: _masked,
  initialMessage: 'Account created. We sent a 6-digit verification code to $_masked.',
);

TextField _field(WidgetTester t) => t.widget<TextField>(find.byType(TextField).first);

/// Puts [code] in the field and presses Verify. (Typing six digits also
/// auto-submits through the same _submit(), but in widget tests text input
/// arrives as a platform message outside the fake-HTTP zone, so tests submit
/// with the button, which runs inside it.)
Future<void> _submitCode(WidgetTester t, String code) async {
  _field(t).controller!.text = code;
  await t.pump();
  await t.tap(find.widgetWithText(ElevatedButton, 'Verify'));
}

Future<void> _settle(WidgetTester t, [int n = 4]) async {
  for (var i = 0; i < n; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// testWidgets that also captures the Flutter log (debugPrint) and fails if a
/// code ever appears in it. debugPrint is restored inside the test body, as
/// the test binding requires.
void testOtp(String name, Future<void> Function(WidgetTester t) body) {
  testWidgets(name, (t) async {
    final printed = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => printed.add(message ?? '');
    try {
      await body(t);
    } finally {
      debugPrint = original;
    }
    expect(printed.where((line) => line.contains(_emailedCode) || line.contains('777777')), isEmpty,
        reason: 'the code must never be printed to the Flutter log');
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() async {
    await TestWidgetsFlutterBinding.instance.runAsync(() => AuthService.instance.clearSession());
  });

  group('Verification page', () {
    testOtp('opens empty, no Development-mode banner, says where the code went', (t) async {
      await _pump(t, _screen);
      expect(_field(t).controller!.text, isEmpty);
      expect(find.textContaining('Development mode'), findsNothing);
      expect(find.textContaining('backend terminal'), findsNothing);
      expect(find.textContaining('filled in'), findsNothing);
      expect(find.byIcon(Icons.terminal_rounded), findsNothing);
      expect(find.text('We sent a 6-digit verification code to $_masked. It expires in 10 minutes.'),
          findsOneWidget);
      expect(find.textContaining(_email), findsNothing, reason: 'only the masked address');
      expect(find.text('Verify'), findsOneWidget);
      expect(find.textContaining('Resend code in'), findsOneWidget);
    });

    testOtp('typing the emailed code verifies and lands on the role dashboard', (t) async {
      final server = _Server();
      await http.runWithClient(() async {
        await _pump(t, _screen);
        await _submitCode(t, _emailedCode);
        await _settle(t);
        await t.pumpAndSettle();
      }, () => server.client);
      expect(server.confirms, [
        {'email': _email, 'channel': 'email', 'code': _emailedCode}
      ]);
      expect(find.text('farmer dashboard'), findsOneWidget);
    });

    testOtp('verified but awaiting review → pending page', (t) async {
      final server = _Server()
        ..confirmReply = (_) => {
              '__status': 403, 'next': 'pending_approval',
              'detail': 'Your account is awaiting review.', 'account_status': 'pending',
            };
      await http.runWithClient(() async {
        await _pump(t, _screen);
        await _submitCode(t, _emailedCode);
        await _settle(t);
        await t.pumpAndSettle();
      }, () => server.client);
      expect(find.text('pending page'), findsOneWidget);
    });

    testOtp('a wrong or expired code shows the generic error; retry with the right one', (t) async {
      final server = _Server();
      await http.runWithClient(() async {
        await _pump(t, _screen);
        await _submitCode(t, '000000');
        await _settle(t);
        expect(find.textContaining('That code is incorrect or has expired'), findsOneWidget);
        expect(find.textContaining(_emailedCode), findsNothing, reason: 'never reveals the right code');
        expect(t.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Verify')).onPressed,
            isNotNull, reason: 'button usable again');
        await _submitCode(t, _emailedCode);
        await _settle(t);
        await t.pumpAndSettle();
      }, () => server.client);
      expect(server.confirms.map((b) => b['code']), ['000000', _emailedCode]);
      expect(find.text('farmer dashboard'), findsOneWidget);
    });

    testOtp('loading state and no duplicate submission', (t) async {
      final server = _Server()..gate = Completer<void>();
      await http.runWithClient(() async {
        await _pump(t, _screen);
        await _submitCode(t, _emailedCode); // submit #1
        await t.pump();
        expect(find.byType(CircularProgressIndicator), findsWidgets, reason: 'verifying…');
        await t.tap(find.byType(ElevatedButton), warnIfMissed: false); // submit #2 (ignored)
        await t.pump();
        server.gate!.complete();
        await _settle(t);
        await t.pumpAndSettle();
      }, () => server.client);
      expect(server.confirms, hasLength(1));
    });

    testOtp('a short code is checked locally (no request)', (t) async {
      final server = _Server();
      await http.runWithClient(() async {
        await _pump(t, _screen);
        await t.enterText(find.byType(TextField).first, '123');
        await t.tap(find.widgetWithText(ElevatedButton, 'Verify'));
        await t.pump();
      }, () => server.client);
      expect(find.text('Enter the 6-digit code.'), findsOneWidget);
      expect(server.confirms, isEmpty);
    });
  });

  group('Resend', () {
    testOtp('after the cooldown: new code emailed, field stays empty even if a legacy '
        'server leaks one', (t) async {
      final server = _Server(legacyLeak: true);
      await http.runWithClient(() async {
        await _pump(t, _screen);
        expect(find.widgetWithText(TextButton, 'Resend code'), findsNothing);
        await t.pump(const Duration(seconds: 61));
        await t.tap(find.widgetWithText(TextButton, 'Resend code'));
        await _settle(t);
      }, () => server.client);
      expect(server.resends.single, {'email': _email, 'channel': 'email'});
      expect(_field(t).controller!.text, isEmpty);
      expect(find.textContaining('777777'), findsNothing);
      expect(find.textContaining('Development mode'), findsNothing);
      expect(find.textContaining('A new code was sent to $_masked'), findsOneWidget);
      expect(find.textContaining('Resend code in'), findsOneWidget, reason: 'cooldown restarted');
    });

    testOtp('server says wait (retry_after): no "sent" claim, cooldown follows it', (t) async {
      final server = _Server()..retryAfter = 42;
      await http.runWithClient(() async {
        await _pump(t, _screen);
        await t.pump(const Duration(seconds: 61));
        await t.tap(find.widgetWithText(TextButton, 'Resend code'));
        await _settle(t);
      }, () => server.client);
      expect(find.textContaining('Please wait before requesting another code'), findsOneWidget);
      expect(find.textContaining('A new code was sent'), findsNothing);
      expect(find.textContaining('Resend code in 4'), findsOneWidget);
    });
  });

  group('Password reset screen', () {
    testOtp('code step starts empty with no Development-mode banner (legacy leak ignored)',
        (t) async {
      final server = _Server(legacyLeak: true);
      await http.runWithClient(() async {
        await _pump(t, const PasswordResetScreen(initialEmail: _email));
        await t.tap(find.widgetWithText(ElevatedButton, 'Send code'));
        await _settle(t);
      }, () => server.client);
      expect(find.text('Choose a new password'), findsOneWidget);
      final codeField = t.widget<TextField>(find.descendant(
          of: find.byType(OtpCodeField), matching: find.byType(TextField)));
      expect(codeField.controller!.text, isEmpty);
      expect(find.textContaining('777777'), findsNothing);
      expect(find.textContaining('Development mode'), findsNothing);
    });
  });

  group('Layout', () {
    for (final size in const [Size(360, 740), Size(1400, 900)]) {
      testOtp('fits at ${size.width.toInt()}px', (t) async {
        await _pump(t, _screen, size: size);
        expect(t.takeException(), isNull);
        expect(find.text('Verify'), findsOneWidget);
      });
    }
  });
}
