// Web: hand the bytes to the browser as a download. No file path exists on the
// web; the browser saves it to the user's download location.
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'pdf_saver.dart';

Future<PdfSaveResult> savePdf(Uint8List bytes, String fileName) async {
  final blob = web.Blob(
      <JSAny>[bytes.toJS].toJS, web.BlobPropertyBag(type: 'application/pdf'));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body!.append(anchor);
  try {
    anchor.click();
  } finally {
    anchor.remove();
    // Give the browser a moment to start the download before the blob URL
    // is released.
    Future<void>.delayed(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
  }
  return PdfSaveResult(PdfSaveOutcome.saved, 'Downloaded $fileName');
}
