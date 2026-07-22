// lib/models/obstetric_score.dart

class ObstetricScore {
  final int gravida;
  final int para;
  final int abortus;
  final int livingChildren;

  const ObstetricScore({
    required this.gravida,
    required this.para,
    required this.abortus,
    required this.livingChildren,
  });

  /// Formatted string like "G2 P1 A0"
  String get formattedGpa => 'G$gravida P$para A$abortus';

  /// Formatted string with bullets like "G2 • P1 • A0"
  String get formattedGpaBullet => 'G$gravida • P$para • A$abortus';

  /// Formatted string like "G2 P1 A0 L1"
  String get formattedGpal => formattedGpa;

  /// Formatted string with bullets like "G2 • P1 • A0 • L1"
  String get formattedGpalBullet => formattedGpaBullet;

  /// Calculates G-P-A-L dynamically from past pregnancy items + current pregnancy status
  factory ObstetricScore.calculate({
    required List<dynamic> pastPregnancies,
    required bool isCurrentlyPregnant,
  }) {
    int g = pastPregnancies.length + (isCurrentlyPregnant ? 1 : 0);
    int p = 0;
    int a = 0;
    int l = 0;

    for (final item in pastPregnancies) {
      int fetalCount = 1;
      double? gestationalAge;
      List<String> outcomesList = [];

      if (item is Map<String, dynamic>) {
        fetalCount = (item['fetal_count'] as num?)?.toInt() ??
            (item['fetalCount'] as num?)?.toInt() ??
            1;
        gestationalAge =
            (item['gestational_age_at_end'] as num?)?.toDouble() ??
                (item['gestationalAgeAtEnd'] as num?)?.toDouble();

        if (item['outcomes'] is List && (item['outcomes'] as List).isNotEmpty) {
          final subOutcomes = item['outcomes'] as List;
          for (final o in subOutcomes) {
            if (o is Map) {
              final val = (o['outcome'] ?? '').toString();
              if (val.isNotEmpty) outcomesList.add(val);
              gestationalAge ??=
                  (o['gestational_age_at_end'] as num?)?.toDouble();
            }
          }
        } else if (item['outcome'] != null) {
          outcomesList.add(item['outcome'].toString());
        }
      } else {
        // Dynamic object access for _PastPregnancy or similar class instances
        try {
          fetalCount = (item.fetalCount as num?)?.toInt() ?? 1;
        } catch (_) {}
        try {
          gestationalAge = (item.gestationalAgeAtEnd as num?)?.toDouble();
        } catch (_) {}

        try {
          final list = item.outcomes as List?;
          if (list != null && list.isNotEmpty) {
            for (final sub in list) {
              try {
                final val = (sub.outcome ?? '').toString();
                if (val.isNotEmpty) outcomesList.add(val);
              } catch (_) {}
            }
          }
        } catch (_) {}

        if (outcomesList.isEmpty) {
          try {
            final val = (item.outcome ?? '').toString();
            if (val.isNotEmpty) outcomesList.add(val);
          } catch (_) {}
        }
      }

      if (outcomesList.isEmpty) {
        outcomesList.add('live_birth');
      }

      final normalizedOutcomes = outcomesList
          .map((e) => e.trim().toLowerCase().replaceAll(' ', '_'))
          .toList();

      final hasBirth = normalizedOutcomes.any(
          (o) => o == 'live_birth' || o == 'stillbirth' || o.contains('birth'));
      final hasLoss = normalizedOutcomes.any((o) =>
          o == 'miscarriage' || o == 'abortion' || o == 'ectopic');

      // Determine Para vs Abortus
      if (hasLoss && !hasBirth) {
        a += 1;
      } else if (hasBirth || (gestationalAge != null && gestationalAge >= 20)) {
        p += 1;
      } else if (gestationalAge != null && gestationalAge < 20) {
        a += 1;
      } else {
        p += 1;
      }

      // Determine Living Children
      final liveBirthsCount = normalizedOutcomes
          .where((o) => o == 'live_birth')
          .length;
      if (liveBirthsCount > 0) {
        l += (fetalCount > liveBirthsCount ? fetalCount : liveBirthsCount);
      }
    }

    return ObstetricScore(
      gravida: g,
      para: p,
      abortus: a,
      livingChildren: l,
    );
  }

  Map<String, dynamic> toMap() => {
        'gravida': gravida,
        'para': para,
        'abortus': abortus,
        'living_children': livingChildren,
      };

  factory ObstetricScore.fromMap(Map<String, dynamic> map) {
    return ObstetricScore(
      gravida: (map['gravida'] as num?)?.toInt() ?? 0,
      para: (map['para'] as num?)?.toInt() ?? 0,
      abortus: (map['abortus'] as num?)?.toInt() ?? 0,
      livingChildren: (map['living_children'] as num?)?.toInt() ?? 0,
    );
  }
}
