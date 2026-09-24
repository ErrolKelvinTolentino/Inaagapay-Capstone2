import 'dart:typed_data';

Future<String?> saveBytes({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) {
  throw UnsupportedError('Saving files is not supported on this platform.');
}
