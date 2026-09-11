// Widget tests for the OTP verification and self-service password-reset
// screens. No backend in the harness, so network calls fail — the screens must
// still build, validate input locally, run the resend countdown, and surface a
// clean error without the submit button getting stuck.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:featherflow/features/auth/presentation/screens/otp_verification_screen.dart';
import 'package:featherflow/features/auth/presentation/screens/password_reset_screen.dart';
import 'package:featherflow/features/auth/presentation/widgets/signup_widgets.dart';

Future<void> _pump(WidgetTester tester, Widget screen) async {
  final router = GoRouter(
    initialLocation: '/x',
    routes: [
      GoRoute(path: '/x', builder: (_, __) => screen),
      GoRoute(path: '/login', builder: (_, __) => const Scaffold(body: Text('login'))),
      GoRoute(path: '/signup/pending', builder: (_, __) => const Scaffold(body: Text('pending'))),
      GoRoute(path: '/farmer', builder: (_, __) => const Scaffold(body: Text('farmer'))),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('OTP verification screen', () {
    testWidgets('builds and shows the destination + verify button', (t) async {
      await _pump(t, const OtpVerificationScreen(
          email: 'sam@example.com', channel: 'email'));
      expect(t.takeException(), isNull);
      expect(find.text('Verify your email'), findsOneWidget);
      expect(find.textContaining('sam@example.com'), findsWidgets);
      expect(find.byType(SignupSubmitButton), findsOneWidget);
      expect(find.byType(OtpCodeField), findsOneWidget);
    });

    testWidgets('resend is on cooldown right after opening', (t) async {
      await _pump(t, const OtpVerificationScreen(
          email: 'sam@example.com', channel: 'email'));
      expect(find.textContaining('Resend code in'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Resend code'), findsNothing);
    });

    testWidgets('the code field only accepts 6 digits', (t) async {
      await _pump(t, const OtpVerificationScreen(
          email: 'sam@example.com', channel: 'email'));
      await t.enterText(find.byType(TextField).first, '12ab34cd9999');
      await t.pump();
      final field = t.widget<TextField>(find.byType(TextField).first);
      expect(field.controller!.text, '123499');
    });

    testWidgets('a short code shows a local validation error, no crash', (t) async {
      await _pump(t, const OtpVerificationScreen(
          email: 'sam@example.com', channel: 'email'));
      await t.enterText(find.byType(TextField).first, '123');
      await t.tap(find.widgetWithText(ElevatedButton, 'Verify'));
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('Enter the 6-digit code.'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('a full code submits, network fails, button recovers', (t) async {
      await _pump(t, const OtpVerificationScreen(
          email: 'sam@example.com', channel: 'email', debugCode: '654321'));
      // debugCode pre-fills the field.
      final field = t.widget<TextField>(find.byType(TextField).first);
      expect(field.controller!.text, '654321');
      await t.tap(find.widgetWithText(ElevatedButton, 'Verify'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(milliseconds: 300));
      expect(t.takeException(), isNull);
      // an error message is shown and we are still on the OTP screen
      expect(find.text('Verify your email'), findsOneWidget);
    });
  });

  group('Password reset screen', () {
    testWidgets('step 1 builds with an email field + send button', (t) async {
      await _pump(t, const PasswordResetScreen());
      expect(t.takeException(), isNull);
      expect(find.text('Forgot your password?'), findsOneWidget);
      expect(find.widgetWithText(SignupSubmitButton, 'Send code'), findsOneWidget);
    });

    testWidgets('an invalid email shows a local error', (t) async {
      await _pump(t, const PasswordResetScreen());
      await t.enterText(find.byType(TextField).first, 'not-an-email');
      await t.tap(find.widgetWithText(ElevatedButton, 'Send code'));
      await t.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('Enter the email address on your account'),
          findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('prefills the email passed in', (t) async {
      await _pump(t, const PasswordResetScreen(initialEmail: 'x@y.com'));
      final field = t.widget<TextField>(find.byType(TextField).first);
      expect(field.controller!.text, 'x@y.com');
    });
  });
}
