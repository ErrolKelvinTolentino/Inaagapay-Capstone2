import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Single source of truth for maternal Td (tetanus-diphtheria) immunisation state.
///
/// Both the prenatal checkup screen and the dedicated Td screen read through
/// this service. They previously each ran their own query and their own string
/// matching, and disagreed: `maternal_td_records.dose_number` is canonical
/// (`Td2`) while `prenatal_checkups.td_vaccine_dose` was written spaced and
/// upper-cased (`TD 2`). The prenatal screen compared raw strings against
/// `'Td$i'`, so any dose recorded through a checkup was invisible to it.
///
/// Every dose key that enters this file goes through [normalizeDoseKey], so the
/// rest of the app only ever sees `Td1`..`Td5`.
class MaternalTdService {
  const MaternalTdService._();

  /// DOH 5-dose maternal Td schedule.
  static const List<TdDoseDef> doseDefs = [
    TdDoseDef(
      key: 'Td1',
      number: 1,
      title: 'Td 1 (Initial Priming)',
      timing: 'As early as possible in pregnancy',
      minIntervalLabel: 'None (first dose)',
      protection: 'Initial sensitisation (no neonatal protection yet)',
      minIntervalDays: 0,
    ),
    TdDoseDef(
      key: 'Td2',
      number: 2,
      title: 'Td 2 (Infant Protection)',
      timing: 'At least 4 weeks (28 days) after Td1',
      minIntervalLabel: '4 weeks (28 days) after Td1',
      protection: '3 years protection - baby is Protected at Birth (PAB)',
      minIntervalDays: 28,
    ),
    TdDoseDef(
      key: 'Td3',
      number: 3,
      title: 'Td 3 (Extended Protection)',
      timing: 'At least 6 months after Td2',
      minIntervalLabel: '6 months (180 days) after Td2',
      protection: '5 years protection for mother and future infants',
      minIntervalDays: 180,
    ),
    TdDoseDef(
      key: 'Td4',
      number: 4,
      title: 'Td 4 (10-Year Protection)',
      timing: 'At least 1 year after Td3',
      minIntervalLabel: '1 year (365 days) after Td3',
      protection: '10 years maternal and neonatal protection',
      minIntervalDays: 365,
    ),
    TdDoseDef(
      key: 'Td5',
      number: 5,
      title: 'Td 5 (Lifetime Protection / FIM)',
      timing: 'At least 1 year after Td4',
      minIntervalLabel: '1 year (365 days) after Td4',
      protection: 'Lifetime protection (Fully Immunised Mother / FIM)',
      minIntervalDays: 365,
    ),
  ];

  static TdDoseDef defFor(String doseKey) =>
      doseDefs.firstWhere((d) => d.key == doseKey, orElse: () => doseDefs.first);

  /// Canonicalises any Td spelling the database has ever held.
  ///
  /// `TD 2`, `Td2`, `td-2`, `2`, `Dose 2` all collapse to `Td2`.
  /// Returns null for `-`, `none`, empty, or out-of-range values.
  static String? normalizeDoseKey(Object? raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty || s == '-' || s.toLowerCase() == 'none') return null;

    final match = RegExp(r'\d+').firstMatch(s);
    if (match == null) return null;

