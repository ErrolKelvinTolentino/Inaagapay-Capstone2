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

DateTime? _asDateTime(Object? value) {
  if (value is DateTime) return value;
  final text = value?.toString();
  return text == null || text.isEmpty ? null : DateTime.tryParse(text);
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
    required this.itemType,
    required this.unit,
    required this.minimumStock,
  });

  factory InventoryCatalogRecord.fromJson(Map<String, dynamic> json) {
    return InventoryCatalogRecord(
      itemId: _asInt(json['item_id']),
      name: _asString(json['name'], fallback: 'Inventory item'),
      itemType: _asString(json['item_type'], fallback: 'other'),
      unit: _asString(json['unit_of_measure'], fallback: 'units'),
      minimumStock: _asInt(json['minimum_stock_threshold'], fallback: 50),
    );
  }

  final int itemId;
  final String name;
  final String itemType;
  final String unit;
  final int minimumStock;
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
      receivedDate: _asDateTime(json['received_date']),
      expirationDate: _asDateTime(json['expiration_date']),
      manufacturer: _asString(json['manufacturer']),
      status: _asString(json['status'], fallback: 'active'),
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
}

class FacilityInventoryRecord {
  const FacilityInventoryRecord({
    required this.catalog,
    required this.batches,
  });

  final InventoryCatalogRecord catalog;
  final List<InventoryBatchRecord> batches;

  int get quantity => batches
      .where((batch) => batch.isActive)
      .fold(0, (total, batch) => total + batch.quantityRemaining);

  String get batchLabel {
    final active = batches.where((batch) => batch.isActive).toList();
    if (active.isEmpty) return 'No active batch';
    if (active.length == 1) return active.first.batchNumber;
    return '${active.first.batchNumber} +${active.length - 1} more';
  }
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
      requestedAt: _asDateTime(
            json['requested_at'] ?? json['submitted_at'] ?? json['created_at'],
          ) ??
          DateTime.now(),
      completedAt: _asDateTime(
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

enum InventoryNotificationKind { approved, rejected, issued }

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
      createdAt: _asDateTime(json['created_at']) ?? DateTime.now(),
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
      issuedAt: _asDateTime(json['issued_at'] ?? json['created_at']) ??
          DateTime.now(),
      receivedAt: _asDateTime(json['received_at']),
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
      loggedAt: _asDateTime(json['logged_at']) ?? DateTime.now(),
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
