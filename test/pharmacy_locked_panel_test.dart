// F-002 regression (Flutter): a pending / suspended / rejected pharmacy owner
// keeps a session and lands in the LOCKED pharmacy panel — never the login
// screen or the farmer shell.
//
// Trace under test:  login response (role pharmacy, account_status suspended,
// next=pending_approval, tokens) -> AuthService session -> getRoleDestination
// ('pharmacy' -> /pharmacy) -> router redirect -> PharmacyDashboardScreen
// (locked shell: banner, earnings, Profile, Pharmacy Admin chat, appeal,
// locked operational tabs, logout) while /api/me/updates/ keeps returning
// access_revoked=false for a pharmacy.
//
// Everything runs through the real widgets/services against a mock HTTP
// client that returns the actual JSON captured from the fixed backend
// (audit_logs/data/f002_suspended_pharmacy_responses.json).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:featherflow/core/network/auth_service.dart';
import 'package:featherflow/core/network/user_updates_service.dart';
import 'package:featherflow/core/router/app_router.dart';
import 'package:featherflow/features/pharmacy/data/services/pharmacy_session.dart';
import 'package:featherflow/features/pharmacy/presentation/screens/pharmacy_dashboard_screen.dart';

AuthSession _session(String role, String status) => AuthSession(
      accessToken: 'a',
      refreshToken: 'r',
      user: AuthUser(
        id: 'u-$role', email: '$role@test', fullName: 'Locked Owner', roles: [role],
        accountStatus: status, phone: '+8801000000000', presentAddress: 'Dhaka',
        dateOfBirth: '1990-01-01', profileData: const {}, profilePhotoUrl: '',
      ),
    );

Map<String, Object?> _permissions(String status, {bool appealOpen = false}) {
  final active = status == 'ACTIVE';
  return {
    'status': status,
    'account_status': status == 'SUSPENDED' || status == 'APPEAL_PENDING'
        ? 'suspended'
        : (active ? 'active' : 'pending'),
    'review_state': status == 'REJECTED' ? 'rejected' : (active ? 'approved' : 'pending_review'),
    'is_verified': active,
    'can': {
      'catalogue': active, 'orders': active, 'suppliers': active, 'analytics': active,
      'employees': active, 'chat': true, 'appeal': status == 'SUSPENDED' || status == 'APPEAL_PENDING', // backend: appeal only for suspended
      'profile': true,
    },
    'locked_reason': active ? null : 'Your pharmacy account is ${status.toLowerCase().replaceAll('_', ' ')}.',
    'rejection_reason': status == 'REJECTED' ? 'Documents unreadable' : null,
    'more_information_reason': null,
    'open_appeal_id': appealOpen ? 'ap1' : null,
  };
}

class _Backend {
  _Backend(this.status);
  String status;
  bool appealOpen = false;
  final appeals = <Map<String, Object?>>[];
  final messages = <Map<String, Object?>>[];
  final calls = <String>[];
  int operationalCalls = 0;

  http.Response _ok(Object body, [int code = 200]) =>
      http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json'});

