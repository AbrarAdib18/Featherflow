// Widget tests for the two doctor-dashboard fixes in DOCTOR_DASHBOARD_FIXES.md:
//
// 1. The navbar/app-bar profile avatar (key doctorProfileButton) used to be a
//    plain initials-only CircleAvatar that never read a photo URL at all, so
//    it could never reflect an uploaded photo. It's now a read-only
//    ProfilePhotoField wired to the same AuthService session the Profile
//    screen and welcome header already use.
// 2. Articles and Community quick-action tiles were added to the bottom of
//    the doctor dashboard's Quick Actions grid, reusing the existing
//    top-level, role-agnostic /paper-portal and /community features
//    verbatim (no new screens).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:featherflow/core/network/auth_service.dart';
import 'package:featherflow/core/widgets/profile_photo_field.dart';
import 'package:featherflow/features/doctor/presentation/screens/doctor_dashboard_screen.dart';

bool _isKnownPreexistingOverflow(FlutterErrorDetails details) =>
    details.exception is FlutterError &&
    details.exception.toString().contains('A RenderFlex overflowed');

AuthSession _sessionWithPhoto(String photoUrl) => AuthSession(
      accessToken: 'a',
      refreshToken: 'r',
      user: AuthUser(
        id: 'u1',
        email: 'vet@featherflow.dev',
        fullName: 'Dr. Fixture',
        roles: const ['doctor'],
        accountStatus: 'active',
        phone: '+8801000000000',
        presentAddress: 'Dhaka',
        dateOfBirth: '1990-01-01',
        profileData: const {},
        profilePhotoUrl: photoUrl,
      ),
    );

