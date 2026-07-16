// lib/services/child_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/child_model.dart';
import 'auth_storage.dart';

class ChildService {
  static SupabaseClient get client => Supabase.instance.client;

  static Future<int> _getMotherId() async {
    final motherId = await AuthStorage.getMotherId();
    if (motherId == null) {
      throw Exception('Mother ID not found. Please log out and log in again.');
    }
    return motherId;
  }

  // Fetch all children for the current mother
  static Future<List<ChildModel>> fetchChildren() async {
    final motherId = await _getMotherId();

    try {
      final response = await client.from('children').select('''
            *,
            birth_details (
              birthdate,
              birth_weight,
              birth_length,
              birthplace_city_municipality,
              birthplace_province
            )
          ''').eq('mother_id', motherId).order('added_at', ascending: false);

      final List<dynamic> data = response;

      return data.map((json) {
        final birthDetails = json['birth_details'] as Map<String, dynamic>?;
        return ChildModel(
          childId: json['child_id'] as int,
          motherId: json['mother_id'] as int,
          firstName: json['first_name'] as String? ?? '',
          middleName: json['middle_name'] as String?,
          lastName: json['last_name'] as String? ?? '',
          extensionName: json['extension_name'] as String?,
          sex: json['sex'] as String? ?? 'male',
          addedAt: DateTime.parse(json['added_at']),
          birthdate: birthDetails != null && birthDetails['birthdate'] != null
              ? DateTime.parse(birthDetails['birthdate'])
              : null,
          birthWeight: (birthDetails?['birth_weight'] as num?)?.toDouble(),
          birthLength: (birthDetails?['birth_length'] as num?)?.toDouble(),
          birthplaceCity:
              birthDetails?['birthplace_city_municipality'] as String?,
          birthplaceProvince: birthDetails?['birthplace_province'] as String?,
        );
      }).toList();
    } catch (e) {
      throw Exception('Failed to load children: $e');
    }
  }

  // Fetch a single child with all details
  static Future<Map<String, dynamic>> fetchChildDetails(int childId) async {
    final motherId = await _getMotherId();

    try {
      // Fetch child with birth details
      final childResponse = await client.from('children').select('''
            *,
            birth_details (
              birthdate,
              birth_weight,
              birth_length,
              birthplace_city_municipality,
              birthplace_province
            )
          ''').eq('child_id', childId).eq('mother_id', motherId).maybeSingle();

      if (childResponse == null) {
        throw Exception('Child not found');
      }

      // Fetch growth records
      final growthResponse = await client
          .from('child_details')
          .select('*')
          .eq('child_id', childId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      // Fetch immunization records
      final immunizationResponse = await client
          .from('immunization_record')
          .select('''
            *,
            vaccine:vaccine_id (*)
          ''')
          .eq('child_id', childId)
          .order('vaccination_date', ascending: false);

      final birthDetails =
          childResponse['birth_details'] as Map<String, dynamic>?;

      final child = ChildModel(
        childId: childResponse['child_id'] as int,
        motherId: childResponse['mother_id'] as int,
        firstName: childResponse['first_name'] as String? ?? '',
        middleName: childResponse['middle_name'] as String?,
        lastName: childResponse['last_name'] as String? ?? '',
        extensionName: childResponse['extension_name'] as String?,
        sex: childResponse['sex'] as String? ?? 'male',
        addedAt: DateTime.parse(childResponse['added_at']),
        birthdate: birthDetails != null && birthDetails['birthdate'] != null
            ? DateTime.parse(birthDetails['birthdate'])
            : null,
        birthWeight: (birthDetails?['birth_weight'] as num?)?.toDouble(),
        birthLength: (birthDetails?['birth_length'] as num?)?.toDouble(),
        birthplaceCity:
            birthDetails?['birthplace_city_municipality'] as String?,
        birthplaceProvince: birthDetails?['birthplace_province'] as String?,
      );

      final latestGrowth =
          growthResponse != null ? GrowthRecord.fromJson(growthResponse) : null;

      final immunizations = (immunizationResponse as List)
          .map((json) => ImmunizationRecord.fromJson(json))
          .toList();

      return {
        'child': child,
        'latest_growth': latestGrowth,
        'immunizations': immunizations,
      };
    } catch (e) {
      throw Exception('Failed to load child details: $e');
    }
  }

  // Fetch growth history for a child
  static Future<Map<String, dynamic>> fetchGrowthHistory(int childId) async {
    final motherId = await _getMotherId();

    try {
      final childResponse = await client
          .from('children')
          .select('first_name, last_name, sex')
          .eq('child_id', childId)
          .eq('mother_id', motherId)
          .maybeSingle();

      if (childResponse == null) {
        throw Exception('Child not found');
      }

      final growthResponse = await client
          .from('child_details')
          .select('*')
          .eq('child_id', childId)
          .order('created_at', ascending: true);

      final growthRecords = (growthResponse as List)
          .map((json) => GrowthRecord.fromJson(json))
          .toList();

      final heightValues = growthRecords.map((r) => r.height).toList();
      final weightValues = growthRecords.map((r) => r.weight).toList();
      final labels =
          growthRecords.asMap().entries.map((e) => '${e.key + 1}').toList();

      final heightStart = heightValues.isNotEmpty ? heightValues.first : null;
      final heightLatest = heightValues.isNotEmpty ? heightValues.last : null;
      final heightGain = heightStart != null && heightLatest != null
          ? (heightLatest - heightStart).toStringAsFixed(1)
          : null;

      final weightStart = weightValues.isNotEmpty ? weightValues.first : null;
      final weightLatest = weightValues.isNotEmpty ? weightValues.last : null;
      final weightGain = weightStart != null && weightLatest != null
          ? (weightLatest - weightStart).toStringAsFixed(1)
          : null;

      return {
        'child_name':
            '${childResponse['first_name']} ${childResponse['last_name']}'
                .trim(),
        'gender': childResponse['sex'],
        'height': {
          'values': heightValues,
          'start': heightStart,
          'latest': heightLatest,
          'gain': heightGain,
        },
        'weight': {
          'values': weightValues,
          'start': weightStart,
          'latest': weightLatest,
          'gain': weightGain,
        },
        'labels': labels,
        'records_count': growthRecords.length,
      };
    } catch (e) {
      throw Exception('Failed to load growth history: $e');
    }
  }

  // Fetch immunization records for a child
  static Future<List<ImmunizationRecord>> fetchImmunizations(
      int childId) async {
    try {
      final response = await client
          .from('immunization_record')
          .select('''
            *,
            vaccine:vaccine_id (*)
          ''')
          .eq('child_id', childId)
          .order('vaccination_date', ascending: false);

      return (response as List)
          .map((json) => ImmunizationRecord.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Failed to load immunizations: $e');
    }
  }
}
