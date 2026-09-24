// lib/services/export_file_saver.dart
//
// Hands a generated report to the person who asked for it.
//
//   Android / iOS   the system "Save as" sheet, so the file lands where she
//                   chooses (Downloads, Drive) instead of in app storage that
//                   no file manager can reach
//   desktop         the native save dialog
//   web             a browser download

import 'dart:typed_data';

import 'export_file_saver_stub.dart'
    if (dart.library.io) 'export_file_saver_io.dart'
    if (dart.library.js_interop) 'export_file_saver_web.dart' as implementation;

class ExportSaveResult {
  const ExportSaveResult({required this.saved, this.location});

  /// False when the person closed the save dialog without choosing a place.
  final bool saved;

  /// Where the file went, when the platform says.
  final String? location;
}

class ExportFileSaver {
  const ExportFileSaver._();

  static const pdfMime = 'application/pdf';
  static const xlsxMime =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  static Future<ExportSaveResult> save({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final location = await implementation.saveBytes(
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
    );
    return ExportSaveResult(saved: location != null, location: location);
  }
}
