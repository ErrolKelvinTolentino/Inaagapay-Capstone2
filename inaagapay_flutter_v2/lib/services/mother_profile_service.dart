// lib/services/mother_profile_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

import 'auth_storage.dart';

class MotherProfileService {
  static SupabaseClient get client => Supabase.instance.client;

  // Fetch complete mother profile with all related data
  static Future<Map<String, dynamic>> fetchMotherProfile(int motherId) async {
    try {
      if (kDebugMode) {
        print('=== FETCHING MOTHER PROFILE ===');
        print('Mother ID: $motherId');
      }

      // Step 1: Run ALL independent top-level queries concurrently
      final results = await Future.wait<dynamic>([
        // [0] motherResponse
        client.from('mothers').select('''
              *,
              registered_by:midwives!registered_by_midwife_id (
                midwife_id,
                account:accounts (first_name, last_name)
              ),
              account:account_id (
                account_id,
                email_address,
                first_name,
                middle_name,
                last_name,
                extension_name,
                phone_number,
                status,
                created_at
              )
            ''').eq('mother_id', motherId).single(),

        // [1] pregnanciesResponse (flat scalar query - no heavy embedded child array subqueries)
        client
            .from('pregnancies')
            .select('*')
            .eq('mother_id', motherId)
            .order('created_at', ascending: false)
            .timeout(const Duration(seconds: 8))
            .catchError((e) {
              debugPrint('Pregnancies query note: $e');
              return <Map<String, dynamic>>[];
            }),

        // [2] medicalConditions
        client
            .from('medical_conditions')
            .select('*')
            .eq('mother_id', motherId)
            .order('created_at', ascending: false)
            .timeout(const Duration(seconds: 8))
            .catchError((e) {
              debugPrint('Medical conditions query note: $e');
              return <Map<String, dynamic>>[];
            }),

        // [3] allergies
        client
            .from('allergies')
            .select('*')
            .eq('mother_id', motherId)
            .order('created_at', ascending: false)
            .timeout(const Duration(seconds: 8))
            .catchError((e) {
              debugPrint('Allergies query note: $e');
              return <Map<String, dynamic>>[];
            }),

        // [4] emergencyContacts
        client
            .from('emergency_contacts')
            .select('*')
            .eq('mother_id', motherId)
            .order('created_at', ascending: false)
            .timeout(const Duration(seconds: 8))
            .catchError((e) {
              debugPrint('Emergency contacts query note: $e');
              return <Map<String, dynamic>>[];
            }),

        // [5] children
        client.from('children').select('''
              *,
              birth_details (*)
            ''').eq('mother_id', motherId).order('added_at', ascending: false)
            .timeout(const Duration(seconds: 8))
            .catchError((e) {
              debugPrint('Mother children query note: $e');
              return <Map<String, dynamic>>[];
            }),
      ]);

      final motherResponse = results[0] as Map<String, dynamic>;
      final pregnanciesRaw = results[1] as List<dynamic>;
      final medicalConditions = results[2] as List<dynamic>;
      final allergies = results[3] as List<dynamic>;
      final emergencyContacts = results[4] as List<dynamic>;
      final children = results[5] as List<dynamic>;

      final pregnancies = pregnanciesRaw
          .map((p) => Map<String, dynamic>.from(p as Map))
          .toList();

      final account = motherResponse['account'] as Map<String, dynamic>? ?? {};

      final pregnancyIds = pregnancies
          .map((p) => p['pregnancy_id'])
          .whereType<int>()
          .toList();

      final encounterById = <int, Map<String, dynamic>>{};
      final aiByCheckupId = <int, Map<String, dynamic>>{};
      final riskByAiResponseId = <int, Map<String, dynamic>>{};
      final factorsByRiskId = <int, List<Map<String, dynamic>>>{};

      // Step 2: Fetch pregnancy child tables, encounters, and risk data concurrently
      if (pregnancyIds.isNotEmpty) {
        final step2Futures = <Future<dynamic>>[
          // [0] Encounters
          client.from('clinical_encounters').select('''
                encounter_id,
                pregnancy_id,
                encounter_datetime,
                age_of_gestation_weeks,
                age_of_gestation_days,
                midwife_notes,
                remarks_source,
                is_midwife_approved,
                recorded_by:midwives (
                  midwife_id,
                  account:accounts (first_name, last_name)
                ),
                symptoms:pregnancy_symptoms (
                  symptom_id,
                  notes,
                  symptom_type_id,
                  symptom_type:symptom_types (
                    symptom_name,
                    risk_category
                  )
                ),
                weight_gain:weight_gain_evaluations (
                  evaluation_id,
                  mode,
                  status,
                  confidence,
                  message,
                  flags,
                  actual_gain,
                  weekly_gain
                )
              ''').inFilter('pregnancy_id', pregnancyIds),

          // [1] Checkups
          client.from('prenatal_checkups').select('''
                encounter_id,
                pregnancy_id,
                checkup_weight,
                blood_pressure_systolic,
                blood_pressure_diastolic,
                fetal_position,
                fetal_heart_beat,
                fetal_heart_tone,
                td_vaccine_dose,
                edema,
                next_schedule
              ''').inFilter('pregnancy_id', pregnancyIds),

          // [2] Ultrasounds
          //
          // `ultrasound_image` and `lab_test_image` are deliberately NOT
          // selected here. They hold base64 image data inline — a single
          // ultrasound measured 3 MB, and one mother's records came to 36 MB
          // across fifteen rows. Pulling that to draw a list of dates killed
          // the query at the Postgres statement timeout (57014), the Dart
          // guard turned the failure into an empty list, and the screen said
          // "No ultrasounds recorded yet" to a mother who had six.
          //
          // Nothing on the list needs the bytes; it renders a date and a type.
          // The image is fetched by encounter_id when a record is opened, so
          // one image loads instead of fifteen.
          client.from('ultrasounds').select('''
                encounter_id,
                pregnancy_id,
                ultrasound_date,
                ultrasound_location,
                remarks:findings_summary,
                health_worker_name,
                health_worker_institution,
                health_worker_profession,
                monitoring_classification,
                created_at
              ''').inFilter('pregnancy_id', pregnancyIds),

          // [3] Lab Tests
          client.from('lab_tests').select('''
                encounter_id,
                pregnancy_id,
                lab_test_type,
                lab_test_location,
                fasting_glucose_mg_dl,
                glucose_1hr_mg_dl,
                glucose_2hr_mg_dl,
                glucose_3hr_mg_dl,
                hemoglobin_g_dl,
                hematocrit_pct,
                wbc_count,
                platelet_count,
                urinalysis_protein,
                urinalysis_glucose,
                hepatitis_b_status,
                health_worker_name,
                health_worker_institution,
                health_worker_profession,
                created_at
              ''').inFilter('pregnancy_id', pregnancyIds),

          // [4] Maternal Vitals
          client.from('maternal_vitals').select('''
                vital_id,
                pregnancy_id,
                recorded_at,
                age_of_gestation,
                weight_kg,
                height_cm,
                notes,
                created_at
              ''').inFilter('pregnancy_id', pregnancyIds),

          // [5] Deliveries
          client.from('deliveries').select('''
                delivery_id:encounter_id,
                pregnancy_id,
                delivery_date,
                place_of_delivery,
                delivery_method,
                fetus_number
              ''').inFilter('pregnancy_id', pregnancyIds),

          // [6] Outcomes
          client.from('pregnancy_outcomes').select('''
                outcome_id,
                pregnancy_id,
                fetus_number,
                outcome,
                outcome_date
              ''').inFilter('pregnancy_id', pregnancyIds),

          // [7] Risk Assessments
          client
              .from('pregnancy_risk_assessments')
              .select('''
                pregnancy_risk_id,
                pregnancy_id,
                ai_response_id,
                risk_level,
                assessed_by_ai,
                created_at,
                updated_at
              ''')
              .inFilter('pregnancy_id', pregnancyIds)
              .order('created_at', ascending: false),
        ];

        // Every one of these is guarded, because Future.wait fails whole: a
        // single slow table takes the pregnancies, checkups, children and
        // vitals down with it and the screen shows "Error Loading Profile".
        //
        // The tables here are mostly *un-indexed* on pregnancy_id — only
        // clinical_encounters and pregnancy_risk_assessments have one — so
        // lab_tests, ultrasounds and prenatal_checkups are sequential scans
        // that lengthen every time a record is saved. Recording lab tests all
        // afternoon is exactly what pushes them past the statement timeout.
        //
        // Each failure is named in the log so the culprit identifies itself
        // rather than hiding behind a generic profile error. The lasting fix
        // is database/migrations/20260815_ai_responses_index.sql.
        const step2Labels = [
          'encounters',
          'checkups',
          'ultrasounds',
          'lab tests',
          'maternal vitals',
          'deliveries',
          'outcomes',
          'risk assessments',
        ];

        final guardedStep2 = <Future<dynamic>>[];
        for (var i = 0; i < step2Futures.length; i++) {
          final label = i < step2Labels.length ? step2Labels[i] : 'query $i';
          guardedStep2.add(
            step2Futures[i].timeout(const Duration(seconds: 6)).catchError((e) {
              debugPrint(
                  'Profile: $label unavailable, profile still loads — $e');
              return <Map<String, dynamic>>[];
            }),
          );
        }

        final step2Results = await Future.wait(guardedStep2);
        final encountersList = step2Results[0] as List<dynamic>;
        final checkupsList = step2Results[1] as List<dynamic>;
        final ultrasoundsList = step2Results[2] as List<dynamic>;
        final labTestsList = step2Results[3] as List<dynamic>;
        final vitalsList = step2Results[4] as List<dynamic>;
        final deliveriesList = step2Results[5] as List<dynamic>;
        final outcomesList = step2Results[6] as List<dynamic>;
        final riskRows = step2Results[7] as List<dynamic>;

        for (final row in riskRows.cast<Map<String, dynamic>>()) {
          final aiId = row['ai_response_id'];
          if (aiId is int && !riskByAiResponseId.containsKey(aiId)) {
            riskByAiResponseId[aiId] = row;
          }
        }

        for (final enc in encountersList.cast<Map<String, dynamic>>()) {
          final id = enc['encounter_id'];
          if (id is int) encounterById[id] = enc;
        }

        final checkupsByPregId = <int, List<Map<String, dynamic>>>{};
        final checkupIds = <int>[];
        for (final row in checkupsList.cast<Map<String, dynamic>>()) {
          final pId = row['pregnancy_id'];
          if (pId is int) {
            checkupsByPregId.putIfAbsent(pId, () => []);
            checkupsByPregId[pId]!.add(row);
          }
          final encId = row['encounter_id'];
          if (encId is int) checkupIds.add(encId);
        }

        final ultrasoundsByPregId = <int, List<Map<String, dynamic>>>{};
        for (final row in ultrasoundsList.cast<Map<String, dynamic>>()) {
          final pId = row['pregnancy_id'];
          if (pId is int) {
            ultrasoundsByPregId.putIfAbsent(pId, () => []);
            ultrasoundsByPregId[pId]!.add(row);
          }
        }

        final labTestsByPregId = <int, List<Map<String, dynamic>>>{};
        for (final row in labTestsList.cast<Map<String, dynamic>>()) {
          final pId = row['pregnancy_id'];
          if (pId is int) {
            labTestsByPregId.putIfAbsent(pId, () => []);
            labTestsByPregId[pId]!.add(row);
          }
        }

        final vitalsByPregId = <int, List<Map<String, dynamic>>>{};
        for (final row in vitalsList.cast<Map<String, dynamic>>()) {
          final pId = row['pregnancy_id'];
          if (pId is int) {
            vitalsByPregId.putIfAbsent(pId, () => []);
            vitalsByPregId[pId]!.add(row);
          }
        }

        final deliveriesByPregId = <int, List<Map<String, dynamic>>>{};
        for (final row in deliveriesList.cast<Map<String, dynamic>>()) {
          final pId = row['pregnancy_id'];
          if (pId is int) {
            deliveriesByPregId.putIfAbsent(pId, () => []);
            deliveriesByPregId[pId]!.add(row);
          }
        }

        final outcomesByPregId = <int, List<Map<String, dynamic>>>{};
        for (final row in outcomesList.cast<Map<String, dynamic>>()) {
          final pId = row['pregnancy_id'];
          if (pId is int) {
            outcomesByPregId.putIfAbsent(pId, () => []);
            outcomesByPregId[pId]!.add(row);
          }
        }

        // Attach child table arrays to pregnancy objects
        for (final pregnancy in pregnancies) {
          final pId = pregnancy['pregnancy_id'] as int;
          pregnancy['checkups'] = checkupsByPregId[pId] ?? <Map<String, dynamic>>[];
          pregnancy['ultrasounds'] = ultrasoundsByPregId[pId] ?? <Map<String, dynamic>>[];
          pregnancy['lab_tests'] = labTestsByPregId[pId] ?? <Map<String, dynamic>>[];
          pregnancy['maternal_vitals'] = vitalsByPregId[pId] ?? <Map<String, dynamic>>[];
          pregnancy['delivery'] = deliveriesByPregId[pId] ?? <Map<String, dynamic>>[];
          pregnancy['outcomes'] = outcomesByPregId[pId] ?? <Map<String, dynamic>>[];
        }

        // Fetch AI responses and Risk factors concurrently in Step 2b if checkupIds / riskRows exist
        if (checkupIds.isNotEmpty) {
          // Degrades instead of taking the whole profile down.
          //
          // ai_responses carries no index and grows with every AI call, so
          // this filter becomes a sequential scan over an ever larger table.
          // Unguarded, one slow scan threw out of fetchMotherProfile entirely
          // and the screen showed "Error Loading Profile" — losing her
          // pregnancies, checkups, children and vitals to recover a panel of
          // AI commentary. Losing the commentary is the better trade.
          //
          // The lasting fix is the index in
          // database/migrations/20260815_ai_responses_index.sql.
          final aiRows = await client
              .from('ai_responses')
              .select('''
                ai_response_id,
                reference_id,
                response,
                ai_model,
                status,
                generated_by_ai,
                created_at,
                updated_at
              ''')
              .eq('reference_table', 'prenatal_checkups')
              .eq('response_type', 'risk_assessment')
              .inFilter('reference_id', checkupIds)
              .timeout(const Duration(seconds: 6))
              .catchError((e) {
                debugPrint('AI responses query note (profile still loads): $e');
                return <Map<String, dynamic>>[];
              });

          for (final row in (aiRows as List).cast<Map<String, dynamic>>()) {
            final refId = row['reference_id'];
            if (refId is int) aiByCheckupId[refId] = row;
          }
        }

        final riskIds = riskByAiResponseId.values
            .map((r) => r['pregnancy_risk_id'])
            .whereType<int>()
            .toList();

        if (riskIds.isNotEmpty) {
          final factorRows = await client
              .from('pregnancy_risk_factors')
              .select('''
                risk_factor_id,
                pregnancy_risk_id,
                factor,
                risk_influence,
                source_table,
                source_id
              ''')
              .inFilter('pregnancy_risk_id', riskIds)
              .order('created_at', ascending: true)
              .timeout(const Duration(seconds: 6))
              .catchError((e) {
                debugPrint('Risk factors query note (profile still loads): $e');
                return <Map<String, dynamic>>[];
              });

          for (final row in (factorRows as List).cast<Map<String, dynamic>>()) {
            final riskId = row['pregnancy_risk_id'];
            if (riskId is! int) continue;
            factorsByRiskId.putIfAbsent(riskId, () => <Map<String, dynamic>>[]);
            factorsByRiskId[riskId]!.add(row);
          }
        }
      }

      // Step 3: Re-assemble encounter data onto checkups, ultrasounds, lab_tests
      for (final p in pregnancies) {
        final pregnancy = p;
        final checkups = (pregnancy['checkups'] as List?) ?? const [];
        for (final c in checkups) {
          final checkup = c as Map<String, dynamic>;
          final encId = checkup['encounter_id'];
          if (encId is int && encounterById.containsKey(encId)) {
            checkup['encounter'] = encounterById[encId];
          }

          // Map encounter fields to top-level keys
          final encounter = checkup['encounter'] as Map<String, dynamic>?;
          if (encounter != null) {
            checkup['checkup_datetime'] = encounter['encounter_datetime'];
            checkup['midwife'] = encounter['recorded_by'];
            final weeks = (encounter['age_of_gestation_weeks'] as num?)?.toDouble() ?? 0;
            final days = (encounter['age_of_gestation_days'] as num?)?.toDouble() ?? 0;
            checkup['age_of_gestation'] = weeks + days / 7.0;
            checkup['remarks'] = encounter['midwife_notes'];
            // Carried alongside the note so the record view can say how it was
            // written rather than labelling every summary the same way.
            checkup['remarks_source'] = encounter['remarks_source'];
            checkup['symptoms'] = encounter['symptoms'];
            checkup['weight_gain'] = encounter['weight_gain'];
            checkup['is_midwife_approved'] = encounter['is_midwife_approved'];
          }

          final checkupId = checkup['encounter_id'];
          if (checkupId is! int) continue;
          final aiRow = aiByCheckupId[checkupId];
          if (aiRow != null) {
            checkup['risk_ai_response'] = aiRow;
            final aiId = aiRow['ai_response_id'];
            if (aiId is int) {
              final risk = riskByAiResponseId[aiId];
              if (risk != null) {
                checkup['risk_assessment'] = risk;
                final riskId = risk['pregnancy_risk_id'];
                if (riskId is int) {
                  checkup['risk_factors'] =
                      factorsByRiskId[riskId] ?? <Map<String, dynamic>>[];
                }
              }
            }
          }
        }

        final ultrasounds = (pregnancy['ultrasounds'] as List?) ?? const [];
        for (final us in ultrasounds) {
          final usMap = us as Map<String, dynamic>;
          final encId = usMap['encounter_id'];
          if (encId is int && encounterById.containsKey(encId)) {
            usMap['encounter'] = encounterById[encId];
          }
          usMap['ultrasound_id'] = usMap['encounter_id'];
          usMap['recorded_by'] = usMap['encounter']?['recorded_by'];
          usMap['is_midwife_approved'] =
              usMap['encounter']?['is_midwife_approved'];
        }

        final labTests = (pregnancy['lab_tests'] as List?) ?? const [];
        for (final lt in labTests) {
          final ltMap = lt as Map<String, dynamic>;
          final encId = ltMap['encounter_id'];
          if (encId is int && encounterById.containsKey(encId)) {
            ltMap['encounter'] = encounterById[encId];
          }
          ltMap['lab_test_id'] = ltMap['encounter_id'];
          ltMap['lab_test_date'] = ltMap['encounter']?['encounter_datetime'];
          ltMap['remarks'] = ltMap['encounter']?['midwife_notes'];
          ltMap['recorded_by'] = ltMap['encounter']?['recorded_by'];
          ltMap['is_midwife_approved'] =
              ltMap['encounter']?['is_midwife_approved'];
        }
      }

      // Separate current and past pregnancies
      Map<String, dynamic>? currentPregnancy;
      final List<Map<String, dynamic>> pastPregnancies = [];

      for (var p in pregnancies) {
        final pregnancy = Map<String, dynamic>.from(p as Map);
        if (pregnancy['status'] == 'ongoing') {
          currentPregnancy = pregnancy;
        } else {
          pastPregnancies.add(pregnancy);
        }
      }

      // Build complete profile
      final profile = <String, dynamic>{
        'mother_id': motherId,
        'account_id': motherResponse['account_id'],
        'assigned_bhc_id': motherResponse['assigned_bhc_id'],
        'birthdate': motherResponse['birthdate'],
        'house_number': motherResponse['house_number'],
        'street': motherResponse['street'],
        'barangay': motherResponse['barangay'],
        'city_municipality': motherResponse['city_municipality'],
        'province': motherResponse['province'],
        'height': motherResponse['height'],
        'weight': motherResponse['weight'],
        'blood_type': motherResponse['blood_type'],
        'status': motherResponse['status'],
        'gravida': motherResponse['gravida'],
        'para': motherResponse['para'],
        'abortus': motherResponse['abortus'],
        'living_children': motherResponse['living_children'],
        'registered_by': motherResponse['registered_by'],

        // Account info
        'first_name': account['first_name'],
        'middle_name': account['middle_name'],
        'last_name': account['last_name'],
        'extension_name': account['extension_name'],
        'email_address': account['email_address'],
        'phone_number': account['phone_number'],
        'account_status': account['status'],
        'created_at': account['created_at'],

        // Full name
        'full_name': [
          account['first_name'],
          account['middle_name'],
          account['last_name'],
          account['extension_name']
        ].where((e) => e != null && e.toString().trim().isNotEmpty).join(' '),

        // Pregnancies
        'current_pregnancy': currentPregnancy,
        'past_pregnancies': pastPregnancies,
        'pregnancies_count': pregnancies.length,

        // Medical info
        'medical_conditions': medicalConditions,
        'allergies': allergies,
        'emergency_contacts': emergencyContacts,

        // Children
        'children': children,
        'children_count': children.length,
      };

      if (kDebugMode) {
        print('✅ Profile fetched successfully');
      }

      return profile;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error fetching mother profile: $e');
      }
      throw Exception('Failed to load mother profile: $e');
    }
  }

  /// Closes a pregnancy and files its outcome for each fetus.
  ///
  /// Three things about the order of writes here are deliberate, because the
  /// first version got all three wrong and left records behind that nobody
  /// could see or undo from the app:
  ///
  /// 1. **A delivery is a clinical encounter.** `deliveries.encounter_id` is
  ///    NOT NULL and unique — it *is* the primary key — so the encounter row
  ///    has to exist first. Inserting the delivery on its own failed with
  ///    `null value in column "encounter_id" ... violates not-null constraint`
  ///    every single time, which is why concluding a pregnancy never worked.
  ///
  /// 2. **The pregnancy is marked ended last.** It used to be marked first, so
  ///    a failure anywhere after it left a pregnancy that was closed but had no
  ///    outcome and no delivery — and the midwife had no screen to fix it from.
  ///    Ending last means a failed attempt leaves the pregnancy exactly as it
  ///    was, and the midwife can simply try again.
  ///
  /// 3. **Retrying does not duplicate.** Existing rows for the same fetus are
  ///    updated rather than inserted again. `pregnancy_outcomes` drives the
  ///    `trg_update_ob_history` trigger, which recomputes gravida/para/abortus
  ///    on the mother by counting rows — so a second attempt used to raise her
  ///    para by one more each time.
  static Future<bool> concludePregnancy(
      int pregnancyId,
      double? gestationalAgeAtEnd,
      List<Map<String, dynamic>> fetalOutcomes) async {
    try {
      // Read what is needed before writing anything.
      final pregnancy = await client
          .from('pregnancies')
          .select('mother_id')
          .eq('pregnancy_id', pregnancyId)
          .maybeSingle();

      final motherId = (pregnancy?['mother_id'] as num?)?.toInt();
      if (motherId == null) {
        if (kDebugMode) {
          print('Cannot conclude pregnancy $pregnancyId: no mother on file');
        }
        return false;
      }

      final recorder = await _currentMidwifeRecorder();

      final existingOutcomes = await client
          .from('pregnancy_outcomes')
          .select('outcome_id, fetus_number')
          .eq('pregnancy_id', pregnancyId);
      final outcomeIdByFetus = <int, int>{
        for (final row in (existingOutcomes as List))
          if ((row['fetus_number'] as num?)?.toInt() != null)
            (row['fetus_number'] as num).toInt():
                (row['outcome_id'] as num).toInt(),
      };

      final existingDeliveries = await client
          .from('deliveries')
          .select('encounter_id, fetus_number')
          .eq('pregnancy_id', pregnancyId);
      final deliveryEncounterByFetus = <int, int>{
        for (final row in (existingDeliveries as List))
          if ((row['fetus_number'] as num?)?.toInt() != null)
            (row['fetus_number'] as num).toInt():
                (row['encounter_id'] as num).toInt(),
      };

      for (final f in fetalOutcomes) {
        final fetusNumber = (f['fetus_number'] as num?)?.toInt() ?? 1;
        final outcome = f['outcome']?.toString();

        final outcomeFields = {
          'outcome': outcome,
          'outcome_date': f['outcome_date'],
          'is_outcome_date_estimated': false,
        };

        final existingOutcomeId = outcomeIdByFetus[fetusNumber];
        if (existingOutcomeId != null) {
          await client
              .from('pregnancy_outcomes')
              .update(outcomeFields)
              .eq('outcome_id', existingOutcomeId);
        } else {
          await client.from('pregnancy_outcomes').insert({
            'pregnancy_id': pregnancyId,
            'fetus_number': fetusNumber,
            ...outcomeFields,
          });
        }

        if (outcome != 'live_birth' && outcome != 'stillbirth') continue;

        // The form only asks for one date. Falling back to it keeps the
        // delivery row from being filed with no date at all.
        final deliveryDate = f['delivery_date'] ?? f['outcome_date'];

        final deliveryFields = {
          'delivery_date': deliveryDate,
          'place_of_delivery': f['place_of_delivery'],
          'delivery_method': f['delivery_method'],
          'is_delivery_date_estimated': false,
        };

        final existingEncounterId = deliveryEncounterByFetus[fetusNumber];
        if (existingEncounterId != null) {
          await client
              .from('deliveries')
              .update(deliveryFields)
              .eq('encounter_id', existingEncounterId);
          continue;
        }

        final encounter = await client
            .from('clinical_encounters')
            .insert({
              'pregnancy_id': pregnancyId,
              'mother_id': motherId,
              'encounter_type': 'delivery',
              'encounter_datetime': deliveryDate != null
                  ? '${deliveryDate}T00:00:00'
                  : DateTime.now().toIso8601String(),
              if (recorder?['midwife_id'] != null)
                'recorded_by': recorder!['midwife_id'],
              if (recorder?['facility_id'] != null)
                'facility_id': recorder!['facility_id'],
            })
            .select('encounter_id')
            .maybeSingle();

        final encounterId = (encounter?['encounter_id'] as num?)?.toInt();
        if (encounterId == null) {
          if (kDebugMode) {
            print('Could not open a delivery encounter for fetus $fetusNumber');
          }
          return false;
        }

        await client.from('deliveries').insert({
          'encounter_id': encounterId,
          'pregnancy_id': pregnancyId,
          'fetus_number': fetusNumber,
          ...deliveryFields,
        });
      }

      await client.from('pregnancies').update({
        'status': 'ended',
        'gestational_age_at_end': gestationalAgeAtEnd,
        'ended_at': DateTime.now().toIso8601String(),
      }).eq('pregnancy_id', pregnancyId);

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error concluding pregnancy: $e');
      }
      return false;
    }
  }

  /// The signed-in midwife, so the delivery encounter carries a name and a
  /// health centre instead of appearing in the record as unattributed.
  ///
  /// Best-effort: a database where the posting column is missing, or a session
  /// that cannot be resolved, files the encounter without attribution rather
  /// than failing the conclusion.
  static Future<Map<String, dynamic>?> _currentMidwifeRecorder() async {
    try {
      final accountId = await AuthStorage.getUserId();
      if (accountId == null) return null;

      final midwife = await client
          .from('midwives')
          .select('midwife_id, assigned_bhc_id')
          .eq('account_id', accountId)
          .maybeSingle();
      if (midwife == null) return null;

      return {
        'midwife_id': (midwife['midwife_id'] as num?)?.toInt(),
        'facility_id': (midwife['assigned_bhc_id'] as num?)?.toInt(),
      };
    } catch (e) {
      if (kDebugMode) {
        print('Delivery encounter will be unattributed: $e');
      }
      return null;
    }
  }

  // Start new pregnancy
  static Future<bool> startNewPregnancy(
      int motherId, DateTime lmp, DateTime edd) async {
    try {
      await client.from('pregnancies').insert({
        'mother_id': motherId,
        'last_menstrual_period': lmp.toIso8601String().split('T')[0],
        'expected_date_of_delivery': edd.toIso8601String().split('T')[0],
        'status': 'ongoing',
      });
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error starting pregnancy: $e');
      }
      return false;
    }
  }

  // Get AI analysis for checkup
  static Future<String?> getCheckupAIAnalysis(int checkupId) async {
    try {
      final response = await client
          .from('ai_responses')
          .select('response')
          .eq('reference_table', 'prenatal_checkups')
          .eq('reference_id', checkupId)
          .eq('response_type', 'checkup_analysis')
          .maybeSingle();

      return response?['response'] as String?;
    } catch (e) {
      return null;
    }
  }

  // Get AI analysis for ultrasound
  static Future<String?> getUltrasoundAIAnalysis(int ultrasoundId) async {
    try {
      final response = await client
          .from('ai_responses')
          .select('response')
          .eq('reference_table', 'ultrasounds')
          .eq('reference_id', ultrasoundId)
          .eq('response_type', 'ultrasound_analysis')
          .eq('status', 'approved')
          .maybeSingle();

      return response?['response'] as String?;
    } catch (e) {
      return null;
    }
  }

  // Get AI analysis for lab test
  static Future<String?> getLabTestAIAnalysis(int labTestId) async {
    try {
      final primaryResponse = await client
          .from('ai_responses')
          .select('response')
          .eq('reference_table', 'lab_tests')
          .eq('reference_id', labTestId)
          .eq('response_type', 'lab_test_analysis')
          .eq('status', 'approved')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (primaryResponse?['response'] != null) {
        return primaryResponse!['response'] as String?;
      }

      // Backward compatibility for older response_type naming.
      final fallbackResponse = await client
          .from('ai_responses')
          .select('response')
          .eq('reference_table', 'lab_tests')
          .eq('reference_id', labTestId)
          .eq('response_type', 'lab_analysis')
          .eq('status', 'approved')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      return fallbackResponse?['response'] as String?;
    } catch (e) {
      return null;
    }
  }
}
