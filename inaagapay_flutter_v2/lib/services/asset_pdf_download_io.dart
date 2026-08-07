import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

Future<({bool handledByBrowser, String destination})> saveAssetPdf({
  required String assetPath,
  required String fileName,
}) async {
  final asset = await rootBundle.load(assetPath);

  Directory? destinationDirectory;
  try {
    destinationDirectory = await getDownloadsDirectory();
  } catch (_) {
    destinationDirectory = null;
  }
  destinationDirectory ??= await getApplicationDocumentsDirectory();

  final file = File(
    '${destinationDirectory.path}${Platform.pathSeparator}$fileName',
  );
  await file.writeAsBytes(
    asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
    flush: true,
  );

  return (handledByBrowser: false, destination: file.path);
}
