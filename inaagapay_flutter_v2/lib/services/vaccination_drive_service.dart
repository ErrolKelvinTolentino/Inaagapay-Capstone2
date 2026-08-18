// lib/services/vaccination_drive_service.dart
//
// Scheduling a vaccination drive at a health centre, and telling the mothers
// who need to come.
//
// The drive itself needs no new table. `immunization_schedule` is already a
// facility + vaccine + date, which is exactly what a drive is, and the
// Schedules screen already reads from it — so a drive created here appears on
// the calendar without anything further.
//
// WHO GETS TOLD
//
// Only mothers who are actually unprotected. Two tetanus-diphtheria doses are
// what protect a newborn against neonatal tetanus, so the default target is
// TD2: a mother with no dose or only TD1 is invited, and one already at TD2 or
// beyond is not. Inviting everyone short of the full five-dose series would
// send messages to mothers already protected for the pregnancy they are in,
// spend SMS credits doing it, and teach people that these messages are not
// really for them.
//
// SENDING IS NEVER AUTOMATIC
//
// Creating a drive does not message anybody. The recipient list is built,
// counted and shown first, and a person decides to send. Text messages cannot
// be recalled, cost money per recipient, and go to pregnant women who will act
// on them — that is not a side effect to bury inside a save button.

import 'package:flutter/foundation.dart';

import 'email_service.dart';
import 'immunization_schedule.dart';
import 'sms_service.dart';
import 'supabase_service.dart';

/// One dose in a vaccine's series, as the catalogue stores it.
class DriveDose {
  const DriveDose({
    required this.vaccineId,
    this.doseNumber,
    this.recommendedAgeMonths,
    this.minimumIntervalWeeks,
    this.maximumAgeMonths,
  });

  final int vaccineId;
  final int? doseNumber;
  final double? recommendedAgeMonths;

  /// How long must have passed since the previous dose before this one may be
  /// given. Null on first doses, which have no predecessor to wait on.
  ///
  /// Age alone decides nothing for a catch-up. A child given Pentavalent 1
  /// last week is old enough for Pentavalent 2 and must still wait four weeks
  /// for it — and a dose given inside the interval may not count, so inviting
  /// her wastes a vial and leaves her believing she is covered.
  final int? minimumIntervalWeeks;

  /// Upper age limit past which the dose is no longer given at all. Only
  /// Rotavirus carries one in the DOH childhood schedule.
  final double? maximumAgeMonths;
}

/// A vaccine a drive can be held for, with what is on the shelf for it.
///
/// One entry per *vaccine*, not per dose. The `vaccines` table holds a row for
/// every dose — TD1 through TD5 are five rows all named "Tetanus-Diphtheria
/// (Td)" — so listing rows put the same vaccine in the menu five times over.
/// A midwife schedules "a TD drive"; which dose each mother receives is
/// decided per mother when she arrives.
class DriveVaccine {
  const DriveVaccine({
    required this.name,
    required this.forChildren,
    required this.stock,
    required this.doses,
  });

  final String name;

  /// Every dose of this vaccine in the catalogue, lowest first.
  final List<DriveDose> doses;

  /// The row recorded against the drive. The first dose stands for the series
  /// — the schedule entry says which vaccine is being given that day, not
  /// which dose any particular person is due.
  int get vaccineId => doses.first.vaccineId;

  /// True when this dose is given to children rather than to the mother.
  final bool forChildren;

  /// Units on hand at this health centre — active batches that have not
  /// expired. Null when no inventory item could be matched to the vaccine,
  /// which is different from zero and is said differently on screen.
  final int? stock;

  bool get isOutOfStock => stock != null && stock! <= 0;

  /// A vaccine with no matching inventory item is still selectable — the
  /// stock simply is not tracked under a name this can find, and blocking the
  /// drive over a naming mismatch would be worse than letting it through.
  bool get canBeScheduled => !isOutOfStock;

  String get stockLabel {
    if (stock == null) return 'stock not tracked';
    if (stock! <= 0) return 'out of stock';
    return '$stock in stock';
  }

  String get menuLabel => '$name  ·  $stockLabel';
}

/// One mother who should be invited, with the contacts to reach her by.
class DriveRecipient {
  const DriveRecipient({
    required this.motherId,
    required this.accountId,
    required this.name,
    required this.currentDose,
    this.phoneNumber,
    this.email,
    this.lastDoseOn,
    this.childId,
    this.childName,
    this.dueLabel,
  });

  final int motherId;
  final int? accountId;
  final String name;

