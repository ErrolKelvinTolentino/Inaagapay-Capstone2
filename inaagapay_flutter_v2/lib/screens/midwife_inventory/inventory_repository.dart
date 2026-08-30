import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_storage.dart';
import 'inventory_models.dart';

/// Live inventory access for the midwife app.
///
/// It uses the app's own Supabase client. It used to construct a second one
/// from a URL and anon key written into this file, aimed at whichever project
/// those constants named — so the stock this screen showed and the stock a
/// clinical screen deducted from were not guaranteed to be the same shelf.
/// Both now come from .env, resolved once in main.dart.
class InventoryRepository {
  InventoryRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  bool _workflowRpcUnavailable = false;

  /// The signed-in midwife and the health centre whose shelf she works from.
  ///
  /// There used to be a fallback to a fixed demo account here, taken whenever
  /// the saved session did not resolve. It kept the screen usable, but every
  /// dispense, write-off and request made from that state was recorded against
  /// Pinagbarilan BHC and attributed to account #9 — real stock movements
  /// posted to the wrong health centre under the wrong name. An error the
  /// midwife can read is the only honest outcome when the session is unknown.
  Future<MidwifeInventoryContext> resolveContext() async {
    final savedAccountId = await AuthStorage.getUserId();
    final savedRole = await AuthStorage.getUserRole();
    final savedToken = await AuthStorage.getToken();

    if (savedAccountId == null ||
        savedRole?.toLowerCase() != 'midwife' ||
        savedToken == null ||
        savedToken.isEmpty) {
      throw const InventoryRepositoryException(
        'Sign in with your midwife account to open the health center '
        'inventory.',
      );
    }

    return _contextForAccount(accountId: savedAccountId);
  }

