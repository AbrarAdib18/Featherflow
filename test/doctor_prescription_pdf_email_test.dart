// Prescription issuing, PDF viewing and email delivery status
// (DOCTOR_PRESCRIPTION_PDF_EMAIL.md, DOCTOR_PRESCRIPTION_AUTHORITY_AUDIT.md).
//
// Reported: "Prescription authority has not been approved." under the Case
// page's prescription form — a server-side gate no real doctor could pass.
// These tests drive the real DoctorSession / Case page / farmer screen /
// PDF viewer against a fake API (`http.runWithClient` + MockClient) with the
// server's response shapes — no mock data in the app.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:featherflow/core/documents/prescription_pdf_viewer.dart';
import 'package:featherflow/core/network/auth_service.dart';
import 'package:featherflow/features/doctor/data/models/doctor_models.dart';
import 'package:featherflow/features/doctor/data/services/doctor_session.dart';
import 'package:featherflow/features/doctor/presentation/screens/doctor_case_notes_screen.dart';
import 'package:featherflow/features/farmer/presentation/screens/farmer_consultations_screen.dart';

AuthSession _session(String id) => AuthSession(
      accessToken: 'token-$id',
      refreshToken: 'r',
      user: AuthUser(
        id: id,
        email: '$id@featherflow.dev',
        fullName: 'Rx Fixture',
        roles: const ['tester'],
        accountStatus: 'active',
        phone: '+8801000000000',
        presentAddress: 'Dhaka',
        dateOfBirth: '1990-01-01',
        profileData: const {},
      ),
    );

/// A prescription as the API returns it (doctor case row / farmer row).
Map<String, dynamic> _rx({String status = 'sent', String? error}) => {
      'id': 'rx1',
      'case_id': 'c1',
      'consultation_id': 'a1',
      'medicines': [
        {'name': 'Amprolium 20%', 'dosage': '1 ml / L', 'duration': '5 days', 'notes': 'In drinking water'},
      ],
      'dosage_notes': 'Mix fresh daily',
      'case_advice': 'Keep litter dry',
      'follow_up_instructions': 'Photo on day 3',
      'referred_to': null,
      'created_at': '2026-11-01T04:30:00+00:00',
      'issued_at': '2026-11-01T04:30:00+00:00',
      'pdf_url': '/api/consultations/prescriptions/rx1/pdf/',
      'email_sent_at': status == 'sent' ? '2026-11-01T04:30:05+00:00' : null,
      'reference_number': 'RX-20261101-9EDE789E',
      'doctor_name': 'Dr. Samira Rahman',
      'pdf_available': true,
      'email_status': status,
      'email_recipient': 'farmer.rashed@example.com',
      'email_attempts': 1,
      'email_error': error,
    };

Map<String, dynamic> _case({String stage = 'prescribed', Map<String, dynamic>? rx}) => {
      'id': 'c1', 'appointment_id': 'a1', 'farmer_name': 'Md. Rashed Karim',
      'farm_name': 'Rashed Poultry Farm', 'flock_size': 500, 'bird_age_weeks': 6,
      'breed': 'Sonali', 'mortality_count': 0, 'symptoms': ['Wet droppings'],
      'diagnosis': 'Coccidiosis', 'treatment_plan': 'Amprolium', 'disease_tags': <String>[],
      'urgency': 'routine', 'status': 'closed', 'stage': stage, 'editable': false,
      'consultation_status': 'completed', 'mode': 'online', 'scheduled_at': '2026-11-02T11:00:00',
      'updated_at': '2026-11-01T04:30:00+00:00', 'feed_notes': null, 'vaccine_history': null,
      'farmer_notes': null, 'biosecurity_notes': null, 'warnings': null, 'next_steps': null,
      'created_at': '2026-10-30T10:00:00+00:00', 'follow_up_date': null,
      'prescription': rx, 'prescription_count': rx == null ? 0 : 1,
    };

/// A minimal valid one-page PDF.
final _pdfBytes = utf8.encode('%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n'
    '2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n'
    '3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]>>endobj\n'
    'trailer<</Root 1 0 R>>\n%%EOF');

http.Response _json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

class _Api {
  _Api(this.caseRow);
  Map<String, dynamic> caseRow;
  final requests = <http.Request>[];
  Completer<void>? gate;
  final pdfStatuses = <int>[]; // queued PDF responses; default 200
  String issueOutcome = 'sent';
  Map<String, dynamic>? farmerRow; // defaults to _farmerRow()

  int count(String method, String suffix) =>
      requests.where((r) => r.method == method && r.url.path.endsWith(suffix)).length;

