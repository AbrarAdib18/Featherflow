// Prescription PDF viewer (PRESCRIPTION_PDF_VIEWER_AUDIT.md, PRESCRIPTION_PDF_FIX.md).
//
// Reported: opening a prescription PDF (farmer and doctor) showed "Could not
// satisfy the request Accept header." The app asked for `Accept:
// application/pdf`; DRF only had JSON renderers, so it answered 406 before the
// view ran. The earlier fake server ignored headers, so tests passed. The fake
// here negotiates like DRF did: asking for the PDF alone gets that same 406.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:featherflow/core/documents/prescription_pdf_viewer.dart';
import 'package:featherflow/core/network/auth_service.dart';
import 'package:featherflow/features/doctor/data/services/doctor_session.dart';
import 'package:featherflow/features/doctor/presentation/screens/doctor_case_notes_screen.dart';
import 'package:featherflow/features/farmer/presentation/screens/farmer_consultations_screen.dart';

final _pdf = Uint8List.fromList(utf8.encode(
    '%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n'
    '2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n'
    '3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]>>endobj\n'
    'trailer<</Root 1 0 R>>\n%%EOF'));

AuthSession _session(String id) => AuthSession(
      accessToken: 'token-$id',
      refreshToken: 'r',
      user: AuthUser(
        id: id, email: '$id@featherflow.dev', fullName: 'Viewer Fixture',
        roles: const ['tester'], accountStatus: 'active', phone: '+8801000000000',
        presentAddress: 'Dhaka', dateOfBirth: '1990-01-01', profileData: const {},
      ),
    );

Map<String, dynamic> _rx() => {
      'id': 'rx1', 'case_id': 'c1', 'consultation_id': 'a1',
      'medicines': [{'name': 'Amprolium', 'dosage': '1 ml/L', 'duration': '5 days', 'notes': ''}],
      'case_advice': 'Keep litter dry', 'dosage_notes': null, 'follow_up_instructions': null,
      'referred_to': null, 'created_at': '2026-11-01T04:30:00+00:00',
      'issued_at': '2026-11-01T04:30:00+00:00', 'reference_number': 'RX-20261101-1A37DBF2',
      'doctor_name': 'Dr. Samira Rahman', 'pdf_available': true, 'email_status': 'sent',
      'email_recipient': 'farmer.rashed@example.com', 'email_sent_at': '2026-11-01T04:30:05+00:00',
      'pdf_url': '/api/consultations/prescriptions/rx1/pdf/',
    };

Map<String, dynamic> _caseRow() => {
      'id': 'c1', 'appointment_id': 'a1', 'farmer_name': 'Md. Rashed Karim',
      'farm_name': 'Rashed Poultry Farm', 'flock_size': 500, 'bird_age_weeks': 6, 'breed': 'Sonali',
      'mortality_count': 0, 'symptoms': <String>[], 'diagnosis': 'Coccidiosis',
      'treatment_plan': 'Amprolium', 'disease_tags': <String>[], 'urgency': 'routine',
      'status': 'closed', 'stage': 'prescribed', 'editable': false, 'consultation_status': 'completed',
      'mode': 'online', 'scheduled_at': '2026-11-02T11:00:00', 'updated_at': '2026-11-01T04:30:00+00:00',
      'created_at': '2026-10-30T10:00:00+00:00', 'follow_up_date': null,
      'prescription': _rx(), 'prescription_count': 1,
    };

Map<String, dynamic> _farmerRow() => {
      'id': 'a1', 'doctor_name': 'Dr. Samira Rahman', 'doctor_id': 'd1', 'doctor_profile_id': 'dp1',
      'mode': 'online', 'status': 'completed', 'urgency': 'routine', 'date': '2026-11-02',
      'time': '11:00', 'fee': 900.0, 'case': null, 'proposed_date': null, 'proposed_time': null,
      'decision_reason': null, 'rating': null, 'review': '', 'rated_at': null, 'conversation_id': null,
      'video': {'room_url': null, 'active': false, 'started_at': null}, 'disputes': <Object>[],
      'clinical_results_available': true, 'payment_receipt_available': true, 'payment_receipt': null,
      'history': <Object>[], 'prescriptions': [_rx()], 'follow_ups': <Object>[],
    };

http.Response _json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status,
    headers: {'content-type': 'application/json'});

/// A backend that negotiates the PDF endpoint the way DRF did before the fix.
class _Server {
  final pdfRequests = <http.Request>[];
  final queue = <http.Response Function()>[]; // next PDF responses (default: the PDF)

  static bool drfCanAnswer(String? accept) =>
      accept == null || accept.contains('application/json') || accept.contains('*/*');

