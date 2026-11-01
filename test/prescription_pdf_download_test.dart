// Prescription PDF viewer: Share → Download (PRESCRIPTION_PDF_DOWNLOAD_FIX.md).
//
// Download saves the bytes the viewer already fetched from the authorised
// endpoint (no second request). Web: browser download. Windows: Save dialog,
// then the app writes the file (exercised here against a temp folder through
// a fake FilePicker).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:featherflow/core/documents/pdf_saver.dart';
import 'package:featherflow/core/documents/pdf_saver_io.dart' as io_saver;
import 'package:featherflow/core/documents/prescription_pdf_viewer.dart';
import 'package:featherflow/core/network/auth_service.dart';
import 'package:featherflow/features/doctor/data/services/doctor_session.dart';
import 'package:featherflow/features/doctor/presentation/screens/doctor_case_notes_screen.dart';
import 'package:featherflow/features/farmer/presentation/screens/farmer_consultations_screen.dart';

const _ref = 'RX-20261101-1A37DBF2';
const _fileName = 'FeatherFlow_Prescription_RX-20261101-1A37DBF2.pdf';
final _pdf = Uint8List.fromList(utf8.encode(
    '%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n'
    '2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n'
    '3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]>>endobj\n'
    'trailer<</Root 1 0 R>>\n%%EOF'));

AuthSession _session(String id) => AuthSession(
      accessToken: 'token-$id', refreshToken: 'r',
      user: AuthUser(id: id, email: '$id@featherflow.dev', fullName: 'Download Fixture',
          roles: const ['tester'], accountStatus: 'active', phone: '+8801000000000',
          presentAddress: 'Dhaka', dateOfBirth: '1990-01-01', profileData: const {}),
    );

Map<String, dynamic> _rx() => {
      'id': 'rx1', 'case_id': 'c1', 'consultation_id': 'a1',
      'medicines': [{'name': 'Amprolium', 'dosage': '1 ml/L', 'duration': '5 days', 'notes': ''}],
      'case_advice': 'Keep litter dry', 'dosage_notes': null, 'follow_up_instructions': null,
      'referred_to': null, 'created_at': '2026-11-01T04:30:00+00:00', 'issued_at': '2026-11-01T04:30:00+00:00',
      'reference_number': _ref, 'doctor_name': 'Dr. Samira Rahman', 'pdf_available': true,
      'email_status': 'sent', 'email_recipient': 'farmer.rashed@example.com',
      'email_sent_at': '2026-11-01T04:30:05+00:00', 'pdf_url': '/api/consultations/prescriptions/rx1/pdf/',
    };

Map<String, dynamic> _caseRow() => {
      'id': 'c1', 'appointment_id': 'a1', 'farmer_name': 'Md. Rashed Karim', 'farm_name': 'Rashed Poultry Farm',
      'flock_size': 500, 'bird_age_weeks': 6, 'breed': 'Sonali', 'mortality_count': 0, 'symptoms': <String>[],
      'diagnosis': 'Coccidiosis', 'treatment_plan': 'Amprolium', 'disease_tags': <String>[], 'urgency': 'routine',
      'status': 'closed', 'stage': 'prescribed', 'editable': false, 'consultation_status': 'completed',
      'mode': 'online', 'scheduled_at': '2026-11-02T11:00:00', 'updated_at': '2026-11-01T04:30:00+00:00',
      'created_at': '2026-10-30T10:00:00+00:00', 'follow_up_date': null, 'prescription': _rx(), 'prescription_count': 1,
    };

Map<String, dynamic> _farmerRow() => {
      'id': 'a1', 'doctor_name': 'Dr. Samira Rahman', 'doctor_id': 'd1', 'doctor_profile_id': 'dp1',
      'mode': 'online', 'status': 'completed', 'urgency': 'routine', 'date': '2026-11-02', 'time': '11:00',
      'fee': 900.0, 'case': null, 'proposed_date': null, 'proposed_time': null, 'decision_reason': null,
      'rating': null, 'review': '', 'rated_at': null, 'conversation_id': null,
      'video': {'room_url': null, 'active': false, 'started_at': null}, 'disputes': <Object>[],
      'clinical_results_available': true, 'payment_receipt_available': true, 'payment_receipt': null,
      'history': <Object>[], 'prescriptions': [_rx()], 'follow_ups': <Object>[],
    };

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

/// The prescription endpoints; the PDF endpoint answers [pdfStatus].
class _Server {
  _Server({this.pdfStatus = 200});
  final int pdfStatus;
  final pdfRequests = <http.Request>[];

  MockClient get client => MockClient((r) async {
        final path = r.url.path;
        if (path.endsWith('/prescriptions/rx1/pdf/')) {
          pdfRequests.add(r);
          if (pdfStatus != 200) return _json({'detail': 'no', 'code': 'forbidden'}, pdfStatus);
          return http.Response.bytes(_pdf, 200, headers: {'content-type': 'application/pdf'});
        }
        if (path.endsWith('/doctor/cases/c1/')) return _json(_caseRow());
        if (path.endsWith('/doctor/cases/')) return _json({'cases': [_caseRow()]});
        if (path.endsWith('/api/consultations/')) return _json({'consultations': [_farmerRow()]});
        if (path.endsWith('/api/consultations/chats/')) return _json({'conversations': []});
        return _json({'detail': 'unused'}, 404);
      });
}