  /// Resolves the signed-in midwife's shelf, or says precisely what is missing.
  ///
  /// This used to return null for five unrelated reasons and the caller printed
  /// one sentence for all of them: "not assigned to a barangay health center".
  /// A superseded login token and a missing midwife row both read as a posting
  /// problem, so the RHU was asked to fix an assignment that was already
  /// correct. Each cause now names itself.
  Future<MidwifeInventoryContext> _contextForAccount({
    required int accountId,
  }) async {
    final account = await _client
        .from('accounts')
        .select('account_id, account_type, status, first_name, last_name')
        .eq('account_id', accountId)
        .maybeSingle();

    if (account == null) {
      throw InventoryRepositoryException(
        'This device is signed in as account #$accountId, which is no longer '
        'in the system. Sign out and sign in again.',
      );
    }

    if (account['account_type']?.toString().toLowerCase() != 'midwife') {
      throw const InventoryRepositoryException(
        'The health center inventory is for midwife accounts. This account is '
        'signed in with a different role.',
      );
    }

    if (account['status']?.toString().toLowerCase() != 'active') {
      throw InventoryRepositoryException(
        'This midwife account is '
        '${account['status']?.toString().toLowerCase() ?? 'inactive'}, so its '
        'stock is not available. Ask the RHU to reactivate it.',
      );
    }

    // There was a session check here: reject the device unless its saved token
    // equalled accounts.last_login_token. It was removed because that column
    // cannot be written, so the check had no true positives — only lockouts.
    //
    // Sign-in is a custom lookup against the accounts table; the app never
    // calls signInWithPassword, so there is no Supabase Auth session and
    // auth.uid() is null. The policy governing the write is
    //
    //   CREATE POLICY "Users can update own account" ON public.accounts
    //   FOR UPDATE USING (auth_id = auth.uid());
    //
    // which therefore matches no row. SupabaseService.login still generates a
    // token, still hands it to the device, and still reports success — the
    // UPDATE simply affects nothing and raises nothing. On this database the
    // column is null for four of six midwives and holds a legacy value for the
    // rest, so every midwife was refused her own health centre's stock.
    //
    // Reinstating this needs the token to be written first — a SECURITY DEFINER
    // RPC at login, or an UPDATE policy that does not depend on auth.uid() —
    // and until then it is a check in name only. What still gates the screen is
    // the account itself: it must exist, be a midwife, and be active.

    final midwife = await _client
        .from('midwives')
        .select('midwife_id, assigned_bhc_id')
        .eq('account_id', accountId)
        .maybeSingle();

    if (midwife == null) {
      throw const InventoryRepositoryException(
        'This account has no midwife record, so there is no health center to '
        'draw stock from. Ask the RHU to complete the midwife profile.',
      );
    }

    // The posting on the midwife row is authoritative — it is what the admin
    // portal writes. facility_assignments is the older home for the same fact
    // and is still the only place some accounts carry it, so it is read as a
    // fallback exactly as SupabaseService.getMidwifeContext does.
    //
    // What is deliberately NOT copied from there is that method's last resort:
    // defaulting to the first BHC in the table. A guess is survivable when it
    // only labels a screen; here every dispense, write-off and stock request
    // would post to a health centre the midwife does not work at.
    var facilityId = _nullableInt(midwife['assigned_bhc_id']);
    facilityId ??= await _postingFromAssignments(accountId);

    if (facilityId == null) {
      throw const InventoryRepositoryException(
        'This account is not assigned to a barangay health center yet, so it '
        'has no stock to show. Ask the RHU to set the assignment.',
      );
    }

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
      midwifeId: _nullableInt(midwife['midwife_id']) ?? accountId,
      facilityId: facilityId,
      facilityName: facilityName,
      displayName: fullName.isEmpty ? 'Midwife' : fullName,
      isDemo: false,
      supplierName: supplierName,
    );
  }

  /// The most recent active posting on `facility_assignments`.
  ///
  /// Ordered and limited rather than `maybeSingle()`: an account with more than
  /// one active row makes that throw a 406, and accounts with several rows are
  /// exactly the ones this fallback exists for. A database without the table at
  /// all simply has no fallback, which the caller reports as an unset posting.
  Future<int?> _postingFromAssignments(int accountId) async {
    try {
      final rows = await _client
          .from('facility_assignments')
          .select('facility_id, assigned_at')
          .eq('account_id', accountId)
          .eq('is_active', true)
          .order('assigned_at', ascending: false)
          .limit(1);

      final list = rows as List<dynamic>;
      if (list.isEmpty) return null;
      return _nullableInt((list.first as Map)['facility_id']);
    } catch (_) {
      return null;
    }
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
        _loadDoseLedger(context.facilityId),
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
          // Transfers where this facility is EITHER end.
          //
          // This used to filter on destination_facility_id alone, which was
          // right while a health centre could only ever receive. It cannot any
          // more: a centre sends stock sideways to a neighbour that has run
          // out, and upward to the RHU when a brownout means it cannot keep the
          // cold chain. Those units were debited from this shelf the moment the
          // transfer was issued, so filtering them out made the count drop with
          // nothing on the screen to explain where they had gone.
          final workflowResults = await Future.wait<dynamic>([
            _client
                .from('inventory_stock_requests')
                .select('*')
                .eq('facility_id', context.facilityId)
                .order('created_at', ascending: false),
            _client
                .from('inventory_transfers')
                .select('*')
                .or(
                  'destination_facility_id.eq.${context.facilityId},'
                  'source_facility_id.eq.${context.facilityId}',
                )
                .order('issued_at', ascending: false),
          ]);

          requests = _rows(workflowResults[0])
              .map(InventoryStockRequestRecord.fromJson)
              .toList();

          final transferRows = _rows(workflowResults[1]);
          transfers = await _hydrateTransfers(transferRows);
        } on Object catch (error) {
          // source_facility_id arrives with 20260829. On a database without it
          // the OR filter above is rejected outright, so fall back to the
          // destination-only query rather than losing the whole workflow — the
          // portal and the migrations deploy separately, and the app has to
          // work either side of that gap.
          if (_isMissingSourceFacilityColumn(error)) {
            try {
              final legacy = await Future.wait<dynamic>([
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
              requests = _rows(legacy[0])
                  .map(InventoryStockRequestRecord.fromJson)
                  .toList();
              transfers = await _hydrateTransfers(_rows(legacy[1]));
            } catch (_) {
              workflowAvailable = false;
              workflowMessage =
                  'The request and receipt workflow could not be loaded.';
            }
          } else {
            workflowAvailable = false;
            workflowMessage = _isMissingWorkflow(error)
                ? 'The inventory request and receipt migration has not been '
                    'installed in Supabase yet.'
                : 'The request and receipt workflow could not be loaded.';
          }
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
            // `type` is what makes a row an inventory notification at all.
            // It was documented as the durable signal and then never selected,
            // so classification fell back to matching four English titles.
            'notification_id, account_id, title, message, type, is_read, '
            'created_at',
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

  /// Set once `inventory_dose_ledger` has been found missing, so the fallback
  /// query is used directly on every later refresh instead of paying for a
  /// rejected request first.
  bool _doseLedgerUnavailable = false;

  /// Discards whatever doses are left in a batch's open vial.
  ///
  /// The BHC is who holds the vial and who watches the shelf-life clock run
  /// out, but until now `discard_open_vial_doses` was only ever called from the
  /// admin portal — so a midwife could watch the app say EXPIRED and had no way
  /// to act on it except to telephone the RHU. The RPC is facility-agnostic and
  /// writes its own ledger and audit rows, so calling it from here needs no new
  /// server work.
  ///
  /// Returns the RPC's payload. Throws [InventoryWorkflowUnavailableException]
  /// on a database without the function, which the caller reports rather than
  /// swallowing — silently doing nothing to a vial is worse than saying so.
  Future<Map<String, dynamic>> discardOpenVialDoses({
    required MidwifeInventoryContext context,
    required int batchId,
    required String reason,
  }) async {
    try {
      final response = await _client.rpc(
        'discard_open_vial_doses',
        params: {
          'p_batch_id': batchId,
          'p_discarded_by': context.midwifeId,
          'p_reason': reason,
        },
      );

      final row = response is Map
          ? Map<String, dynamic>.from(response)
          : _singleRow(response);

      if (row == null) {
        throw const InventoryRepositoryException(
          'Supabase did not return a result for the discard.',
        );
      }

      // The RPC reports refusals in its payload rather than by raising, so a
      // false here is a real failure and must not read as success.
      if (row['success'] == false) {
        final reported = row['error']?.toString().trim() ?? '';
        throw InventoryRepositoryException(
          reported.isEmpty
              ? 'The open vial could not be discarded.'
              : reported,
        );
      }

      return row;
    } on Object catch (error) {
      if (error is InventoryRepositoryException) rethrow;
      if (_isMissingWorkflow(error)) {
        throw InventoryWorkflowUnavailableException(
          'The open-vial discard function is not installed in Supabase yet.',
          cause: error,
        );
      }
      throw InventoryRepositoryException(_friendlyError(error), cause: error);
    }
  }

  /// The BHC's stock movements, with the dose maths, the performing account and
  /// the receiving patient already resolved.
  ///
  /// Reads `inventory_dose_ledger` (20260830_dose_traceability.sql). That view
  /// is what turns an opaque "Child Immunization #57" into a named child and a
  /// dose count, and resolving it client-side instead would be one round trip
  /// per row on a screen that lists a hundred.
  ///
  /// A database without the migration simply has no such view, so this falls
  /// back to the base table: the timeline still renders, minus the patient and
  /// the post-movement dose level. The portal and the migrations deploy
  /// separately and the app has to work either side of that gap.
  Future<List<Map<String, dynamic>>> _loadDoseLedger(int facilityId) async {
    if (!_doseLedgerUnavailable) {
      try {
        final response = await _client
            .from('inventory_dose_ledger')
            .select()
            .eq('facility_id', facilityId)
            .order('logged_at', ascending: false)
            .limit(300);
        return _rows(response);
      } on Object catch (error) {
        if (!_isMissingWorkflow(error)) rethrow;
        _doseLedgerUnavailable = true;
      }
    }

    final legacy = await _client
        .from('inventory_transactions')
        .select(
          'transaction_id, batch_id, facility_id, transaction_type, '
          'quantity, reference_type, reference_id, logged_at, '
          'inventory_batches(batch_id, item_id, batch_number, '
          'inventory_items(item_id, name, unit_of_measure))',
        )
        .eq('facility_id', facilityId)
        .order('logged_at', ascending: false)
        .limit(300);
    return _rows(legacy);
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

  /// The database has not run 20260829 yet, so inventory_transfers has no
  /// source_facility_id and the outbound half of the OR filter is rejected.
  /// Narrower than [_isMissingWorkflow] on purpose: a genuinely broken
  /// workflow must not be mistaken for an un-migrated one and silently retried.
  static bool _isMissingSourceFacilityColumn(Object error) {
    final text = error.toString().toLowerCase();
    if (!text.contains('source_facility_id')) return false;
    final code =
        error is PostgrestException ? (error.code ?? '').toLowerCase() : '';
    return code == '42703' ||
        code == 'pgrst100' ||
        code == 'pgrst204' ||
        text.contains('does not exist') ||
        text.contains('unexpected') ||
        text.contains('schema cache');
  }

  /// Turn raw inventory_transfers rows into records, resolving the source batch
  /// (for the item and batch number) and naming both facilities.
  ///
  /// Naming both ends is new and is the point of the change: a transfer this
  /// facility SENT is meaningless without the name of where it went, and until
  /// now the app never had to render one.
  Future<List<InventoryTransferRecord>> _hydrateTransfers(
    List<Map<String, dynamic>> transferRows,
  ) async {
    if (transferRows.isEmpty) return const [];

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

    final facilityIds = <int>{};
    for (final row in transferRows) {
      final source = _nullableInt(row['source_facility_id']) ??
          sourceBatches[_nullableInt(row['source_batch_id'])]?.facilityId;
      final target = _nullableInt(row['destination_facility_id']);
      if (source != null) facilityIds.add(source);
      if (target != null) facilityIds.add(target);
    }

    final facilityNames = <int, String>{};
    if (facilityIds.isNotEmpty) {
      try {
        final facilityRows = await _client
            .from('health_facilities')
            .select('facility_id, name')
            .inFilter('facility_id', facilityIds.toList());
        for (final row in _rows(facilityRows)) {
          final id = _nullableInt(row['facility_id']);
          if (id != null) {
            facilityNames[id] = (row['name'] ?? '').toString();
          }
        }
      } catch (_) {
        // Names are decoration; a transfer without them still renders with the
        // quantity, the batch and the direction, which is what has to be right.
      }
    }

    return transferRows.map((json) {
      final record = InventoryTransferRecord.fromJson(
        json,
        sourceBatch: sourceBatches[_nullableInt(json['source_batch_id'])],
      );
      return record.copyWithFacilityNames(
        // A NULL source facility is the municipal warehouse, which is a real
        // place but has no health_facilities row of its own here.
        sourceName: record.sourceFacilityId == null
            ? 'Municipal Warehouse'
            : facilityNames[record.sourceFacilityId!],
        targetName: facilityNames[record.targetFacilityId],
      );
    }).toList();
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
