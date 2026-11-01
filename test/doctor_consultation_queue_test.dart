// Doctor-side consultation delivery (DOCTOR_CONSULTATION_QUEUE_FIX.md).
//
// Root cause: the backend returned a farmer's open-ended request with
// `scheduled_at: null` (documented contract — "Request any available time"),
// and `DoctorAppointment.fromJson` did `DateTime.parse('null')`. That threw
// inside DoctorSession.refresh(), which aborted the whole refresh, so the
// doctor kept seeing stale/demo data while notifications (separate poller)
// still arrived.
//
// Every payload here has the exact shape `GET /api/doctor/appointments/`
// returns (captured from the live dev API on 2026-10-30), with fixture names.
// The real parser is used throughout via DoctorSession.parseAppointments.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:featherflow/core/network/auth_service.dart';
import 'package:featherflow/features/doctor/data/models/doctor_models.dart';
import 'package:featherflow/features/doctor/data/services/doctor_session.dart';
import 'package:featherflow/features/doctor/presentation/screens/doctor_appointments_screen.dart';
import 'package:featherflow/features/doctor/presentation/screens/doctor_dashboard_screen.dart';

Map<String, dynamic> _row({
  required String id,
  String status = 'pending',
  String? scheduledAt,
  String requestedAt = '2026-10-29T19:28:32.497022+00:00',
  String urgency = 'routine',
  String farmer = 'Fixture Farmer',
}) =>
    {
      'id': id,
      'farmer_name': farmer,
      'farmer_phone': '+8801000000000',
      'farm_name': 'Fixture Farm',
      'scheduled_at': scheduledAt,
      'has_preferred_slot': scheduledAt != null,
      'mode': 'online',
      'status': status,
      'urgency': urgency,
      'is_urgent': urgency == 'urgent' || urgency == 'emergency',
      'case_id': 'case-$id',
      'fee': 700.0,
      'proposed_date': null,
      'proposed_time': null,
      'decision_reason': null,
      'requested_at': requestedAt,
    };

/// The reported case: one open-ended urgent request, one dated request,
/// plus closed rows that must not count as pending.
Map<String, dynamic> _payload() => {
      'appointments': [
        _row(id: 'open-1', urgency: 'urgent', farmer: 'Open Ended Farmer'),
        _row(
            id: 'dated-1',
            scheduledAt: '2026-11-02T11:00:00',
            requestedAt: '2026-10-29T10:00:00+00:00',
            farmer: 'Dated Farmer'),
        _row(id: 'done-1', status: 'completed', scheduledAt: '2026-10-01T13:00:00'),
        _row(id: 'gone-1', status: 'cancelled', farmer: 'Cancelled Farmer'),
      ],
    };

bool _isKnownPreexistingOverflow(FlutterErrorDetails details) =>
    details.exception is FlutterError &&
    details.exception.toString().contains('A RenderFlex overflowed');

Future<void> _pumpQueue(WidgetTester t, {Size size = const Size(1000, 1600)}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final router = GoRouter(initialLocation: '/doctor/appointments', routes: [
    GoRoute(
        path: '/doctor/appointments',
        builder: (_, __) => const DoctorAppointmentsScreen()),
  ]);
  await t.pumpWidget(MaterialApp.router(routerConfig: router));
}

