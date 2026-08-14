import 'package:web/web.dart' as web;

Future<({bool handledByBrowser, String destination})> saveAssetPdf({
  required String assetPath,
  required String fileName,
}) async {
  final anchor = web.HTMLAnchorElement()
    ..href = 'assets/$assetPath'
    ..download = fileName
    ..style.display = 'none';

  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();

  return (handledByBrowser: true, destination: fileName);
}