    final n = int.tryParse(match.group(0)!);
    if (n == null || n < 1 || n > 5) return null;
    return 'Td$n';
  }

  /// Reads every source of maternal Td truth and merges them into one status.
  ///
  /// `maternal_td_records` wins over the legacy checkup column when both hold
  /// the same dose, because only the former carries inventory linkage and the
  /// DOH-computed protection window.
  static Future<MaternalTdStatus> fetchStatus(
    int motherId, {
    Iterable<Object?> extraDoseKeys = const [],
  }) async {
    final client = Supabase.instance.client;
    final doses = <String, MaternalTdRecord>{};

    // 1. Authoritative dedicated records.
    try {
      final res = await client
          .from('maternal_td_records')
          .select(
              'td_record_id, dose_number, vaccination_date, facility_id, facility_name, source, protection_until, next_due_date, remarks')
          .eq('mother_id', motherId)
          .order('vaccination_date', ascending: true);

      for (final row in (res as List<dynamic>)) {
        final m = Map<String, dynamic>.from(row as Map);
        final key = normalizeDoseKey(m['dose_number']);
        if (key == null) continue;
        final date = DateTime.tryParse(m['vaccination_date']?.toString() ?? '');
        if (date == null) continue;

        doses[key] = MaternalTdRecord(
          doseKey: key,
          date: DateTime(date.year, date.month, date.day),
          facilityId: (m['facility_id'] as num?)?.toInt(),
          facilityName: m['facility_name']?.toString(),
          source: m['source']?.toString() ?? 'bhc',
          protectionUntil:
              DateTime.tryParse(m['protection_until']?.toString() ?? ''),
          nextDueDate: DateTime.tryParse(m['next_due_date']?.toString() ?? ''),
          remarks: m['remarks']?.toString(),
          isLegacy: false,
        );
      }
    } catch (e) {
      debugPrint('MaternalTdService: maternal_td_records read failed: $e');
    }

    // 2. Legacy doses still living only on the prenatal checkup row.
    try {
      final res = await client
          .from('clinical_encounters')
          .select(
              'encounter_datetime, created_at, facility_id, prenatal_checkups!inner(td_vaccine_dose)')
          .eq('mother_id', motherId)
          .order('encounter_datetime', ascending: true);

      for (final row in (res as List<dynamic>)) {
        final m = Map<String, dynamic>.from(row as Map);
        final pc = m['prenatal_checkups'];
        if (pc == null) continue;

        final Object? rawDose = pc is List
            ? (pc.isEmpty ? null : (pc.first as Map)['td_vaccine_dose'])
            : (pc as Map)['td_vaccine_dose'];

        final key = normalizeDoseKey(rawDose);
        if (key == null || doses.containsKey(key)) continue;

        final date =
            DateTime.tryParse(m['encounter_datetime']?.toString() ?? '') ??
                DateTime.tryParse(m['created_at']?.toString() ?? '');
        if (date == null) continue;

        final day = DateTime(date.year, date.month, date.day);
        doses[key] = MaternalTdRecord(
          doseKey: key,
          date: day,
          facilityId: (m['facility_id'] as num?)?.toInt(),
          facilityName: 'Health Center',
          source: 'bhc',
          protectionUntil: defFor(key).protectionFrom(day),
          nextDueDate: null,
          remarks: 'Recorded during prenatal checkup',
          isLegacy: true,
        );
      }
    } catch (e) {
      debugPrint('MaternalTdService: legacy checkup read failed: $e');
    }

    // 3. Caller-supplied hints (e.g. doses reported during registration that
    //    have no committed row yet). Dateless, so they count toward completion
    //    but never toward interval maths.
    for (final raw in extraDoseKeys) {
      final key = normalizeDoseKey(raw);
      if (key == null || doses.containsKey(key)) continue;
      doses[key] = MaternalTdRecord(
        doseKey: key,
        date: null,
        source: 'bhc',
        isLegacy: true,
        remarks: 'Reported during registration',
      );
    }

    return MaternalTdStatus(doses: doses);
  }
}

/// Static DOH definition of one dose in the 5-dose series.
@immutable
class TdDoseDef {
  const TdDoseDef({
    required this.key,
    required this.number,
    required this.title,
    required this.timing,
    required this.minIntervalLabel,
    required this.protection,
    required this.minIntervalDays,
  });

  final String key;
  final int number;
  final String title;
  final String timing;
  final String minIntervalLabel;
  final String protection;

  /// Minimum days that must elapse after the *previous* dose.
  final int minIntervalDays;

  /// How long this dose protects for, measured from [from].
  DateTime? protectionFrom(DateTime from) {
    switch (key) {
      case 'Td1':
        return null;
      case 'Td2':
        return DateTime(from.year + 3, from.month, from.day);
      case 'Td3':
        return DateTime(from.year + 5, from.month, from.day);
      case 'Td4':
        return DateTime(from.year + 10, from.month, from.day);
      case 'Td5':
        return DateTime(from.year + 50, from.month, from.day);
    }
    return null;
  }
}

/// One recorded dose, whatever table it came from.
@immutable
class MaternalTdRecord {
  const MaternalTdRecord({
    required this.doseKey,
    required this.date,
    required this.source,
    this.facilityId,
    this.facilityName,
    this.protectionUntil,
    this.nextDueDate,
    this.remarks,
    this.isLegacy = false,
  });