  MockClient get client => MockClient((r) async {
        requests.add(r);
        final path = r.url.path;
        if (path.endsWith('/prescriptions/rx1/pdf/')) {
          final status = pdfStatuses.isEmpty ? 200 : pdfStatuses.removeAt(0);
          if (status != 200) {
            return _json({'detail': 'nope', 'code': 'forbidden'}, status);
          }
          return http.Response.bytes(_pdfBytes, 200, headers: {'content-type': 'application/pdf'});
        }
        if (path.endsWith('/doctor/prescriptions/rx1/resend-email/')) {
          if (gate != null) await gate!.future;
          final rx = _rx();
          caseRow = {...caseRow, 'prescription': rx};
          return _json({'email_sent_at': rx['email_sent_at'], ...rx});
        }
        if (path.endsWith('/doctor/prescriptions/')) {
          final rx = _rx(status: issueOutcome,
              error: issueOutcome == 'failed' ? 'SMTPAuthenticationError: (535, ***)' : null);
          caseRow = {...caseRow, 'stage': 'prescribed', 'prescription': rx, 'prescription_count': 1};
          return _json(rx, 201);
        }
        if (path.endsWith('/doctor/cases/c1/')) return _json(caseRow);
        if (path.endsWith('/doctor/cases/')) return _json({'cases': [caseRow]});
        if (path.endsWith('/api/consultations/')) {
          return _json({'consultations': [farmerRow ?? _farmerRow()]});
        }
        if (path.endsWith('/api/consultations/chats/')) return _json({'conversations': []});
        return _json({'detail': 'unused'}, 404);
      });
}

Map<String, dynamic> _farmerRow() => {
      'id': 'a1', 'doctor_name': 'Dr. Samira Rahman', 'doctor_id': 'd1', 'doctor_profile_id': 'dp1',
      'mode': 'online', 'status': 'completed', 'urgency': 'routine',
      'date': '2026-11-02', 'time': '11:00', 'fee': 900.0,
      'case': {'id': 'c1', 'farmer_name': 'Md. Rashed Karim', 'farm_name': 'Rashed Poultry Farm',
               'flock_id': null, 'bird_age': '6 weeks', 'breed': 'Sonali', 'flock_count': 500,
               'mortality_count': 0, 'symptoms': ['Wet droppings'], 'farmer_notes': null,
               'feed_notes': null, 'vaccine_history': null, 'biosecurity_notes': null, 'status': 'closed'},
      'proposed_date': null, 'proposed_time': null, 'decision_reason': null,
      'rating': null, 'review': '', 'rated_at': null, 'conversation_id': null,
      'video': {'room_url': null, 'active': false, 'started_at': null},
      'disputes': <Object>[], 'clinical_results_available': true,
      'payment_receipt_available': true, 'payment_receipt': null, 'history': <Object>[],
      'prescriptions': [_rx()],
      'follow_ups': [
        {'id': 'f1', 'scheduled_date': '2026-11-10', 'scheduled_time': '15:30', 'status': 'pending', 'notes': 'Photo on day 3'}
      ],
    };

Future<void> _pumpCase(WidgetTester t, {Size size = const Size(1000, 2600)}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.runAsync(() => AuthService.instance.saveSession(_session('doc-user')));
  await t.pumpWidget(const MaterialApp(home: CaseDetailScreen(caseId: 'c1')));
  await t.pumpAndSettle();
}

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

/// Taps a control that opens the PDF viewer and lets the fetch complete.
Future<void> _openPdf(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  for (var i = 0; i < 6; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump(const Duration(milliseconds: 100));
  }
}

