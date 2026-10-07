import 'package:supabase_flutter/supabase_flutter.dart';
import 'growth_record_scores.dart';
import 'report_export_service.dart';
import 'supabase_service.dart';
import 'auth_storage.dart';

enum ChildExportKind { profile, growth, immunization }

class ChildRecordExport {
  const ChildRecordExport._();

  static Future<ReportDocument> load(int childId, ChildExportKind kind) async {
    final client = Supabase.instance.client;
    var childQuery = client.from('children').select('''
      *, mother:mother_id(barangay, city_municipality, province,
        account:account_id(first_name, middle_name, last_name, phone_number)),
      guardian:guardian_id(first_name, middle_name, last_name, phone_number, address, relationship)
    ''').eq('child_id', childId);
    if ((await AuthStorage.getUserRole())?.toLowerCase() == 'mother') {
      final motherId = await AuthStorage.getMotherId();
      if (motherId == null) {
        throw StateError('Sign in to export your child records.');
      }
      childQuery = childQuery.eq('mother_id', motherId);
    }
    // Verify the child belongs to the signed-in mother before reading history.
    final child = Map<String, dynamic>.from(await childQuery.single());
    final rows = await Future.wait<dynamic>([
      client
          .from('birth_details')
          .select('*')
          .eq('child_id', childId)
          .maybeSingle(),
      if (kind != ChildExportKind.immunization)
        client
            .from('child_growth_records')
            .select('*')
            .eq('child_id', childId)
            .order('created_at'),
      if (kind != ChildExportKind.growth)
        client
            .from('immunization_records')
            .select(
                '*, vaccine:vaccine_id(vaccine_name, dose_number), batch:inventory_batch_id(batch_number)')
            .eq('child_id', childId)
            .order('vaccination_date'),
    ]);
    final birth = rows[0] == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(rows[0] as Map);
    final growth = kind == ChildExportKind.immunization
        ? <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(rows[1]);
    final immunizations = kind == ChildExportKind.growth
        ? <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(rows.last);
    return build(
        child: child,
        birth: birth,
        growth: growth,
        immunizations: immunizations,
        kind: kind);
  }

  static ReportDocument build(
      {required Map<String, dynamic> child,
      required Map<String, dynamic> birth,
      required List<Map<String, dynamic>> growth,
      required List<Map<String, dynamic>> immunizations,
      required ChildExportKind kind}) {
    final birthdate = DateTime.tryParse(birth['birthdate']?.toString() ?? '');
    final name = ['first_name', 'middle_name', 'last_name', 'extension_name']
        .map((key) => child[key]?.toString() ?? '')
        .where((v) => v.isNotEmpty)
        .join(' ');
    final mother = child['mother'] as Map?;
    final guardian = child['guardian'] as Map?;
    final parent = guardian ?? mother?['account'] as Map?;
    final parentName = parent == null
        ? ''
        : ['first_name', 'middle_name', 'last_name']
            .map((key) => parent[key]?.toString() ?? '')
            .where((v) => v.isNotEmpty)
            .join(' ');
    final address = guardian?['address'] ??
        (mother == null
            ? ''
            : ['barangay', 'city_municipality', 'province']
                .map((key) => mother[key]?.toString() ?? '')
                .where((v) => v.isNotEmpty)
                .join(', '));
    return ReportDocument(
        title: switch (kind) {
          ChildExportKind.profile => 'Child Record',
          ChildExportKind.growth => 'Child Growth Records',
          ChildExportKind.immunization => 'Child Immunization Records',
        },
        facilityName: name,
        facilityLabel: 'Child',
        periodLabel: SupabaseService.formatChildNumber(
                int.tryParse(child['child_number']?.toString() ?? '')) ??
            'Not assigned',
        periodCaption: 'Child number',
        preparedBy: 'InaAgapay',
        includeSignatures: false,
        landscape: kind != ChildExportKind.profile,
        blocks: [
          ReportBlock(
              title: 'Child details',
              columns: const ['Field', 'Recorded value'],
              showRowCount: false,
              rows: [
                ['Name', name],
                ['Sex', child['sex']],
                ['Birthdate', birthdate],
                [
                  'Birthplace',
                  [
                    'birthplace_facility',
                    'birthplace_city_municipality',
                    'birthplace_province'
                  ]
                      .map((key) => birth[key]?.toString() ?? '')
                      .where((v) => v.isNotEmpty)
                      .join(', ')
                ],
                ['Birth weight (kg)', birth['birth_weight']],
                ['Birth length (cm)', birth['birth_length']],
                ['Parent or guardian', parentName],
                [
                  'Relationship',
                  guardian?['relationship'] ?? (mother == null ? '' : 'Mother')
                ],
                ['Contact number', parent?['phone_number']],
                ['Address', address],
              ]),
          if (kind != ChildExportKind.immunization)
            ReportBlock(title: 'Growth measurements', columns: const [
              'Measured on',
              'Weight (kg)',
              'Height (cm)',
              'Weight Z',
              'Interpretation',
              'Height Z',
              'Interpretation'
            ], rows: [
              for (final record in growth)
                _growthRow(record, birthdate, child['sex']?.toString())
            ], notes: const [
              'Z scores use the recorded age and sex on the measurement date and the app\'s WHO reference data. Missing measurements or reference data are shown as unavailable.'
            ]),
          if (kind != ChildExportKind.growth)
            ReportBlock(title: 'Immunizations given', columns: const [
              'Date',
              'Vaccine',
              'Dose',
              'Batch',
              'Notes'
            ], rows: [
              for (final row in immunizations)
                [
                  DateTime.tryParse(row['vaccination_date']?.toString() ?? ''),
                  (row['vaccine'] as Map?)?['vaccine_name'],
                  (row['vaccine'] as Map?)?['dose_number'],
                  (row['batch'] as Map?)?['batch_number'],
                  row['remarks'] ?? row['notes']
                ],
            ]),
        ]);
  }

  static List<Object?> _growthRow(
      Map<String, dynamic> row, DateTime? birthdate, String? sex) {
    final scores =
        GrowthRecordScores(record: row, birthdate: birthdate, sex: sex);
    return [
      DateTime.tryParse(row['created_at']?.toString() ?? ''),
      row['child_weight'],
      row['child_height'],
      GrowthRecordScores.value(scores.weightZ),
      GrowthRecordScores.interpretation(scores.weightZ),
      GrowthRecordScores.value(scores.heightZ),
      GrowthRecordScores.interpretation(scores.heightZ)
    ];
  }
}
