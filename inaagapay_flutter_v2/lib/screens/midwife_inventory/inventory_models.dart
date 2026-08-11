// Database-facing models for the midwife inventory presentation branch.
// These contain no Flutter UI types so the repository can be tested separately.

int _asInt(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

String _asString(Object? value, {String fallback = ''}) {
  final result = value?.toString().trim() ?? '';
  return result.isEmpty ? fallback : result;
}

DateTime? _asDate(Object? value) {
  if (value is DateTime) {
    return DateTime(value.year, value.month, value.day);
  }
  final text = value?.toString();
  final parsed = text == null || text.isEmpty ? null : DateTime.tryParse(text);
  return parsed == null
      ? null
      : DateTime(parsed.year, parsed.month, parsed.day);
}

DateTime? _asTimestamp(Object? value) {
  if (value is DateTime) return value.isUtc ? value.toLocal() : value;
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;

  final hasExplicitZone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(text);
  if (hasExplicitZone) return parsed.toLocal();

  // Supabase stores several audit timestamps as UTC in timestamp-without-zone
  // columns. Treat a zone-less value as UTC before formatting on the device.
  return DateTime.utc(
    parsed.year,
    parsed.month,
    parsed.day,
    parsed.hour,
    parsed.minute,
    parsed.second,
    parsed.millisecond,
    parsed.microsecond,
  ).toLocal();
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is List && value.isNotEmpty) return _asMap(value.first);
  return null;
}

class MidwifeInventoryContext {
  const MidwifeInventoryContext({
    required this.accountId,
    required this.midwifeId,
    required this.facilityId,
    required this.facilityName,
    required this.displayName,
    required this.isDemo,
  });

  final int accountId;
  final int midwifeId;
  final int facilityId;
  final String facilityName;
  final String displayName;
  final bool isDemo;
}

class InventoryCatalogRecord {
  const InventoryCatalogRecord({
    required this.itemId,
    required this.name,
    required this.genericName,
    required this.itemCode,
    required this.strengthDescription,
    required this.dosageForm,
    required this.itemType,
    required this.unit,
    required this.minimumStock,
    this.isArchived = false,
  });

  factory InventoryCatalogRecord.fromJson(Map<String, dynamic> json) {
    return InventoryCatalogRecord(
      itemId: _asInt(json['item_id']),
      name: _asString(json['name'], fallback: 'Inventory item'),
      genericName: _asString(json['generic_name']),
      itemCode: _asString(json['item_code']),
      strengthDescription: _asString(json['strength_description']),
      dosageForm: _asString(json['dosage_form']),
      itemType: _asString(json['item_type'], fallback: 'other'),
      unit: _asString(json['unit_of_measure'], fallback: 'units'),
      minimumStock: _asInt(json['minimum_stock_threshold'], fallback: 50),
      isArchived: json['is_archived'] == true,
    );
  }

  final int itemId;
  final String name;
  final String genericName;
  final String itemCode;
  final String strengthDescription;
  final String dosageForm;
  final String itemType;
  final String unit;
  final int minimumStock;
  final bool isArchived;
}

class InventoryBatchRecord {
  const InventoryBatchRecord({
    required this.batchId,
    required this.itemId,
    required this.facilityId,
    required this.batchNumber,
    required this.quantityReceived,
    required this.quantityRemaining,
    required this.receivedDate,
    required this.expirationDate,
    required this.manufacturer,
    required this.status,
  });

  factory InventoryBatchRecord.fromJson(Map<String, dynamic> json) {
    return InventoryBatchRecord(
      batchId: _asInt(json['batch_id']),
      itemId: _asInt(json['item_id']),
      facilityId:
          json['facility_id'] == null ? null : _asInt(json['facility_id']),
      batchNumber: _asString(json['batch_number'], fallback: 'Unspecified'),
      quantityReceived: _asInt(json['quantity_received']),
      quantityRemaining: _asInt(json['quantity_remaining']),
      receivedDate: _asDate(json['received_date']),
      expirationDate: _asDate(json['expiration_date']),
      manufacturer: _asString(json['manufacturer']),
      status: _asString(json['status'], fallback: 'unknown'),
    );
  }

  final int batchId;
  final int itemId;
  final int? facilityId;
  final String batchNumber;
  final int quantityReceived;
  final int quantityRemaining;
  final DateTime? receivedDate;
  final DateTime? expirationDate;
  final String manufacturer;
  final String status;

  bool get isActive => status.toLowerCase() == 'active';

  DateTime? get expirationDay {
    final value = expirationDate;
    if (value == null) return null;
    return DateTime(value.year, value.month, value.day);
  }