String _text(WidgetTester t, String key) => t.widget<Text>(find.byKey(Key(key))).data ?? '';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() async {
    await TestWidgetsFlutterBinding.instance.runAsync(() => AuthService.instance.clearSession());
  });

  group('API contract', () {
    test('prescription delivery fields parse; issue time is the server instant', () {
      final p = DoctorPrescription.fromJson(_rx(status: 'failed', error: 'boom'));
      expect(p.referenceNumber, 'RX-20261101-9EDE789E');
      expect(p.emailStatus, 'failed');
      expect(p.emailFailed, isTrue);
      expect(p.emailError, 'boom');
      expect(p.emailRecipient, 'farmer.rashed@example.com');
      expect(p.pdfAvailable, isTrue);
      expect(p.createdAt.isAtSameMomentAs(DateTime.utc(2026, 11, 1, 4, 30)), isTrue);
    });

    test('an older row without email_status falls back to email_sent_at', () {
      final legacy = _rx()..remove('email_status');
      expect(DoctorPrescription.fromJson(legacy).emailStatus, 'sent');
      final pending = (_rx()..remove('email_status'))..['email_sent_at'] = null;
      expect(DoctorPrescription.fromJson(pending).emailStatus, 'pending');
    });
  });

  group('Doctor Case page', () {
    testWidgets('issuing works (no authority block) and reports the email',
        (t) async {
      final api = _Api(_case(stage: 'completed'));
      DoctorSession.instance.debugLoadCasesPayload({'cases': [api.caseRow]});
      await http.runWithClient(() async {
        await _pumpCase(t);
        await _tap(t, find.byKey(const Key('caseIssuePrescriptionButton')));
        await t.enterText(find.byKey(const Key('rxMedicineName_0')), 'Amprolium 20%');
        await t.enterText(find.byKey(const Key('rxMedicineDosage_0')), '1 ml / L');
        await t.enterText(find.byKey(const Key('rxMedicineDuration_0')), '5 days');
        await t.enterText(find.byKey(const Key('rxCaseAdvice')), 'Keep litter dry');
        await _tap(t, find.byKey(const Key('casePrescriptionSubmit')));
      }, () => api.client);
      expect(api.count('POST', '/doctor/prescriptions/'), 1);
      expect(find.textContaining('Prescription authority'), findsNothing);
      expect(find.textContaining('RX-20261101-9EDE789E issued. PDF emailed to the farmer'),
          findsOneWidget);
      expect(find.byKey(const Key('casePrescriptionCard')), findsOneWidget);
      expect(_text(t, 'casePrescriptionEmailStatus'),
          'PDF emailed to farmer.rashed@example.com');
      expect(find.byKey(const Key('casePrescriptionRetryEmail')), findsNothing,
          reason: 'a delivered email is never offered for re-sending');
    });

    testWidgets('a failed email is reported and can be retried once', (t) async {
      final api = _Api(_case(stage: 'completed'))..issueOutcome = 'failed';
      DoctorSession.instance.debugLoadCasesPayload({'cases': [api.caseRow]});
      api.gate = Completer<void>();
      await http.runWithClient(() async {
        await _pumpCase(t);
        await _tap(t, find.byKey(const Key('caseIssuePrescriptionButton')));
        await t.enterText(find.byKey(const Key('rxMedicineName_0')), 'Amprolium 20%');
        await t.enterText(find.byKey(const Key('rxMedicineDosage_0')), '1 ml / L');
        await t.enterText(find.byKey(const Key('rxMedicineDuration_0')), '5 days');
        await t.enterText(find.byKey(const Key('rxCaseAdvice')), 'Keep litter dry');
        await _tap(t, find.byKey(const Key('casePrescriptionSubmit')));
        expect(find.textContaining('The email could not be sent'), findsOneWidget);
        expect(_text(t, 'casePrescriptionEmailStatus'),
            contains('Email not delivered: SMTPAuthenticationError'));
        final retry = find.byKey(const Key('casePrescriptionRetryEmail'));
        expect(retry, findsOneWidget);

        await t.ensureVisible(retry);
        await t.tap(retry);
        await t.pump();
        expect(t.widget<OutlinedButton>(retry).onPressed, isNull,
            reason: 'disabled while the retry is in flight');
        await t.tap(retry, warnIfMissed: false);
        await t.pump();
        api.gate!.complete();
        await t.pumpAndSettle();
      }, () => api.client);
      expect(api.count('POST', '/resend-email/'), 1, reason: 'no duplicate retry');
      expect(api.count('POST', '/doctor/prescriptions/'), 1,
          reason: 'retrying the email never re-issues the prescription');
      expect(_text(t, 'casePrescriptionEmailStatus'), 'PDF emailed to farmer.rashed@example.com');
      expect(find.byKey(const Key('casePrescriptionRetryEmail')), findsNothing);
    });

    testWidgets('View PDF fetches the protected endpoint with the JWT and '
        'opens the viewer', (t) async {
      final api = _Api(_case(rx: _rx()));
      DoctorSession.instance.debugLoadCasesPayload({'cases': [api.caseRow]});
      await http.runWithClient(() async {
        await _pumpCase(t);
        expect(_text(t, 'casePrescriptionReference'), contains('RX-20261101-9EDE789E'));
        await _openPdf(t, find.byKey(const Key('casePrescriptionViewPdf')));
      }, () => api.client);
      final get = api.requests.lastWhere((r) => r.url.path.endsWith('/pdf/'));
      expect(get.url.path, '/api/consultations/prescriptions/rx1/pdf/');
      expect(get.headers['Authorization'], 'Bearer token-doc-user');
      expect(find.byType(PrescriptionPdfViewer), findsOneWidget);
      expect(find.text('Prescription RX-20261101-9EDE789E'), findsOneWidget);
      expect(find.byKey(const Key('prescriptionPdfPreview')), findsOneWidget);
    });

    for (final size in const [Size(360, 2600), Size(1400, 2600)]) {
      testWidgets('prescription card fits at ${size.width.toInt()}px', (t) async {
        final api = _Api(_case(rx: _rx(status: 'failed',
            error: 'SMTPAuthenticationError: a long provider message ' * 4)));
        DoctorSession.instance.debugLoadCasesPayload({'cases': [api.caseRow]});
        await http.runWithClient(() => _pumpCase(t, size: size), () => api.client);
        expect(t.takeException(), isNull);
        expect(find.byKey(const Key('casePrescriptionViewPdf')), findsOneWidget);
        expect(find.byKey(const Key('casePrescriptionRetryEmail')), findsOneWidget);
      });
    }
  });

  group('PDF viewer', () {
    // Updated for PRESCRIPTION_PDF_FIX.md: Retry is offered for retryable
    // failures (a 403 now shows a permission message with Close instead).
    testWidgets('a temporary failure shows a clear message and Retry loads it', (t) async {
      var calls = 0;
      Future<List<int>> load() async {
        calls++;
        if (calls == 1) {
          throw const PrescriptionPdfException(PrescriptionPdfFailure.unavailable, statusCode: 503);
        }
        return _pdfBytes;
      }

      await t.pumpWidget(MaterialApp(
        home: PrescriptionPdfViewer(
          prescriptionId: 'rx1',
          reference: 'RX-1',
          loader: () async => Uint8List.fromList(await load()),
        ),
      ));
      await t.pump();
      await t.pump();
      expect(find.text('The prescription PDF could not be loaded. Check your connection and try again.'),
          findsOneWidget);
      await t.tap(find.byKey(const Key('prescriptionPdfRetry')));
      await t.pump();
      await t.pump();
      expect(calls, 2);
      expect(find.byKey(const Key('prescriptionPdfPreview')), findsOneWidget);
    });

    testWidgets('the fetch maps HTTP errors to clear messages', (t) async {
      final api = _Api(_case(rx: _rx()))..pdfStatuses.addAll([403, 404, 401]);
      await t.runAsync(() => AuthService.instance.saveSession(_session('farmer-user')));
      final messages = <String>[];
      await http.runWithClient(() async {
        for (var i = 0; i < 3; i++) {
          await t.runAsync(() async {
            try {
              await PrescriptionPdfService.fetch('rx1');
            } on PrescriptionPdfException catch (e) {
              messages.add(e.message);
            }
          });
        }
      }, () => api.client);
      // Messages specified in PRESCRIPTION_PDF_FIX.md.
      expect(messages, [
        'You do not have permission to view this prescription.',
        'Prescription not available.',
        'Your session has expired. Please sign in again.',
      ]);
    });
  });

  group('Farmer: My Consultations', () {
    Future<void> pumpFarmer(WidgetTester t, _Api api, {Size size = const Size(1000, 2400)}) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.runAsync(() => AuthService.instance.saveSession(_session('farmer-user')));
      await http.runWithClient(() async {
        await t.pumpWidget(const MaterialApp(
            home: FarmerConsultationsScreen(pane: ConsultationsPane.consultations)));
        for (var i = 0; i < 6; i++) {
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await t.pump(const Duration(milliseconds: 50));
        }
      }, () => api.client);
    }

    testWidgets('shows the prescription details and delivery, opens the PDF',
        (t) async {
      final api = _Api(_case(rx: _rx()));
      await pumpFarmer(t, api);
      final card = find.byKey(const Key('farmerPrescription_rx1'));
      expect(card, findsOneWidget);
      for (final text in ['Amprolium 20%', '1 ml / L', '5 days', 'In drinking water',
                          'Keep litter dry', 'Photo on day 3', 'Dr. Samira Rahman', 'RX-20261101-9EDE789E']) {
        expect(find.descendant(of: card, matching: find.textContaining(text)), findsWidgets,
            reason: text);
      }
      expect(find.textContaining('Follow-up: 2026-11-10 at 15:30'), findsOneWidget);
      expect(_text(t, 'farmerPrescriptionDelivery'),
          'A PDF copy was emailed to your registered address.');
      await http.runWithClient(() async {
        await _openPdf(t, find.byKey(const Key('farmerViewPrescriptionPdf')));
      }, () => api.client);
      final get = api.requests.lastWhere((r) => r.url.path.endsWith('/pdf/'));
      expect(get.headers['Authorization'], 'Bearer token-farmer-user');
      expect(find.byKey(const Key('prescriptionPdfPreview')), findsOneWidget);
    });

    testWidgets('a failed email still leaves the PDF available, and narrow '
        'screens fit', (t) async {
      final api = _Api(_case(rx: _rx()))
        ..farmerRow = (_farmerRow()..['prescriptions'] = [_rx(status: 'failed', error: 'x')]);
      await pumpFarmer(t, api, size: const Size(360, 2400));
      expect(t.takeException(), isNull);
      expect(_text(t, 'farmerPrescriptionDelivery'),
          'We could not email the PDF yet; it is always available here.');
      expect(find.byKey(const Key('farmerViewPrescriptionPdf')), findsOneWidget);
    });
  });
}
