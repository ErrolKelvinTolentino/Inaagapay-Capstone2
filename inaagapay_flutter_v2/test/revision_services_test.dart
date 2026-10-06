import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:inaagapay_flutter_v2/screens/mother/help_support_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/services/child_record_export.dart';
import 'package:inaagapay_flutter_v2/services/growth_record_scores.dart';
import 'package:inaagapay_flutter_v2/services/mother_chat_context.dart';
import 'package:inaagapay_flutter_v2/services/mother_directory_order.dart';
import 'package:inaagapay_flutter_v2/services/pdf_fonts.dart';
import 'package:inaagapay_flutter_v2/services/report_export_service.dart';
import 'package:inaagapay_flutter_v2/services/speech_text.dart';
import 'package:inaagapay_flutter_v2/services/timed_async_cache.dart';
import 'package:inaagapay_flutter_v2/services/wav_audio.dart';
import 'support/fake_backend.dart';

Uint8List wave(List<int> pcm, {bool extended = false, int rate = 24000}) {
  final extra = extended ? 12 : 0;
  final bytes = Uint8List(44 + extra + pcm.length);
  final data = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, ascii.encode('RIFF'));
  data.setUint32(4, bytes.length - 8, Endian.little);
  bytes.setRange(8, 16, ascii.encode('WAVEfmt '));
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  if (extended) {
    bytes.setRange(36, 40, ascii.encode('JUNK'));
    data.setUint32(40, 4, Endian.little);
  }
  bytes.setRange(36 + extra, 40 + extra, ascii.encode('data'));
  data.setUint32(40 + extra, pcm.length, Endian.little);
  bytes.setRange(44 + extra, bytes.length, pcm);
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'speech keeps clinical values and accents but excludes emojis and action tags',
      () {
    expect(
        SpeechText.clean(
            '🌸 **Kumusta, Peñaflor!**\nBP 110/70, 24 weeks. ❤️ [SUGGEST: hello] [CALL_HOTLINE: 911]'),
        'Kumusta, Peñaflor! BP 110/70, 24 weeks.');
  });
  test('WAV joining rewrites lengths and skips extended chunk headers', () {
    final joined = WavAudio.concatenate([
      wave([1, 2, 3, 4], extended: true),
      wave([5, 6])
    ]);
    final data = ByteData.sublistView(joined);
    expect(data.getUint32(4, Endian.little), joined.length - 8);
    expect(data.getUint32(40, Endian.little), 6);
    expect(joined.sublist(44), [1, 2, 3, 4, 5, 6]);
    expect(
        () => WavAudio.concatenate([
              wave([1, 2]),
              wave([3, 4], rate: 16000)
            ]),
        throwsFormatException);
    expect(
        () => WavAudio.concatenate([
              [1, 2, 3]
            ]),
        throwsFormatException);
  });
  test(
      'directory sorts displayed patient numbers, keeps missing values last in both directions',
      () {
    final rows = [
      {'mother_id': 1, 'bhc_patient_id': 'INA-010'},
      {'mother_id': 99, 'bhc_patient_id': 'INA-002'},
      {'mother_id': 2, 'bhc_patient_id': null},
    ];
    rows.sort((a, b) => MotherDirectoryOrder.compare(a, b, 'ID Number', true));
    expect(rows.map((r) => r['mother_id']), [99, 1, 2]);
    rows.sort((a, b) => MotherDirectoryOrder.compare(a, b, 'ID Number', false));
    expect(rows.map((r) => r['mother_id']), [1, 99, 2]);
  });
  test(
      'cache shares requests, separates owners and ignores invalidated completions',
      () async {
    final cache = TimedAsyncCache<int>(const Duration(minutes: 1));
    final pending = Completer<int>();
    var calls = 0;
    final first = cache.get('owner-1', () {
      calls++;
      return pending.future;
    });
    final second = cache.get('owner-1', () async {
      calls++;
      return 7;
    });
    expect(calls, 1);
    cache.clear();
    pending.complete(3);
    expect(await first, 3);
    expect(await second, 3);
    expect(cache.peek('owner-1'), null);
    expect(await cache.get('owner-2', () async => 4), 4);
    expect(cache.peek('owner-1'), null);
  });
  test('missing sex or dates cannot produce a reassuring Z score', () {
    final scores = GrowthRecordScores(record: {
      'child_weight': 5,
      'child_height': 60,
      'created_at': '2026-10-07'
    }, birthdate: null, sex: null);
    expect(scores.weightZ, null);
    expect(GrowthRecordScores.interpretation(scores.weightZ),
        'Insufficient reference data');
  });
  test('bundled Unicode fonts render child reports and full history exports',
      () async {
    for (final name in ['regular', 'bold', 'italic', 'bolditalic']) {
      final asset = await rootBundle.load('assets/fonts/roboto-$name.ttf');
      expect(asset.lengthInBytes, greaterThan(10000));
    }
    await PdfFonts.theme();
    final doc = ChildRecordExport.build(
        child: {
          'child_id': 1,
          'first_name': 'Ana',
          'last_name': 'Peñaflor',
          'sex': 'female'
        },
        birth: {
          'birthdate': '2026-09-01'
        },
        growth: [
          {
            'created_at': '2026-10-01',
            'child_weight': 4.2,
            'child_height': 53.4
          },
        ],
        immunizations: List.generate(
            8,
            (i) => {
                  'vaccination_date': '2026-10-01',
                  'vaccine': {'vaccine_name': 'Example $i', 'dose_number': 1}
                }),
        kind: ChildExportKind.profile);
    expect(doc.blocks.last.rows.length, 8);
    expect(doc.blocks[1].columns, contains('Weight Z'));
    final pdf = await ReportExportService.toPdf(doc);
    expect(ascii.decode(pdf.sublist(0, 5)), '%PDF-');
    final output = Platform.environment['REPORT_SAMPLE_DIR'];
    if (output != null) File('$output/child.pdf').writeAsBytesSync(pdf);
  });
  group('current chatbot context', () {
    setUpAll(() async {
      await FakeBackend.init();
      await loadPhoneFonts();
    });
    setUp(FakeBackend.reset);
    test('refreshes ongoing pregnancy dates and upcoming appointments',
        () async {
      final lmp = DateTime.now().subtract(const Duration(days: 150));
      FakeBackend.tables.addAll({
        'pregnancies': [
          {
            'pregnancy_id': 4,
            'mother_id': 2,
            'status': 'ongoing',
            'last_menstrual_period': lmp.toIso8601String()
          }
        ],
        'mothers': [
          {'mother_id': 2, 'assigned_bhc_id': 3}
        ],
        'schedules': [
          {'mother_id': 2, 'status': 'scheduled', 'schedule_date': '2026-11-01'}
        ],
        'checkup_schedule': [],
        'prenatal_checkups': [],
        'immunization_schedule': [
          {'bhc_id': 3, 'schedule_date': '2026-11-02'}
        ],
      });
      final context = await MotherChatContext.load(2);
      expect(context.week, 21);
      expect(context.trimester, 'Second Trimester');
      expect(context.schedules, contains('Scheduled checkup: 2026-11-01'));
      expect(context.schedules.any((s) => s.contains('2026-11-02')), isTrue);
      expect(
          FakeBackend.requests.any((r) => r.contains('bhc_id=eq.3')), isTrue);
      FakeBackend.tables['pregnancies'] = [];
      expect((await MotherChatContext.load(2)).pregnancy, null);
    });
    test('child export loads all histories and refuses another mother\'s child',
        () async {
      FakeBackend.reset(storage: {'mother_id': '2', 'user_role': 'mother'});
      FakeBackend.tables.addAll({
        'children': [
          {
            'child_id': 7,
            'mother_id': 2,
            'child_number': 12,
            'first_name': 'Ana',
            'sex': 'female'
          }
        ],
        'birth_details': [
          {'child_id': 7, 'birthdate': '2026-09-01', 'birth_length': 49}
        ],
        'child_growth_records': List.generate(
            8,
            (i) => {
                  'child_id': 7,
                  'created_at': '2026-10-01',
                  'child_weight': 4.2,
                  'child_height': 53.4
                }),
        'immunization_records': List.generate(
            8,
            (i) => {
                  'child_id': 7,
                  'vaccination_date': '2026-10-01',
                  'remarks': 'Recorded note'
                }),
      });
      final doc = await ChildRecordExport.load(7, ChildExportKind.profile);
      expect(doc.periodLabel, 'NAK-012');
      expect(doc.blocks[1].rows.length, 8);
      expect(doc.blocks[2].rows.length, 8);
      expect(doc.blocks[2].rows.first.last, 'Recorded note');
      FakeBackend.requests.clear();
      await expectLater(ChildRecordExport.load(8, ChildExportKind.profile),
          throwsA(isA<Exception>()));
      expect(
          FakeBackend.requests.any((r) =>
              r.contains('immunization_records') ||
              r.contains('child_growth_records')),
          isFalse);
    });
    testWidgets(
        'Help and Support reads the linked facility and midwife contacts',
        (tester) async {
      FakeBackend.reset(storage: {'mother_id': '2', 'user_role': 'mother'});
      FakeBackend.tables.addAll({
        'mothers': [
          {'mother_id': 2, 'assigned_bhc_id': 3}
        ],
        'health_facilities': [
          {'facility_id': 3, 'name': 'Sabang BHC'}
        ],
        'midwives': [
          {
            'assigned_bhc_id': 3,
            'account': {
              'first_name': 'Maria',
              'last_name': 'Santos',
              'phone_number': '09171234567'
            }
          }
        ],
      });
      await tester.pumpWidget(const MaterialApp(home: HelpSupportScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Sabang BHC'), findsOneWidget);
      expect(find.text('Maria Santos'), findsOneWidget);
      expect(find.textContaining('not linked'), findsNothing);
    });
  });
}
