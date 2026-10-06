import 'package:supabase_flutter/supabase_flutter.dart';
import 'pregnancy_stage.dart';

/// Current recorded facts, refreshed before every response rather than inferred
/// from the greeting or from older conversation messages.
class MotherChatContext {
  const MotherChatContext({required this.pregnancy, required this.schedules});
  final Map<String, dynamic>? pregnancy;
  final List<String> schedules;

  int? get days => pregnancy == null
      ? null
      : PregnancyStage.gestationalDays(
          lmp: PregnancyStage.parse(pregnancy!['last_menstrual_period']),
          edd: PregnancyStage.parse(pregnancy!['expected_date_of_delivery']),
          now: DateTime.now(),
        );
  int? get week =>
      days == null || days! < 0 ? null : PregnancyStage.completedWeeks(days!);
  String get trimester => days == null || days! < 0
      ? 'Not recorded'
      : switch (PregnancyStage.trimesterOf(days!)) {
          Trimester.first => 'First Trimester',
          Trimester.second => 'Second Trimester',
          Trimester.third => 'Third Trimester',
        };

  static Future<MotherChatContext> load(int motherId) async {
    final client = Supabase.instance.client;
    final today = DateTime.now().toIso8601String().split('T').first;
    final base = await Future.wait([
      client
          .from('pregnancies')
          .select(
              'pregnancy_id, last_menstrual_period, expected_date_of_delivery, pregnancy_risk_level')
          .eq('mother_id', motherId)
          .eq('status', 'ongoing')
          .order('created_at', ascending: false)
          .limit(1),
      client
          .from('mothers')
          .select('assigned_bhc_id')
          .eq('mother_id', motherId)
          .limit(1),
    ]);
    final pregnancy =
        base[0].isEmpty ? null : Map<String, dynamic>.from(base[0].first);
    final facility = base[1].isEmpty ? null : base[1].first['assigned_bhc_id'];
    final dates = <String>{};
    Future<void> collect(
        Future<dynamic> query, String dateKey, String label) async {
      try {
        final rows = await query;
        for (final row in rows as List) {
          final date = row[dateKey]?.toString();
          if (date != null) dates.add('$label: $date');
        }
      } catch (_) {
        dates.add('$label: schedule data unavailable; do not infer dates');
      }
    }

    await Future.wait([
      collect(
          client
              .from('schedules')
              .select('schedule_date')
              .eq('mother_id', motherId)
              .eq('status', 'scheduled')
              .gte('schedule_date', today)
              .order('schedule_date')
              .limit(20),
          'schedule_date',
          'Scheduled checkup'),
      collect(
          client
              .from('checkup_schedule')
              .select('scheduled_date')
              .eq('mother_id', motherId)
              .eq('status', 'scheduled')
              .gte('scheduled_date', today)
              .order('scheduled_date')
              .limit(20),
          'scheduled_date',
          'Scheduled checkup'),
      if (pregnancy != null)
        collect(
            client
                .from('prenatal_checkups')
                .select('next_schedule')
                .eq('pregnancy_id', pregnancy['pregnancy_id'])
                .gte('next_schedule', today)
                .order('next_schedule')
                .limit(20),
            'next_schedule',
            'Prenatal follow-up'),
      if (facility != null)
        collect(
            client
                .from('immunization_schedule')
                .select('schedule_date')
                .eq('bhc_id', facility)
                .gte('schedule_date', today)
                .order('schedule_date')
                .limit(20),
            'schedule_date',
            'Health center immunization session (confirm eligibility with midwife)'),
    ]);
    final sorted = dates.toList()..sort();
    return MotherChatContext(pregnancy: pregnancy, schedules: sorted);
  }
}
