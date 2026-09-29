import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/screens/midwife/midwife_download_apk_screen.dart';
import 'package:inaagapay_flutter_v2/services/app_download_link.dart';
import 'package:inaagapay_flutter_v2/widgets/main_header.dart';
import 'package:qr_flutter/qr_flutter.dart';

const _officialUrl =
    'https://inaagapay-capstone.vercel.app/download.html?auto=1';

Future<void> _pumpDownloadScreen(
  WidgetTester tester, {
  Size size = const Size(375, 812),
  double textScale = 1,
  String downloadPageUrl = AppDownloadLink.pageUrl,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: MidwifeDownloadApkScreen(downloadPageUrl: downloadPageUrl),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('public APK download link', () {
    test('the QR targets the official page with automatic browser download',
        () {
      expect(AppDownloadLink.automaticDownloadUri().toString(), _officialUrl);
    });

    test('a deployment override keeps its query and sets auto=1', () {
      final uri = AppDownloadLink.automaticDownloadUri(
        ' https://example.com/download.html?source=midwife&auto=0#instructions ',
      );
      expect(uri?.host, 'example.com');
      expect(uri?.queryParameters, {'source': 'midwife', 'auto': '1'});
      expect(uri?.fragment, isEmpty);
    });

    test('an invalid public URL never becomes a QR code', () {
      for (final value in [
        '',
        'download.html',
        'http://example.com/download.html',
        'javascript:alert(1)',
        'https://user:secret@example.com/download.html',
      ]) {
        expect(AppDownloadLink.automaticDownloadUri(value), isNull);
      }
    });
  });

  testWidgets('profile action closes the menu and opens the APK QR screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: {
          MidwifeDownloadApkScreen.routeName: (_) =>
              const MidwifeDownloadApkScreen(),
        },
        home: Builder(
          builder: (context) => Scaffold(
            body: MainHeader(
              title: 'Home',
              onReports: () {},
              onDownloadApk: () => Navigator.pushNamed(
                context,
                MidwifeDownloadApkScreen.routeName,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.person));
    await tester.pumpAndSettle();
    expect(find.text('Download APK QR code'), findsOneWidget);

    await tester.tap(find.text('Download APK QR code'));
    await tester.pumpAndSettle();

    expect(find.byType(MidwifeDownloadApkScreen), findsOneWidget);
    expect(find.text('Download APK QR code'), findsNothing);
    final qr = tester.widget<QrImageView>(find.byType(QrImageView));
    expect(qr.backgroundColor, Colors.white);
    expect(qr.padding, const EdgeInsets.all(20));
    final paintedQr = tester
        .widget<CustomPaint>(
          find.descendant(
              of: find.byType(QrImageView), matching: find.byType(CustomPaint)),
        )
        .painter as QrPainter;
    // Compare the rendered pattern against the public URL independently, as
    // QrImageView keeps its encoded data private.
    final expectedQr = QrPainter(
      data: _officialUrl,
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
      gapless: qr.gapless,
      eyeStyle: qr.eyeStyle,
      dataModuleStyle: qr.dataModuleStyle,
    );
    final images = await tester.runAsync(
      () => Future.wait(
          [paintedQr.toImageData(256), expectedQr.toImageData(256)]),
    );
    expect(images, hasLength(2));
    expect(images![0], isNotNull);
    expect(images[1], isNotNull);
    expect(images[0]!.buffer.asUint8List(), images[1]!.buffer.asUint8List());
    expect(tester.takeException(), isNull);
  });

  testWidgets('the profile menu omits APK sharing when it is not enabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MainHeader(title: 'Home'))),
    );
    await tester.tap(find.byIcon(Icons.person));
    await tester.pumpAndSettle();
    expect(find.text('View Profile'), findsOneWidget);
    expect(find.text('Download APK QR code'), findsNothing);

    // Remove the overlay before the test finishes.
    await tester.tapAt(const Offset(20, 400));
    await tester.pumpAndSettle();
  });

  testWidgets('QR and actions stay usable on a small phone with larger text', (
    tester,
  ) async {
    await _pumpDownloadScreen(
      tester,
      size: const Size(320, 568),
      textScale: 1.6,
    );
    expect(find.byType(QrImageView), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Open download page'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Copy download link'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the menu is scrollable on a short landscape phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(568, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var selected = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MainHeader(
            title: 'Home',
            onReports: () {},
            onDownloadApk: () => selected = true,
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.person));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Download APK QR code'));
    await tester.tap(find.text('Download APK QR code'));
    await tester.pumpAndSettle();
    expect(selected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('copy link shares the same URL encoded by the QR',
      (tester) async {
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await _pumpDownloadScreen(tester);
    await tester.ensureVisible(find.text('Copy download link'));
    await tester.tap(find.text('Copy download link'));
    await tester.pumpAndSettle();

    expect(copiedText, _officialUrl);
    expect(find.text('Download link copied.'), findsOneWidget);
  });

  testWidgets('open download page uses the external browser', (tester) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    Map? launchArguments;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        if (call.method == 'launch') {
          launchArguments = call.arguments as Map;
          return true;
        }
        return false;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    await _pumpDownloadScreen(tester);
    await tester.ensureVisible(find.text('Open download page'));
    await tester.tap(find.text('Open download page'));
    await tester.pumpAndSettle();

    expect(launchArguments?['url'], _officialUrl);
    expect(launchArguments?['useWebView'], isFalse);
    expect(launchArguments?['useSafariVC'], isFalse);
  });

  testWidgets('browser launch failure keeps copy-link recovery available', (
    tester,
  ) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => false,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    await _pumpDownloadScreen(tester);
    await tester.ensureVisible(find.text('Open download page'));
    await tester.tap(find.text('Open download page'));
    await tester.pumpAndSettle();

    expect(find.text('Copy download link'), findsOneWidget);
    expect(
      find.text('Could not open your browser. Copy the download link instead.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing configuration shows a readable fallback',
      (tester) async {
    await _pumpDownloadScreen(tester, downloadPageUrl: '');
    expect(find.text('Download link unavailable'), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);
    expect(find.text('Open download page'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