  final String doseKey;

  /// Null only for registration-reported doses with no known date.
  final DateTime? date;
  final int? facilityId;
  final String? facilityName;
  final String source;
  final DateTime? protectionUntil;
  final DateTime? nextDueDate;
  final String? remarks;
  final bool isLegacy;
}

/// What the midwife may do next.
enum TdNextAction {
  /// Dose may be given today.
  eligibleNow,

  /// Series is on track but the DOH interval has not elapsed yet.
  waiting,

  /// An earlier dose is missing, so the next one cannot be sequenced. The
  /// correct action is backfilling history, not administering.
  missingPrevious,

  /// All five doses recorded.
  complete,
}

/// Merged, canonical maternal Td state.
@immutable
class MaternalTdStatus {
  const MaternalTdStatus({required this.doses});

  final Map<String, MaternalTdRecord> doses;

  static const MaternalTdStatus empty = MaternalTdStatus(doses: {});

  bool has(String doseKey) => doses.containsKey(doseKey);

  MaternalTdRecord? recordFor(String doseKey) => doses[doseKey];

  /// Highest dose on file, e.g. Td1 + Td3 recorded gives 3.
  int get highestCompletedDose {
    for (var n = 5; n >= 1; n--) {
      if (doses.containsKey('Td$n')) return n;
    }
    return 0;
  }

  int get completedCount => doses.length;

  bool get isFim => doses.containsKey('Td5');

  /// Baby is Protected at Birth once Td2 is on file and its protection window
  /// has not lapsed.
  bool get isProtectedAtBirth {
    final highest = highestCompletedDose;
    if (highest < 2) return false;
    if (isFim) return true;

    final until = doses['Td$highest']?.protectionUntil;
    if (until == null) return true;
    return until.isAfter(DateTime.now());
  }

  DateTime? get protectionUntil =>
      doses['Td$highestCompletedDose']?.protectionUntil;

  /// The next dose in the series, or null when the mother is FIM.
  String? get nextDoseKey {
    for (var n = 1; n <= 5; n++) {
      if (!doses.containsKey('Td$n')) return 'Td$n';
    }
    return null;
  }

  /// The dose immediately before [nextDoseKey], if any.
  String? get previousOfNext {
    final next = nextDoseKey;
    if (next == null) return null;
    final n = int.parse(next.substring(2));
    return n <= 1 ? null : 'Td${n - 1}';
  }

  /// Earliest date [nextDoseKey] may be administered.
  DateTime? get nextEligibleDate {
    final next = nextDoseKey;
    if (next == null) return null;
    if (next == 'Td1') return _today;

    final prevKey = previousOfNext;
    final prevDate = prevKey == null ? null : doses[prevKey]?.date;
    if (prevDate == null) return null;

    return prevDate
        .add(Duration(days: MaternalTdService.defFor(next).minIntervalDays));
  }

  /// Days until [nextDoseKey] becomes administrable. 0 when already eligible.
  int get daysUntilEligible {
    final on = nextEligibleDate;
    if (on == null) return 0;
    final diff = on.difference(_today).inDays;
    return diff > 0 ? diff : 0;
  }

  TdNextAction get nextAction {
    final next = nextDoseKey;
    if (next == null) return TdNextAction.complete;
    if (next == 'Td1') return TdNextAction.eligibleNow;

    final prevKey = previousOfNext;
    final prev = prevKey == null ? null : doses[prevKey];
    if (prev == null || prev.date == null) return TdNextAction.missingPrevious;

    return daysUntilEligible > 0
        ? TdNextAction.waiting
        : TdNextAction.eligibleNow;
  }

  /// The dose that must be backfilled before the series can continue.
  String? get blockingDoseKey =>
      nextAction == TdNextAction.missingPrevious ? previousOfNext : null;

  /// True when a dose may legitimately be recorded today.
  bool get canAdministerToday => nextAction == TdNextAction.eligibleNow;

  /// Doses selectable in the prenatal checkup dropdown: the next one only, and
  /// only while it is actually due.
  List<String> get selectableDoseKeys {
    final next = nextDoseKey;
    if (next == null || !canAdministerToday) return const [];
    return [next];
  }

  static DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }
}
