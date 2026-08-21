import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_storage.dart';
import 'inventory_models.dart';

/// Live inventory access for the presentation branch.
///
/// It owns a client pointed at the same project as `admin-web`. This keeps the
/// branch isolated from the normal Flutter app, whose legacy configuration may
/// still target a different Supabase project.
class InventoryRepository {
  InventoryRepository({SupabaseClient? client})
      : _client = client ?? SupabaseClient(_supabaseUrl, _supabaseAnonKey);

  static const String _supabaseUrl = 'https://krooorixhjwygcsdoomg.supabase.co';
  static const String _supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
      'eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imtyb29vcml4aGp3eWdjc2Rvb21nIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ0NjI5NDIsImV4cCI6MjEwMDAzODk0Mn0.'
      'iVIxsgZhd_k0c-rDOjRK5J9xBiL0z-bH2l1LXH9IksU';

  static const int _demoAccountId = 9;
  static const int _demoFacilityId = 3;

  final SupabaseClient _client;
  bool _workflowRpcUnavailable = false;

  Future<MidwifeInventoryContext> resolveContext() async {
    final savedAccountId = await AuthStorage.getUserId();
    final savedRole = await AuthStorage.getUserRole();
    final savedToken = await AuthStorage.getToken();

    if (savedAccountId != null &&
        savedRole?.toLowerCase() == 'midwife' &&
        savedToken != null &&
        savedToken.isNotEmpty) {
      try {
        final savedContext = await _contextForAccount(
          accountId: savedAccountId,
          expectedToken: savedToken,
          isDemo: false,
        );
        if (savedContext != null) return savedContext;
      } catch (_) {
        // The direct-launch demo must remain usable if a legacy saved session
        // belongs to the Flutter project's other Supabase database.
      }
    }

    return await _contextForAccount(
          accountId: _demoAccountId,
          isDemo: true,
          fallbackFacilityId: _demoFacilityId,
        ) ??
        const MidwifeInventoryContext(
          accountId: _demoAccountId,
          midwifeId: 3,
          facilityId: _demoFacilityId,
          facilityName: 'Pinagbarilan BHC',
          displayName: 'Demo Midwife',
          isDemo: true,
        );
  }

  Future<MidwifeInventoryContext?> _contextForAccount({
    required int accountId,
    required bool isDemo,
    String? expectedToken,
    int? fallbackFacilityId,
  }) async {
    final account = await _client
        .from('accounts')
        .select(
          'account_id, account_type, status, first_name, last_name, '
          'last_login_token',
        )
        .eq('account_id', accountId)
        .maybeSingle();

    if (account == null ||
        account['account_type']?.toString().toLowerCase() != 'midwife' ||
        account['status']?.toString().toLowerCase() != 'active') {
      return null;
    }

    if (expectedToken != null &&
        account['last_login_token']?.toString() != expectedToken) {
      return null;
    }

    final midwife = await _client
        .from('midwives')
        .select('midwife_id, assigned_bhc_id')
        .eq('account_id', accountId)
        .maybeSingle();

    final facilityId =
        _nullableInt(midwife?['assigned_bhc_id']) ?? fallbackFacilityId;
    if (facilityId == null) return null;

    String facilityName = 'Barangay Health Center #$facilityId';
    String? supplierName;
    try {
      // parent_facility_id arrived with the MHO hierarchy; selecting it inside
      // the same round trip keeps the older fallback below intact for a
      // database that has not run that migration.
      final facility = await _client
          .from('health_facilities')
          .select('name, parent:parent_facility_id (name, facility_type)')
          .eq('facility_id', facilityId)
          .maybeSingle();
      final name = facility?['name']?.toString().trim();
      if (name != null && name.isNotEmpty) facilityName = name;

      final parent = facility?['parent'];
      final parentMap = parent is List
          ? (parent.isEmpty ? null : parent.first as Map?)
          : parent as Map?;
      final parentName = parentMap?['name']?.toString().trim();
      if (parentName != null && parentName.isNotEmpty) supplierName = parentName;
    } catch (_) {
      try {
        final bhc = await _client
            .from('bhc')
            .select('bhc_name')
            .eq('bhc_id', facilityId)
            .maybeSingle();
        final name = bhc?['bhc_name']?.toString().trim();
        if (name != null && name.isNotEmpty) facilityName = name;
      } catch (_) {}
    }

    final firstName = account['first_name']?.toString().trim() ?? '';
    final lastName = account['last_name']?.toString().trim() ?? '';
    final fullName = '$firstName $lastName'.trim();

    return MidwifeInventoryContext(
      accountId: accountId,
      midwifeId: _nullableInt(midwife?['midwife_id']) ?? accountId,
      facilityId: facilityId,
      facilityName: facilityName,
      displayName: fullName.isEmpty ? 'Midwife' : fullName,
      isDemo: isDemo,
      supplierName: supplierName,
    );
  }

