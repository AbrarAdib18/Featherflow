// Doctor Case page workflow + Schedule page separation (DOCTOR_CASE_PAGE_FIX.md,
// DOCTOR_SCHEDULE_PAGE_AUDIT.md).
//
// Before: the Case page rendered Diagnosis / Treatment Plan / Warning / Farm
// Management Notes / Next Steps as read-only Text (empty cards when the
// saved value was ''), and "Mark Complete" + "Issue prescription & advice"
// lived on the Schedule page.
//
// Widget tests drive the real DoctorSession + DoctorApiService against a fake
// doctor API (`http.runWithClient` + MockClient) that mirrors the server's
// stage rules (backend/doctor/case_workflow.py) — no mock data in the app.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:featherflow/core/network/auth_service.dart';
import 'package:featherflow/features/doctor/data/models/doctor_models.dart';
import 'package:featherflow/features/doctor/data/services/doctor_session.dart';
import 'package:featherflow/features/doctor/presentation/screens/doctor_appointments_screen.dart';
import 'package:featherflow/features/doctor/presentation/screens/doctor_case_notes_screen.dart';

const _fields = [
  'diagnosis',
  'treatment_plan',
  'warnings',
  'disease_tags',
  'feed_notes',
  'vaccine_history',
  'biosecurity_notes',
  'next_steps',
];

AuthSession _session() => AuthSession(
      accessToken: 'a',
      refreshToken: 'r',
      user: AuthUser(
        id: 'doc-user',
        email: 'doc@featherflow.dev',
        fullName: 'Case Fixture',
        // Not 'doctor': avoids DoctorSession's login refresh + timers.
        roles: const ['tester'],
        accountStatus: 'active',
        phone: '+8801000000000',
        presentAddress: 'Dhaka',
        dateOfBirth: '1990-01-01',
        profileData: const {},
      ),
    );

/// A `GET /api/doctor/cases/<id>/` row, as the server returns it.
Map<String, dynamic> _caseRow({
  String id = 'c1',
  String stage = 'open',
  String consultationStatus = 'accepted',
  String status = 'open',
  String? diagnosis,
  String? treatment,
}) =>
    {
      'id': id,
      'appointment_id': 'a1',
      'farmer_name': 'Md. Rashed Karim',
      'farm_name': 'Rashed Poultry Farm',
      'flock_size': 500,
      'bird_age_weeks': 6,
      'breed': 'Sonali',
      'mortality_count': 4,
      'symptoms': ['Lethargy', 'Wet droppings'],
      'diagnosis': diagnosis,
      'treatment_plan': treatment,
      'disease_tags': <String>[],
      'urgency': 'routine',
      'status': status,
      'stage': stage,
      'editable': stage == 'open',
      'consultation_status': consultationStatus,
      'mode': 'online',
      'scheduled_at': '2026-11-02T11:00:00',
      'updated_at': '2026-10-31T04:00:00+00:00',
      'feed_notes': 'Layer mash',
      'vaccine_history': null,
      'farmer_notes': null,
      'biosecurity_notes': null,
      'warnings': null,
      'next_steps': null,
      'created_at': '2026-10-30T10:00:00+00:00',
      'follow_up_date': null,
      'prescription': null,
      'prescription_count': 0,
    };

Map<String, dynamic> _bodyOf(http.Request r) =>
    r.body.isEmpty ? {} : Map<String, dynamic>.from(jsonDecode(r.body) as Map);

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

/// The doctor API for one case, with the server's stage rules.
class _FakeApi {
  _FakeApi(this.row);
  Map<String, dynamic> row;
  List<Map<String, dynamic>> appointments = [];
  final requests = <http.Request>[];
  Completer<void>? gate;
  int failWrites = 0;
  bool notFound = false;

  List<http.Request> writes(String suffix) => requests
      .where((r) => r.method != 'GET' && r.url.path.endsWith(suffix))
      .toList();