  /// Which child the appointment is for, so the invitation can be recorded
  /// against them rather than only against their mother. Null on a maternal
  /// drive.
  final int? childId;

  /// For a child drive, whose appointment this is. Null on a maternal drive.
  ///
  /// The mother is always the one messaged — hers is the phone number on file
  /// — so a child's invitation has to name the child, or she will read it as
  /// being about herself.
  final String? childName;

  /// What this recipient is due for, ready to show. Set for child drives,
  /// where [currentDose] does not describe the situation.
  final String? dueLabel;

  bool get isForChild => childName != null;

  /// Highest TD dose on record across every pregnancy, 0 when none has been
  /// given. Tetanus doses accumulate over a lifetime, not per pregnancy.
  final int currentDose;

  /// When that dose was given, where the record says.
  final DateTime? lastDoseOn;

  /// The dose she is due next.
  int get nextDose => currentDose + 1;

  final String? phoneNumber;
  final String? email;

  bool get hasPhone => (phoneNumber ?? '').trim().isNotEmpty;
  bool get hasEmail => (email ?? '').trim().isNotEmpty;

  /// True when there is no way to reach her. Worth surfacing rather than
  /// quietly dropping her from the count.
  bool get isUnreachable => !hasPhone && !hasEmail;

  String get doseLabel => dueLabel ??
      (currentDose == 0
          ? 'No TD dose yet — needs TD1'
          : 'Has TD$currentDose — needs TD$nextDose');

  /// Who the row is about — the child for a child drive, otherwise the mother.
  String get subjectName => childName ?? name;
}

/// What happened when the notifications went out.
///
/// Counted in **mothers**, not in messages. One mother reached by both text
/// and email is one mother, not two — reporting "reached 2 of 1" was the
/// arithmetic of channels leaking into a sentence about people.
class DriveNotificationResult {
  const DriveNotificationResult({
    required this.total,
    required this.notified,
    required this.smsSent,
    required this.smsFailed,
    required this.emailsQueued,
    required this.unreachable,
  });

  /// Everyone on the invitation list.
  final int total;

  /// Mothers who got word by at least one channel.
  final int notified;

  /// Channel counts, for the detail line.
  final int smsSent;
  final int smsFailed;
  final int emailsQueued;

  /// Mothers with neither a phone number nor an email on file.
  final int unreachable;

  /// On the list, reachable in principle, but every channel failed.
  int get failed => total - notified - unreachable;

  /// A plain sentence a midwife can act on.
  String get summary {
    if (total == 0) return 'Drive scheduled. Nobody needed inviting.';

    final parts = <String>[];
    if (smsSent > 0) parts.add('$smsSent by text');
    if (emailsQueued > 0) parts.add('$emailsQueued by email');
    final how = parts.isEmpty ? '' : ' (${parts.join(', ')})';

    final buffer = StringBuffer(
      notified == total
          ? 'Drive scheduled. All $total '
              '${total == 1 ? 'mother was' : 'mothers were'} notified$how.'
          : 'Drive scheduled. $notified of $total mothers notified$how.',
    );

    if (unreachable > 0) {
      buffer.write(' $unreachable have no phone or email — tell them in '
          'person.');
    }
    if (failed > 0) {
      buffer.write(' $failed could not be reached; try again later.');
    }
    return buffer.toString();
  }
}

class VaccinationDriveService {
  const VaccinationDriveService._();

  /// Same figure [ImmunizationSchedule] uses, so an age computed here and an
  /// age computed there put a child in the same place.
  static const double _daysPerMonth = 30.44;

  /// Doses in the tetanus-diphtheria series.
  ///
  /// Five, not two. TD2 is what protects the newborn against neonatal tetanus
  /// in *this* pregnancy, which is why it is the threshold the dashboard
  /// reports coverage against — but the series continues to TD5, and a mother
  /// who stops at two is protected for roughly three years rather than for
  /// life. A drive is exactly the occasion to move her along it.
  static const int completeSeries = 5;

  /// The dose that protects the newborn in the current pregnancy. Used for
  /// coverage reporting, not for deciding who to invite.
  static const int protectiveDose = 2;