  Future<InventorySnapshot> loadSnapshot(
    MidwifeInventoryContext context,
  ) async {
    try {
      final results = await Future.wait<dynamic>([
        _client
            .from('inventory_items')
            .select(
              'item_id, name, generic_name, item_code, '
              'strength_description, dosage_form, item_type, '
              'unit_of_measure, minimum_stock_threshold, '
              'doses_per_unit, open_vial_shelf_hours',
            )
            .order('name'),
        _client
            .from('inventory_batches')
            .select(
              'batch_id, item_id, facility_id, batch_number, '
              'quantity_received, quantity_remaining, received_date, '
              'expiration_date, manufacturer, status, '
              'doses_remaining_in_open_vial, open_vials_count, vial_opened_at',
            )
            .eq('facility_id', context.facilityId)
            .order('expiration_date'),
        _client
            .from('inventory_transactions')
            .select(
              'transaction_id, batch_id, facility_id, transaction_type, '
              'quantity, reference_type, reference_id, logged_at, '
              'inventory_batches(batch_id, item_id, batch_number, '
              'inventory_items(item_id, name, unit_of_measure))',
            )
            .eq('facility_id', context.facilityId)
            .order('logged_at', ascending: false)
            .limit(100),
      ]);

      final catalog = _rows(results[0])
          .map(InventoryCatalogRecord.fromJson)
          .where((item) => item.itemId > 0)
          .toList();
      final batches = _rows(results[1])
          .map(InventoryBatchRecord.fromJson)
          .where((batch) => batch.batchId > 0)
          .toList();

      final catalogById = {
        for (final item in catalog) item.itemId: item,
      };
      final batchesById = {
        for (final batch in batches) batch.batchId: batch,
      };

      final transactions = _rows(results[2]).map((json) {
        final batchId = _nullableInt(json['batch_id']);
        final batch = batchId == null ? null : batchesById[batchId];
        final item = batch == null ? null : catalogById[batch.itemId];
        return InventoryTransactionRecord.fromJson(
          json,
          batch: batch,
          item: item,
        );
      }).toList();

      var workflowAvailable = !_workflowRpcUnavailable;
      String? workflowMessage;
      List<InventoryStockRequestRecord> requests = const [];
      List<InventoryTransferRecord> transfers = const [];

      if (workflowAvailable) {
        try {
          final workflowResults = await Future.wait<dynamic>([
            _client
                .from('inventory_stock_requests')
                .select('*')
                .eq('facility_id', context.facilityId)
                .order('created_at', ascending: false),
            _client
                .from('inventory_transfers')
                .select('*')
                .eq('destination_facility_id', context.facilityId)
                .order('issued_at', ascending: false),
          ]);

          requests = _rows(workflowResults[0])
              .map(InventoryStockRequestRecord.fromJson)
              .toList();

          final transferRows = _rows(workflowResults[1]);
          final sourceBatchIds = transferRows
              .map((row) => _nullableInt(row['source_batch_id']))
              .whereType<int>()
              .toSet()
              .toList();
          final sourceBatches = <int, InventoryBatchRecord>{};
          if (sourceBatchIds.isNotEmpty) {
            final sourceRows = await _client
                .from('inventory_batches')
                .select(
                  'batch_id, item_id, facility_id, batch_number, '
                  'quantity_received, quantity_remaining, received_date, '
                  'expiration_date, manufacturer, status',
                )
                .inFilter('batch_id', sourceBatchIds);
            for (final row in _rows(sourceRows)) {
              final batch = InventoryBatchRecord.fromJson(row);
              sourceBatches[batch.batchId] = batch;
            }
          }

          transfers = transferRows
              .map(
                (json) => InventoryTransferRecord.fromJson(
                  json,
                  sourceBatch:
                      sourceBatches[_nullableInt(json['source_batch_id'])],
                ),
              )
              .toList();
        } catch (error) {
          workflowAvailable = false;
          workflowMessage = _isMissingWorkflow(error)
              ? 'The inventory request and receipt migration has not been '
                  'installed in Supabase yet.'
              : 'The request and receipt workflow could not be loaded.';
        }
      } else {
        workflowMessage = 'The inventory workflow RPCs are not available.';
      }

      final batchesByItem = <int, List<InventoryBatchRecord>>{};
      for (final batch in batches) {
        batchesByItem.putIfAbsent(batch.itemId, () => []).add(batch);
      }
      final inventory = catalog
          .map(
            (item) => FacilityInventoryRecord(
              catalog: item,
              batches:
                  List.unmodifiable(batchesByItem[item.itemId] ?? const []),
            ),
          )
          .toList();

      return InventorySnapshot(
        context: context,
        inventory: inventory,
        requests: requests,
        transfers: transfers,
        transactions: transactions,
        workflowAvailable: workflowAvailable,
        workflowMessage: workflowMessage,
        loadedAt: DateTime.now(),
      );
    } catch (error) {
      throw InventoryRepositoryException(
        _friendlyError(error),
        cause: error,
      );
    }
  }

