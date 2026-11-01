// Windows (and other native platforms): ask where to save with the system
// "Save as" dialog, then write the bytes there.
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'pdf_saver.dart';

Future<PdfSaveResult> savePdf(Uint8List bytes, String fileName) async {
  if (Platform.isAndroid || Platform.isIOS) {
    // Mobile pickers write the bytes themselves.
    final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save prescription PDF', fileName: fileName,
        type: FileType.custom, allowedExtensions: const ['pdf'], bytes: bytes);
    return path == null
        ? const PdfSaveResult.cancelled()
        : PdfSaveResult(PdfSaveOutcome.saved, 'Saved $fileName');
  }
  // Desktop: the dialog starts with the suggested name; Windows itself asks
  // before replacing an existing file, so nothing is overwritten silently.
  final chosen = await FilePicker.platform.saveFile(
    dialogTitle: 'Save prescription PDF',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
    lockParentWindow: true,
  );
  if (chosen == null) return const PdfSaveResult.cancelled();
  final path = chosen.toLowerCase().endsWith('.pdf') ? chosen : '$chosen.pdf';
  final file = File(path);
  await file.writeAsBytes(bytes, flush: true);
  // Name and folder the user chose; never an app-internal path.
  return PdfSaveResult(PdfSaveOutcome.saved,
      'Saved ${file.uri.pathSegments.last} to ${file.parent.uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? 'the selected folder'}');
}