  int? daysUntilExpiration([DateTime? from]) {
    final expiration = expirationDay;
    if (expiration == null) return null;
    final source = from ?? DateTime.now();
    final today = DateTime(source.year, source.month, source.day);
    return expiration.difference(today).inDays;
  }

  bool isExpiredOn([DateTime? day]) {
    final remainingDays = daysUntilExpiration(day);
    // Match the admin portal: stock dated today is already treated as expired.
    return remainingDays != null && remainingDays <= 0;
  }

  bool isExpiringWithin(int days, [DateTime? from]) {
    final remainingDays = daysUntilExpiration(from);
    return remainingDays != null && remainingDays > 0 && remainingDays <= days;
  }

  bool isUsableOn([DateTime? day]) {
    return isActive && quantityRemaining > 0 && !isExpiredOn(day);
  }
}

class FacilityInventoryRecord {
  const FacilityInventoryRecord({
    required this.catalog,
    required this.batches,
  });

  final InventoryCatalogRecord catalog;
  final List<InventoryBatchRecord> batches;

  int quantityOn([DateTime? day]) => batches
      .where((batch) => batch.isUsableOn(day))
      .fold(0, (total, batch) => total + batch.quantityRemaining);

  int get quantity => quantityOn();

  int expiredQuantityOn([DateTime? day]) => batches
      .where(
        (batch) =>
            batch.quantityRemaining > 0 &&
            (batch.isExpiredOn(day) || batch.status.toLowerCase() == 'expired'),
      )
      .fold(0, (total, batch) => total + batch.quantityRemaining);

  int expiringQuantityOn(int days, [DateTime? from]) => batches
      .where((batch) =>
          batch.isUsableOn(from) && batch.isExpiringWithin(days, from))
      .fold(0, (total, batch) => total + batch.quantityRemaining);

  List<InventoryBatchRecord> usableBatchesOn([DateTime? day]) {
    final result = batches.where((batch) => batch.isUsableOn(day)).toList();
    result.sort((first, second) {
      final firstExpiry = first.expirationDay;
      final secondExpiry = second.expirationDay;
      if (firstExpiry == null && secondExpiry == null) {
        return first.batchNumber.compareTo(second.batchNumber);
      }
      if (firstExpiry == null) return 1;
      if (secondExpiry == null) return -1;
      final expiryOrder = firstExpiry.compareTo(secondExpiry);
      return expiryOrder != 0
          ? expiryOrder
          : first.batchNumber.compareTo(second.batchNumber);
    });
    return result;
  }

  InventoryBatchRecord? get nextUsableBatch {
    final usable = usableBatchesOn();
    return usable.isEmpty ? null : usable.first;
  }

  String get batchLabel {
    final usable = usableBatchesOn();
    if (usable.isEmpty) return 'No usable batch';
    if (usable.length == 1) return usable.first.batchNumber;
    return '${usable.first.batchNumber} +${usable.length - 1} more';
  }
}

enum InventoryStockActivityType { dispense, unusable }

class InventoryStockActivityResult {
  const InventoryStockActivityResult({
    required this.transactionId,
    required this.batchId,
    required this.quantityChanged,
    required this.quantityRemaining,
    required this.batchStatus,
    required this.loggedAt,
    required this.reportId,
  });

  factory InventoryStockActivityResult.fromJson(Map<String, dynamic> json) {
    return InventoryStockActivityResult(
      transactionId: _asInt(json['transaction_id']),
      batchId: _asInt(json['batch_id']),
      quantityChanged: _asInt(json['quantity_changed'] ?? json['quantity']),
      quantityRemaining: _asInt(json['quantity_remaining']),
      batchStatus: _asString(json['batch_status'], fallback: 'active'),
      loggedAt: _asTimestamp(json['logged_at']) ?? DateTime.now(),
      reportId: json['report_id'] == null ? null : _asInt(json['report_id']),
    );
  }

  final int transactionId;
  final int batchId;
  final int quantityChanged;
  final int quantityRemaining;
  final String batchStatus;
  final DateTime loggedAt;
  final int? reportId;
}

class InventoryStockRequestRecord {
  const InventoryStockRequestRecord({
    required this.requestId,
    required this.facilityId,
    required this.itemId,
    required this.quantity,
    required this.reason,
    required this.remarks,
    required this.adminRemarks,
    required this.status,
    required this.requestedAt,
    required this.completedAt,
  });