  Future<InventoryStockRequestRecord> submitStockRequest({
    required MidwifeInventoryContext context,
    required int itemId,
    required int quantity,
    required String reason,
    String? remarks,
  }) async {
    if (_workflowRpcUnavailable) {
      throw const InventoryWorkflowUnavailableException(
        'Install the inventory workflow migration before submitting requests.',
      );
    }

    try {
      final response = await _client.rpc(
        'submit_inventory_stock_request',
        params: {
          'p_requested_by': context.accountId,
          'p_item_id': itemId,
          'p_requested_quantity': quantity,
          'p_reason': reason.trim(),
          'p_remarks': (remarks == null || remarks.trim().isEmpty)
              ? null
              : remarks.trim(),
        },
      );
      final row = _singleRow(response);
      if (row == null) {
        throw const InventoryRepositoryException(
          'Supabase did not return the submitted stock request.',
        );
      }
      return InventoryStockRequestRecord.fromJson(row);
    } catch (error) {
      if (_isMissingWorkflow(error)) {
        _workflowRpcUnavailable = true;
        throw InventoryWorkflowUnavailableException(
          'The stock request RPC is not installed in Supabase yet.',
          cause: error,
        );
      }
      if (error is InventoryRepositoryException) rethrow;
      throw InventoryRepositoryException(
        _friendlyError(error),
        cause: error,
      );
    }
  }

  Future<InventoryTransferRecord> receiveTransfer({
    required MidwifeInventoryContext context,
    required int transferId,
  }) async {
    if (_workflowRpcUnavailable) {
      throw const InventoryWorkflowUnavailableException(
        'Install the inventory workflow migration before receiving stock.',
      );
    }

    try {
      final response = await _client.rpc(
        'receive_inventory_transfer',
        params: {
          'p_transfer_id': transferId,
          'p_received_by': context.accountId,
        },
      );
      final row = _singleRow(response);
      if (row == null) {
        throw const InventoryRepositoryException(
          'Supabase did not return the received transfer.',
        );
      }
      return InventoryTransferRecord.fromJson(row);
    } catch (error) {
      if (_isMissingWorkflow(error)) {
        _workflowRpcUnavailable = true;
        throw InventoryWorkflowUnavailableException(
          'The stock receipt RPC is not installed in Supabase yet.',
          cause: error,
        );
      }
      if (error is InventoryRepositoryException) rethrow;
      throw InventoryRepositoryException(
        _friendlyError(error),
        cause: error,
      );
    }
  }

  Future<InventoryStockActivityResult> recordStockActivity({
    required MidwifeInventoryContext context,
    required int batchId,
    required InventoryStockActivityType activityType,
    required int quantity,
    required String reason,
    required String operationKey,
    String? notes,
  }) async {
    if (quantity <= 0) {
      throw const InventoryRepositoryException(
        'Quantity must be a positive whole number.',
      );
    }

    try {
      final response = await _client.rpc(
        'record_midwife_inventory_activity',
        params: {
          'p_performed_by': context.accountId,
          'p_batch_id': batchId,
          'p_activity_type': switch (activityType) {
            InventoryStockActivityType.dispense => 'dispense',
            InventoryStockActivityType.unusable => 'unusable',
          },
          'p_quantity': quantity,
          'p_reason': reason.trim(),
          'p_operation_key': operationKey.trim(),
          'p_notes':
              (notes == null || notes.trim().isEmpty) ? null : notes.trim(),
        },
      );
      final row = _singleRow(response);
      if (row == null) {
        throw const InventoryRepositoryException(
          'Supabase did not return the recorded stock activity.',
        );
      }
      return InventoryStockActivityResult.fromJson(row);
    } catch (error) {
      if (_isMissingWorkflow(error)) {
        throw InventoryWorkflowUnavailableException(
          'Install the midwife dispensing and expiry-report migration in '
          'Supabase before recording stock activity.',
          cause: error,
        );
      }
      if (error is InventoryRepositoryException) rethrow;
      throw InventoryRepositoryException(
        _friendlyError(error),
        cause: error,
      );
    }
  }

