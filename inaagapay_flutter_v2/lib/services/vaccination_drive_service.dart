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
  });

  final int motherId;
  final int? accountId;
  final String name;

  /// Highest TD dose on record, 0 when none has been given.
  final int currentDose;

  final String? phoneNumber;
  final String? email;

  bool get hasPhone => (phoneNumber ?? '').trim().isNotEmpty;
  bool get hasEmail => (email ?? '').trim().isNotEmpty;

  /// True when there is no way to reach her. Worth surfacing rather than
  /// quietly dropping her from the count.
  bool get isUnreachable => !hasPhone && !hasEmail;

  String get doseLabel =>
      currentDose == 0 ? 'No TD dose on record' : 'Last had TD$currentDose';
}

/// What happened when the notifications went out.
class DriveNotificationResult {
  const DriveNotificationResult({
    required this.smsSent,
    required this.smsFailed,
    required this.emailsQueued,
    required this.unreachable,
  });

  final int smsSent;
  final int smsFailed;
  final int emailsQueued;
  final int unreachable;

  int get reached => smsSent + emailsQueued;
}

class VaccinationDriveService {
  const VaccinationDriveService._();

  /// Doses that protect the newborn. A mother at or above this is not invited.
  static const int protectiveDose = 2;

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

  /// Pregnant mothers at this centre who have not reached [targetDose].
  ///
  /// Reads TD doses off prenatal checkups, which is the only place they are
  /// recorded. A mother whose dose text cannot be read counts as 0 rather than
  /// being skipped — an unreadable record is not evidence of protection.
  static Future<List<DriveRecipient>> fetchUnprotectedMothers({
    required int bhcId,
    int targetDose = protectiveDose,
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

      // Only ongoing pregnancies. A drive is about protecting the pregnancy
      // she is in now.
      final pregnancies = await SupabaseService.client
          .from('pregnancies')
          .select('pregnancy_id, mother_id')
          .inFilter('mother_id', motherIds)
          .eq('status', 'ongoing');

      final motherByPregnancy = <int, int>{};
      for (final row in List<Map<String, dynamic>>.from(pregnancies)) {
        final pregnancyId = _int(row['pregnancy_id']);
        final motherId = _int(row['mother_id']);
        if (pregnancyId != null && motherId != null) {
          motherByPregnancy[pregnancyId] = motherId;
        }
      }
      if (motherByPregnancy.isEmpty) return [];

      final checkups = await SupabaseService.client
          .from('prenatal_checkups')
          .select('pregnancy_id, td_vaccine_dose')
          .inFilter('pregnancy_id', motherByPregnancy.keys.toList())
          .not('td_vaccine_dose', 'is', null);

      final highestDose = <int, int>{};
      for (final row in List<Map<String, dynamic>>.from(checkups)) {
        final motherId = motherByPregnancy[_int(row['pregnancy_id']) ?? -1];
        if (motherId == null) continue;
        final dose = parseDoseNumber(row['td_vaccine_dose']?.toString()) ?? 0;
        if (dose > (highestDose[motherId] ?? 0)) highestDose[motherId] = dose;
      }

      final recipients = <DriveRecipient>[];
      for (final motherId in motherByPregnancy.values.toSet()) {
        final dose = highestDose[motherId] ?? 0;
        if (dose >= targetDose) continue;

        final row = byId[motherId];
        if (row == null) continue;
        final account = row['accounts'] as Map<String, dynamic>?;
        final name = '${account?['first_name'] ?? ''} '
                '${account?['last_name'] ?? ''}'
            .trim();

        recipients.add(DriveRecipient(
          motherId: motherId,
          accountId: _int(row['account_id']),
          name: name.isEmpty ? 'Unnamed mother' : name,
          currentDose: dose,
          phoneNumber: account?['phone_number']?.toString(),
          email: account?['email_address']?.toString(),
        ));
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
    // has, try the one the working screens use and fall back to the other.
    for (final column in ['bhc_id', 'facility_id']) {
      try {
        final row = await SupabaseService.client
            .from('immunization_schedule')
            .insert({...payload, column: bhcId})
            .select('immunization_schedule_id')
            .maybeSingle();

        final id = _int(row?['immunization_schedule_id']);
        if (id != null) return id;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[Drive] Insert with $column failed: $e');
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

    for (final recipient in recipients) {
      if (recipient.isUnreachable) {
        unreachable++;
        continue;
      }

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
          ok ? smsSent++ : smsFailed++;
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
        if (queued) emailsQueued++;
      }

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