  MockClient get client => MockClient((r) async {
        requests.add(r);
        final path = r.url.path;
        if (r.method != 'GET') {
          if (gate != null) await gate!.future;
          if (failWrites > 0) {
            failWrites--;
            return _json({'detail': 'Server unavailable.'}, 503);
          }
        }
        if (path.endsWith('/doctor/cases/${row['id']}/')) {
          if (notFound) return _json({'detail': 'Not found.'}, 404);
          if (r.method == 'GET') return _json(row);
          return _patch(_bodyOf(r));
        }
        if (path.endsWith('/doctor/cases/')) return _json({'cases': [row]});
        if (path.endsWith('/doctor/appointments/a1/action/')) {
          if (row['consultation_status'] == 'completed') {
            return _json({'id': 'a1', 'status': 'completed', 'already_completed': true});
          }
          row = {...row, 'consultation_status': 'completed', 'status': 'closed', 'stage': 'completed', 'editable': false};
          return _json({'id': 'a1', 'status': 'completed'});
        }
        if (path.endsWith('/doctor/prescriptions/')) {
          if (row['consultation_status'] != 'completed') {
            return _json({'detail': 'Complete the consultation before issuing its prescription.'}, 409);
          }
          final b = _bodyOf(r);
          row = {
            ...row,
            'stage': 'prescribed',
            'prescription_count': (row['prescription_count'] as int) + 1,
            'prescription': {
              'id': 'rx1', 'case_id': row['id'], 'consultation_id': 'a1',
              'medicines': b['medicines'], 'case_advice': b['case_advice'],
              'dosage_notes': b['dosage_notes'],
              'follow_up_instructions': b['follow_up_instructions'],
              'referred_to': null, 'created_at': '2026-10-31T05:00:00+00:00',
            },
          };
          return _json(row['prescription'] as Object, 201);
        }
        if (path.endsWith('/doctor/appointments/')) {
          return _json({'appointments': appointments});
        }
        return _json({'detail': 'unused in this test'}, 404);
      });

  http.Response _patch(Map<String, dynamic> body) {
    final status = body.remove('status') as String?;
    final stage = row['stage'];
    final reopening = stage == 'closed' && status != null && status != 'closed';
    if (!reopening && (body.isNotEmpty || status != null) && stage != 'open') {
      return _json({'detail': 'This case is closed. Reopen it to edit the clinical fields.', 'code': 'case_closed'}, 409);
    }
    final next = {...row, ...body};
    if (status == 'closed') {
      final missing = {
        for (final k in ['diagnosis', 'treatment_plan'])
          if ('${next[k] ?? ''}'.trim().isEmpty) k: 'Required before the case can be closed.'
      };
      if (missing.isNotEmpty) {
        return _json({'detail': 'Enter a diagnosis and treatment plan before closing the case.', 'code': 'case_incomplete', 'errors': missing}, 400);
      }
    }
    if (status != null) {
      next['status'] = status;
      next['stage'] = status == 'closed' ? 'closed' : 'open';
      next['editable'] = next['stage'] == 'open';
    }
    row = next;
    return _json(row);
  }
}

Future<void> _pumpCase(WidgetTester t, {Size size = const Size(1000, 2600)}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.runAsync(() => AuthService.instance.saveSession(_session()));
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const CaseDetailScreen(caseId: 'c1'))),
            child: const Text('open case'),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open case'));
  await t.pumpAndSettle();
}

Finder _field(String key) => find.byKey(Key('caseField_$key'));