  Future<List<InventoryNotificationRecord>> loadInventoryNotifications({
    required MidwifeInventoryContext context,
    int limit = 40,
  }) async {
    try {
      final response = await _client
          .from('notifications')
          .select(
            'notification_id, account_id, title, message, is_read, created_at',
          )
          .eq('account_id', context.accountId)
          .order('created_at', ascending: false)
          .limit(limit);

      return _rows(response)
          .map(InventoryNotificationRecord.tryFromJson)
          .whereType<InventoryNotificationRecord>()
          .toList();
    } catch (error) {
      throw InventoryRepositoryException(
        _friendlyError(error),
        cause: error,
      );
    }
  }

  Future<void> markInventoryNotificationsRead(
    Iterable<int> notificationIds,
  ) async {
    final ids = notificationIds.where((id) => id > 0).toSet().toList();
    if (ids.isEmpty) return;

    try {
      await _client
          .from('notifications')
          .update({'is_read': true}).inFilter('notification_id', ids);
    } catch (error) {
      throw InventoryRepositoryException(
        _friendlyError(error),
        cause: error,
      );
    }
  }

  RealtimeChannel subscribeToInventoryNotifications({
    required MidwifeInventoryContext context,
    required void Function(InventoryNotificationRecord notification)
        onNotification,
    void Function(bool connected)? onConnectionChanged,
  }) {
    return _client
        .channel('inventory-notifications-${context.accountId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'account_id',
            value: context.accountId,
          ),
          callback: (payload) {
            final notification =
                InventoryNotificationRecord.tryFromJson(payload.newRecord);
            if (notification != null) onNotification(notification);
          },
        )
        .subscribe((status, _) {
      onConnectionChanged?.call(
        status == RealtimeSubscribeStatus.subscribed,
      );
    });
  }

  RealtimeChannel subscribeToFacilityInventory({
    required MidwifeInventoryContext context,
    required void Function() onInventoryChanged,
    void Function(bool connected)? onConnectionChanged,
  }) {
    return _client
        .channel('facility-inventory-${context.facilityId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          // This feed contains only a table name, operation and timestamp. It
          // avoids publishing raw stock rows through Realtime; the app reloads
          // its normal facility-filtered queries after a relevant signal.
          table: 'admin_change_events',
          callback: (payload) {
            final tableName = payload.newRecord['table_name']?.toString();
            if (const {
              'inventory_items',
              'inventory_batches',
              'inventory_transactions',
              'inventory_stock_requests',
              'inventory_transfers',
              'inventory_unusable_stock_reports',
            }.contains(tableName)) {
              onInventoryChanged();
            }
          },
        )
        .subscribe((status, _) {
      onConnectionChanged?.call(
        status == RealtimeSubscribeStatus.subscribed,
      );
    });
  }

  Future<void> removeRealtimeChannel(RealtimeChannel channel) async {
    try {
      await _client.removeChannel(channel);
    } catch (_) {
      // A closing screen should not surface channel teardown errors.
    }
  }

  static List<Map<String, dynamic>> _rows(Object? response) {
    if (response is List) {
      return response
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    }
    return const [];
  }

  static Map<String, dynamic>? _singleRow(Object? response) {
    if (response is Map) return Map<String, dynamic>.from(response);
    final rows = _rows(response);
    return rows.isEmpty ? null : rows.first;
  }

  static int? _nullableInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static bool _isMissingWorkflow(Object error) {
    final text = error.toString().toLowerCase();
    final code =
        error is PostgrestException ? (error.code ?? '').toLowerCase() : '';
    return code == 'pgrst202' ||
        code == 'pgrst205' ||
        code == '42p01' ||
        code == '42883' ||
        text.contains('schema cache') ||
        text.contains('could not find the table') ||
        text.contains('could not find the function') ||
        text.contains('does not exist');
  }

  static String _friendlyError(Object error) {
    final text = error.toString();
    final lower = text.toLowerCase();
    if (lower.contains('socketexception') ||
        lower.contains('clientexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('network')) {
      return 'Unable to reach the inventory database. Check your internet '
          'connection and try again.';
    }
    if (error is PostgrestException && error.message.trim().isNotEmpty) {
      return error.message;
    }
    return 'Unable to synchronize inventory data. Please try again.';
  }
}
