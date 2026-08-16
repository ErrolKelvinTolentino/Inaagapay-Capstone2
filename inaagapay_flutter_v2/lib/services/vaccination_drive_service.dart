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
import 'sms_service.dart';
import 'supabase_service.dart';

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
  });

  final int motherId;
  final int? accountId;
  final String name;

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

  String get doseLabel => currentDose == 0
      ? 'No TD dose yet — needs TD1'
      : 'Has TD$currentDose — needs TD$nextDose';
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

  /// Mother-facing vaccines a drive can be held for.
  static Future<List<Map<String, dynamic>>> fetchMaternalVaccines() async {
    try {
      final rows = await SupabaseService.client
          .from('vaccines')
          .select('vaccine_id, vaccine_name, dose_number')
          .eq('target_recipients', 'mother')
          .order('vaccine_name');
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      if (kDebugMode) debugPrint('[Drive] Vaccine list unavailable: $e');
      return [];
    }
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
        final message = 'Kumusta $firstName! May $vaccineName drive sa '
            '$facilityName sa $dateText. Inaasahan po namin kayo. - AGAPAY';
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