/// Records what Download hands to the platform saver.
class _Saver {
  final calls = <(Uint8List, String)>[];
  Completer<void>? gate;
  int failures = 0;
  bool cancel = false;

  Future<PdfSaveResult> call(Uint8List bytes, String name) async {
    calls.add((bytes, name));
    if (gate != null) await gate!.future;
    if (failures > 0) {
      failures--;
      throw const FileSystemException('Access is denied', r'C:\Users\someone\Secret\x.pdf');
    }
    if (cancel) return const PdfSaveResult.cancelled();
    return PdfSaveResult(PdfSaveOutcome.saved, 'Downloaded $name');
  }
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

final _download = find.byKey(const Key('prescriptionPdfDownload'));

/// [finder] inside the viewer (SnackBars also appear on the page beneath it).
Finder _inViewer(Finder finder) =>
    find.descendant(of: find.byType(PrescriptionPdfViewer), matching: finder);

/// A viewer opened from a launcher page, fed by [loader].
Future<void> _openViewer(WidgetTester t, {required Future<Uint8List> Function() loader,
    Size size = const Size(1000, 1200)}) async {
  _size(t, size);
  await t.pumpWidget(MaterialApp(
    home: Builder(builder: (context) => Scaffold(
          body: Center(child: ElevatedButton(
              onPressed: () => showPrescriptionPdf(context,
                  prescriptionId: 'rx1', reference: _ref, loader: loader),
              child: const Text('open pdf'))))),
  ));
  await t.tap(find.text('open pdf'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Saver saver;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    saver = _Saver();
    PrescriptionPdfViewer.debugSaverOverride = saver.call;
  });
  tearDown(() async {
    PrescriptionPdfViewer.debugSaverOverride = null;
    await TestWidgetsFlutterBinding.instance.runAsync(() => AuthService.instance.clearSession());
  });

  group('File name', () {
    test('FeatherFlow_Prescription_<reference>.pdf, path-safe', () {
      expect(prescriptionPdfFileName(_ref), _fileName);
      expect(prescriptionPdfFileName(r'RX-1/../..\evil name'), 'FeatherFlow_Prescription_RX-1_evil_name.pdf');
      expect(prescriptionPdfFileName(''), 'FeatherFlow_Prescription_document.pdf');
    });
  });

  group('Viewer toolbar', () {
    testWidgets('Share removed, Print kept, Download appears once the PDF is loaded', (t) async {
      final gate = Completer<Uint8List>();
      await _openViewer(t, loader: () => gate.future);
      expect(_download, findsNothing, reason: 'nothing to download until the authorised PDF loads');
      gate.complete(_pdf);
      await t.pump();
      await t.pump();
      final preview = t.widget<PdfPreview>(find.byKey(const Key('prescriptionPdfPreview')));
      expect(preview.allowSharing, isFalse);
      expect(preview.allowPrinting, isTrue);
      expect(find.byIcon(Icons.share), findsNothing);
      expect(_download, findsOneWidget);
      expect(find.descendant(of: _download, matching: find.text('Download')), findsOneWidget);
    });

    testWidgets('loading → downloading → success; double tap saves once', (t) async {
      await _openViewer(t, loader: () async => _pdf);
      await t.pump();
      saver.gate = Completer<void>();
      await t.tap(_download);
      await t.pump();
      expect(find.text('Downloading…'), findsOneWidget);
      expect(t.widget<TextButton>(_download).onPressed, isNull);
      await t.tap(_download, warnIfMissed: false);
      await t.pump();
      saver.gate!.complete();
      await t.pump();
      await t.pump();
      expect(saver.calls, hasLength(1), reason: 'double tap → one download');
      expect(_inViewer(find.byKey(const Key('prescriptionPdfDownloaded'))), findsOneWidget);
      expect(_inViewer(find.text('Downloaded $_fileName')), findsOneWidget);
      expect(_inViewer(find.text('Download')), findsOneWidget, reason: 'button re-enabled');
    });

    testWidgets('a failed save shows a safe message with Retry, which then succeeds', (t) async {
      saver.failures = 1;
      await _openViewer(t, loader: () async => _pdf);
      await t.pump();
      await t.tap(_download);
      await t.pump();
      await t.pump();
      expect(_inViewer(find.byKey(const Key('prescriptionPdfDownloadFailed'))), findsOneWidget);
      expect(_inViewer(find.text('The PDF could not be saved. Please try again.')), findsOneWidget);
      expect(find.textContaining('Secret'), findsNothing, reason: 'no local path leaks');
      await t.pump(const Duration(milliseconds: 800)); // SnackBar slides in
      await t.tap(_inViewer(find.text('Retry')));
      await t.pump();
      await t.pump();
      // The error SnackBar animates out before the success one shows.
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
      expect(saver.calls, hasLength(2));
      expect(_inViewer(find.text('Downloaded $_fileName')), findsOneWidget);
    });

    testWidgets('cancelling the save dialog is not an error', (t) async {
      saver.cancel = true;
      await _openViewer(t, loader: () async => _pdf);
      await t.pump();
      await t.tap(_download);
      await t.pump();
      await t.pump();
      expect(_inViewer(find.byKey(const Key('prescriptionPdfDownloadCancelled'))), findsOneWidget);
      expect(find.byKey(const Key('prescriptionPdfDownloadFailed')), findsNothing);
    });

    for (final size in const [Size(360, 780), Size(1400, 900)]) {
      testWidgets('app bar with Download fits at ${size.width.toInt()}px', (t) async {
        await _openViewer(t, loader: () async => _pdf, size: size);
        await t.pump();
        expect(t.takeException(), isNull);
        expect(_download, findsOneWidget);
        final bar = t.getRect(find.byType(AppBar));
        expect(bar.contains(t.getRect(_download).center), isTrue);
      });
    }
  });

  group('Farmer and doctor download the authorised PDF (no second request)', () {
    testWidgets('farmer: My Consultations → View PDF → Download', (t) async {
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
        await t.tap(_download);
        await _frames(t, 2);
      }, () => server.client);
      expect(server.pdfRequests, hasLength(1), reason: 'Download reuses the loaded bytes');
      expect(server.pdfRequests.single.headers['Authorization'], 'Bearer token-farmer-user');
      expect(saver.calls.single.$1, _pdf, reason: 'the exact authorised PDF');
      expect(saver.calls.single.$2, _fileName);
      expect(_inViewer(find.text('Downloaded $_fileName')), findsOneWidget);
    });

    testWidgets('doctor: Case page → View PDF → Download', (t) async {
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
        await t.tap(_download);
        await _frames(t, 2);
      }, () => server.client);
      expect(server.pdfRequests, hasLength(1));
      expect(server.pdfRequests.single.headers['Authorization'], 'Bearer token-doc-user');
      expect(saver.calls.single.$1, _pdf);
      expect(saver.calls.single.$2, _fileName);
    });

    for (final (role, user) in const [('another farmer', 'farmer2'), ('another doctor', 'doc2')]) {
      testWidgets('$role (403): no PDF, no Download, nothing saved', (t) async {
        _size(t, const Size(1000, 1200));
        final server = _Server(pdfStatus: 403);
        await t.runAsync(() => AuthService.instance.saveSession(_session(user)));
        await http.runWithClient(() async {
          await t.pumpWidget(MaterialApp(
            home: Builder(builder: (context) => Scaffold(body: ElevatedButton(
                onPressed: () => showPrescriptionPdf(context, prescriptionId: 'rx1', reference: _ref),
                child: const Text('open pdf')))),
          ));
          await t.tap(find.text('open pdf'));
          await _frames(t);
        }, () => server.client);
        expect(find.text('You do not have permission to view this prescription.'), findsOneWidget);
        expect(_download, findsNothing);
        expect(saver.calls, isEmpty);
      });
    }
  });

  group('Windows save (real file write, fake Save dialog)', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('ff_rx_download_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('writes the exact bytes where the user chose; message has no full path', () async {
      final picker = _FakePicker('${dir.path}${Platform.pathSeparator}$_fileName');
      FilePicker.platform = picker;
      final result = await io_saver.savePdf(_pdf, _fileName);
      final saved = File('${dir.path}${Platform.pathSeparator}$_fileName');
      expect(result.outcome, PdfSaveOutcome.saved);
      expect(saved.readAsBytesSync(), _pdf);
      expect(picker.suggestedName, _fileName);
      expect(picker.allowedExtensions, ['pdf']);
      expect(result.message, startsWith('Saved $_fileName to '));
      expect(result.message, isNot(contains(dir.parent.path)));
    });

    test('a name typed without .pdf still saves a .pdf', () async {
      FilePicker.platform = _FakePicker('${dir.path}${Platform.pathSeparator}my rx');
      await io_saver.savePdf(_pdf, _fileName);
      expect(File('${dir.path}${Platform.pathSeparator}my rx.pdf').existsSync(), isTrue);
    });

    test('cancelling the dialog writes nothing', () async {
      FilePicker.platform = _FakePicker(null);
      final result = await io_saver.savePdf(_pdf, _fileName);
      expect(result.outcome, PdfSaveOutcome.cancelled);
      expect(dir.listSync(), isEmpty);
    });

    test('an unwritable location fails (shown as the safe error with Retry)', () async {
      FilePicker.platform = _FakePicker('${dir.path}${Platform.pathSeparator}missing${Platform.pathSeparator}x.pdf');
      await expectLater(io_saver.savePdf(_pdf, _fileName), throwsA(isA<FileSystemException>()));
    });
  });
}

class _FakePicker extends FilePicker {
  _FakePicker(this.result);
  final String? result;
  String? suggestedName;
  List<String>? allowedExtensions;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    suggestedName = fileName;
    this.allowedExtensions = allowedExtensions;
    return result;
  }
}
