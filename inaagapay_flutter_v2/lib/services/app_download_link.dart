/// Public website address, configurable when building for another deployment:
/// --dart-define=APP_DOWNLOAD_PAGE_URL=https://example.com/download.html
class AppDownloadLink {
  static const pageUrl = String.fromEnvironment(
    'APP_DOWNLOAD_PAGE_URL',
    defaultValue: 'https://inaagapay-capstone.vercel.app/download.html',
  );

  /// The public website starts a browser download and provides a button when
  /// the scanner's browser requires a tap before it will save the APK.
  static Uri? automaticDownloadUri([String downloadPageUrl = pageUrl]) {
    final page = Uri.tryParse(downloadPageUrl.trim());
    if (page == null ||
        page.scheme != 'https' ||
        page.host.isEmpty ||
        page.userInfo.isNotEmpty) {
      return null;
    }

    return page.replace(
      queryParameters: {...page.queryParameters, 'auto': '1'},
    ).removeFragment();
  }
}