  /// How long must pass after each dose before the next one counts.
  ///
  /// ⚠️ CONFIRM BEFORE DEFENCE. These are the intervals in the DOH/WHO
  /// tetanus-diphtheria schedule for women of reproductive age: four weeks
  /// after TD1, six months after TD2, then a year after each of TD3 and TD4.
  /// Verify against the guideline the RHU follows and cite it in the study.
  ///
  /// This matters clinically, not just administratively: a dose given too soon
  /// after the previous one does not extend protection, so inviting a mother
  /// early wastes a vial and leaves her believing she is covered.
  static const Map<int, Duration> _minimumIntervalAfterDose = {
    1: Duration(days: 28),
    2: Duration(days: 182),
    3: Duration(days: 365),
    4: Duration(days: 365),
  };

  /// Whether [recipient] can be given her next dose on [driveDate].
  ///
  /// A mother with no dose recorded is always due. Where the record has a dose
  /// but no date, she is treated as due — an undated record is not evidence
  /// that the interval has not elapsed, and the midwife can check the card.
  static bool isDueBy(DriveRecipient recipient, DateTime driveDate) {
    if (recipient.currentDose >= completeSeries) return false;
    if (recipient.currentDose == 0) return true;

    final last = recipient.lastDoseOn;
    if (last == null) return true;

    final wait = _minimumIntervalAfterDose[recipient.currentDose];
    if (wait == null) return true;

    return !driveDate.isBefore(last.add(wait));
  }

