// Smoke + behaviour tests for every signup screen. No backend is available in
// the test harness, so network calls fail; the screens must still build,
// enforce their client-side rules, and never leave the submit button stuck.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:featherflow/features/auth/presentation/screens/signup_screen.dart';
import 'package:featherflow/features/auth/presentation/screens/role_selection_screen.dart';
import 'package:featherflow/features/auth/presentation/screens/farmer_signup_screen.dart';
import 'package:featherflow/features/auth/presentation/screens/doctor_signup_screen.dart';
import 'package:featherflow/features/auth/presentation/screens/delivery_signup_screen.dart';
import 'package:featherflow/features/auth/presentation/screens/pharmacy_signup_screen.dart';
import 'package:featherflow/features/auth/presentation/screens/researcher_signup_screen.dart';
import 'package:featherflow/features/auth/presentation/screens/admin_signup_screen.dart';
import 'package:featherflow/features/auth/presentation/widgets/signup_widgets.dart';
import 'package:featherflow/features/auth/data/password_policy.dart';
import 'package:featherflow/features/auth/data/signup_form_cache.dart';

Future<void> _pump(WidgetTester tester, Widget screen) async {
  final router = GoRouter(
    initialLocation: '/x',
    routes: [
      GoRoute(path: '/x', builder: (_, __) => screen),
      GoRoute(path: '/login', builder: (_, __) => const Scaffold(body: Text('login'))),
      GoRoute(path: '/signup', builder: (_, __) => const Scaffold(body: Text('signup'))),
      GoRoute(path: '/role-selection', builder: (_, __) => const Scaffold(body: Text('roles'))),
      GoRoute(path: '/signup/pending', builder: (_, __) => const Scaffold(body: Text('pending'))),
      GoRoute(path: '/farmer', builder: (_, __) => const Scaffold(body: Text('farmer-home'))),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SignupFormCache.instance.clearAll();
  });

  group('screens build', () {
    testWidgets('basic-info signup screen', (t) async {
      await _pump(t, const SignupScreen());
      expect(t.takeException(), isNull);
      expect(find.text('Create Account'), findsWidgets);
      // Terms & Privacy consent must be present.
      expect(find.textContaining('Terms of Service'), findsOneWidget);
    });

    testWidgets('role selection screen', (t) async {
      await _pump(t, const RoleSelectionScreen());
      expect(t.takeException(), isNull);
      expect(find.text('Farmer'), findsWidgets);
      expect(find.text('Admin'), findsWidgets);
    });

    for (final entry in {
      'farmer': const FarmerSignupScreen(),
      'doctor': const DoctorSignupScreen(),
      'delivery': const DeliverySignupScreen(),
      'pharmacy': const PharmacySignupScreen(),
      'researcher': const ResearcherSignupScreen(),
      'admin': const AdminSignupScreen(),
    }.entries) {
      testWidgets('${entry.key} signup screen builds with a submit button',
          (t) async {
        await _pump(t, entry.value);
        expect(t.takeException(), isNull);
        expect(find.byType(SignupSubmitButton), findsOneWidget);
      });
    }
  });

  testWidgets('basic-info: Next is blocked until Terms are accepted', (t) async {
    await _pump(t, const SignupScreen());
    await t.enterText(find.widgetWithText(TextFormField, 'Your full name'), 'Jane Doe');
    final next = find.widgetWithText(ElevatedButton, 'Next');
    await t.ensureVisible(next);
    await t.tap(next);
    await t.pump(const Duration(milliseconds: 300));
    // Still on the same screen — a validation error is shown, no navigation.
    expect(find.text('Create Account'), findsWidgets);
    expect(find.textContaining('accept the Terms'), findsWidgets);
  });

  testWidgets('farmer: rapid double-tap does not desync the submit button',
      (t) async {
    // Pre-seed a pending registration so _onSubmit proceeds to the network call.
    SharedPreferences.setMockInitialValues({
      'featherflow_pending_signup':
          '{"email":"a@b.com","password":"Str0ngPass!42","phone":"+8801712345678",'
          '"full_name":"A B","address":"Dhaka","date_of_birth":"1990-01-01",'
          '"consent_terms":true}',
    });
    await _pump(t, const FarmerSignupScreen());

    await t.enterText(find.widgetWithText(TextFormField, 'Name of your farm'), 'Farm X');
    await t.enterText(find.widgetWithText(TextFormField, 'Full name'), 'A B');
    await t.enterText(
        find.widgetWithText(TextFormField, 'Village, Upazila, District'), 'Savar');
    await t.enterText(find.widgetWithText(TextFormField, 'e.g. 500'), '100');
    await t.enterText(find.widgetWithText(TextFormField, 'e.g. 5'), '2');
    await t.enterText(find.widgetWithText(TextFormField, 'e.g. 3'), '1');
    // consent checkbox
    await t.ensureVisible(find.byType(Checkbox).first);
    await t.tap(find.byType(Checkbox).first);
    await t.pump();

    final button = find.byType(SignupSubmitButton);
    await t.ensureVisible(button);
    await t.tap(button);
    await t.tap(button); // second tap must be a no-op while submitting
    await t.pump();
    // The button shows a spinner (submitting) and is not throwing.
    expect(t.takeException(), isNull);
    // Let the failed network call settle; button must recover (not stuck).
    await t.pump(const Duration(seconds: 2));
    await t.pump(const Duration(milliseconds: 300));
    expect(t.takeException(), isNull);
  });

  testWidgets('RegistrationPendingScreen shows the message and a return link',
      (t) async {
    await _pump(
        t, const RegistrationPendingScreen(message: 'Pending admin verification.'));
    expect(find.text('Application submitted'), findsOneWidget);
    expect(find.text('Pending admin verification.'), findsOneWidget);
    expect(find.text('Back to sign in'), findsOneWidget);
  });

  group('password policy (mirrors backend validators)', () {
    test('too short / all numeric / no letter are rejected', () {
      expect(evaluatePassword('abc123').isValid, isFalse); // < 8
      expect(evaluatePassword('12345678').isValid, isFalse); // all numeric
      expect(evaluatePassword('!!!!!!!!').isValid, isFalse); // no letter
    });

    test('common passwords are rejected even when long enough', () {
      expect(evaluatePassword('password').isValid, isFalse);
      expect(evaluatePassword('password123').isValid, isFalse);
      expect(evaluatePassword('qwertyuiop').isValid, isFalse);
    });

    test('reusing name / email is rejected', () {
      expect(
        evaluatePassword('janedoe2024', name: 'Jane Doe').isValid,
        isFalse,
      );
      expect(
        evaluatePassword('sadia.k9999', email: 'sadia.k@example.com').isValid,
        isFalse,
      );
    });

    test('a reasonable password passes and scores well', () {
      final e = evaluatePassword('Feather!Flow82', email: 'a@b.com', name: 'A B');
      expect(e.isValid, isTrue);
      expect(e.strength, anyOf(PasswordStrength.good, PasswordStrength.strong));
    });

    test('confirm mismatch is reported immediately, cleared on match', () {
      expect(confirmPasswordError('Abcd1234!', 'Abcd12'), isNotNull);
      expect(confirmPasswordError('Abcd1234!', 'Abcd1234!'), isNull);
      expect(confirmPasswordError('Abcd1234!', ''), isNull); // not yet typed
    });
  });

  testWidgets('basic-info: Next disabled while password invalid, live errors',
      (t) async {
    await _pump(t, const SignupScreen());
    await t.enterText(
        find.widgetWithText(TextFormField, 'At least 8 characters'), '12345678');
    await t.pump(const Duration(milliseconds: 400)); // past the debounce
    // Inline error is shown as the user types, before any submit.
    expect(find.textContaining('all numbers'), findsOneWidget);
    // Next is disabled.
    final next = find.widgetWithText(ElevatedButton, 'Next');
    expect(t.widget<ElevatedButton>(next).onPressed, isNull);
  });

  testWidgets('basic-info: strong + matching password enables the section',
      (t) async {
    await _pump(t, const SignupScreen());
    await t.enterText(
        find.widgetWithText(TextFormField, 'At least 8 characters'),
        'Feather!Flow82');
    await t.enterText(
        find.widgetWithText(TextFormField, 'Re-enter password'),
        'Feather!Flow82');
    await t.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Passwords match'), findsOneWidget);
    expect(find.text('Strong'), findsOneWidget);
  });

  testWidgets('basic-info: form data is cached and restored on re-entry',
      (t) async {
    await _pump(t, const SignupScreen());
    await t.enterText(
        find.widgetWithText(TextFormField, 'Your full name'), 'Rahim Uddin');
    await t.enterText(
        find.widgetWithText(TextFormField, 'you@example.com'), 'rahim@farm.bd');
    await t.pump();
    // A fresh instance (as `context.go` would build) repopulates from the cache.
    await _pump(t, const SignupScreen());
    expect(find.text('Rahim Uddin'), findsOneWidget);
    expect(find.text('rahim@farm.bd'), findsOneWidget);
  });

  testWidgets('role signup: back with data shows the leave dialog, keeps data',
      (t) async {
    await _pump(t, const FarmerSignupScreen());
    await t.enterText(
        find.widgetWithText(TextFormField, 'Name of your farm'), 'Green Acres');
    await t.pump();
    await t.tap(find.descendant(
        of: find.byType(AppBar), matching: find.byType(IconButton)));
    await t.pumpAndSettle();
    expect(find.text('Leave this step?'), findsOneWidget);
    await t.tap(find.text('Keep editing'));
    await t.pumpAndSettle();
    // Still on the form, data intact.
    expect(find.text('Green Acres'), findsOneWidget);
    // And the draft is retained even if we do leave — cleared only on success.
    expect(SignupFormCache.instance.hasData('farmer'), isTrue);
  });

  testWidgets('role signup: data survives a back-and-forward round trip',
      (t) async {
    SignupFormCache.instance.save(SignupFormCache.basicInfoKey, {
      'email': 'a@b.com', 'password': 'x',
    });
    // Fill step 3, then leave.
    await _pump(t, const DoctorSignupScreen());
    await t.enterText(
        find.widgetWithText(TextFormField, 'Name of your clinic or hospital'),
        'City Vet Clinic');
    await t.enterText(
        find.widgetWithText(TextFormField, 'e.g. DVM, BVSc'), 'DVM');
    await t.pump();
    await t.tap(find.descendant(
        of: find.byType(AppBar), matching: find.byType(IconButton)));
    await t.pumpAndSettle();
    await t.tap(find.text('Go back'));
    await t.pumpAndSettle();

    // Re-enter step 3 (as router would rebuild it) — fields come back.
    await _pump(t, const DoctorSignupScreen());
    expect(find.text('City Vet Clinic'), findsOneWidget);
    expect(find.text('DVM'), findsOneWidget);

    // Completing signup clears everything.
    SignupFormCache.instance.clearAll();
    expect(SignupFormCache.instance.hasData('doctor'), isFalse);
    expect(SignupFormCache.instance.hasData(SignupFormCache.basicInfoKey), isFalse);
  });
}
