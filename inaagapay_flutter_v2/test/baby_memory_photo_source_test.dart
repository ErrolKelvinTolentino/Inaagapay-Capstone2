import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/models/baby_memory.dart';
import 'package:inaagapay_flutter_v2/widgets/baby_memory_photo.dart';

/// Where a memory's picture comes from.
///
/// A memory has three possible sources and only one of them survives closing
/// the app. Before this, `BabyMemory` had two — freshly picked bytes and
/// bundled sample artwork — which is why a saved photo could not be shown
/// even in principle: there was no field for a photo that lives in storage,
/// and `loadMemories` did not read one.
Widget _wrap(BabyMemory memory) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 200,
          height: 200,
          child: BabyMemoryPhoto(memory: memory),
        ),
      ),
    );

void main() {
  test('a memory must have some picture to show', () {
    // The assertion is the guard: a memory with a caption and no image is a
    // gallery tile that renders an empty frame.
    expect(
      () => BabyMemory(
        id: 'x',
        title: 'No picture',
        caption: '',
        date: DateTime(2026, 8, 1),
      ),
      throwsA(isA<AssertionError>()),
    );
  });

  test('a stored photo is enough on its own', () {
    // The case that matters after a restart: no bytes in memory, no bundled
    // asset, just the URL the row points at.
    final memory = BabyMemory(
      id: 'memory-1',
      title: 'Our first ultrasound',
      caption: 'The first little glimpse.',
      date: DateTime(2026, 8, 1),
      imageUrl: 'https://example.test/photo.jpg',
    );
    expect(memory.imageUrl, isNotNull);
    expect(memory.imageBytes, isNull);
    expect(memory.assetPath, isNull);
  });

  testWidgets('a stored photo renders without bytes or an asset', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        BabyMemory(
          id: 'memory-1',
          title: 'Our first ultrasound',
          caption: '',
          date: DateTime(2026, 8, 1),
          imageUrl: 'https://example.test/photo.jpg',
        ),
      ),
    );
    await tester.pump();

    // Image.network, not the asset branch. In the test harness the request
    // itself fails and the error frame is drawn, which is the point: the
    // widget reached for the network at all.
    expect(find.byType(Image), findsOneWidget);
    expect(
      tester.widget<Image>(find.byType(Image)).image,
      isA<NetworkImage>(),
    );
  });

  testWidgets('freshly picked bytes are preferred while they are in hand', (
    tester,
  ) async {
    // Both sources present: show the bytes, which need no round trip.
    await tester.pumpWidget(
      _wrap(
        BabyMemory(
          id: 'memory-1',
          title: 'Just picked',
          caption: '',
          date: DateTime(2026, 8, 1),
          imageBytes: Uint8List.fromList(const <int>[1, 2, 3]),
          imageUrl: 'https://example.test/photo.jpg',
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.widget<Image>(find.byType(Image)).image,
      isA<MemoryImage>(),
    );
  });
}
