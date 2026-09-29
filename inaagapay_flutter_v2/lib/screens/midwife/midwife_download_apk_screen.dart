import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/app_download_link.dart';
import '../../theme/app_colors.dart';

class MidwifeDownloadApkScreen extends StatelessWidget {
  static const routeName = '/midwife-download-apk';

  final String downloadPageUrl;

  const MidwifeDownloadApkScreen({
    super.key,
    this.downloadPageUrl = AppDownloadLink.pageUrl,
  });

  Future<void> _openDownloadPage(BuildContext context, Uri uri) async {
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (opened || !context.mounted) return;
    } catch (_) {
      if (!context.mounted) return;
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'Could not open your browser. Copy the download link instead.'),
      ),
    );
  }

  Future<void> _copyLink(BuildContext context, Uri uri) async {
    await Clipboard.setData(ClipboardData(text: uri.toString()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Download link copied.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final downloadUri = AppDownloadLink.automaticDownloadUri(downloadPageUrl);

    return Scaffold(
      backgroundColor: AppColors.bgPrimaryOf(context),
      appBar: AppBar(
        title: const Text('Download InaAgapay'),
        backgroundColor: AppColors.bgPrimaryOf(context),
        foregroundColor: AppColors.brandText,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.android_rounded,
                    color: AppColors.brandPrimary,
                    size: 42,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Share the InaAgapay app',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.headingSoft,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Scan this QR code with an Android phone to download '
                    'the official InaAgapay APK.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.inputText, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  if (downloadUri != null) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.cardColorOf(context),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.borderPrimary),
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) => Center(
                          child: QrImageView(
                            data: downloadUri.toString(),
                            version: QrVersions.auto,
                            errorCorrectionLevel: QrErrorCorrectLevel.M,
                            size: math.min(300, constraints.maxWidth),
                            // Preserve a white quiet zone for camera scanners.
                            padding: const EdgeInsets.all(20),
                            backgroundColor: Colors.white,
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: Colors.black,
                            ),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: Colors.black,
                            ),
                            semanticsLabel:
                                'Scan to download the InaAgapay Android app',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () => _openDownloadPage(context, downloadUri),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.brandText,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 14),
                      ),
                      icon: const Icon(Icons.open_in_browser_rounded),
                      label: const Text('Open download page',
                          textAlign: TextAlign.center),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _copyLink(context, downloadUri),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.brandText,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 14),
                      ),
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('Copy download link',
                          textAlign: TextAlign.center),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      downloadUri.host,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppColors.inputText, fontSize: 12),
                    ),
                  ] else
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.link_off_rounded,
                              color: AppColors.brandText),
                          SizedBox(height: 12),
                          Text(
                            'Download link unavailable',
                            style: TextStyle(fontWeight: FontWeight.w700),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Please ask your administrator for the official app download link.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.bgSecondaryOf(context),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'On the phone receiving the app',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.brandText,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '1. Scan the code with Camera or Google Lens and open the link.\n'
                          '2. Open it in your browser. If prompted, tap Get InaAgapay.\n'
                          '3. Find inaagapay.apk in Files > Downloads and tap it to install.',
                          style: TextStyle(
                              color: AppColors.inputText, height: 1.6),
                        ),
                        SizedBox(height: 12),
                        Text(
                          'The APK is for Android. Your browser controls the save location; '
                          'keep its download location set to Downloads. If Android asks, '
                          'allow your browser to install this app.',
                          style: TextStyle(
                              color: AppColors.inputText, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
