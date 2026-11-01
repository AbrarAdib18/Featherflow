// Prescription PDF: authenticated fetch + full-screen viewer, shared by the
// farmer (My Consultations) and the doctor (Case page, Prescriptions).
// DOCTOR_PRESCRIPTION_PDF_EMAIL.md, PRESCRIPTION_PDF_FIX.md.
//
// The PDF lives in private server storage and is only served by
// GET /api/consultations/prescriptions/<id>/pdf/ to the consultation's farmer,
// the prescribing doctor or an admin reviewer — so it is fetched with the
// signed-in user's JWT, never opened as a public URL. The bytes go straight
// to PdfPreview (no temp file): on Windows the printing plugin rasterises them
// with its bundled PDFium; on web with pdf.js. Download saves those same bytes
// (pdf_saver.dart); Share was removed (PRESCRIPTION_PDF_DOWNLOAD_FIX.md).
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';

import '../network/auth_service.dart';
import '../router/app_router.dart';
import 'pdf_saver.dart';

enum PrescriptionPdfFailure { session, forbidden, notFound, invalid, unavailable }

/// A user-facing PDF failure. Never carries raw server text.
class PrescriptionPdfException implements Exception {
  const PrescriptionPdfException(this.failure, {this.statusCode});

  final PrescriptionPdfFailure failure;
  final int? statusCode;

  String get message => switch (failure) {
        PrescriptionPdfFailure.session =>
          'Your session has expired. Please sign in again.',
        PrescriptionPdfFailure.forbidden =>
          'You do not have permission to view this prescription.',
        PrescriptionPdfFailure.notFound => 'Prescription not available.',
        PrescriptionPdfFailure.invalid =>
          'The prescription file could not be read. Please try again.',
        PrescriptionPdfFailure.unavailable =>
          'The prescription PDF could not be loaded. Check your connection and try again.',
      };

  /// Worth retrying: the request or the file may succeed next time.
  bool get canRetry =>
      failure == PrescriptionPdfFailure.invalid ||
      failure == PrescriptionPdfFailure.unavailable;

  @override
  String toString() => message;
}

bool _looksLikePdf(Uint8List bytes) =>
    bytes.length > 8 &&
    bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46 && bytes[4] == 0x2D; // %PDF-

class PrescriptionPdfService {
  const PrescriptionPdfService._();

  static Future<Uint8List> fetch(String prescriptionId) async {
    final auth = AuthService.instance;
    final session = auth.currentSession ?? await auth.getStoredSession();
    if (session == null) {
      throw const PrescriptionPdfException(PrescriptionPdfFailure.session);
    }
    final uri = Uri.parse('${auth.baseUrl}/api/consultations/prescriptions/'
        '${Uri.encodeComponent(prescriptionId)}/pdf/');
    final http.Response response;
    try {
      response = await http.get(uri, headers: {
        // JSON is listed too so an error is always answerable: asking for the
        // PDF alone made the server reply 406 "Could not satisfy the request
        // Accept header." (PRESCRIPTION_PDF_VIEWER_AUDIT.md).
        'Accept': 'application/pdf, application/json;q=0.9',
        'Authorization': 'Bearer ${session.accessToken}',
      });
    } catch (_) {
      throw const PrescriptionPdfException(PrescriptionPdfFailure.unavailable);
    }
    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      final isPdf =
          response.headers['content-type']?.contains('application/pdf') == true;
      if (!isPdf || !_looksLikePdf(response.bodyBytes)) {
        throw PrescriptionPdfException(PrescriptionPdfFailure.invalid, statusCode: status);
      }
      return response.bodyBytes;
    }
    throw PrescriptionPdfException(
        switch (status) {
          401 => PrescriptionPdfFailure.session,
          403 => PrescriptionPdfFailure.forbidden,
          404 => PrescriptionPdfFailure.notFound,
          _ => PrescriptionPdfFailure.unavailable,
        },
        statusCode: status);
  }
}

Route<void>? _viewerRoute;

/// Opens the full-screen prescription viewer (view / print / download). A second
/// tap while a viewer is on screen is ignored — one route, one request. The
/// guard follows the route itself (not a flag reset when it pops), so a viewer
/// removed any other way — e.g. "Sign in" replacing the whole stack — can't
/// leave it stuck.
Future<void> showPrescriptionPdf(BuildContext context,
    {required String prescriptionId,
    String? reference,
    Future<Uint8List> Function()? loader}) async {
  if (_viewerRoute?.isActive ?? false) return;
  final route = MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => PrescriptionPdfViewer(
      prescriptionId: prescriptionId,
      reference: reference,
      loader: loader,
    ),
  );
  _viewerRoute = route;
  await Navigator.of(context).push(route);
}

class PrescriptionPdfViewer extends StatefulWidget {
  const PrescriptionPdfViewer({
    super.key,
    required this.prescriptionId,
    this.reference,
    this.loader,
  });

  final String prescriptionId;
  final String? reference;

  /// Test seam; defaults to [PrescriptionPdfService.fetch].
  final Future<Uint8List> Function()? loader;

  /// Where Download saves the bytes. Tests replace it; the app uses
  /// [savePdfToDevice] (browser download on web, Save dialog on Windows).
  @visibleForTesting
  static PdfSaver? debugSaverOverride;

  @override
  State<PrescriptionPdfViewer> createState() => _PrescriptionPdfViewerState();
}