Future<void> _pump(WidgetTester tester, {String initial = '/doctor'}) async {
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (_isKnownPreexistingOverflow(details)) return;
    previousOnError?.call(details);
  };
  addTearDown(() => FlutterError.onError = previousOnError);

  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
          path: '/doctor', builder: (_, __) => const DoctorDashboardScreen()),
      GoRoute(
          path: '/paper-portal',
          builder: (_, __) => Scaffold(
              appBar: AppBar(title: const Text('Paper Portal')),
              body: const Text('PAPER PORTAL PLACEHOLDER'))),
      GoRoute(
          path: '/community',
          builder: (_, __) => Scaffold(
              appBar: AppBar(title: const Text('Community')),
              body: const Text('COMMUNITY PLACEHOLDER'))),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() async {
    // AuthService is a process-wide singleton — a session saved by one test
    // must not leak into the next test in this file.
    await TestWidgetsFlutterBinding.instance.runAsync(
        () => AuthService.instance.clearSession());
  });

  group('Navbar profile photo (DOCTOR_DASHBOARD_FIXES.md #1)', () {
    testWidgets(
        'the app-bar avatar button is a photo-aware ProfilePhotoField, not '
        'an initials-only CircleAvatar', (t) async {
      await _pump(t);
      expect(t.takeException(), isNull);
      final button = find.byKey(const Key('doctorProfileButton'));
      expect(button, findsOneWidget);
      // Exactly the same widget type used on the Profile screen and welcome
      // header — not a hand-rolled avatar that can drift out of sync again.
      final field = find.descendant(
          of: button, matching: find.byType(ProfilePhotoField));
      expect(field, findsOneWidget);
      final widget = t.widget<ProfilePhotoField>(field);
      expect(widget.editable, isFalse,
          reason: 'the nav button navigates on tap; it must not also pop up '
              'its own file picker/camera badge');
    });

    testWidgets('shows the uploaded photo URL from the persisted session on '
        'the very first frame (survives logout/login + app restart)',
        (t) async {
      await t.runAsync(() => AuthService.instance
          .saveSession(_sessionWithPhoto('https://cdn.example/vet.jpg')));
      await _pump(t);
      expect(t.takeException(), isNull);

      final button = find.byKey(const Key('doctorProfileButton'));
      final field = t.widget<ProfilePhotoField>(
          find.descendant(of: button, matching: find.byType(ProfilePhotoField)));
      expect(field.currentUrl, 'https://cdn.example/vet.jpg');

      // The welcome header's own avatar reads the same URL — one source of
      // truth, not a second cache that can go stale.
      final headerField = t.widgetList<ProfilePhotoField>(
          find.byType(ProfilePhotoField));
      expect(headerField.every((w) => w.currentUrl == 'https://cdn.example/vet.jpg'),
          isTrue);
    });

    testWidgets('the avatar updates after a profile photo change, without a '
        'route change or full app restart', (t) async {
      await t.runAsync(() => AuthService.instance
          .saveSession(_sessionWithPhoto('https://cdn.example/old.jpg')));
      await _pump(t);
      var button = find.byKey(const Key('doctorProfileButton'));
      var field = t.widget<ProfilePhotoField>(
          find.descendant(of: button, matching: find.byType(ProfilePhotoField)));
      expect(field.currentUrl, 'https://cdn.example/old.jpg');

      // Simulates what ProfilePhotoField._pickAndUpload does on a successful
      // upload elsewhere on screen (e.g. from the Profile screen): update the
      // shared AuthService session and notify.
      await t.runAsync(() => AuthService.instance
          .saveSession(_sessionWithPhoto('https://cdn.example/new.jpg')));
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(seconds: 1));

      button = find.byKey(const Key('doctorProfileButton'));
      field = t.widget<ProfilePhotoField>(
          find.descendant(of: button, matching: find.byType(ProfilePhotoField)));
      expect(field.currentUrl, 'https://cdn.example/new.jpg');
    });

    testWidgets('falls back to the doctor\'s initial when there is no photo '
        'yet, same as before', (t) async {
      await _pump(t);
      final button = find.byKey(const Key('doctorProfileButton'));
      final field = t.widget<ProfilePhotoField>(
          find.descendant(of: button, matching: find.byType(ProfilePhotoField)));
      expect(field.currentUrl, isEmpty);
      expect(field.fallbackInitial, isNotEmpty);
    });
  });

  group('Articles and Community quick actions (DOCTOR_DASHBOARD_FIXES.md #2)',
      () {
    testWidgets('both tiles exist at the bottom of Quick Actions', (t) async {
      await _pump(t);
      expect(t.takeException(), isNull);
      await t.scrollUntilVisible(
          find.byKey(const Key('doctorArticlesAction')), 200);
      expect(find.byKey(const Key('doctorArticlesAction')), findsOneWidget);
      expect(find.byKey(const Key('doctorCommunityAction')), findsOneWidget);
      expect(find.text('Articles'), findsOneWidget);
      expect(find.text('Community'), findsOneWidget);
    });

    testWidgets('tapping Articles navigates to the existing /paper-portal '
        'route (reused, not duplicated)', (t) async {
      await _pump(t);
      await t.scrollUntilVisible(
          find.byKey(const Key('doctorArticlesAction')), 200);
      await t.tap(find.byKey(const Key('doctorArticlesAction')));
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(seconds: 1));
      expect(find.text('PAPER PORTAL PLACEHOLDER'), findsOneWidget);
    });

    testWidgets('tapping Community navigates to the existing /community '
        'route (reused, not duplicated)', (t) async {
      await _pump(t);
      await t.scrollUntilVisible(
          find.byKey(const Key('doctorCommunityAction')), 200);
      await t.tap(find.byKey(const Key('doctorCommunityAction')));
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(seconds: 1));
      expect(find.text('COMMUNITY PLACEHOLDER'), findsOneWidget);
    });

    testWidgets('back navigation from Articles returns to the doctor '
        'dashboard (push, not go, gives the AppBar a real back button to '
        'pop back to the dashboard with)', (t) async {
      await _pump(t);
      await t.scrollUntilVisible(
          find.byKey(const Key('doctorArticlesAction')), 200);
      await t.tap(find.byKey(const Key('doctorArticlesAction')));
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(seconds: 1));
      expect(find.text('PAPER PORTAL PLACEHOLDER'), findsOneWidget);
      final backButton = find.byTooltip('Back');
      expect(backButton, findsOneWidget,
          reason: 'pushed (not .go()), so the automatic AppBar back button '
              'has a real stack entry to pop');
      await t.tap(backButton);
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(seconds: 1));
      expect(t.takeException(), isNull);
      expect(find.byKey(const Key('doctorProfileButton')), findsOneWidget);
      expect(find.text('PAPER PORTAL PLACEHOLDER'), findsNothing);
    });

    testWidgets('back navigation from Community returns to the doctor '
        'dashboard', (t) async {
      await _pump(t);
      await t.scrollUntilVisible(
          find.byKey(const Key('doctorCommunityAction')), 200);
      await t.tap(find.byKey(const Key('doctorCommunityAction')));
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(seconds: 1));
      expect(find.text('COMMUNITY PLACEHOLDER'), findsOneWidget);
      final backButton = find.byTooltip('Back');
      expect(backButton, findsOneWidget);
      await t.tap(backButton);
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(seconds: 1));
      expect(t.takeException(), isNull);
      expect(find.byKey(const Key('doctorProfileButton')), findsOneWidget);
      expect(find.text('COMMUNITY PLACEHOLDER'), findsNothing);
    });
  });
}