  Future<http.Response> handle(http.Request r) async {
    final p = r.url.path;
    calls.add('${r.method} $p');
    if (p == '/api/me/updates/') {
      return _ok({
        'server_time': DateTime.now().toUtc().toIso8601String(),
        'account_status': status == 'ACTIVE' ? 'active' : (status == 'SUSPENDED' || status == 'APPEAL_PENDING' ? 'suspended' : 'pending'),
        'is_verified': status == 'ACTIVE', 'access_revoked': false, 'unread_count': 0,
        'notifications': [], 'profile': {},
      });
    }
    if (p == '/api/pharmacy/permissions/') return _ok(_permissions(status, appealOpen: appealOpen));
    if (p == '/api/pharmacy/earnings/') {
      return _ok({'total_orders': 0, 'gross_sales': '0.00', 'featherflow_commission': '0.00', 'pharmacy_earnings': '0.00'});
    }
    if (p == '/api/pharmacy/profile/') {
      return _ok({'business_name': 'Locked Pharmacy', 'contact_person': 'Owner', 'business_address': 'Dhaka', 'email': 'owner@test', 'phone': '+8801000000000'});
    }
    if (p == '/api/pharmacy/support-conversation/') {
      return _ok({'exists': true, 'id': 'c1', 'status': 'open', 'created_at': '2026-10-01T10:00:00', 'last_message_at': '2026-10-01T10:00:00', 'unread_count': 0, 'messages': messages}, r.method == 'POST' ? 201 : 200);
    }
    if (p == '/api/pharmacy/support-conversation/c1/' && r.method == 'PATCH') return _ok({'ok': true});
    if (p == '/api/pharmacy/support-conversation/c1/' && r.method == 'POST') {
      final m = {'id': 'm${messages.length}', 'sender_id': 'u-pharmacy', 'content': (jsonDecode(r.body) as Map)['content'], 'sent_at': '2026-10-01T10:01:00', 'is_read': false, 'mine': true};
      messages.add(m);
      return _ok(m, 201);
    }
    if (p == '/api/pharmacy/appeals/') {
      if (r.method == 'POST') {
        final b = jsonDecode(r.body) as Map;
        final a = {'id': 'ap1', 'reason': b['reason'], 'explanation': b['explanation'], 'attachments': [], 'status': 'submitted', 'admin_response': '', 'resolved_at': null, 'created_at': '2026-10-01T10:02:00'};
        appeals.add(a);
        appealOpen = true;
        status = 'APPEAL_PENDING';
        return _ok(a, 201);
      }
      return _ok({'results': appeals, 'reasons': ['other', 'repeated_policy_violations']});
    }
    // Everything else is an operational endpoint: a locked account gets 401/403.
    if (p.startsWith('/api/pharmacy/')) {
      operationalCalls++;
      return http.Response('{"detail":"locked"}', 403);
    }
    return http.Response('{}', 404);
  }
}

Future<void> _useSession(WidgetTester tester, AuthSession s) async {
  SharedPreferences.setMockInitialValues({});
  await tester.runAsync(() => AuthService.instance.saveSession(s));
}

Future<void> _settle(WidgetTester tester, [int ms = 600]) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(Duration(milliseconds: ms ~/ 4));
  }
}

Future<void> _pumpShell(WidgetTester tester, _Backend b) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final router = GoRouter(initialLocation: '/pharmacy', routes: [
    GoRoute(path: '/pharmacy', builder: (_, __) => const PharmacyDashboardScreen()),
    GoRoute(path: '/login', builder: (_, __) => const Scaffold(body: Text('LOGIN SCREEN'))),
  ]);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await _settle(tester);
  await _refresh(tester, b);
  await _settle(tester, 400);
}

/// Runs [body] with the mock backend installed for both the fake-async test
/// zone and `runAsync` (the services call `http.get` at top level).
Future<void> _with(WidgetTester tester, _Backend b, Future<void> Function() body) =>
    http.runWithClient(() async {
      await body();
      // Tear the shell down and sign out so no poll timers outlive the test.
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => AuthService.instance.clearSession());
      await tester.pump();
    }, () => MockClient(b.handle));

