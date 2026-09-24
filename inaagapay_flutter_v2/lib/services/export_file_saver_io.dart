import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Returns where the file was written, or null when the dialog was cancelled.
Future<String?> saveBytes({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) async {
  final extension = fileName.contains('.') ? fileName.split('.').last : null;
  final path = await FilePicker.platform.saveFile(
    fileName: fileName,
    bytes: bytes,
    type: extension == null ? FileType.any : FileType.custom,
    allowedExtensions: extension == null ? null : [extension],
  );
  if (path == null) return null;

  // On Android and iOS the plugin has already written the bytes. On desktop it
  // only returns the chosen path, so the write is ours.
  if (!Platform.isAndroid && !Platform.isIOS) {
    await File(path).writeAsBytes(bytes, flush: true);
  }
  return path;
}