class _PrescriptionPdfViewerState extends State<PrescriptionPdfViewer> {
  late Future<Uint8List> _pdf = _load();
  bool _downloading = false;

  Future<Uint8List> _load() async {
    final bytes = await (widget.loader ??
        () => PrescriptionPdfService.fetch(widget.prescriptionId))();
    if (!_looksLikePdf(bytes)) {
      throw const PrescriptionPdfException(PrescriptionPdfFailure.invalid);
    }
    return bytes;
  }

  void _retry() {
    setState(() {
      // FutureBuilder subscribes on the next frame; a failure that lands
      // before it must not surface as an unhandled error. ignore() only marks
      // the error as observed; FutureBuilder still receives it.
      _pdf = _load()..ignore();
    });
  }

  Future<void> _signIn() async {
    await AuthService.instance.clearSession();
    if (!mounted) return;
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.go(AppRoutes.login);
    } else {
      Navigator.of(context).pop();
    }
  }

  /// `FeatherFlow_Prescription_<reference>.pdf` (the id when no reference).
  String get _fileName =>
      prescriptionPdfFileName(widget.reference ?? widget.prescriptionId);

  /// Saves the PDF already on screen: the same authorised bytes, no second
  /// request. One download at a time; a double tap is ignored.
  Future<void> _download(Uint8List bytes) async {
    if (_downloading) return;
    setState(() => _downloading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final save = PrescriptionPdfViewer.debugSaverOverride ?? savePdfToDevice;
      final result = await save(bytes, _fileName);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          key: Key(result.outcome == PdfSaveOutcome.saved
              ? 'prescriptionPdfDownloaded'
              : 'prescriptionPdfDownloadCancelled'),
          content: Text(result.message),
          behavior: SnackBarBehavior.floating,
        ));
    } catch (_) {
      // Never the raw platform error (it can contain local paths).
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          key: const Key('prescriptionPdfDownloadFailed'),
          content: const Text('The PDF could not be saved. Please try again.'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 8),
          action: SnackBarAction(label: 'Retry', onPressed: () => _download(bytes)),
        ));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Widget _downloadButton(Uint8List bytes) => Builder(
        builder: (context) {
          final color = IconTheme.of(context).color;
          return TextButton.icon(
            key: const Key('prescriptionPdfDownload'),
            onPressed: _downloading ? null : () => _download(bytes),
            style: TextButton.styleFrom(
                foregroundColor: color, disabledForegroundColor: color),
            icon: _downloading
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: color))
                : const Icon(Icons.download),
            label: Text(_downloading ? 'Downloading…' : 'Download'),
          );
        },
      );

  Widget _failure(Object error) {
    final failure = error is PrescriptionPdfException
        ? error
        : const PrescriptionPdfException(PrescriptionPdfFailure.unavailable);
    return _PdfStateMessage(
      icon: switch (failure.failure) {
        PrescriptionPdfFailure.forbidden => Icons.lock_outline,
        PrescriptionPdfFailure.notFound => Icons.description_outlined,
        PrescriptionPdfFailure.session => Icons.login,
        _ => Icons.picture_as_pdf_outlined,
      },
      message: failure.message,
      action: switch (failure.failure) {
        PrescriptionPdfFailure.session => FilledButton.icon(
            key: const Key('prescriptionPdfSignIn'),
            onPressed: _signIn,
            icon: const Icon(Icons.login),
            label: const Text('Sign in'),
          ),
        _ when failure.canRetry => FilledButton.icon(
            key: const Key('prescriptionPdfRetry'),
            onPressed: _retry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        _ => OutlinedButton(
            key: const Key('prescriptionPdfClose'),
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Close'),
          ),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // The Download action needs the loaded bytes, so the whole page follows
    // the fetch: no button before the PDF is authorised and loaded (a 401 /
    // 403 / 404 never offers a download).
    return FutureBuilder<Uint8List>(
      future: _pdf,
      builder: (context, snapshot) {
        final loaded = snapshot.connectionState == ConnectionState.done &&
            snapshot.hasData;
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.reference == null
                ? 'Prescription PDF'
                : 'Prescription ${widget.reference}'),
            leading: IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
            ),
            actions: [
              if (loaded) _downloadButton(snapshot.data!),
              const SizedBox(width: 8),
            ],
          ),
          body: Builder(builder: (context) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(key: Key('prescriptionPdfLoading')),
                  SizedBox(height: 12),
                  Text('Loading prescription…'),
                ]),
              );
            }
            if (snapshot.hasError) return _failure(snapshot.error!);
            final bytes = snapshot.data!;
            return PdfPreview(
              key: const Key('prescriptionPdfPreview'),
              build: (_) async => bytes,
              pdfFileName: _fileName,
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
              allowPrinting: true,
              // Share replaced by the Download button in the app bar.
              allowSharing: false,
              // A file the renderer can't read (or pdf.js unavailable on
              // web): a clear message with Retry, never a raw renderer error.
              onError: (context, error) => _failure(
                  const PrescriptionPdfException(PrescriptionPdfFailure.invalid)),
            );
          }),
        );
      },
    );
  }
}

class _PdfStateMessage extends StatelessWidget {
  const _PdfStateMessage(
      {required this.icon, required this.message, required this.action});
  final IconData icon;
  final String message;
  final Widget action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48),
              const SizedBox(height: 12),
              Text(message,
                  key: const Key('prescriptionPdfError'),
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              action,
            ],
          ),
        ),
      );
}