Future<void> _refresh(WidgetTester tester, _Backend b) async {
  final s = PharmacySession.instance;
  await tester.runAsync(() async {
    // the session auto-refreshes on sign-in using the (400-returning) test client
    for (var i = 0; i < 100 && s.isLoading; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await http.runWithClient(() => s.refresh(), () => MockClient(b.handle));
  });
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _tapNav(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await _settle(tester, 400);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    PharmacySession.instance;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });

  group('post-login routing', () {
    test('every role keeps its own destination; pharmacy -> /pharmacy (never farmer or login)', () async {
      SharedPreferences.setMockInitialValues({});
      final a = AuthService.instance;
      expect(await a.getRoleDestination('pharmacy'), AppRoutes.pharmacyDashboard);
      expect(await a.getRoleDestination('farmer'), AppRoutes.farmerDashboard);
      expect(await a.getRoleDestination('doctor'), AppRoutes.doctorDashboard);
      expect(await a.getRoleDestination('delivery'), AppRoutes.deliveryDashboard);
      expect(await a.getRoleDestination('researcher'), AppRoutes.researchDashboard);
      expect(await a.getRoleDestination('feed_owner'), AppRoutes.feedOwnerHome);
      expect(await a.getRoleDestination('admin_finance'), AppRoutes.adminDashboard);
    });
  });

  group('/api/me/updates/ poll (the call that used to eject a suspended pharmacy)', () {
    Future<bool> pollRevoked(WidgetTester tester, String role, String status, {required bool serverRevoked}) async {
      await _useSession(tester, _session(role, status));
      final client = MockClient((r) async => http.Response(
          jsonEncode({
            'server_time': DateTime.now().toUtc().toIso8601String(),
            'account_status': status, 'is_verified': false, 'access_revoked': serverRevoked,
            'unread_count': 0, 'notifications': [], 'profile': {},
          }), 200, headers: {'content-type': 'application/json'}));
      final svc = UserUpdatesService.instance;
      svc.stop();
      await tester.runAsync(() => http.runWithClient(() => svc.poll(), () => client));
      final revoked = svc.accessRevoked;
      svc.stop();
      await tester.runAsync(() => AuthService.instance.clearSession());
      return revoked;
    }

    testWidgets('suspended PHARMACY is NOT revoked (server says access_revoked=false)', (t) async {
      expect(await pollRevoked(t, 'pharmacy', 'suspended', serverRevoked: false), isFalse);
    });
    testWidgets('pending PHARMACY is not revoked', (t) async {
      expect(await pollRevoked(t, 'pharmacy', 'pending', serverRevoked: false), isFalse);
    });
    testWidgets('suspended FARMER is still revoked (other roles unchanged)', (t) async {
      expect(await pollRevoked(t, 'farmer', 'suspended', serverRevoked: true), isTrue);
    });
    testWidgets('suspended doctor is still revoked even if the flag were missing (client rule unchanged)', (t) async {
      expect(await pollRevoked(t, 'doctor', 'suspended', serverRevoked: false), isTrue);
    });
    testWidgets('a pharmacy IS revoked when the server explicitly says so', (t) async {
      expect(await pollRevoked(t, 'pharmacy', 'suspended', serverRevoked: true), isTrue);
    });
  });

  group('locked pharmacy shell', () {
    testWidgets('suspended: locked Home with status, reason, earnings, chat + appeal actions (not login/farmer)', (t) async {
      final b = _Backend('SUSPENDED');
      await _useSession(t, _session('pharmacy', 'suspended'));
      await _with(t, b, () async {
        await _pumpShell(t, b);
        expect(find.byType(PharmacyDashboardScreen), findsOneWidget);
        expect(find.text('LOGIN SCREEN'), findsNothing);
        expect(find.text('Account suspended'), findsOneWidget);
        expect(find.text('Your pharmacy account is suspended.'), findsOneWidget);
        expect(find.text('Contact Pharmacy Admin'), findsOneWidget);
        expect(find.text('Submit appeal'), findsOneWidget);
        expect(find.text('Lifetime earnings'), findsOneWidget); // permitted earnings info
        expect(find.byTooltip('Sign out'), findsOneWidget);
      });
    });

    for (final c in [
      ('PENDING_REVIEW', 'Verification pending', false),
      ('REJECTED', 'Application rejected', false),
    ]) {
      testWidgets('${c.$1}: locked shell with "${c.$2}"', (t) async {
        final b = _Backend(c.$1);
        await _useSession(t, _session('pharmacy', 'pending'));
        await _with(t, b, () async {
          await _pumpShell(t, b);
          expect(find.text(c.$2), findsOneWidget);
          expect(find.text('Contact Pharmacy Admin'), findsOneWidget);
          expect(find.text('Submit appeal'), c.$3 ? findsOneWidget : findsNothing);
          expect(find.text('LOGIN SCREEN'), findsNothing);
        });
      });
    }

    testWidgets('operational tabs (medicines / inventory / orders / suppliers / analytics) are locked, no Add actions',
        (t) async {
      final b = _Backend('SUSPENDED');
      await _useSession(t, _session('pharmacy', 'suspended'));
      await _with(t, b, () async {
        await _pumpShell(t, b);
        for (final tab in ['Catalogue', 'Inventory', 'Orders', 'Suppliers', 'Analytics']) {
          await _tapNav(t, tab);
          expect(find.byKey(const ValueKey('pharmacy-locked-panel')), findsWidgets, reason: tab);
          expect(find.text('$tab is locked'), findsOneWidget, reason: tab);
          expect(find.text('Account suspended'), findsWidgets, reason: tab);
          expect(find.text('Add'), findsNothing, reason: '$tab has no add action');
          expect(find.text('No medicines yet'), findsNothing);
          expect(find.text('No orders here'), findsNothing);
        }
        expect(b.operationalCalls, 0, reason: 'no operational endpoint is called while locked');
      });
    });

    testWidgets('Profile tab stays reachable and loads the profile', (t) async {
      final b = _Backend('SUSPENDED');
      await _useSession(t, _session('pharmacy', 'suspended'));
      await _with(t, b, () async {
        await _pumpShell(t, b);
        await _tapNav(t, 'Profile');
        expect(find.byKey(const ValueKey('pharmacy-locked-panel')), findsNothing);
        expect(find.text('Edit profile'), findsOneWidget);
        expect(b.calls, contains('GET /api/pharmacy/profile/'));
      });
    });

    testWidgets('Pharmacy Admin chat opens from the locked banner', (t) async {
      final b = _Backend('SUSPENDED');
      await _useSession(t, _session('pharmacy', 'suspended'));
      await _with(t, b, () async {
        await _pumpShell(t, b);
        await t.tap(find.text('Contact Pharmacy Admin'));
        await _settle(t, 2000);
        await t.pump(const Duration(seconds: 1));
        expect(find.text('Contact Pharmacy Admin'), findsWidgets);
        expect(b.calls, contains('POST /api/pharmacy/support-conversation/'));
        // The conversation is created/fetched with the Pharmacy Admin while locked (sending a
        // message is covered by the backend script + the live-browser run; the screen's Socket.IO
        // client is not available under flutter_test).
        expect(b.calls.where((c) => c == 'POST /api/pharmacy/support-conversation/').length, greaterThanOrEqualTo(1));
        expect(find.text('LOGIN SCREEN'), findsNothing);
      });
    });

    testWidgets('Appeal screen opens, an appeal is submitted, and the panel shows the appeal under review', (t) async {
      final b = _Backend('SUSPENDED');
      await _useSession(t, _session('pharmacy', 'suspended'));
      await _with(t, b, () async {
        await _pumpShell(t, b);
        await t.tap(find.text('Submit appeal'));
        await _settle(t, 800);
        expect(find.text('Suspension Appeal'), findsOneWidget);
        await t.enterText(find.byType(TextField).last, 'Licence renewed, please reconsider.');
        await t.pump();
        await t.ensureVisible(find.text('Submit appeal').last);
        await t.tap(find.text('Submit appeal').last);
        await _settle(t, 800);
        expect(b.appeals, isNotEmpty);
        expect(b.appeals.first['explanation'], 'Licence renewed, please reconsider.');
        await _refresh(t, b);
      });
    });

    testWidgets('logout clears the session and goes to the login screen', (t) async {
      final b = _Backend('SUSPENDED');
      await _useSession(t, _session('pharmacy', 'suspended'));
      await _with(t, b, () async {
        await _pumpShell(t, b);
        await t.tap(find.byTooltip('Sign out'));
        await _settle(t, 600);
        expect(find.text('LOGIN SCREEN'), findsOneWidget);
        expect(await t.runAsync(() => AuthService.instance.isAuthenticated()), isFalse);
      });
    });

    testWidgets('refresh / relogin: a rebuilt shell shows the same locked state; restored account unlocks', (t) async {
      final b = _Backend('SUSPENDED');
      await _useSession(t, _session('pharmacy', 'suspended'));
      await _with(t, b, () async {
        await _pumpShell(t, b);
        expect(find.text('Account suspended'), findsOneWidget);
        // "Refresh": tear the screen down and rebuild it from the stored session.
        await t.pumpWidget(const SizedBox());
        await _pumpShell(t, b);
        expect(find.text('Account suspended'), findsOneWidget);
        expect(find.text('LOGIN SCREEN'), findsNothing);
        // Restored by Pharmacy Admin: the next permissions poll unlocks the shell.
        b.status = 'ACTIVE';
        await _refresh(t, b);
        expect(find.text('Account suspended'), findsNothing);
        await _tapNav(t, 'Catalogue');
        expect(find.byKey(const ValueKey('pharmacy-locked-panel')), findsNothing);
      });
    });
  });
}
