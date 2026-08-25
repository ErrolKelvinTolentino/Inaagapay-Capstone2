import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/widgets/baby_book/memory_details_dialog.dart';

/// The dialog that broke the add-photo flow.
///
/// Its content — a 130px preview above a single-line field and a three-line
/// field — is taller than an `AlertDialog` is given on a short window. As an
/// unscrollable Column that threw during layout on every frame, and once
/// layout was throwing, pointer handling asserted too: the page was left
/// dimmed by a barrier with no usable dialog on it, and the console filled
/// with mouse-tracker assertions. Nothing in the suite covered it because the
/// dialog lived inside a closure behind an image picker.
///
/// A 1x1 PNG. Small enough to inline, and real enough to decode.
final Uint8List _pngBytes = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

Future<MemoryDetails?> _open(WidgetTester tester, {Uint8List? bytes}) async {
  MemoryDetails? result;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<MemoryDetails>(
                context: context,
                builder: (_) =>
                    MemoryDetailsDialog(imageBytes: bytes ?? _pngBytes),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('lays out on a short window without overflowing', (tester) async {
    // Short on purpose: this is the window height the flow actually failed at.
    tester.view.physicalSize = const Size(390, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final errors = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) => errors.add(details.exception.toString());

    await _open(tester);

    FlutterError.onError = previous;
    expect(
      errors,
      isEmpty,
      reason: 'the dialog must fit, or scroll — never overflow',
    );
    expect(find.byKey(const ValueKey('memory-details-dialog')), findsOneWidget);
    expect(find.byKey(const ValueKey('memory-save')), findsOneWidget);
  });

  testWidgets('stays usable on a very short window', (tester) async {
    tester.view.physicalSize = const Size(360, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final errors = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) => errors.add(details.exception.toString());

    await _open(tester);

    FlutterError.onError = previous;
    expect(errors, isEmpty);
    // Save has to be reachable, not merely present: a dialog she cannot
    // confirm is the same failure wearing a different coat.
    await tester.ensureVisible(find.byKey(const ValueKey('memory-save')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('memory-save')).hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('an undecodable photo does not take the dialog down', (
    tester,
  ) async {
    // A HEIC from an iPhone, or a renamed file. She should still be able to
    // name it and save it rather than meeting a broken screen.
    final errors = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) => errors.add(details.exception.toString());

    await _open(
      tester,
      bytes: Uint8List.fromList(const <int>[1, 2, 3, 4, 5, 6, 7, 8]),
    );
    await tester.pump(const Duration(milliseconds: 100));

    FlutterError.onError = previous;
    expect(find.byKey(const ValueKey('memory-details-dialog')), findsOneWidget);
    expect(find.byKey(const ValueKey('memory-save')), findsOneWidget);
    expect(
      errors.where((e) => e.contains('overflowed')),
      isEmpty,
      reason: 'a failed decode must not become a layout failure',
    );
  });

  testWidgets('empty fields fall back rather than saving a blank memory', (
    tester,
  ) async {
    await _open(tester);

    await tester.enterText(
      find.byKey(const ValueKey('memory-title-field')),
      '',
    );
    await tester.tap(find.byKey(const ValueKey('memory-save')));
    await tester.pumpAndSettle();

    // The dialog closed with something usable rather than an untitled row.
    expect(find.byKey(const ValueKey('memory-details-dialog')), findsNothing);
  });
}