  MockClient get client => MockClient((r) async {
        final path = r.url.path;
        if (path.endsWith('/prescriptions/rx1/pdf/')) {
          pdfRequests.add(r);
          if (!drfCanAnswer(r.headers['Accept'])) {
            return _json({'detail': 'Could not satisfy the request Accept header.'}, 406);
          }
          if (queue.isNotEmpty) return queue.removeAt(0)();
          return http.Response.bytes(_pdf, 200, headers: {'content-type': 'application/pdf'});
        }
        if (path.endsWith('/doctor/cases/c1/')) return _json(_caseRow());
        if (path.endsWith('/doctor/cases/')) return _json({'cases': [_caseRow()]});
        if (path.endsWith('/api/consultations/')) return _json({'consultations': [_farmerRow()]});
        if (path.endsWith('/api/consultations/chats/')) return _json({'conversations': []});
        return _json({'detail': 'unused'}, 404);
      });
}

Future<void> _frames(WidgetTester t, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump(const Duration(milliseconds: 100));
  }
}

void _size(WidgetTester t, Size size) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

String _error(WidgetTester t) =>
    t.widget<Text>(find.byKey(const Key('prescriptionPdfError'))).data ?? '';

/// Launcher page → viewer, so back navigation has somewhere to go.
Widget _launcher({Future<Uint8List> Function()? loader}) => MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showPrescriptionPdf(context,
                  prescriptionId: 'rx1', reference: 'RX-20261101-1A37DBF2', loader: loader),
              child: const Text('open pdf'),
            ),
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() async {
    await TestWidgetsFlutterBinding.instance.runAsync(() => AuthService.instance.clearSession());
  });

  group('Root cause: content negotiation', () {
    test('the old request (Accept: application/pdf only) is what the server refused', () {
      expect(_Server.drfCanAnswer('application/pdf'), isFalse,
          reason: 'reproduces the 406 "Could not satisfy the request Accept header."');
    });

    testWidgets('the viewer request is answerable and authenticated', (t) async {
      final server = _Server();
      await t.runAsync(() => AuthService.instance.saveSession(_session('farmer-user')));
      Uint8List? bytes;
      await http.runWithClient(() async {
        await t.runAsync(() async => bytes = await PrescriptionPdfService.fetch('rx1'));
      }, () => server.client);
      final r = server.pdfRequests.single;
      expect(r.method, 'GET');
      expect(r.url.path, '/api/consultations/prescriptions/rx1/pdf/');
      expect(r.headers['Accept'], startsWith('application/pdf'));
      expect(_Server.drfCanAnswer(r.headers['Accept']), isTrue);
      expect(r.headers['Authorization'], 'Bearer token-farmer-user');
      expect(bytes, _pdf);
    });
  });

  group('Doctor: Case page → View PDF', () {
    testWidgets('opens the PDF; back returns to the case', (t) async {
      _size(t, const Size(1000, 2400));
      final server = _Server();
      DoctorSession.instance.debugLoadCasesPayload({'cases': [_caseRow()]});
      await t.runAsync(() => AuthService.instance.saveSession(_session('doc-user')));
      await http.runWithClient(() async {
        await t.pumpWidget(const MaterialApp(home: CaseDetailScreen(caseId: 'c1')));
        await t.pumpAndSettle();
        final view = find.byKey(const Key('casePrescriptionViewPdf'));
        await t.ensureVisible(view);
        await t.pumpAndSettle();
        await t.tap(view);
        await _frames(t);
      }, () => server.client);
      expect(server.pdfRequests.single.headers['Authorization'], 'Bearer token-doc-user');
      expect(find.byKey(const Key('prescriptionPdfPreview')), findsOneWidget);
      expect(find.textContaining('Accept header'), findsNothing);
      await t.tap(find.byTooltip('Close'));
      await t.pumpAndSettle();
      expect(find.byType(PrescriptionPdfViewer), findsNothing);
      expect(find.byType(CaseDetailScreen), findsOneWidget);
    });
  });

  group('Farmer: My Consultations → View prescription PDF', () {
    testWidgets('opens the PDF with the farmer token', (t) async {
      _size(t, const Size(1000, 2400));
      final server = _Server();
      await t.runAsync(() => AuthService.instance.saveSession(_session('farmer-user')));
      await http.runWithClient(() async {
        await t.pumpWidget(const MaterialApp(
            home: FarmerConsultationsScreen(pane: ConsultationsPane.consultations)));
        await _frames(t);
        final view = find.byKey(const Key('farmerViewPrescriptionPdf'));
        await t.ensureVisible(view);
        await t.pump();
        await t.tap(view);
        await _frames(t);
      }, () => server.client);
      expect(server.pdfRequests.single.headers['Authorization'], 'Bearer token-farmer-user');
      expect(find.byKey(const Key('prescriptionPdfPreview')), findsOneWidget);
      expect(find.textContaining('Accept header'), findsNothing);
    });
  });

  group('Viewer states', () {
    Future<void> openWith(WidgetTester t, _Server server, {Size size = const Size(1000, 1600)}) async {
      _size(t, size);
      await t.runAsync(() => AuthService.instance.saveSession(_session('farmer-user')));
      await http.runWithClient(() async {
        await t.pumpWidget(_launcher());
        await t.tap(find.text('open pdf'));
        await _frames(t);
      }, () => server.client);
    }

    testWidgets('loading state while the PDF is fetched', (t) async {
      final gate = Completer<Uint8List>();
      await t.pumpWidget(_launcher(loader: () => gate.future));
      await t.tap(find.text('open pdf'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('prescriptionPdfLoading')), findsOneWidget);
      expect(find.text('Loading prescription…'), findsOneWidget);
      gate.complete(_pdf);
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('prescriptionPdfPreview')), findsOneWidget);
    });

    testWidgets('403 → permission message, no Retry', (t) async {
      final server = _Server()..queue.add(() => _json({'detail': 'You do not have access to this prescription.', 'code': 'forbidden'}, 403));
      await openWith(t, server);
      expect(_error(t), 'You do not have permission to view this prescription.');
      expect(find.byKey(const Key('prescriptionPdfRetry')), findsNothing);
      expect(find.byKey(const Key('prescriptionPdfClose')), findsOneWidget);
    });

    testWidgets('404 → prescription not available', (t) async {
      final server = _Server()..queue.add(() => _json({'detail': 'Prescription not found.', 'code': 'not_found'}, 404));
      await openWith(t, server);
      expect(_error(t), 'Prescription not available.');
    });

    testWidgets('401 → session expired; Sign in clears the session and goes to login',
        (t) async {
      _size(t, const Size(1000, 1600));
      final server = _Server()..queue.add(() => _json({'detail': 'Given token not valid'}, 401));
      await t.runAsync(() => AuthService.instance.saveSession(_session('farmer-user')));
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => Builder(builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showPrescriptionPdf(context, prescriptionId: 'rx1'),
                child: const Text('open pdf'))))),
        GoRoute(path: '/login', builder: (_, __) => const Scaffold(body: Text('Login page'))),
      ]);
      await http.runWithClient(() async {
        await t.pumpWidget(MaterialApp.router(routerConfig: router));
        await t.tap(find.text('open pdf'));
        await _frames(t);
      }, () => server.client);
      expect(_error(t), 'Your session has expired. Please sign in again.');
      await t.tap(find.byKey(const Key('prescriptionPdfSignIn')));
      await _frames(t, 3);
      await t.pumpAndSettle();
      expect(find.text('Login page'), findsOneWidget);
      final stored = await t.runAsync(() => AuthService.instance.getStoredSession());
      expect(stored, isNull, reason: 'the expired session is cleared');
    });

    testWidgets('corrupt file → useful message + Retry, which then succeeds', (t) async {
      final server = _Server()
        ..queue.add(() => http.Response.bytes(utf8.encode('<html>oops</html>'), 200,
            headers: {'content-type': 'application/pdf'}));
      await openWith(t, server);
      expect(_error(t), 'The prescription file could not be read. Please try again.');
      await http.runWithClient(() async {
        await t.tap(find.byKey(const Key('prescriptionPdfRetry')));
        await _frames(t);
      }, () => server.client);
      expect(find.byKey(const Key('prescriptionPdfPreview')), findsOneWidget);
      expect(server.pdfRequests, hasLength(2));
    });

    testWidgets('server error / non-PDF body: generic message, raw text never shown',
        (t) async {
      final server = _Server()
        ..queue.add(() => http.Response('Traceback (most recent call last): secret', 500,
            headers: {'content-type': 'text/html'}))
        ..queue.add(() => _json({'detail': 'x'}, 200));
      await openWith(t, server);
      expect(_error(t), contains('could not be loaded'));
      expect(find.textContaining('Traceback'), findsNothing);
      await http.runWithClient(() async {
        await t.tap(find.byKey(const Key('prescriptionPdfRetry')));
        await _frames(t);
      }, () => server.client);
      expect(_error(t), 'The prescription file could not be read. Please try again.',
          reason: 'a 200 that is not a PDF is never rendered');
    });

    testWidgets('double tap opens one viewer and sends one request', (t) async {
      var calls = 0;
      final gate = Completer<Uint8List>();
      await t.pumpWidget(_launcher(loader: () {
        calls++;
        return gate.future;
      }));
      await t.tap(find.text('open pdf'));
      await t.tap(find.text('open pdf'), warnIfMissed: false);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      gate.complete(_pdf);
      await t.pump();
      expect(calls, 1);
      expect(find.byType(PrescriptionPdfViewer), findsOneWidget);
      await t.tap(find.byTooltip('Close'));
      await t.pumpAndSettle();
      await t.tap(find.text('open pdf'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(PrescriptionPdfViewer), findsOneWidget,
          reason: 'the guard resets once the viewer is closed');
    });

    for (final size in const [Size(360, 780), Size(1400, 900)]) {
      testWidgets('full-screen viewer at ${size.width.toInt()}px', (t) async {
        await openWith(t, _Server(), size: size);
        expect(t.takeException(), isNull);
        expect(find.byKey(const Key('prescriptionPdfPreview')), findsOneWidget);
        expect(t.getSize(find.byType(PrescriptionPdfViewer)), size);
      });
    }
  });
}
