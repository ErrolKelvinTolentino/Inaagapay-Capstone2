import 'asset_pdf_download_stub.dart'
    if (dart.library.io) 'asset_pdf_download_io.dart'
    if (dart.library.js_interop) 'asset_pdf_download_web.dart'
    as implementation;

class AssetPdfDownloadResult {
  final bool handledByBrowser;
  final String destination;

  const AssetPdfDownloadResult({
    required this.handledByBrowser,
    required this.destination,
  });
}

Future<AssetPdfDownloadResult> downloadAssetPdf({
  required String assetPath,
  required String fileName,
}) async {
  final result = await implementation.saveAssetPdf(
    assetPath: assetPath,
    fileName: fileName,
  );

  return AssetPdfDownloadResult(
    handledByBrowser: result.handledByBrowser,
    destination: result.destination,
  );
}
