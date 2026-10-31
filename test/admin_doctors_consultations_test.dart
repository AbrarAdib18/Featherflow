// F-001 regression (Flutter): Admin → Doctors & Patients.
//
// Drives the real AdminDoctorsScreen + AdminApiService through a mock HTTP
// client returning the JSON shapes the fixed backend produces
// (/api/admin-panel/{doctors,consultations,consultation-disputes}/), and checks:
//   * a valid appointment time renders as "<date> <time>";
//   * a missing time renders "Time not scheduled" (and "<date> · Time not
//     scheduled" for a date-only request) — not a blank/garbled string;
//   * a server error is an ERROR state with Retry, never "No doctors found.";
//   * a genuinely empty result shows the empty states;
//   * Retry reloads and recovers.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:featherflow/core/network/auth_service.dart';
import 'package:featherflow/features/admin/presentation/screens/admin_doctors_screen.dart';

const _doctor = {
  'id': 'd1', 'name': 'Dr. Fixture Vet', 'specialty': 'Poultry', 'status': 'Verified',
  'rating': 4.5, 'consultations': 2,
};

Map<String, Object?> _consult(String topic, {String? date, String? time}) => {
      'id': 'c-$topic', 'patient': 'Farmer $topic', 'doctor': 'Fixture Vet', 'topic': topic,
      'appointment_date': date, 'appointment_time': time, 'scheduled': date != null && time != null,
      'time': (date != null && time != null) ? '$date $time' : null,
      'urgent': false, 'status': 'requested',
    };

typedef _Handler = http.Response Function(String path);

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Future<void> _signIn(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  await tester.runAsync(() => AuthService.instance.saveSession(AuthSession(
        accessToken: 'a', refreshToken: 'r',
        user: AuthUser(
          id: 'admin1', email: 'admin@test', fullName: 'Doctor Admin', roles: const ['admin_doctor'],
          accountStatus: 'active', phone: '+8801000000000', presentAddress: 'Dhaka',
          dateOfBirth: '1990-01-01', profileData: const {}, profilePhotoUrl: '',
        ),
      )));
}

Future<void> _open(WidgetTester tester, _Handler handler) async {
  final router = GoRouter(initialLocation: '/admin/doctors', routes: [
    GoRoute(path: '/admin/doctors', builder: (_, __) => const AdminDoctorsScreen()),
    GoRoute(path: '/admin', builder: (_, __) => const SizedBox()),
  ]);
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Runs [body] with a mock backend. Request paths are matched on the module.
void _scenario(String name, _Handler handler, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    await _signIn(tester);
    final client = MockClient((req) async => handler(req.url.path));
    await http.runWithClient(() async {
      await _open(tester, handler);
      await body(tester);
      await tester.pumpWidget(const SizedBox()); // dispose before the zone ends
    }, () => client);
  });
}

http.Response _ok(String path, {List<Object> consults = const [], List<Object> doctors = const [_doctor]}) {
  if (path.endsWith('/doctors/')) return _json({'results': doctors});
  if (path.endsWith('/consultations/')) return _json({'results': consults});
  if (path.endsWith('/consultation-disputes/')) return _json({'results': []});
  return _json({'results': []});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  _scenario('valid appointment time is shown as date + time', (p) => _ok(p, consults: [
        _consult('Vaccination', date: '2026-10-05', time: '10:30'),
      ]), (t) async {
    await _tapTab(t, 'Consultations');
    expect(find.text('2026-10-05 10:30'), findsOneWidget);
    expect(find.text('Time not scheduled'), findsNothing);
  });

  _scenario('missing appointment time shows "Time not scheduled" (and date-only keeps the date)',
      (p) => _ok(p, consults: [
            _consult('NoSlot'),
            _consult('DateOnly', date: '2026-10-07'),
            _consult('Sched', date: '2026-10-05', time: '09:00'),
          ]), (t) async {
    await _tapTab(t, 'Consultations');
    expect(find.text('Time not scheduled'), findsOneWidget);
    expect(find.text('2026-10-07 · Time not scheduled'), findsOneWidget);
    expect(find.text('2026-10-05 09:00'), findsOneWidget);
    // All three rows are rendered (the unscheduled ones are not dropped).
    expect(find.textContaining('Farmer '), findsNWidgets(3));
    expect(find.text('No consultations yet.'), findsNothing);
  });

  _scenario('API error is an error state with Retry — never "No doctors found."', (p) {
    if (p.endsWith('/consultations/')) return http.Response('Internal Server Error', 500);
    return _ok(p);
  }, (t) async {
    // Doctors still load although the consultations endpoint failed.
    expect(find.text('Dr. Fixture Vet'), findsWidgets);
    expect(find.text('No doctors found.'), findsNothing);
    await _tapTab(t, 'Consultations');
    expect(find.text('Admin request failed (500).'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('No consultations yet.'), findsNothing);
  });

  _scenario('doctors endpoint failing shows an error, not "No doctors found."', (p) {
    if (p.endsWith('/doctors/')) return http.Response('boom', 500);
    return _ok(p);
  }, (t) async {
    expect(find.text('Admin request failed (500).'), findsWidgets);
    expect(find.text('Retry'), findsWidgets);
    expect(find.text('No doctors found.'), findsNothing);
  });

  _scenario('genuinely empty data shows the empty states', (p) => _ok(p, doctors: const []), (t) async {
    expect(find.text('No doctors found.'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    await _tapTab(t, 'Consultations');
    expect(find.text('No consultations yet.'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('Retry reloads and recovers after a server error', (tester) async {
    await _signIn(tester);
    var consultationCalls = 0;
    final client = MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/consultations/')) {
        consultationCalls++;
        if (consultationCalls == 1) return http.Response('Internal Server Error', 500);
        return _json({'results': [_consult('Recovered', date: '2026-10-05', time: '11:15')]});
      }
      return _ok(p);
    });
    await http.runWithClient(() async {
      await _open(tester, (_) => _json({}));
      await _tapTab(tester, 'Consultations');
      expect(find.text('Admin request failed (500).'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(consultationCalls, 2);
      expect(find.text('Admin request failed (500).'), findsNothing);
      expect(find.text('2026-10-05 11:15'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }, () => client);
  });
}