  /// Every vaccine a drive can be held for, with the stock behind each.
  ///
  /// Mother and child vaccines in one list — the midwife runs one kind of
  /// session either way, and which one it is decides who gets invited rather
  /// than which screen she opens.
  static Future<List<DriveVaccine>> fetchDriveVaccines({
    required int bhcId,
  }) async {
    try {
      final vaccineRows = await SupabaseService.client
          .from('vaccines')
          .select('*')
          .order('target_recipients')
          .order('recommended_age_months')
          .order('vaccine_name');

      final vaccines = List<Map<String, dynamic>>.from(vaccineRows);
      if (vaccines.isEmpty) return [];

      final stockByItem = await _stockByItemId(bhcId);
      final items = await _inventoryItems();

      // Collapse the catalogue's per-dose rows into one entry per vaccine.
      // Keyed by name *and* recipient so a maternal Td and a childhood Td, if
      // both existed, would not merge into one another.
      final grouped = <String, List<Map<String, dynamic>>>{};
      for (final v in vaccines) {
        final name = v['vaccine_name']?.toString() ?? 'Vaccine';
        final forChildren = v['target_recipients']?.toString() == 'child';
        grouped.putIfAbsent('$forChildren|$name', () => []).add(v);
      }

      return grouped.values.map((rows) {
        final name = rows.first['vaccine_name']?.toString() ?? 'Vaccine';
        final itemId = _int(rows.first['inventory_item_id']) ??
            _matchInventoryItem(name, items);

        final doses = rows
            .map((v) => DriveDose(
                  vaccineId: _int(v['vaccine_id']) ?? -1,
                  doseNumber: _int(v['dose_number']),
                  recommendedAgeMonths:
                      (v['recommended_age_months'] as num?)?.toDouble(),
                  minimumIntervalWeeks: _int(v['minimum_interval_weeks']),
                  maximumAgeMonths:
                      (v['maximum_age_months'] as num?)?.toDouble(),
                ))
            .toList()
          ..sort((a, b) => (a.doseNumber ?? 0).compareTo(b.doseNumber ?? 0));

        return DriveVaccine(
          name: name,
          forChildren: rows.first['target_recipients']?.toString() == 'child',
          stock: itemId == null ? null : (stockByItem[itemId] ?? 0),
          doses: doses,
        );
      }).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[Drive] Vaccine list unavailable: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> _inventoryItems() async {
    try {
      final rows = await SupabaseService.client
          .from('inventory_items')
          .select('item_id, name');
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      if (kDebugMode) debugPrint('[Drive] Inventory items unavailable: $e');
      return [];
    }
  }

  /// Units on hand per inventory item at this centre.
  ///
  /// Active batches that have not expired — expired stock on the shelf is not
  /// stock you can give. Mirrors the check the Add Immunization screen makes.
  static Future<Map<int, int>> _stockByItemId(int bhcId) async {
    try {
      final today = DateTime.now().toIso8601String().split('T')[0];
      final rows = await SupabaseService.client
          .from('inventory_batches')
          .select('item_id, quantity_remaining')
          .eq('facility_id', bhcId)
          .eq('status', 'active')
          .gte('expiration_date', today);

      final totals = <int, int>{};
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final itemId = _int(row['item_id']);
        if (itemId == null) continue;
        totals[itemId] =
            (totals[itemId] ?? 0) + (_int(row['quantity_remaining']) ?? 0);
      }
      return totals;
    } catch (e) {
      if (kDebugMode) debugPrint('[Drive] Stock unavailable: $e');
      return {};
    }
  }

  /// Matches a vaccine to an inventory item by name.
  ///
  /// The same keyword pairs the Add Immunization screen uses, so a vaccine
  /// resolves to the same item in both places. Used only when the vaccine row
  /// carries no `inventory_item_id`.
  static int? _matchInventoryItem(
      String vaccineName, List<Map<String, dynamic>> items) {
    final v = vaccineName.toLowerCase();

    bool pairs(String itemName) {
      final i = itemName.toLowerCase();
      return (v.contains('bcg') && i.contains('bcg')) ||
          (v.contains('penta') && i.contains('penta')) ||
          (v.contains('pcv') && i.contains('pcv')) ||
          (v.contains('opv') && i.contains('opv')) ||
          (v.contains('ipv') && i.contains('ipv')) ||
          (v.contains('rota') && i.contains('rota')) ||
          (v.contains('measles') && (i.contains('mr') || i.contains('measles'))) ||
          (v.contains('mmr') && (i.contains('mr') || i.contains('mmr'))) ||
          (v.contains('hep') && i.contains('hep')) ||
          (v.contains('vitamin a') && i.contains('vitamin a')) ||
          (v.contains('td') && i.contains('td')) ||
          (v.contains('tetanus') && i.contains('tetanus'));
    }

    for (final item in items) {
      if (pairs(item['name']?.toString() ?? '')) return _int(item['item_id']);
    }
    return null;
  }

  /// Pregnant mothers at this centre whose TD series is incomplete.
  ///
  /// Doses are counted across **every** pregnancy she has had, not just the
  /// current one. Tetanus protection accumulates over a lifetime, so a mother
  /// who received TD2 two pregnancies ago needs TD3 now — counting per
  /// pregnancy would have shown her as never vaccinated.
  ///
  /// A dose whose text cannot be read counts as 0 rather than being skipped:
  /// an unreadable record is not evidence of protection.
  ///
  /// [driveDate] decides who is far enough past their last dose to be given
  /// the next one — see [isDueBy].
  static Future<List<DriveRecipient>> fetchMothersDueForDose({
    required int bhcId,
    DateTime? driveDate,
  }) async {
    try {
      final mothers = await SupabaseService.client
          .from('mothers')
          .select('mother_id, account_id, '
              'accounts!inner (first_name, last_name, phone_number, email_address)')
          .eq('assigned_bhc_id', bhcId)
          .eq('status', 'active');

      final motherIds = <int>[];
      final byId = <int, Map<String, dynamic>>{};
      for (final row in List<Map<String, dynamic>>.from(mothers)) {
        final id = _int(row['mother_id']);
        if (id == null) continue;
        motherIds.add(id);
        byId[id] = row;
      }
      if (motherIds.isEmpty) return [];

      // EVERY pregnancy, not just the ongoing one. Doses carry across a
      // lifetime, so a mother who had TD2 two pregnancies ago needs TD3 now.
      // Reading only her current pregnancy showed her as never vaccinated.
      final pregnancies = await SupabaseService.client
          .from('pregnancies')
          .select('pregnancy_id, mother_id, status')
          .inFilter('mother_id', motherIds);

      final motherByPregnancy = <int, int>{};
      final mothersCurrentlyPregnant = <int>{};
      for (final row in List<Map<String, dynamic>>.from(pregnancies)) {
        final pregnancyId = _int(row['pregnancy_id']);
        final motherId = _int(row['mother_id']);
        if (pregnancyId == null || motherId == null) continue;
        motherByPregnancy[pregnancyId] = motherId;
        if (row['status']?.toString() == 'ongoing') {
          mothersCurrentlyPregnant.add(motherId);
        }
      }
      if (mothersCurrentlyPregnant.isEmpty) return [];

      // The dose date lives on the parent encounter, not on the checkup, and
      // it is what decides whether the next dose may be given yet.
      final checkups = await SupabaseService.client
          .from('clinical_encounters')
          .select('pregnancy_id, encounter_datetime, '
              'checkup:prenatal_checkups!inner (td_vaccine_dose)')
          .inFilter('pregnancy_id', motherByPregnancy.keys.toList())
          .eq('encounter_type', 'checkup');

      final highestDose = <int, int>{};
      final doseGivenOn = <int, DateTime>{};
      for (final row in List<Map<String, dynamic>>.from(checkups)) {
        final motherId = motherByPregnancy[_int(row['pregnancy_id']) ?? -1];
        if (motherId == null) continue;

        final raw = row['checkup'];
        final checkup = raw is Map
            ? Map<String, dynamic>.from(raw)
            : (raw is List && raw.isNotEmpty
                ? Map<String, dynamic>.from(raw.first as Map)
                : const <String, dynamic>{});

        final dose = parseDoseNumber(checkup['td_vaccine_dose']?.toString());
        if (dose == null) continue;

        if (dose > (highestDose[motherId] ?? 0)) {
          highestDose[motherId] = dose;
          final when = DateTime.tryParse(
              row['encounter_datetime']?.toString() ?? '');
          if (when != null) doseGivenOn[motherId] = when;
        }
      }

      final when = driveDate ?? DateTime.now();
      final recipients = <DriveRecipient>[];
      for (final motherId in mothersCurrentlyPregnant) {
        final row = byId[motherId];
        if (row == null) continue;
        final account = row['accounts'] as Map<String, dynamic>?;
        final name = '${account?['first_name'] ?? ''} '
                '${account?['last_name'] ?? ''}'
            .trim();

        final candidate = DriveRecipient(
          motherId: motherId,
          accountId: _int(row['account_id']),
          name: name.isEmpty ? 'Unnamed mother' : name,
          currentDose: highestDose[motherId] ?? 0,
          lastDoseOn: doseGivenOn[motherId],
          phoneNumber: account?['phone_number']?.toString(),
          email: account?['email_address']?.toString(),
        );

        // Series complete, or too soon since her last dose for the next one
        // to count.
        if (!isDueBy(candidate, when)) continue;
        recipients.add(candidate);
      }

      recipients.sort((a, b) {
        final byDose = a.currentDose.compareTo(b.currentDose);
        return byDose != 0 ? byDose : a.name.compareTo(b.name);
      });
      return recipients;
    } catch (e) {
      if (kDebugMode) debugPrint('[Drive] Recipient lookup failed: $e');
      return [];
    }
  }

  /// Mothers whose child is due for [vaccine] on [driveDate].
  ///
  /// The mother is the recipient throughout: hers is the phone number on file,
  /// and children have no contact details of their own. The child is named in
  /// the row and in the message so she knows whose appointment it is — a
  /// mother with three children needs to be told which one to bring.
  ///
  /// Timeliness is judged by [ImmunizationSchedule], the same rules the child
  /// profile and the dashboard's overdue count use, so a child cannot read as
  /// "due" here and "not yet due" on her own page.
  static Future<List<DriveRecipient>> fetchChildrenDueForVaccine({
    required int bhcId,
    required DriveVaccine vaccine,
    DateTime? driveDate,
  }) async {
    try {
      final mothers = await SupabaseService.client
          .from('mothers')
          .select('mother_id, account_id, '
              'accounts!inner (first_name, last_name, phone_number, email_address)')
          .eq('assigned_bhc_id', bhcId)
          .eq('status', 'active');

      final byMotherId = <int, Map<String, dynamic>>{};
      for (final row in List<Map<String, dynamic>>.from(mothers)) {
        final id = _int(row['mother_id']);
        if (id != null) byMotherId[id] = row;
      }
      if (byMotherId.isEmpty) return [];

      final children = await SupabaseService.client
          .from('children')
          .select('child_id, mother_id, first_name, last_name, '
              'birth_details (birthdate)')
          .inFilter('mother_id', byMotherId.keys.toList());

      final childRows = List<Map<String, dynamic>>.from(children);
      if (childRows.isEmpty) return [];

      final childIds =
          childRows.map((c) => _int(c['child_id'])).whereType<int>().toList();

      final records = await SupabaseService.client
          .from('immunization_records')
          .select('child_id, vaccine_id, vaccination_date')
          .inFilter('child_id', childIds);

      // Keyed by dose, valued by the date it was given. The date is what makes
      // the minimum interval enforceable; collapsing these rows to a set of
      // ids is what let a drive invite a child whose last dose was days ago.
      // A record with no readable date still counts as given — the dose
      // happened — and only loses the ability to hold the next one back.
      final givenByChild = <int, Map<int, DateTime?>>{};
      for (final row in List<Map<String, dynamic>>.from(records)) {
        final childId = _int(row['child_id']);
        final vaccineId = _int(row['vaccine_id']);
        if (childId != null && vaccineId != null) {
          givenByChild.putIfAbsent(childId, () => <int, DateTime?>{})[vaccineId] =
              DateTime.tryParse(row['vaccination_date']?.toString() ?? '');
        }
      }

      final when = driveDate ?? DateTime.now();
      final recipients = <DriveRecipient>[];

      for (final child in childRows) {
        final childId = _int(child['child_id']);
        final motherId = _int(child['mother_id']);
        if (childId == null || motherId == null) continue;

        final birthdate = _birthdate(child);
        if (birthdate == null) continue;

        final ageMonths = when.difference(birthdate).inDays / _daysPerMonth;

        // The dose she is actually due — old enough for, has not had, still
        // within its age ceiling, and far enough past the previous one.
        final dueDose = dueDoseFor(
          vaccine: vaccine,
          birthdate: birthdate,
          given: givenByChild[childId] ?? const <int, DateTime?>{},
          driveDate: when,
        );
        if (dueDose == null) continue;

        final scheduledAt = dueDose.recommendedAgeMonths ?? 0;

        final motherRow = byMotherId[motherId];
        if (motherRow == null) continue;
        final account = motherRow['accounts'] as Map<String, dynamic>?;
        final motherName = '${account?['first_name'] ?? ''} '
                '${account?['last_name'] ?? ''}'
            .trim();
        final childName = '${child['first_name'] ?? ''} '
                '${child['last_name'] ?? ''}'
            .trim();

        final overdue = ImmunizationSchedule.describeOverdue(
          childAgeMonths: ageMonths,
          scheduledAtMonths: scheduledAt,
        );

        // Named with the dose where the series has more than one, so the
        // midwife knows what to draw up rather than just who to expect.
        final doseName = vaccine.doses.length > 1 && dueDose.doseNumber != null
            ? '${vaccine.name} dose ${dueDose.doseNumber}'
            : vaccine.name;

        recipients.add(DriveRecipient(
          motherId: motherId,
          accountId: _int(motherRow['account_id']),
          name: motherName.isEmpty ? 'Unnamed mother' : motherName,
          childId: childId,
          childName: childName.isEmpty ? 'Child' : childName,
          currentDose: 0,
          dueLabel: overdue.isEmpty
              ? 'Due for $doseName'
              : 'Due for $doseName · $overdue',
          phoneNumber: account?['phone_number']?.toString(),
          email: account?['email_address']?.toString(),
        ));
      }

      // Longest overdue first — those are the ones a drive exists to catch.
      recipients.sort((a, b) => a.subjectName.compareTo(b.subjectName));
      return recipients;
    } catch (e) {
      if (kDebugMode) debugPrint('[Drive] Child recipient lookup failed: $e');
      return [];
    }
  }

  /// Which dose of [vaccine] this child should receive at a drive on
  /// [driveDate], or null if she should not be invited.
  ///
  /// [given] maps each vaccine row already recorded for her to the date it was
  /// given. Presence of the key is what marks a dose as had; the date is what
  /// makes the minimum interval enforceable, and it used to be discarded — the
  /// query fetched `vaccination_date` and then collapsed the rows into a set
  /// of ids, so a Pentavalent drive would list a child who had dose 1 last
  /// week.
  ///
  /// The judgement itself is [ImmunizationSchedule]'s, the same rules the
  /// child's own profile applies, so she cannot read as due here and "wait
  /// four weeks" there. Everything is measured against the drive date rather
  /// than today: a drive three weeks out should include a child whose interval
  /// elapses next week, and exclude one whose interval elapses after it.
  static DriveDose? dueDoseFor({
    required DriveVaccine vaccine,
    required DateTime? birthdate,
    required Map<int, DateTime?> given,
    required DateTime driveDate,
  }) {
    if (birthdate == null) return null;

    final ageMonths = driveDate.difference(birthdate).inDays / _daysPerMonth;

    // The most recent dose actually recorded. A dose skipped because it can no
    // longer be given never becomes the predecessor of the next one.
    DriveDose? lastGiven;

    for (final dose in vaccine.doses) {
      if (given.containsKey(dose.vaccineId)) {
        lastGiven = dose;
        continue;
      }

      final scheduledAt = dose.recommendedAgeMonths ?? 0;
      final status = ImmunizationSchedule.statusOfDose(
        alreadyGiven: false,
        childAgeMonths: ageMonths,
        scheduledAtMonths: scheduledAt,
        maximumAgeMonths: dose.maximumAgeMonths,
        earliestAllowed: ImmunizationSchedule.earliestAllowedDate(
          birthdate: birthdate,
          scheduledAtMonths: scheduledAt,
          previousDoseGivenOn:
              lastGiven == null ? null : given[lastGiven.vaccineId],
          minimumIntervalWeeks: dose.minimumIntervalWeeks,
        ),
        today: driveDate,
      );

      if (status == DoseStatus.due || status == DoseStatus.pastDue) {
        return dose;
      }

      // Past its age ceiling — this dose will never be given, but a later one
      // in the series may still be due.
      if (status == DoseStatus.noLongerGiven) continue;

      // notYetDue (too young) or dueSoon (old enough, interval still running).
      // Either way she is not invited, and no later dose can be closer.
      return null;
    }

    return null;
  }

  static DateTime? _birthdate(Map<String, dynamic> child) {
    final raw = child['birth_details'];
    final details = raw is Map
        ? Map<String, dynamic>.from(raw)
        : (raw is List && raw.isNotEmpty
            ? Map<String, dynamic>.from(raw.first as Map)
            : const <String, dynamic>{});
    final text = details['birthdate']?.toString();
    return text == null ? null : DateTime.tryParse(text);
  }

  /// Records the drive so it shows on the Schedules calendar.
  ///
  /// Returns the new row's id, or null if it could not be saved — the caller
  /// must not go on to message anyone about a drive that was never recorded.
  static Future<int?> createDrive({
    required int bhcId,
    required int vaccineId,
    required DateTime date,
    String? notes,
  }) async {
    final payload = {
      'vaccine_id': vaccineId,
      'schedule_date': _isoDate(date),
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    };

    // The schema file calls this column facility_id while every query in the
    // Schedules screen uses bhc_id. Rather than guess which the live database
    // has, try filling both first — if the table carries both columns, and
    // facility_id is NOT NULL as the schema says, writing only bhc_id fails
    // the constraint and the row ends up saved under a column the calendar is
    // not looking at. Populating both leaves nothing to find it by chance.
    final attempts = <Map<String, dynamic>>[
      {...payload, 'bhc_id': bhcId, 'facility_id': bhcId},
      {...payload, 'bhc_id': bhcId},
      {...payload, 'facility_id': bhcId},
    ];

    for (final attempt in attempts) {
      try {
        final row = await SupabaseService.client
            .from('immunization_schedule')
            .insert(attempt)
            .select('immunization_schedule_id')
            .maybeSingle();

        final id = _int(row?['immunization_schedule_id']);
        if (id != null) return id;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[Drive] Insert with ${attempt.keys.join('+')} failed: $e');
        }
      }
    }
    return null;
  }

