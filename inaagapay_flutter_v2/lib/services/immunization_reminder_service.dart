import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import 'notification_service.dart';
import 'sms_service.dart';

class ImmunizationReminderResult {
  final int pushSent;
  final int smsSent;
  final List<String> errors;

  ImmunizationReminderResult({
    required this.pushSent,
    required this.smsSent,
    required this.errors,
  });
}

class ImmunizationReminderService {
  static final _client = Supabase.instance.client;

  static Future<ImmunizationReminderResult> notifyEligibleBeneficiaries({
    required int bhcId,
    required List<int> vaccineIds,
    required DateTime scheduleDate,
    required String bhcName,
  }) async {
    int pushSent = 0;
    int smsSent = 0;
    final List<String> errors = [];

    try {
      if (vaccineIds.isEmpty) {
        return ImmunizationReminderResult(pushSent: 0, smsSent: 0, errors: []);
      }

      // 1. Fetch vaccine details to categorize
      final vaccinesRes = await _client
          .from('vaccines')
          .select('vaccine_id, vaccine_name, dose_number, recommended_age_months, target_recipients')
          .inFilter('vaccine_id', vaccineIds);
      
      final List<Map<String, dynamic>> vaccines = List<Map<String, dynamic>>.from(vaccinesRes);
      
      final childVaccines = vaccines.where((v) => v['target_recipients'] == 'child').toList();
      final maternalVaccines = vaccines.where((v) => v['target_recipients'] == 'mother').toList();

      if (childVaccines.isEmpty && maternalVaccines.isEmpty) {
        return ImmunizationReminderResult(pushSent: 0, smsSent: 0, errors: []);
      }

      // 2. Fetch all mothers assigned to this BHC
      final mothersRes = await _client
          .from('mothers')
          .select('''
            mother_id,
            account_id,
            account:account_id (
              first_name,
              last_name,
              phone_number
            )
          ''')
          .eq('assigned_bhc_id', bhcId);
      
      final List<Map<String, dynamic>> mothers = List<Map<String, dynamic>>.from(mothersRes);
      if (mothers.isEmpty) {
        return ImmunizationReminderResult(pushSent: 0, smsSent: 0, errors: []);
      }

      final motherIds = mothers.map((m) => m['mother_id'] as int).toList();
      final motherMap = {for (var m in mothers) m['mother_id'] as int: m};

      // 3. Child Vaccine Queries
      final children = <Map<String, dynamic>>[];
      final birthdates = <int, DateTime>{};
      final immunizationRecords = <int, Set<int>>{}; // child_id -> Set of completed vaccine_ids

      if (childVaccines.isNotEmpty) {
        final childrenRes = await _client
            .from('children')
            .select('child_id, first_name, last_name, mother_id')
            .inFilter('mother_id', motherIds);
        
        final List<Map<String, dynamic>> rawChildren = List<Map<String, dynamic>>.from(childrenRes);
        children.addAll(rawChildren);

        if (children.isNotEmpty) {
          final childIds = children.map((c) => c['child_id'] as int).toList();

          final birthRes = await _client
              .from('birth_details')
              .select('child_id, birthdate')
              .inFilter('child_id', childIds);

          for (final b in birthRes) {
            final childId = b['child_id'] as int;
            if (b['birthdate'] != null) {
              birthdates[childId] = DateTime.parse(b['birthdate'].toString());
            }
          }

          final childVaccineIds = childVaccines.map((v) => v['vaccine_id'] as int).toList();
          final recordsRes = await _client
              .from('immunization_record')
              .select('child_id, vaccine_id')
              .inFilter('child_id', childIds)
              .inFilter('vaccine_id', childVaccineIds);

          for (final r in recordsRes) {
            final childId = r['child_id'] as int;
            final vaccineId = r['vaccine_id'] as int;
            immunizationRecords.putIfAbsent(childId, () => {}).add(vaccineId);
          }
        }
      }

      // 4. Maternal Vaccine Queries (Active pregnancies)
      final activePregnancies = <int, Map<String, dynamic>>{}; // mother_id -> pregnancy
      if (maternalVaccines.isNotEmpty) {
        final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final pregRes = await _client
            .from('pregnancies')
            .select('pregnancy_id, mother_id, expected_date_of_delivery, status')
            .inFilter('mother_id', motherIds)
            .eq('status', 'ongoing')
            .gte('expected_date_of_delivery', todayStr);

        for (final p in pregRes) {
          final motherId = p['mother_id'] as int;
          activePregnancies[motherId] = p;
        }
      }

      // 5. Compute eligibility per mother
      final motherChildReminders = <int, Map<String, List<String>>>{}; // mother_id -> {childName -> [vaccineLabels]}
      final motherMaternalEligible = <int, bool>{};       // mother_id -> is eligible for maternal vaccine

      // Determine child vaccine eligibility
      for (final child in children) {
        final childId = child['child_id'] as int;
        final motherId = child['mother_id'] as int;
        final birthdate = birthdates[childId];
        if (birthdate == null) continue;

        // Calculate age on schedule date
        final ageDays = scheduleDate.difference(birthdate).inDays;
        final ageMonths = ageDays / 30.43;

        final completed = immunizationRecords[childId] ?? {};
        final childName = '${child['first_name'] ?? ''} ${child['last_name'] ?? ''}'.trim();

        for (final vaccine in childVaccines) {
          final vaccineId = vaccine['vaccine_id'] as int;
          final recommendedAge = (vaccine['recommended_age_months'] as num).toDouble();

          // If child is old enough and has not taken this vaccine
          if (ageMonths >= recommendedAge - 0.5 && !completed.contains(vaccineId)) {
            final doseStr = vaccine['dose_number'] != null ? ' (Dose ${vaccine['dose_number']})' : '';
            final vaccineLabel = '${vaccine['vaccine_name']}$doseStr';
            motherChildReminders
                .putIfAbsent(motherId, () => {})
                .putIfAbsent(childName, () => [])
                .add(vaccineLabel);
          }
        }
      }

      // Determine maternal vaccine eligibility
      for (final motherId in motherIds) {
        if (activePregnancies.containsKey(motherId)) {
          motherMaternalEligible[motherId] = true;
        }
      }

      // 6. Notify eligible mothers
      final formattedDate = DateFormat('MMMM d, yyyy').format(scheduleDate);
      final oneDayAgo = DateTime.now().subtract(const Duration(hours: 24)).toIso8601String();

      for (final motherId in motherIds) {
        final m = motherMap[motherId]!;
        final account = m['account'] as Map<String, dynamic>?;
        if (account == null) continue;

        final accountId = m['account_id'] as int?;
        if (accountId == null) continue;

        final childRemindersMap = motherChildReminders[motherId] ?? {};
        final childReminders = childRemindersMap.entries.map((e) {
          return '${e.key}: ${e.value.join(', ')}';
        }).toList();

        final hasMaternal = motherMaternalEligible[motherId] == true;

        if (childReminders.isEmpty && !hasMaternal) {
          continue; // Not eligible for any scheduled vaccines
        }

        // Check for recent notifications of type 'vaccine_reminder' to prevent spam (24h cooldown)
        final existing = await _client
            .from('notifications')
            .select('notification_id')
            .eq('account_id', accountId)
            .eq('type', 'vaccine_reminder')
            .gte('created_at', oneDayAgo);

        if (existing.isNotEmpty) {
          if (kDebugMode) {
            print('Deduplicating notification: account $accountId already notified in the last 24 hours.');
          }
          continue;
        }

        // Construct message contents
        final phone = account['phone_number']?.toString();

        String notificationTitle = 'Immunization Schedule / Iskedyul ng Bakuna';
        String msgTagalog = '';
        String msgEnglish = '';

        if (childReminders.isNotEmpty && hasMaternal) {
          final vaccinesList = childReminders.join('; ');
          msgTagalog = 'Paalala mula sa $bhcName: May bakuna ngayong $formattedDate para sa inyo (TD) at sa bata: $vaccinesList. Pumunta po sa health center. Salamat!';
          msgEnglish = 'Reminder from $bhcName: Vaccine schedule on $formattedDate for you (TD) & child: $vaccinesList. Please visit the health center. Thanks!';
        } else if (childReminders.isNotEmpty) {
          final vaccinesList = childReminders.join('; ');
          msgTagalog = 'Paalala mula sa $bhcName: May bakuna ngayong $formattedDate para kay: $vaccinesList. Pumunta po sa health center. Salamat!';
          msgEnglish = 'Reminder from $bhcName: Vaccine schedule on $formattedDate for: $vaccinesList. Please visit the health center. Thanks!';
        } else if (hasMaternal) {
          msgTagalog = 'Paalala mula sa $bhcName: May TD vaccine para sa buntis ngayong $formattedDate. Pumunta po sa health center. Salamat!';
          msgEnglish = 'Reminder from $bhcName: TD vaccine schedule for pregnant mothers on $formattedDate. Please visit the health center. Thanks!';
        }

        final combinedMessage = '$msgTagalog\n\n$msgEnglish';

        // Dispatch Push Notification
        try {
          await NotificationService.createNotification(
            accountId: accountId,
            title: notificationTitle,
            message: combinedMessage,
            type: 'vaccine_reminder',
          );
          pushSent++;
        } catch (e) {
          errors.add('Failed to send push to account $accountId: $e');
        }

        // Dispatch SMS
        if (phone != null && phone.isNotEmpty) {
          try {
            final smsSuccess = await SmsService.sendSmsMessage(phone, combinedMessage);
            if (smsSuccess) {
              smsSent++;
            } else {
              errors.add('SMS gateway failed to send message to $phone');
            }
          } catch (e) {
            errors.add('Failed to send SMS to $phone: $e');
          }
        }
      }

    } catch (e, stackTrace) {
      debugPrint('Error in notifyEligibleBeneficiaries: $e\n$stackTrace');
      errors.add('General error: $e');
    }

    return ImmunizationReminderResult(
      pushSent: pushSent,
      smsSent: smsSent,
      errors: errors,
    );
  }
}