  factory InventoryStockRequestRecord.fromJson(Map<String, dynamic> json) {
    final status = _asString(json['status'], fallback: 'pending');
    final normalizedStatus = status.toLowerCase();
    final isTerminal = <String>{
      'received',
      'completed',
      'rejected',
      'cancelled',
    }.contains(normalizedStatus);

    return InventoryStockRequestRecord(
      requestId: _asInt(json['request_id'] ?? json['stock_request_id']),
      facilityId: _asInt(
        json['facility_id'] ?? json['requesting_facility_id'],
      ),
      itemId: _asInt(json['item_id']),
      quantity: _asInt(
        json['requested_quantity'] ??
            json['quantity_requested'] ??
            json['quantity'],
      ),
      reason: _asString(json['reason'], fallback: 'Stock replenishment'),
      remarks: _asString(json['remarks']),
      adminRemarks: _asString(json['admin_remarks']),
      status: status,
      requestedAt: _asTimestamp(
            json['requested_at'] ?? json['submitted_at'] ?? json['created_at'],
          ) ??
          DateTime.now(),
      completedAt: _asTimestamp(
        json['completed_at'] ??
            json['received_at'] ??
            (isTerminal ? json['updated_at'] : null),
      ),
    );
  }

  final int requestId;
  final int facilityId;
  final int itemId;
  final int quantity;
  final String reason;
  final String remarks;
  final String adminRemarks;
  final String status;
  final DateTime requestedAt;
  final DateTime? completedAt;
}

enum InventoryNotificationKind { approved, rejected, issued, lowStock }

class InventoryNotificationRecord {
  const InventoryNotificationRecord({
    required this.notificationId,
    required this.accountId,
    required this.title,
    required this.message,
    required this.kind,
    required this.isRead,
    required this.createdAt,
  });

  static InventoryNotificationRecord? tryFromJson(
    Map<String, dynamic> json,
  ) {
    final title = _asString(json['title']);
    final message = _asString(json['message']);
    final normalizedTitle = title.toLowerCase();
    final normalizedMessage = message.toLowerCase();

    final InventoryNotificationKind? kind;
    if (normalizedTitle == 'stock request approved') {
      kind = InventoryNotificationKind.approved;
    } else if (normalizedTitle == 'incoming stocks from rhu main') {
      kind = InventoryNotificationKind.issued;
    } else if (normalizedTitle == 'stock request update' &&
        normalizedMessage.contains('not approved')) {
      kind = InventoryNotificationKind.rejected;
    } else if (normalizedTitle == 'low stock after activity') {
      kind = InventoryNotificationKind.lowStock;
    } else {
      kind = null;
    }

    if (kind == null) return null;

    return InventoryNotificationRecord(
      notificationId: _asInt(json['notification_id']),
      accountId: _asInt(json['account_id']),
      title: title,
      message: message,
      kind: kind,
      isRead: json['is_read'] == true,
      createdAt: _asTimestamp(json['created_at']) ?? DateTime.now(),
    );
  }

  final int notificationId;
  final int accountId;
  final String title;
  final String message;
  final InventoryNotificationKind kind;
  final bool isRead;
  final DateTime createdAt;

  String get displayTitle => switch (kind) {
        InventoryNotificationKind.approved => 'Stock request approved',
        InventoryNotificationKind.rejected => 'Stock request rejected',
        InventoryNotificationKind.issued => 'Stocks issued by RHU Main',
        InventoryNotificationKind.lowStock => 'BHC stock is now low',
      };

  InventoryNotificationRecord copyWith({bool? isRead}) {
    return InventoryNotificationRecord(
      notificationId: notificationId,
      accountId: accountId,
      title: title,
      message: message,
      kind: kind,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
    );
  }
}

class InventoryTransferRecord {
  const InventoryTransferRecord({
    required this.transferId,
    required this.requestId,
    required this.sourceBatchId,
    required this.targetFacilityId,
    required this.itemId,
    required this.batchNumber,
    required this.quantityIssued,
    required this.quantityReceived,
    required this.status,
    required this.remarks,
    required this.issuedAt,
    required this.receivedAt,
    required this.issuedByName,
  });

