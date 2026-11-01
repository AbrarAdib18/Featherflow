// Saving a PDF the user is already authorised to see onto their device
// (PRESCRIPTION_PDF_DOWNLOAD_FIX.md). The bytes come from the viewer, which
// fetched them from the access-controlled endpoint; nothing here talks to the
// backend.
//
//   web:     browser download (Blob + <a download>)
//   Windows: the native "Save as" dialog (Windows confirms before
//            overwriting), then the app writes the file
import 'dart:typed_data';

import 'pdf_saver_io.dart' if (dart.library.js_interop) 'pdf_saver_web.dart' as platform;

enum PdfSaveOutcome { saved, cancelled }

class PdfSaveResult {
  const PdfSaveResult(this.outcome, this.message);
  const PdfSaveResult.cancelled() : this(PdfSaveOutcome.cancelled, 'Download cancelled.');

  final PdfSaveOutcome outcome;

  /// User-facing confirmation, e.g. "Downloaded FeatherFlow_Prescription_….pdf".
  /// Never contains a server or internal storage path.
  final String message;
}

typedef PdfSaver = Future<PdfSaveResult> Function(Uint8List bytes, String fileName);

/// `FeatherFlow_Prescription_<reference>.pdf`, reduced to characters that are
/// safe in a file name on every platform (no path separators, no `..`).
String prescriptionPdfFileName(String reference) {
  final safe = reference.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_').replaceAll(RegExp(r'_+'), '_');
  final trimmed = safe.replaceAll(RegExp(r'^_|_$'), '');
  return 'FeatherFlow_Prescription_${trimmed.isEmpty ? 'document' : trimmed}.pdf';
}

/// Saves [bytes] as [fileName] on this device. Throws on failure (the caller
/// shows the error with Retry).
Future<PdfSaveResult> savePdfToDevice(Uint8List bytes, String fileName) =>
    platform.savePdf(bytes, fileName);