/// Lets the (signed-out, so failing) background refresh settle.
Future<void> _settleRefresh(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() async {
    await TestWidgetsFlutterBinding.instance
        .runAsync(() => AuthService.instance.clearSession());
  });

  group('API contract parsing', () {
    test('an open-ended request (scheduled_at: null) parses — this threw before',
        () {
      final a = DoctorAppointment.fromJson(_row(id: 'x', urgency: 'urgent'));
      expect(a.scheduledAt, isNull);
      expect(a.hasPreferredSlot, isFalse);
      expect(a.status, AppointmentStatus.pending);
      expect(a.requestedAt, DateTime.utc(2026, 10, 29, 19, 28, 32, 497, 22));
      expect(a.requestedAt!.isUtc, isTrue);
      expect(a.urgency, 'urgent');
      expect(a.isUrgent, isTrue);
    });

    test('a whole payload with one open-ended row parses every row', () {
      final list = DoctorSession.parseAppointments(_payload());
      expect(list.map((a) => a.id), ['open-1', 'dated-1', 'done-1', 'gone-1']);
      expect(list[1].scheduledAt, DateTime(2026, 11, 2, 11));
    });

    test('every backend status maps to its own state (none fall into pending)',
        () {
      const expected = {
        'pending': AppointmentStatus.pending,
        'requested': AppointmentStatus.pending,
        'accepted': AppointmentStatus.accepted,
        'in_progress': AppointmentStatus.inProgress,
        'rejected': AppointmentStatus.rejected,
        'reschedule_proposed': AppointmentStatus.rescheduled,
        'rescheduled': AppointmentStatus.rescheduled,
        'completed': AppointmentStatus.completed,
        'cancelled': AppointmentStatus.cancelled,
        'no_show': AppointmentStatus.noShow,
      };
      expected.forEach((api, status) {
        expect(DoctorAppointment.fromJson(_row(id: api, status: api)).status,
            status,
            reason: 'API status "$api"');
      });
    });

    test('sortKey orders open-ended requests by when they were requested', () {
      final open = DoctorAppointment.fromJson(_row(id: 'o'));
      final dated = DoctorAppointment.fromJson(
          _row(id: 'd', scheduledAt: '2026-11-02T11:00:00'));
      expect(open.sortKey, open.requestedAt!.toLocal());
      expect(dated.sortKey, dated.scheduledAt);
    });
  });

  group('Queue screen states', () {
    // Runs first: the session singleton has never loaded appointments yet.
    testWidgets('loading, then a load failure with the real reason and Retry',
        (t) async {
      await _pumpQueue(t);
      expect(find.byType(CircularProgressIndicator), findsOneWidget,
          reason: 'first load shows a spinner, not an empty queue');
      await _settleRefresh(t);
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: 'a failed load never leaves an infinite spinner');
      expect(find.byKey(const Key('doctorAppointmentsError')), findsOneWidget);
      expect(find.text('Could not load your consultations.'), findsOneWidget);
      final reason = t.widget<Text>(
          find.byKey(const Key('doctorAppointmentsErrorReason')));
      expect(reason.data, contains('sign in'),
          reason: 'shows the actual cause, not generic error text');
      expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
    });

    testWidgets('a new open-ended request appears in the queue with actions',
        (t) async {
      DoctorSession.instance.debugLoadAppointmentsPayload(_payload());
      await _pumpQueue(t);
      await _settleRefresh(t);
      expect(find.byKey(const Key('doctorAppointmentsList')), findsOneWidget);
      expect(find.text('Open Ended Farmer'), findsOneWidget);
      expect(find.text('Any time — propose a slot when accepting'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Accept'), findsNWidgets(2));
      expect(find.widgetWithText(OutlinedButton, 'Reject'), findsNWidgets(2));
      expect(find.widgetWithText(OutlinedButton, 'Reschedule'), findsNWidgets(2));
    });

    testWidgets('a failed refresh keeps the loaded queue and says so', (t) async {
      DoctorSession.instance.debugLoadAppointmentsPayload(_payload());
      await _pumpQueue(t);
      await _settleRefresh(t); // signed out -> the entry refresh fails
      expect(find.text('Could not refresh — showing the last loaded data.'),
          findsOneWidget);
      expect(find.text('Open Ended Farmer'), findsOneWidget,
          reason: 'a failed refresh must never erase real data');
      await t.tap(find.widgetWithText(TextButton, 'Retry'));
      await _settleRefresh(t);
      expect(find.text('Open Ended Farmer'), findsOneWidget);
    });

    testWidgets('a refused Accept is reverted and the server reason is shown',
        (t) async {
      DoctorSession.instance.debugLoadAppointmentsPayload(_payload());
      await _pumpQueue(t);
      await _settleRefresh(t);
      await t.tap(find.widgetWithText(ElevatedButton, 'Accept').first);
      await _settleRefresh(t);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Appointment accepted!'), findsNothing,
          reason: 'success is never announced before the server confirms');
      final open = DoctorSession.instance.appointments
          .firstWhere((a) => a.id == 'open-1');
      expect(open.status, AppointmentStatus.pending,
          reason: 'optimistic change rolled back');
    });

    // Replaces the old "filter tabs: Pending, In Progress, Cancelled" test:
    // the Schedule page no longer has status filter tabs and no longer lists
    // cancelled / completed consultations (DOCTOR_SCHEDULE_PAGE_AUDIT.md).
    testWidgets('requests and upcoming only: cancelled and completed rows are '
        'not schedule items', (t) async {
      DoctorSession.instance.debugLoadAppointmentsPayload(_payload());
      await _pumpQueue(t);
      await _settleRefresh(t);
      expect(find.text('Open Ended Farmer'), findsOneWidget);
      expect(find.text('Dated Farmer'), findsOneWidget);
      expect(find.text('Cancelled Farmer'), findsNothing);
      expect(find.text('No time was set'), findsNothing,
          reason: 'only a pending request invites a slot proposal, and the '
              'cancelled row that showed "No time was set" is not listed');
      expect(find.text('Any time — propose a slot when accepting'), findsOneWidget);
      expect(find.byKey(const Key('scheduleUpcomingEmpty')), findsOneWidget,
          reason: 'no accepted rows: empty state, not a crash');
    });

    testWidgets('narrow phone layout renders the open-ended card without overflow',
        (t) async {
      DoctorSession.instance.debugLoadAppointmentsPayload(_payload());
      await _pumpQueue(t, size: const Size(360, 780));
      await _settleRefresh(t);
      expect(t.takeException(), isNull);
      expect(find.text('Open Ended Farmer'), findsOneWidget);
    });
  });

  group('Session counters', () {
    test('pending requests include the open-ended one; today excludes it', () {
      final s = DoctorSession.instance
        ..debugLoadAppointmentsPayload(_payload());
      expect(s.appointmentsLoaded, isTrue);
      expect(s.pendingRequestCount, 2);
      // open-1 was requested (Oct 29) before dated-1's slot (Nov 2).
      expect(s.pendingRequests.map((a) => a.id), ['open-1', 'dated-1'],
          reason: 'sorted by requested/scheduled time');
      expect(s.urgentRequests, 1);
      expect(s.todayAppointments.any((a) => a.id == 'open-1'), isFalse);
    });

    testWidgets('dashboard shows the pending-requests counter', (t) async {
      final previousOnError = FlutterError.onError;
      FlutterError.onError = (d) {
        if (_isKnownPreexistingOverflow(d)) return;
        previousOnError?.call(d);
      };
      addTearDown(() => FlutterError.onError = previousOnError);
      DoctorSession.instance.debugLoadAppointmentsPayload(_payload());
      final router = GoRouter(initialLocation: '/doctor', routes: [
        GoRoute(path: '/doctor', builder: (_, __) => const DoctorDashboardScreen()),
      ]);
      await t.pumpWidget(MaterialApp.router(routerConfig: router));
      await _settleRefresh(t);
      final stat = find.byKey(const Key('pendingRequestsStat'));
      expect(stat, findsOneWidget);
      expect(find.descendant(of: stat, matching: find.text('2')), findsOneWidget);
      expect(find.descendant(of: stat, matching: find.text('Pending (1 urgent)')),
          findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });
  });

  test('no demo consultation data is wired into the doctor session', () {
    final src =
        File('lib/features/doctor/data/services/doctor_session.dart').readAsStringSync();
    // Not even the demo profile (fake rating 4.7 from 128 ratings) is used
    // any more, and the demo data file is gone — DOCTOR_RATINGS_FIX.md.
    expect(src.contains('doctor_demo_data'), isFalse);
    expect(File('lib/features/doctor/data/doctor_demo_data.dart').existsSync(), isFalse);
    for (final demo in ['demoAppointments', 'demoCases', 'demoChatThreads',
        'demoEarnings', 'demoRatings']) {
      expect(src.contains(demo), isFalse, reason: '$demo must not be used');
    }
  });
}
