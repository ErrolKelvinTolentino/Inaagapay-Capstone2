// lib/services/mother_transfer_service.dart
//
// Moving a mother to another barangay health centre, from the midwife app.
// The move itself is transfer_mother (20260928_mother_transfer.sql): her
// record, patient number and children go together, both centres' midwives are
// told, and the database decides whether this midwife may do it.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_storage.dart';
import 'supabase_service.dart';

class TransferDestination {
  const TransferDestination(this.id, this.name, this.barangay);

  final int id;
  final String name;
  final String? barangay;

  String get label =>
      barangay == null || barangay!.isEmpty ? name : '$name ($barangay)';
}

class MotherTransferResult {
  const MotherTransferResult(this.success, this.message);

  final bool success;
  final String message;
}

class MotherTransferService {
  const MotherTransferService._();

  /// Active barangay health centres other than [excludeBhcId].
  static Future<List<TransferDestination>> destinations({int? excludeBhcId}) async {
    final rows = await SupabaseService.client
        .from('health_facilities')
        .select('facility_id, name, barangay, is_active')
        .eq('facility_type', 'BHC')
        .order('name');
    return [
      for (final row in rows)
        if (row['is_active'] != false &&
            (row['facility_id'] as num?)?.toInt() != excludeBhcId)
          TransferDestination(
            (row['facility_id'] as num).toInt(),
            row['name']?.toString() ?? 'Health center',
            row['barangay']?.toString(),
          ),
    ];
  }

  static Future<MotherTransferResult> transfer({
    required int motherId,
    required int toBhcId,
    required String reason,
    bool moveChildren = true,
    String? newBarangay,
  }) async {
    final actorId = await AuthStorage.getUserId();
    if (actorId == null) {
      return const MotherTransferResult(false, 'You are not signed in.');
    }
    try {
      final data = await SupabaseService.client.rpc('transfer_mother', params: {
        'p_actor_id': actorId,
        'p_mother_id': motherId,
        'p_to_bhc_id': toBhcId,
        'p_reason': reason.trim(),
        'p_move_children': moveChildren,
        'p_new_barangay':
            (newBarangay ?? '').trim().isEmpty ? null : newBarangay!.trim(),
      });
      final result = Map<String, dynamic>.from(data as Map);
      if (result['success'] != true) {
        return MotherTransferResult(
            false, result['error']?.toString() ?? 'The transfer was refused.');
      }
      // Her caseload counts change at both centres.
      SupabaseService.clearMidwifeContextCache();
      final kids = (result['children_moved'] as num?)?.toInt() ?? 0;
      return MotherTransferResult(
        true,
        'Transferred to ${result['to_name']}'
        '${kids > 0 ? ' with $kids ${kids == 1 ? 'child' : 'children'}' : ''}. '
        'New patient no. ${result['patient_number'] ?? '-'}.',
      );
    } on PostgrestException catch (e) {
      if (kDebugMode) debugPrint('transfer_mother failed: ${e.code} ${e.message}');
      if (e.code == 'PGRST202' || e.code == '42883') {
        return const MotherTransferResult(
          false,
          'Transfers need a database update (20260928). Ask your administrator.',
        );
      }
      return MotherTransferResult(false, 'The transfer failed: ${e.message}');
    } catch (e) {
      return const MotherTransferResult(
          false, 'The transfer failed. Check the connection and try again.');
    }
  }
}