String _saveStatus(WidgetTester t) =>
    t.widget<Text>(find.byKey(const Key('caseSaveStatus'))).data ?? '';

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() async {
    await TestWidgetsFlutterBinding.instance
        .runAsync(() => AuthService.instance.clearSession());
  });

  group('API contract parsing', () {
    test('every server stage maps to its CaseStage', () {
      const expected = {
        'awaiting_acceptance': CaseStage.awaitingAcceptance,
        'open': CaseStage.open,
        'closed': CaseStage.closed,
        'completed': CaseStage.completed,
        'prescribed': CaseStage.prescribed,
        'ended': CaseStage.ended,
      };
      expected.forEach((api, stage) {
        final c = DoctorCase.fromJson(_caseRow(stage: api));
        expect(c.stage, stage, reason: api);
        expect(c.editable, api == 'open', reason: api);
      });
    });

    test('an older server without `stage` falls back to the case status', () {
      final row = _caseRow(status: 'closed')..remove('stage')..remove('editable');
      expect(DoctorCase.fromJson(row).stage, CaseStage.closed);
      final open = _caseRow()..remove('stage')..remove('editable');
      expect(DoctorCase.fromJson(open).editable, isTrue);
    });

    test('Schedule sections: only requests and upcoming appointments', () {
      const expected = {
        'pending': ScheduleSection.requests,
        'reschedule_proposed': ScheduleSection.requests,
        'accepted': ScheduleSection.upcoming,
        'in_progress': ScheduleSection.upcoming,
        'completed': null,
        'rejected': null,
        'cancelled': null,
        'no_show': null,
      };
      expected.forEach((api, section) {
        final a = DoctorAppointment.fromJson({
          'id': api, 'farmer_name': 'F', 'farm_name': 'Farm', 'farmer_phone': '',
          'scheduled_at': '2026-11-02T11:00:00', 'mode': 'online', 'status': api,
          'fee': 900,
        });
        expect(a.scheduleSection, section, reason: api);
      });
    });
  });

  group('Case page: open case', () {
    late _FakeApi api;
    setUp(() {
      api = _FakeApi(_caseRow(diagnosis: '', treatment: ''));
      DoctorSession.instance.debugLoadCasesPayload({'cases': [api.row]});
    });

    testWidgets('shows a real, enabled text input for every case field',
        (t) async {
      await http.runWithClient(() => _pumpCase(t), () => api.client);
      for (final key in _fields) {
        expect(_field(key), findsOneWidget, reason: key);
        expect(t.widget<TextField>(_field(key)).enabled, isNot(false), reason: key);
      }
      expect(t.widget<TextField>(_field('diagnosis')).maxLines, greaterThan(1),
          reason: 'diagnosis is a multiline textarea');
      expect(t.widget<TextField>(_field('disease_tags')).maxLines, 1,
          reason: 'tags are a single line');
      expect(find.byKey(const Key('caseCloseButton')), findsOneWidget);
      expect(find.byKey(const Key('caseMarkCompletePanel')), findsNothing);
      expect(find.byKey(const Key('caseIssuePrescriptionPanel')), findsNothing);
      expect(find.text('Layer mash'), findsOneWidget,
          reason: 'saved values pre-fill the inputs');
    });

    testWidgets('typing marks unsaved; Save sends only the changed field and '
        'the value survives a reopen', (t) async {
      await http.runWithClient(() async {
        await _pumpCase(t);
        await t.enterText(_field('diagnosis'), 'Early coccidiosis');
        await t.pump();
        expect(_saveStatus(t), 'Unsaved changes');
        await t.tap(find.byKey(const Key('caseSaveButton')));
        await t.pumpAndSettle();
        expect(_saveStatus(t), 'All changes saved');
        final patches = api.writes('/cases/c1/');
        expect(patches, hasLength(1));
        expect(_bodyOf(patches.single), {'diagnosis': 'Early coccidiosis'},
            reason: 'partial save: no other field is re-sent or blanked');

        // Reopen the page: the value comes back from the server.
        await t.pageBack();
        await t.pumpAndSettle();
        DoctorSession.instance.debugLoadCasesPayload({'cases': [_caseRow()]});
        await t.tap(find.text('open case'));
        await t.pumpAndSettle();
      }, () => api.client);
      expect(api.row['diagnosis'], 'Early coccidiosis');
      expect(find.text('Early coccidiosis'), findsOneWidget,
          reason: 'reopened page shows the persisted server value');
    });

    testWidgets('Saving… state, Save disabled in flight, one request for a '
        'double tap', (t) async {
      api.gate = Completer<void>();
      await http.runWithClient(() async {
        await _pumpCase(t);
        await t.enterText(_field('treatment_plan'), 'Amprolium 5 days');
        await t.pump();
        await t.tap(find.byKey(const Key('caseSaveButton')));
        await t.pump();
        expect(_saveStatus(t), 'Saving…');
        expect(t.widget<ElevatedButton>(find.byKey(const Key('caseSaveButton'))).onPressed,
            isNull);
        expect(t.widget<TextField>(_field('treatment_plan')).enabled, isFalse,
            reason: 'inputs are locked while the save is in flight');
        await t.tap(find.byKey(const Key('caseSaveButton')), warnIfMissed: false);
        await t.pump();
        api.gate!.complete();
        await t.pumpAndSettle();
      }, () => api.client);
      expect(api.writes('/cases/c1/'), hasLength(1));
      expect(api.row['treatment_plan'], 'Amprolium 5 days');
    });

    testWidgets('a failed save keeps the text, shows the reason and Retry '
        'succeeds', (t) async {
      api.failWrites = 1;
      await http.runWithClient(() async {
        await _pumpCase(t);
        await t.enterText(_field('next_steps'), 'Re-check on day 5');
        await t.pump();
        await t.tap(find.byKey(const Key('caseSaveButton')));
        await t.pumpAndSettle();
        expect(_saveStatus(t), contains('Server unavailable.'));
        expect(find.text('Re-check on day 5'), findsOneWidget);
        await t.tap(find.byKey(const Key('caseSaveRetry')));
        await t.pumpAndSettle();
        expect(_saveStatus(t), 'All changes saved');
      }, () => api.client);
      expect(api.writes('/cases/c1/').map(_bodyOf).toList(), [
        {'next_steps': 'Re-check on day 5'},
        {'next_steps': 'Re-check on day 5'},
      ]);
      expect(api.row['next_steps'], 'Re-check on day 5');
    });

    testWidgets('Close case needs diagnosis + treatment: inline errors, no '
        'request', (t) async {
      await http.runWithClient(() async {
        await _pumpCase(t);
        await _tap(t, find.byKey(const Key('caseCloseButton')));
      }, () => api.client);
      expect(find.text('Required before the case can be closed.'), findsNWidgets(2));
      expect(api.writes('/cases/c1/'), isEmpty);
    });

    testWidgets('unsaved edits are protected on back navigation', (t) async {
      await http.runWithClient(() async {
        await _pumpCase(t);
        await t.enterText(_field('warnings'), 'Withdraw eggs 7 days');
        await t.pump();
        await t.pageBack();
        await t.pumpAndSettle();
        expect(find.text('Discard unsaved changes?'), findsOneWidget);
        await t.tap(find.text('Keep editing'));
        await t.pumpAndSettle();
        expect(find.byType(CaseDetailScreen), findsOneWidget);
        await t.pageBack();
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('caseDiscardChanges')));
        await t.pumpAndSettle();
      }, () => api.client);
      expect(find.byType(CaseDetailScreen), findsNothing);
      expect(api.writes('/cases/c1/'), isEmpty);
    });

    testWidgets('a background refresh never overwrites unsaved typing',
        (t) async {
      await http.runWithClient(() async {
        await _pumpCase(t);
        await t.enterText(_field('diagnosis'), 'typing in progress');
        await t.pump();
        api.row = {...api.row, 'treatment_plan': 'Set from another device'};
        await t.tap(find.byKey(const Key('caseRefresh')));
        await t.pumpAndSettle();
      }, () => api.client);
      expect(find.text('typing in progress'), findsOneWidget);
      expect(find.text('Set from another device'), findsOneWidget,
          reason: 'untouched fields take the fresh server value');
      expect(_saveStatus(t), 'Unsaved changes');
    });
  });

  group('Case page: full workflow', () {
    testWidgets('open → save → close → Mark as Complete → Issue prescription '
        '& advice, all on the Case page', (t) async {
      final api = _FakeApi(_caseRow());
      DoctorSession.instance.debugLoadCasesPayload({'cases': [api.row]});
      await http.runWithClient(() async {
        await _pumpCase(t);
        await t.enterText(_field('diagnosis'), 'Early coccidiosis');
        await t.enterText(_field('treatment_plan'), 'Amprolium 1 ml/L, 5 days');
        await t.pump();
        expect(find.text('Save and close case'), findsOneWidget);

        // Close (pending edits go with it) after confirmation.
        await _tap(t, find.byKey(const Key('caseCloseButton')));
        expect(find.text('Close this case?'), findsOneWidget);
        await t.tap(find.byKey(const Key('caseConfirmClose')));
        await t.pumpAndSettle();
        final close = _bodyOf(api.writes('/cases/c1/').single);
        expect(close, {
          'diagnosis': 'Early coccidiosis',
          'treatment_plan': 'Amprolium 1 ml/L, 5 days',
          'status': 'closed',
        });

        // Closed: Mark as Complete window, fields read-only.
        expect(find.byKey(const Key('caseMarkCompletePanel')), findsOneWidget);
        expect(_field('diagnosis'), findsNothing);
        expect(find.byKey(const Key('caseReadOnly_diagnosis')), findsOneWidget);
        expect(find.text('Early coccidiosis'), findsOneWidget);
        expect(find.byKey(const Key('caseCloseButton')), findsNothing);

        // Cancel the confirmation: nothing is sent.
        await _tap(t, find.byKey(const Key('caseMarkCompleteButton')));
        await t.tap(find.text('Cancel'));
        await t.pumpAndSettle();
        expect(api.writes('/appointments/a1/action/'), isEmpty);

        await _tap(t, find.byKey(const Key('caseMarkCompleteButton')));
        await t.tap(find.byKey(const Key('caseConfirmComplete')));
        await t.pumpAndSettle();
        expect(_bodyOf(api.writes('/appointments/a1/action/').single),
            {'action': 'complete'});

        // Completed: Issue Prescription and Advice on the same page.
        expect(find.byKey(const Key('caseMarkCompletePanel')), findsNothing);
        expect(find.byKey(const Key('caseIssuePrescriptionPanel')), findsOneWidget);
        await _tap(t, find.byKey(const Key('caseIssuePrescriptionButton')));
        expect(find.byKey(const Key('casePrescriptionForm')), findsOneWidget);

        // Validation before anything is sent.
        await _tap(t, find.byKey(const Key('casePrescriptionSubmit')));
        expect(find.byKey(const Key('rxError')), findsOneWidget);
        expect(api.writes('/prescriptions/'), isEmpty);

        await t.enterText(find.byKey(const Key('rxMedicineName_0')), 'Amprolium');
        await t.enterText(find.byKey(const Key('rxMedicineDosage_0')), '1 ml/L');
        await t.enterText(find.byKey(const Key('rxMedicineDuration_0')), '5 days');
        await t.enterText(find.byKey(const Key('rxCaseAdvice')), 'Keep litter dry');
        await _tap(t, find.byKey(const Key('casePrescriptionSubmit')));
      }, () => api.client);

      final rx = _bodyOf(api.writes('/prescriptions/').single);
      expect(rx['consultation_id'], 'a1');
      expect(rx['case_advice'], 'Keep litter dry');
      expect((rx['medicines'] as List).single,
          {'name': 'Amprolium', 'dosage': '1 ml/L', 'duration': '5 days', 'notes': ''});
      expect(find.byKey(const Key('casePrescriptionCard')), findsOneWidget);
      expect(find.text('Keep litter dry'), findsOneWidget);
      expect(find.byKey(const Key('caseIssueRevisedButton')), findsOneWidget);
      expect(find.byKey(const Key('casePrescriptionForm')), findsNothing);
    });

    testWidgets('server refusal on close shows the field errors from the API',
        (t) async {
      final api = _FakeApi(_caseRow(diagnosis: 'x', treatment: 'y'));
      DoctorSession.instance.debugLoadCasesPayload({'cases': [api.row]});
      await http.runWithClient(() async {
        await _pumpCase(t);
        // Cleared locally but the server is the one that refuses.
        api.row = {...api.row, 'treatment_plan': ''};
        await _tap(t, find.byKey(const Key('caseCloseButton')));
        await t.tap(find.byKey(const Key('caseConfirmClose')));
        await t.pumpAndSettle();
      }, () => api.client);
      expect(find.text('Required before the case can be closed.'), findsOneWidget);
      expect(_saveStatus(t), contains('Enter a diagnosis and treatment plan'));
      expect(api.row['stage'], 'open');
    });

    testWidgets('a closed case can be reopened for editing', (t) async {
      final api = _FakeApi(_caseRow(stage: 'closed', status: 'closed',
          diagnosis: 'd', treatment: 't'));
      DoctorSession.instance.debugLoadCasesPayload({'cases': [api.row]});
      await http.runWithClient(() async {
        await _pumpCase(t);
        expect(_field('diagnosis'), findsNothing);
        await _tap(t, find.byKey(const Key('caseReopenButton')));
      }, () => api.client);
      expect(_bodyOf(api.writes('/cases/c1/').single), {'status': 'open'});
      expect(_field('diagnosis'), findsOneWidget);
    });
  });

  group('Case page: read-only and inaccessible', () {
    testWidgets('awaiting acceptance: no inputs, points to the Schedule page',
        (t) async {
      final api = _FakeApi(_caseRow(stage: 'awaiting_acceptance', consultationStatus: 'requested'));
      DoctorSession.instance.debugLoadCasesPayload({'cases': [api.row]});
      await http.runWithClient(() => _pumpCase(t), () => api.client);
      for (final key in _fields) {
        expect(_field(key), findsNothing, reason: key);
      }
      expect(find.textContaining('Accept it on the Schedule page'), findsOneWidget);
      expect(find.byKey(const Key('caseSaveButton')), findsNothing);
      expect(find.byKey(const Key('caseMarkCompleteButton')), findsNothing);
    });

    testWidgets('completed case shows saved values read-only and blanks as '
        '"Not recorded" (no empty cards)', (t) async {
      final api = _FakeApi(_caseRow(stage: 'completed', consultationStatus: 'completed',
          status: 'closed', diagnosis: 'Coccidiosis', treatment: ''));
      DoctorSession.instance.debugLoadCasesPayload({'cases': [api.row]});
      await http.runWithClient(() => _pumpCase(t), () => api.client);
      expect(_field('diagnosis'), findsNothing);
      expect(find.text('Coccidiosis'), findsOneWidget);
      expect(find.text('Not recorded'), findsWidgets);
      expect(find.byKey(const Key('caseIssuePrescriptionPanel')), findsOneWidget);
    });

    testWidgets("another doctor's case (404) is not shown: error + Retry",
        (t) async {
      final api = _FakeApi(_caseRow(id: 'c1'))..notFound = true;
      DoctorSession.instance.debugLoadCasesPayload({'cases': []});
      await http.runWithClient(() => _pumpCase(t), () => api.client);
      expect(find.text('Not found.'), findsOneWidget);
      expect(find.byKey(const Key('caseRetryLoad')), findsOneWidget);
      expect(_field('diagnosis'), findsNothing);
    });
  });

  group('Case page: responsive layout', () {
    for (final size in const [Size(360, 2600), Size(1400, 2600)]) {
      testWidgets('renders without overflow at ${size.width.toInt()}px',
          (t) async {
        final api = _FakeApi(_caseRow(stage: 'completed', consultationStatus: 'completed',
            status: 'closed', diagnosis: 'd', treatment: 't'));
        DoctorSession.instance.debugLoadCasesPayload({'cases': [api.row]});
        await http.runWithClient(() async {
          await _pumpCase(t, size: size);
          await _tap(t, find.byKey(const Key('caseIssuePrescriptionButton')));
        }, () => api.client);
        expect(t.takeException(), isNull);
        expect(find.byKey(const Key('casePrescriptionForm')), findsOneWidget);
      });
    }
  });

  group('Schedule page', () {
    Map<String, dynamic> appt(String id, String status, String farmer) => {
          'id': id, 'farmer_name': farmer, 'farmer_phone': '+8801711000101',
          'farm_name': 'Rashed Poultry Farm', 'scheduled_at': '2026-11-02T11:00:00',
          'has_preferred_slot': true, 'mode': 'online', 'status': status,
          'urgency': 'routine', 'is_urgent': false, 'case_id': 'case-$id',
          'fee': 900.0, 'requested_at': '2026-10-29T10:00:00+00:00',
        };

    Future<void> pumpSchedule(WidgetTester t, List<Map<String, dynamic>> rows,
        {Size size = const Size(1000, 2000)}) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      DoctorSession.instance.debugLoadAppointmentsPayload({'appointments': rows});
      await t.pumpWidget(const MaterialApp(home: DoctorAppointmentsScreen()));
      for (var i = 0; i < 5; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('only Consultation Requests and Upcoming Schedule; no case '
        'workflow', (t) async {
      await pumpSchedule(t, [
        appt('p1', 'pending', 'Pending Farmer'),
        appt('r1', 'reschedule_proposed', 'Proposed Farmer'),
        appt('a1', 'accepted', 'Accepted Farmer'),
        appt('i1', 'in_progress', 'Active Farmer'),
        appt('d1', 'completed', 'Completed Farmer'),
        appt('x1', 'cancelled', 'Cancelled Farmer'),
        appt('n1', 'no_show', 'NoShow Farmer'),
        appt('j1', 'rejected', 'Rejected Farmer'),
      ]);
      expect(find.byKey(const Key('scheduleRequestsSection')), findsOneWidget);
      expect(find.byKey(const Key('scheduleUpcomingSection')), findsOneWidget);
      for (final shown in ['Pending Farmer', 'Proposed Farmer', 'Accepted Farmer', 'Active Farmer']) {
        expect(find.text(shown), findsOneWidget, reason: shown);
      }
      for (final hidden in ['Completed Farmer', 'Cancelled Farmer', 'NoShow Farmer', 'Rejected Farmer']) {
        expect(find.text(hidden), findsNothing, reason: hidden);
      }
      expect(find.textContaining('Mark Complete'), findsNothing);
      expect(find.textContaining('Mark as Complete'), findsNothing);
      expect(find.textContaining('prescription', findRichText: true), findsNothing);
      expect(find.textContaining('Prescription'), findsNothing);
      expect(find.byKey(const Key('scheduleOpenCase')), findsNWidgets(2));
      expect(find.widgetWithText(ElevatedButton, 'Accept'), findsOneWidget);
      // Upcoming lists in the second section: order is requests then upcoming.
      final requestsY = t.getTopLeft(find.byKey(const Key('scheduleRequestsSection'))).dy;
      final upcomingY = t.getTopLeft(find.byKey(const Key('scheduleUpcomingSection'))).dy;
      expect(t.getTopLeft(find.text('Pending Farmer')).dy, inInclusiveRange(requestsY, upcomingY));
      expect(t.getTopLeft(find.text('Accepted Farmer')).dy, greaterThan(upcomingY));
    });

    testWidgets('empty states for both sections', (t) async {
      await pumpSchedule(t, [appt('d1', 'completed', 'Completed Farmer')]);
      expect(find.byKey(const Key('scheduleRequestsEmpty')), findsOneWidget);
      expect(find.text('No pending consultation requests'), findsOneWidget);
      expect(find.byKey(const Key('scheduleUpcomingEmpty')), findsOneWidget);
      expect(find.text('No upcoming schedules'), findsOneWidget);
    });

    testWidgets('Open case navigates to the Case page, where completion lives',
        (t) async {
      final api = _FakeApi(_caseRow(id: 'case-a1', stage: 'closed', status: 'closed',
          diagnosis: 'd', treatment: 't'))
        ..appointments = [appt('a1', 'accepted', 'Accepted Farmer')];
      DoctorSession.instance.debugLoadCasesPayload({'cases': [api.row]});
      await http.runWithClient(() async {
        await t.runAsync(() => AuthService.instance.saveSession(_session()));
        await pumpSchedule(t, [appt('a1', 'accepted', 'Accepted Farmer')]);
        await t.tap(find.byKey(const Key('scheduleOpenCase')));
        await t.pumpAndSettle();
      }, () => api.client);
      expect(find.byType(CaseDetailScreen), findsOneWidget);
      expect(find.byKey(const Key('caseMarkCompletePanel')), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.byType(DoctorAppointmentsScreen), findsOneWidget);
    });

    testWidgets('narrow phone: request actions are not clipped', (t) async {
      await pumpSchedule(t, [appt('p1', 'pending', 'Pending Farmer')],
          size: const Size(360, 900));
      expect(t.takeException(), isNull);
      final label = find.text('Reschedule');
      expect(label, findsOneWidget);
      expect(t.getSize(label).height, lessThan(24),
          reason: 'one line — it used to wrap as "Reschedul / e"');
    });
  });
}