  /// The rows [recordInvitations] writes, built separately so the shape can be
  /// checked without a database.
  ///
  /// Blank contact details are omitted rather than stored as empty strings: a
  /// missing number and an empty one mean the same thing to a person and
  /// different things to a query, and tomorrow's reminder decides who to text
  /// by asking whether a number is there.
  static List<Map<String, dynamic>> invitationRows({
    required int scheduleId,
    required List<DriveRecipient> recipients,
  }) {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    return recipients.map((r) {
      final phone = clean(r.phoneNumber);
      final email = clean(r.email);
      final child = clean(r.childName);

      return <String, dynamic>{
        'immunization_schedule_id': scheduleId,
        'mother_id': r.motherId,
        if (r.childId != null) 'child_id': r.childId,
        if (child != null) 'child_name': child,
        if (phone != null) 'phone_number': phone,
        if (email != null) 'email_address': email,
      };
    }).toList();
  }

  /// Records who this drive is for, so they can be reminded the day before.
  ///
  /// Called with the same list that is about to be messaged, including anyone
  /// unreachable: the record answers "who was due for this drive", which is a
  /// different question from "who could we contact". A mother with no phone
  /// still belongs in it — that she was due and could not be reached is worth
  /// knowing, and is invisible today.
  ///
  /// Failures are swallowed on purpose. The invitations are a record and a
  /// convenience for tomorrow's reminder; losing them must never stop today's
  /// messages going out or make a saved drive look like it failed.
  ///
  /// Returns how many rows were written.
  static Future<int> recordInvitations({
    required int scheduleId,
    required List<DriveRecipient> recipients,
  }) async {
    if (recipients.isEmpty) return 0;

    final rows = invitationRows(
      scheduleId: scheduleId,
      recipients: recipients,
    );

    try {
      // A plain insert, not an upsert. `createDrive` always writes a new
      // schedule row, so the id is fresh every time and there is nothing to
      // conflict with. The unique index behind this table is a guard against a
      // double submit, and if it fires the batch it rejects is a duplicate of
      // one already recorded — so nothing is lost by letting it fail.
      final saved = await SupabaseService.client
          .from('drive_invitations')
          .insert(rows)
          .select('invitation_id');
      return List<Map<String, dynamic>>.from(saved).length;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Drive] Could not record invitations: $e');
      }
      return 0;
    }
  }

  /// Messages every recipient. Call only after a person has confirmed.
  static Future<DriveNotificationResult> notify({
    required List<DriveRecipient> recipients,
    required String vaccineName,
    required DateTime date,
    required String facilityName,
    String? notes,
  }) async {
    final dateText = _friendlyDate(date);
    int smsSent = 0, smsFailed = 0, emailsQueued = 0, unreachable = 0;
    int notified = 0;

    for (final recipient in recipients) {
      if (recipient.isUnreachable) {
        unreachable++;
        continue;
      }

      // Counted once per mother, however many channels worked for her.
      var reachedThisMother = false;
      final firstName = recipient.name.split(' ').first;

      if (recipient.hasPhone) {
        // Kept under 160 characters on purpose. Semaphore bills per 160-char
        // segment, so a message that spills to 161 costs double for every
        // mother on the list — on a 30-mother drive that is 60 credits
        // instead of 30. The longest realistic substitution
        // ("Tetanus-diphtheria (TD)" at a long facility name) lands around
        // 125, which leaves room without truncating anyone's name.
        //
        // Signed AGAPAY because that is the registered sender name the
        // message will actually arrive from.
        // A child's invitation names the child. A mother with three children
        // cannot act on "please come in" — she needs to know which one to
        // bring. Her own invitation stays in the second person.
        final child = recipient.childName;
        final message = child == null
            ? 'Kumusta $firstName! May $vaccineName drive sa $facilityName sa '
                '$dateText. Inaasahan po namin kayo. - AGAPAY'
            : 'Kumusta $firstName! May $vaccineName drive sa $facilityName sa '
                '$dateText. Isama po si $child. - AGAPAY';
        try {
          final ok = await SmsService.sendSmsMessage(
            recipient.phoneNumber!.trim(),
            message,
          );
          if (ok) {
            smsSent++;
            reachedThisMother = true;
          } else {
            smsFailed++;
          }
        } catch (e) {
          smsFailed++;
          if (kDebugMode) debugPrint('[Drive] SMS failed: $e');
        }
      }

      if (recipient.hasEmail) {
        final queued = await EmailService.sendVaccinationDriveNotice(
          email: recipient.email!.trim(),
          motherName: recipient.name,
          vaccineName: vaccineName,
          dateText: dateText,
          facilityName: facilityName,
          notes: notes,
        );
        if (queued) {
          emailsQueued++;
          reachedThisMother = true;
        }
      }

      if (reachedThisMother) notified++;

      // An in-app notice as well, so the reminder survives a deleted text.
      final accountId = recipient.accountId;
      if (accountId != null) {
        try {
          await SupabaseService.client.from('notifications').insert({
            'account_id': accountId,
            'title': '$vaccineName vaccination drive',
            'message': '$facilityName is holding a $vaccineName vaccination '
                'drive on $dateText. Please come in.',
            'type': 'vaccine_reminder',
          });
        } catch (e) {
          if (kDebugMode) debugPrint('[Drive] In-app notice failed: $e');
        }
      }
    }

    return DriveNotificationResult(
      total: recipients.length,
      notified: notified,
      smsSent: smsSent,
      smsFailed: smsFailed,
      emailsQueued: emailsQueued,
      unreachable: unreachable,
    );
  }

  /// The dose number written on a checkup, however it was written.
  ///
  /// Free text in practice — "TD 2", "TD2", "2", "second dose". Returns null
  /// when it cannot be read, and callers treat that as no dose: an unreadable
  /// record is not evidence that a mother was vaccinated.
  static int? parseDoseNumber(String? raw) {
    if (raw == null) return null;
    final text = raw.toLowerCase().trim();
    if (text.isEmpty) return null;

    final digits = RegExp(r'(\d+)').firstMatch(text);
    if (digits != null) return int.tryParse(digits.group(1)!);

    const words = {'first': 1, 'second': 2, 'third': 3, 'fourth': 4, 'fifth': 5};
    for (final entry in words.entries) {
      if (text.contains(entry.key)) return entry.value;
    }
    return null;
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static String _isoDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String _friendlyDate(DateTime value) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[value.month - 1]} ${value.day}, ${value.year}';
  }
}