  factory InventoryTransferRecord.fromJson(
    Map<String, dynamic> json, {
    InventoryBatchRecord? sourceBatch,
  }) {
    final nestedBatch = _asMap(
      json['source_batch'] ?? json['inventory_batches'],
    );
    return InventoryTransferRecord(
      transferId: _asInt(json['transfer_id']),
      requestId: json['request_id'] == null ? null : _asInt(json['request_id']),
      sourceBatchId: _asInt(
        json['source_batch_id'] ?? json['batch_id'],
      ),
      targetFacilityId: _asInt(
        json['destination_facility_id'] ??
            json['target_facility_id'] ??
            json['facility_id'],
      ),
      itemId: _asInt(
        json['item_id'] ?? nestedBatch?['item_id'] ?? sourceBatch?.itemId,
      ),
      batchNumber: _asString(
        json['batch_number'] ??
            nestedBatch?['batch_number'] ??
            sourceBatch?.batchNumber,
        fallback: 'Unspecified',
      ),
      quantityIssued: _asInt(
        json['quantity_issued'] ?? json['issued_quantity'] ?? json['quantity'],
      ),
      quantityReceived:
          json['quantity_received'] == null && json['received_quantity'] == null
              ? null
              : _asInt(
                  json['quantity_received'] ?? json['received_quantity'],
                ),
      status: _asString(json['status'], fallback: 'pending_acceptance'),
      remarks: _asString(json['remarks']),
      issuedAt: _asTimestamp(json['issued_at'] ?? json['created_at']) ??
          DateTime.now(),
      receivedAt: _asTimestamp(json['received_at']),
      issuedByName: _asString(
        json['issued_by_name'],
        fallback: 'RHU Main',
      ),
    );
  }

  final int transferId;
  final int? requestId;
  final int sourceBatchId;
  final int targetFacilityId;
  final int itemId;
  final String batchNumber;
  final int quantityIssued;
  final int? quantityReceived;
  final String status;
  final String remarks;
  final DateTime issuedAt;
  final DateTime? receivedAt;
  final String issuedByName;

  bool get isPending {
    final normalized = status.toLowerCase();
    return receivedAt == null &&
        normalized != 'received' &&
        normalized != 'completed' &&
        normalized != 'cancelled';
  }
}

class InventoryTransactionRecord {
  const InventoryTransactionRecord({
    required this.transactionId,
    required this.batchId,
    required this.facilityId,
    required this.transactionType,
    required this.quantity,
    required this.referenceType,
    required this.loggedAt,
    required this.itemId,
    required this.itemName,
    required this.unit,
    required this.batchNumber,
  });

  factory InventoryTransactionRecord.fromJson(
    Map<String, dynamic> json, {
    InventoryBatchRecord? batch,
    InventoryCatalogRecord? item,
  }) {
    final nestedBatch = _asMap(json['inventory_batches']);
    final nestedItem = _asMap(
      nestedBatch?['inventory_items'] ?? json['inventory_items'],
    );
    return InventoryTransactionRecord(
      transactionId: _asInt(json['transaction_id']),
      batchId: _asInt(json['batch_id']),
      facilityId:
          json['facility_id'] == null ? null : _asInt(json['facility_id']),
      transactionType:
          _asString(json['transaction_type'], fallback: 'movement'),
      quantity: _asInt(json['quantity']),
      referenceType: _asString(json['reference_type']),
      loggedAt: _asTimestamp(json['logged_at']) ?? DateTime.now(),
      itemId: _asInt(
        nestedItem?['item_id'] ??
            nestedBatch?['item_id'] ??
            batch?.itemId ??
            item?.itemId,
      ),
      itemName: _asString(
        nestedItem?['name'] ?? item?.name,
        fallback: 'Inventory item',
      ),
      unit: _asString(
        nestedItem?['unit_of_measure'] ?? item?.unit,
        fallback: 'units',
      ),
      batchNumber: _asString(
        nestedBatch?['batch_number'] ?? batch?.batchNumber,
        fallback: 'Unspecified',
      ),
    );
  }

  final int transactionId;
  final int batchId;
  final int? facilityId;
  final String transactionType;
  final int quantity;
  final String referenceType;
  final DateTime loggedAt;
  final int itemId;
  final String itemName;
  final String unit;
  final String batchNumber;
}

class InventorySnapshot {
  const InventorySnapshot({
    required this.context,
    required this.inventory,
    required this.requests,
    required this.transfers,
    required this.transactions,
    required this.workflowAvailable,
    required this.workflowMessage,
    required this.loadedAt,
  });

  final MidwifeInventoryContext context;
  final List<FacilityInventoryRecord> inventory;
  final List<InventoryStockRequestRecord> requests;
  final List<InventoryTransferRecord> transfers;
  final List<InventoryTransactionRecord> transactions;
  final bool workflowAvailable;
  final String? workflowMessage;
  final DateTime loadedAt;
}

class InventoryRepositoryException implements Exception {
  const InventoryRepositoryException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class InventoryWorkflowUnavailableException
    extends InventoryRepositoryException {
  const InventoryWorkflowUnavailableException(super.message, {super.cause});
}
