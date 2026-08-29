import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_storage.dart';
import '../../services/push_notification_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/stock_indicators.dart';
import '../../widgets/app_input_field.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/branded_date_picker.dart';
import '../../widgets/confirmation_dialog_box.dart';
import '../../widgets/main_button.dart';
import '../../widgets/main_header.dart';
import '../../widgets/overview_info.dart';
import '../../widgets/secondary_button.dart';
import '../../widgets/tab_button.dart';
import '../midwife/midwife_notification_center.dart';
import 'inventory_models.dart' as live;
import 'inventory_repository.dart';
import 'midwife_inventory_report_service.dart';

/// Midwife side of the RHU -> BHC inventory flow: incoming shipments, receipt
/// confirmation, and stock requests. Reads and writes the same Supabase project
/// as `admin-web`.
class MidwifeInventoryPage extends StatefulWidget {
  const MidwifeInventoryPage({super.key});

  @override
  State<MidwifeInventoryPage> createState() => _MidwifeInventoryPageState();
}

class _MidwifeInventoryPageState extends State<MidwifeInventoryPage>
    with WidgetsBindingObserver {
  static const double _pullUpRefreshThreshold = 56;

  final TextEditingController _stockSearchController = TextEditingController();
  final TextEditingController _historySearchController =
      TextEditingController();
  final InventoryRepository _repository = InventoryRepository();
  final List<InventoryItem> _inventory = [];
  final List<IncomingShipment> _shipments = [];
  final List<StockRequest> _requests = [];
  final List<InventoryEvent> _events = [];

  /// The raw batch ledger for this BHC, kept alongside [_events] because the
  /// dose trace needs the full row — patient, performer, post-movement vial
  /// level — and an InventoryEvent is only ever a one-line summary of it.
  final List<live.InventoryTransactionRecord> _transactions = [];
  final List<live.InventoryNotificationRecord> _inventoryNotifications = [];

  int _selectedTab = 0;
  String _stockFilter = 'all';
  String _historyFilter = 'all';
  String _historySort = 'newest';
  String _historyDatePreset = 'all';
  DateTimeRange? _historyDateRange;
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _workflowAvailable = false;
  String? _workflowMessage;
  String? _loadError;
  DateTime? _lastSyncedAt;
  live.MidwifeInventoryContext? _liveContext;
  final Set<int> _receivingTransferIds = <int>{};
  double _pullUpOverscroll = 0;
  bool _pullUpRefreshQueued = false;
  RealtimeChannel? _notificationChannel;
  Timer? _notificationPollingTimer;
  Timer? _notificationRefreshDebounce;
  Timer? _facilityRefreshDebounce;
  Timer? _expiryRolloverTimer;
  int? _notificationAccountId;
  int? _subscribedFacilityId;
  bool _notificationsInitialized = false;
  bool _notificationRefreshInFlight = false;
  bool _inventoryRealtimeConnected = false;
  bool _stockActivityAvailable = true;
  String? _stockActivityMessage;
  RealtimeChannel? _facilityInventoryChannel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleExpiryRollover();
    _loadLiveInventory();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isLoading) {
      unawaited(_loadLiveInventory(refresh: true));
      _scheduleExpiryRollover();
    }
  }

  @override
  void dispose() {
    _notificationPollingTimer?.cancel();
    _notificationRefreshDebounce?.cancel();
    _facilityRefreshDebounce?.cancel();
    _expiryRolloverTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    final notificationChannel = _notificationChannel;
    if (notificationChannel != null) {
      unawaited(_repository.removeRealtimeChannel(notificationChannel));
    }
    final facilityChannel = _facilityInventoryChannel;
    if (facilityChannel != null) {
      unawaited(_repository.removeRealtimeChannel(facilityChannel));
    }
    _stockSearchController.dispose();
    _historySearchController.dispose();
    super.dispose();
  }

  void _scheduleExpiryRollover() {
    _expiryRolloverTimer?.cancel();
    final now = DateTime.now();
    final nextDay = DateTime(now.year, now.month, now.day + 1, 0, 0, 2);
    _expiryRolloverTimer = Timer(nextDay.difference(now), () {
      if (!mounted) return;
      unawaited(_loadLiveInventory(refresh: true));
      _scheduleExpiryRollover();
    });
  }

  Future<void> _loadLiveInventory({bool refresh = false}) async {
    if (refresh && _isRefreshing) return;
    if (mounted) {
      setState(() {
        if (refresh && _inventory.isNotEmpty) {
          _isRefreshing = true;
        } else {
          _isLoading = true;
        }
        _loadError = null;
      });
    }

    try {
      final context = await _repository.resolveContext();
      final snapshot = await _repository.loadSnapshot(context);
      final itemsById = {
        for (final stock in snapshot.inventory)
          stock.catalog.itemId: stock.catalog,
      };

      final inventory = snapshot.inventory
          .map(
            (stock) => InventoryItem(
              itemId: stock.catalog.itemId,
              name: stock.catalog.name,
              genericName: stock.catalog.genericName,
              itemCode: stock.catalog.itemCode,
              strengthDescription: stock.catalog.strengthDescription,
              dosageForm: stock.catalog.dosageForm,
              category: _categoryLabel(stock.catalog.itemType),
              unit: stock.catalog.unit.toLowerCase(),
              quantity: stock.quantity,
              minimumStock: stock.catalog.minimumStock,
              batchNumber: stock.batchLabel,
              batches: stock.batches,
              icon: _itemIcon(stock.catalog.itemType),
              dosesPerUnit: stock.catalog.dosesPerUnit,
              openVialShelfHours: stock.catalog.openVialShelfHours,
            ),
          )
          .toList();

      final requests = snapshot.requests.map((request) {
        final item = itemsById[request.itemId];
        return StockRequest(
          requestId: request.requestId,
          id: _requestCode(request.requestId),
          itemName: item?.name ?? 'Inventory item #${request.itemId}',
          quantity: request.quantity,
          unit: item?.unit.toLowerCase() ?? 'units',
          reason: request.reason,
          remarks: request.remarks,
          adminRemarks: request.adminRemarks,
          approvedQuantity: request.approvedQuantity,
          status: _displayStatus(request.status),
          submittedAt: request.requestedAt,
          completedAt: request.completedAt,
        );
      }).toList();

      final facilityId = snapshot.context.facilityId;
      final shipments = snapshot.transfers.map((transfer) {
        final item = itemsById[transfer.itemId];
        final outbound = transfer.isOutboundFor(facilityId) &&
            !transfer.isInboundFor(facilityId);
        final counterpart = outbound
            ? transfer.targetFacilityName
            : transfer.sourceFacilityName;
        return IncomingShipment(
          transferId: transfer.transferId,
          id: _transferCode(transfer.transferId),
          itemName: item?.name ?? 'Inventory item #${transfer.itemId}',
          batchNumber: transfer.batchNumber,
          issuedQuantity: transfer.quantityIssued,
          unit: item?.unit.toLowerCase() ?? 'units',
          issuedAt: transfer.issuedAt,
          issuedBy: transfer.issuedByName,
          status: transfer.status,
          isOutbound: outbound,
          direction: transfer.direction,
          counterpartName: counterpart,
          cancelReason: transfer.cancelReason,
          requestId: transfer.requestId == null
              ? null
              : _requestCode(transfer.requestId!),
          remarks: transfer.remarks.isEmpty
              ? (outbound
                  ? 'Sent from this health center to ${counterpart ?? 'another facility'}.'
                  : 'Issued to this health center by ${counterpart ?? 'RHU Main'}.')
              : transfer.remarks,
          receivedQuantity: transfer.quantityReceived,
          receivedAt: transfer.receivedAt,
        );
      }).toList();

      final events = <InventoryEvent>[
        ...snapshot.transactions.map(_eventFromTransaction),
        ...snapshot.transfers.map((transfer) {
          final item = itemsById[transfer.itemId];
          final isCancelled = transfer.isCancelled;
          final outbound = transfer.isOutboundFor(facilityId) &&
              !transfer.isInboundFor(facilityId);
          final counterpart = (outbound
                  ? transfer.targetFacilityName
                  : transfer.sourceFacilityName) ??
              'another facility';

          // The timeline says which way the stock went and who the other end
          // is. It used to say "RHU Main" for everything, which was true while
          // that was the only place stock could come from.
          final String title;
          if (isCancelled) {
            title = outbound
                ? 'Your dispatch was cancelled'
                : 'Incoming transfer cancelled';
          } else if (outbound) {
            title = transfer.isPending
                ? 'Stock sent to $counterpart'
                : '$counterpart confirmed your transfer';
          } else if (transfer.isPending) {
            title = transfer.direction == live.TransferDirection.returnUpward
                ? 'Stock returned to you by $counterpart'
                : 'Stock issued by $counterpart';
          } else {
            title = 'Stocks received from $counterpart';
          }

          return InventoryEvent(
            title: title,
            details:
                '${transfer.quantityIssued} ${item?.unit.toLowerCase() ?? 'units'} of ${item?.name ?? 'Inventory item'} • ${transfer.batchNumber}',
            occurredAt: transfer.receivedAt ?? transfer.issuedAt,
            icon: isCancelled
                ? Icons.cancel_outlined
                : outbound
                    ? Icons.outbound_rounded
                    : transfer.isPending
                        ? Icons.local_shipping_outlined
                        : Icons.inventory_2_rounded,
            color: isCancelled
                ? AppColors.error
                : outbound
                    ? AppColors.warning
                    : transfer.isPending
                        ? AppColors.brandPrimary
                        : AppColors.success,
          );
        }),
        ...snapshot.requests.map((request) {
          final item = itemsById[request.itemId];
          return InventoryEvent(
            title:
                'Stock request ${_displayStatus(request.status).toLowerCase()}',
            details:
                '${request.quantity} ${item?.unit.toLowerCase() ?? 'units'} of ${item?.name ?? 'Inventory item'}',
            occurredAt: request.completedAt ?? request.requestedAt,
            icon: Icons.send_rounded,
            color: AppColors.warning,
          );
        }),
      ]..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

      if (!mounted) return;
      setState(() {
        _liveContext = snapshot.context;
        _workflowAvailable = snapshot.workflowAvailable;
        _workflowMessage = snapshot.workflowMessage;
        _lastSyncedAt = snapshot.loadedAt;
        _inventory
          ..clear()
          ..addAll(inventory);
        _requests
          ..clear()
          ..addAll(requests);
        _shipments
          ..clear()
          ..addAll(shipments);
        _events
          ..clear()
          ..addAll(events);
        _transactions
          ..clear()
          ..addAll(snapshot.transactions);
        _isLoading = false;
        _isRefreshing = false;
        _loadError = null;
      });
      unawaited(_ensureInventoryNotifications(snapshot.context));
      unawaited(_ensureFacilityInventoryRealtime(snapshot.context));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
        _loadError = error.toString();
      });
    }
  }

  InventoryEvent _eventFromTransaction(
    live.InventoryTransactionRecord transaction,
  ) {
    final type = transaction.transactionType.toLowerCase();
    final doses = transaction.dosesMoved;
    // Direction has to come from the dose figure, not the unit figure. A dose
    // drawn from a vial that was already open moves no whole unit, so
    // `quantity` is 0 — which used to read as "incoming" and paint the tile
    // green with a "+0 vial" subtitle.
    final isIncoming = transaction.doseQuantity != null
        ? transaction.doseQuantity! > 0
        : transaction.quantity > 0;

    final title = switch (type) {
      'receipt' => 'Stock receipt recorded',
      'dispense' =>
        transaction.hasPatient ? 'Dose given to a patient' : 'Stock dispensed',
      'expiry_disposal' => 'Unusable stock reported',
      'discard' => 'Open vial discarded',
      'adjustment' => 'Stock adjusted',
      _ => isIncoming ? 'Stock added' : 'Stock deducted',
    };

    // Doses for a multi-dose presentation, units for everything else — a
    // midwife counts BCG in doses and iron tablets in bottles.
    final sign = isIncoming ? '+' : '−';
    final measure = transaction.isMultiDose
        ? '$sign$doses ${doses == 1 ? 'dose' : 'doses'}'
        : '$sign${transaction.quantity.abs()} ${transaction.unit.toLowerCase()}';

    final parts = <String>[
      measure,
      transaction.itemName,
      'Batch ${transaction.batchNumber}',
      if (transaction.patientLabel != null) transaction.patientLabel!,
      if (transaction.performedByName != null)
        'by ${transaction.performedByName}',
      if (transaction.resultingOpenVialDoses != null &&
          transaction.isMultiDose &&
          transaction.resultingOpenVialDoses! > 0)
        '${transaction.resultingOpenVialDoses} left in vial',
    ];

    return InventoryEvent(
      title: title,
      details: parts.join(' • '),
      occurredAt: transaction.loggedAt,
      icon: switch (type) {
        'expiry_disposal' || 'discard' => Icons.report_outlined,
        _ when transaction.hasPatient => Icons.vaccines_rounded,
        _ when isIncoming => Icons.add_circle_outline_rounded,
        _ => Icons.remove_circle_outline_rounded,
      },
      color: switch (type) {
        'expiry_disposal' || 'discard' => AppColors.error,
        _ when isIncoming => AppColors.success,
        _ => AppColors.info,
      },
      transaction: transaction,
    );
  }

  Future<void> _ensureFacilityInventoryRealtime(
    live.MidwifeInventoryContext context,
  ) async {
    if (_subscribedFacilityId == context.facilityId &&
        _facilityInventoryChannel != null) {
      return;
    }

    final previousChannel = _facilityInventoryChannel;
    if (previousChannel != null) {
      await _repository.removeRealtimeChannel(previousChannel);
    }

    _subscribedFacilityId = context.facilityId;
    _inventoryRealtimeConnected = false;
    _facilityInventoryChannel = _repository.subscribeToFacilityInventory(
      context: context,
      onInventoryChanged: () {
        _facilityRefreshDebounce?.cancel();
        _facilityRefreshDebounce = Timer(
          const Duration(milliseconds: 650),
          () {
            if (mounted) unawaited(_loadLiveInventory(refresh: true));
          },
        );
      },
      onConnectionChanged: (connected) {
        if (!mounted || _subscribedFacilityId != context.facilityId) return;
        setState(() => _inventoryRealtimeConnected = connected);
      },
    );
  }

  String _categoryLabel(String itemType) {
    return switch (itemType.toLowerCase()) {
      'vaccine' => 'Vaccine',
      'supplement' => 'Supplement',
      'medical_device' => 'Medical device',
      'contraceptive' => 'Contraceptive',
      _ => 'Other',
    };
  }

  IconData _itemIcon(String itemType) {
    return switch (itemType.toLowerCase()) {
      'vaccine' => Icons.vaccines_rounded,
      'supplement' => Icons.medication_rounded,
      'medical_device' => Icons.medical_services_rounded,
      _ => Icons.health_and_safety_rounded,
    };
  }

  String _displayStatus(String status) {
    final normalized = status.trim().toLowerCase().replaceAll('_', ' ');
    if (normalized.isEmpty) return 'Pending';
    return normalized
        .split(' ')
        .map((word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  String _requestCode(int requestId) =>
      'REQ-${requestId.toString().padLeft(5, '0')}';

  String _transferCode(int transferId) =>
      'TRF-${transferId.toString().padLeft(5, '0')}';

  /// The "Incoming stocks" tile counts what this centre has to CONFIRM.
  /// An outbound shipment is pending too, but pending on somebody else, and
  /// counting it here would inflate a number people act on.
  int get _pendingShipmentCount => _shipments
      .where((shipment) => shipment.isPending && !shipment.isOutbound)
      .length;

  int get _unreadNotificationCount => _inventoryNotifications
      .where((notification) => !notification.isRead)
      .length;

  List<InventoryItem> get _lowStockItems =>
      _inventory.where((item) => item.isLowStock).toList();

  List<InventoryItem> get _openVialItems =>
      _inventory.where((item) => item.hasOpenVial).toList();

  List<InventoryItem> get _expiryAttentionItems {
    final items = _inventory
        .where(
          (item) => item.expiredQuantity > 0 || item.expiringSoonQuantity > 0,
        )
        .toList();
    items.sort((first, second) {
      if (first.expiredQuantity != second.expiredQuantity) {
        return second.expiredQuantity.compareTo(first.expiredQuantity);
      }
      final firstDays = first.nearestExpiryDays ?? 999999;
      final secondDays = second.nearestExpiryDays ?? 999999;
      return firstDays.compareTo(secondDays);
    });
    return items;
  }

  List<InventoryItem> get _dispensableItems =>
      _inventory.where((item) => item.quantity > 0).toList();

  List<InventoryItem> get _reportableItems =>
      _inventory.where((item) => item.reportableBatches.isNotEmpty).toList();

  bool _handleInventoryScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;

    if (notification is ScrollStartNotification) {
      _pullUpOverscroll = 0;
    } else if (notification is OverscrollNotification &&
        notification.metrics.extentAfter == 0 &&
        notification.overscroll > 0) {
      _pullUpOverscroll += notification.overscroll;
    } else if (notification is ScrollEndNotification) {
      final shouldRefresh = _pullUpOverscroll >= _pullUpRefreshThreshold &&
          !_isLoading &&
          !_isRefreshing &&
          !_pullUpRefreshQueued;
      _pullUpOverscroll = 0;

      if (shouldRefresh) {
        _pullUpRefreshQueued = true;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) {
            _pullUpRefreshQueued = false;
            return;
          }
          try {
            await _loadLiveInventory(refresh: true);
          } finally {
            _pullUpRefreshQueued = false;
          }
        });
      }
    }

    return false;
  }

  Future<void> _ensureInventoryNotifications(
    live.MidwifeInventoryContext context,
  ) async {
    if (_notificationAccountId == context.accountId &&
        _notificationChannel != null) {
      return;
    }

    final previousChannel = _notificationChannel;
    if (previousChannel != null) {
      await _repository.removeRealtimeChannel(previousChannel);
    }

    _notificationPollingTimer?.cancel();
    _notificationAccountId = context.accountId;
    _notificationsInitialized = false;

    _notificationChannel = _repository.subscribeToInventoryNotifications(
      context: context,
      onNotification: _handleRealtimeInventoryNotification,
    );

    _notificationPollingTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(
        _refreshInventoryNotifications(context, announceNew: true),
      ),
    );

    await _refreshInventoryNotifications(context, announceNew: false);
  }

  Future<void> _refreshInventoryNotifications(
    live.MidwifeInventoryContext context, {
    required bool announceNew,
  }) async {
    if (_notificationRefreshInFlight ||
        _notificationAccountId != context.accountId) {
      return;
    }

    _notificationRefreshInFlight = true;
    try {
      final loaded = await _repository.loadInventoryNotifications(
        context: context,
      );
      if (!mounted || _notificationAccountId != context.accountId) return;

      final existingIds = _inventoryNotifications
          .map((notification) => notification.notificationId)
          .toSet();
      final newNotifications = _notificationsInitialized && announceNew
          ? loaded
              .where(
                (notification) =>
                    !existingIds.contains(notification.notificationId),
              )
              .toList()
          : const <live.InventoryNotificationRecord>[];

      final merged = <int, live.InventoryNotificationRecord>{
        for (final notification in _inventoryNotifications)
          notification.notificationId: notification,
        for (final notification in loaded)
          notification.notificationId: notification,
      }.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      setState(() {
        _inventoryNotifications
          ..clear()
          ..addAll(merged.take(40));
        _notificationsInitialized = true;
      });

      if (newNotifications.isNotEmpty) {
        _announceInventoryNotification(newNotifications.first);
      }
    } catch (_) {
      // Inventory remains usable when realtime notifications are unavailable.
      // The page refresh gestures still synchronize request statuses.
    } finally {
      _notificationRefreshInFlight = false;
    }
  }

  void _handleRealtimeInventoryNotification(
    live.InventoryNotificationRecord notification,
  ) {
    if (!mounted || notification.accountId != _notificationAccountId) return;
    if (_inventoryNotifications.any(
      (current) => current.notificationId == notification.notificationId,
    )) {
      return;
    }

    setState(() {
      _inventoryNotifications.insert(0, notification);
      if (_inventoryNotifications.length > 40) {
        _inventoryNotifications.removeLast();
      }
    });
    _announceInventoryNotification(notification);
  }

  void _announceInventoryNotification(
    live.InventoryNotificationRecord notification,
  ) {
    switch (notification.kind) {
      case live.InventoryNotificationKind.approved:
        AppSnackbar.success(context, notification.message);
        break;
      case live.InventoryNotificationKind.rejected:
        AppSnackbar.error(context, notification.message);
        break;
      case live.InventoryNotificationKind.issued:
        AppSnackbar.info(context, notification.message);
        break;
      case live.InventoryNotificationKind.lowStock:
        AppSnackbar.warning(context, notification.message);
        break;
      case live.InventoryNotificationKind.other:
        AppSnackbar.info(context, notification.message);
        break;
    }

    _notificationRefreshDebounce?.cancel();
    _notificationRefreshDebounce = Timer(
      const Duration(milliseconds: 450),
      () {
        if (mounted) unawaited(_loadLiveInventory(refresh: true));
      },
    );
  }

  Widget _buildInventoryHeader() {
    return MainHeader(
      title: 'Inventory',
      showBackButton: true,
      onBack: () => Navigator.of(context).maybePop(),
      onNotificationTap: () async {
        await MidwifeNotificationCenter.show(context);
        if (mounted) unawaited(_loadLiveInventory(refresh: true));
      },
      notificationCount: _unreadNotificationCount,
      onSettings: () => Navigator.pushNamed(context, '/settings'),
      onLogout: _logout,
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget? page =
        _isLoading || (_loadError != null && _inventory.isEmpty)
            ? null
            : switch (_selectedTab) {
                1 => _buildStockTab(),
                2 => _buildRequestsTab(),
                3 => _buildHistoryTab(),
                _ => _buildOverviewTab(),
              };

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: Column(
        children: [
          _buildInventoryHeader(),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.brandPrimary,
                    ),
                  )
                : _loadError != null && _inventory.isEmpty
                    ? _buildInitialErrorState()
                    : NotificationListener<ScrollNotification>(
                        onNotification: _handleInventoryScroll,
                        child: RefreshIndicator(
                          color: AppColors.brandPrimary,
                          onRefresh: () => _loadLiveInventory(refresh: true),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: SingleChildScrollView(
                              key: ValueKey<int>(_selectedTab),
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding:
                                  const EdgeInsets.fromLTRB(20, 20, 20, 32),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_isRefreshing) ...[
                                    const LinearProgressIndicator(
                                      color: AppColors.brandPrimary,
                                      minHeight: 2,
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  if (_loadError != null) ...[
                                    _buildSyncWarning(),
                                    const SizedBox(height: 12),
                                  ],
                                  if (_liveContext?.isDemo == true) ...[
                                    _buildDemoIdentityBanner(),
                                    const SizedBox(height: 12),
                                  ],
                                  if (!_workflowAvailable) ...[
                                    _buildWorkflowBanner(),
                                    const SizedBox(height: 14),
                                  ],
                                  if (!_stockActivityAvailable) ...[
                                    _buildStockActivityBanner(),
                                    const SizedBox(height: 14),
                                  ],
                                  _buildTabSelector(),
                                  const SizedBox(height: 20),
                                  page!,
                                  const SizedBox(height: 24),
                                  _buildPullUpRefreshFooter(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitialErrorState() {
    return RefreshIndicator(
      color: AppColors.brandPrimary,
      onRefresh: () => _loadLiveInventory(refresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 72),
          Icon(
            Icons.cloud_off_rounded,
            size: 54,
            color: AppColors.warning.withValues(alpha: 0.9),
          ),
          const SizedBox(height: 14),
          const Text(
            'Inventory could not be synchronized',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            _loadError ?? 'Check your internet connection and try again.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          MainButton(
            label: 'Retry connection',
            leftIcon: Icons.refresh_rounded,
            onPressed: _loadLiveInventory,
          ),
        ],
      ),
    );
  }

  Widget _buildSyncWarning() {
    return _buildStateBanner(
      icon: Icons.cloud_off_outlined,
      color: AppColors.warning,
      title: 'Showing the last synchronized data',
      message: _loadError ?? 'Pull down to retry the inventory connection.',
      actionLabel: 'Retry',
      onAction: () => _loadLiveInventory(refresh: true),
    );
  }

  Widget _buildWorkflowBanner() {
    return _buildStateBanner(
      icon: Icons.construction_rounded,
      color: AppColors.warning,
      title: 'Request and receipt migration required',
      message: _workflowMessage ??
          'Live stock is connected, but Supabase does not have the request and transfer workflow yet. Writes are disabled to protect inventory totals.',
    );
  }

  Widget _buildStockActivityBanner() {
    return _buildStateBanner(
      icon: Icons.inventory_outlined,
      color: AppColors.warning,
      title: 'Stock activity migration required',
      message: _stockActivityMessage ??
          'Run the midwife stock-activity migration in Supabase to enable '
              'dispensing and unusable-stock reports.',
    );
  }

  Widget _buildDemoIdentityBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.16)),
      ),
      child: const Row(
        children: [
          Icon(Icons.science_outlined, color: AppColors.info, size: 18),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'Live demo • Actions use Pinagbarilan BHC account #9 and update the shared inventory.',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 11,
                height: 1.3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPullUpRefreshFooter() {
    return Center(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: _isRefreshing
            ? const Row(
                key: ValueKey<String>('refreshing'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.brandPrimary,
                    ),
                  ),
                  SizedBox(width: 9),
                  Text(
                    'Refreshing inventory...',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              )
            : const Row(
                key: ValueKey<String>('pull-up'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.keyboard_double_arrow_up_rounded,
                    color: AppColors.brandPrimary,
                    size: 20,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Pull up and release to refresh',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildStateBanner({
    required IconData icon,
    required Color color,
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }

  Widget _buildTabSelector() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          TabButton(
            label: 'Overview',
            isActive: _selectedTab == 0,
            onTap: () => setState(() => _selectedTab = 0),
          ),
          const SizedBox(width: 10),
          TabButton(
            label: 'My Stock',
            isActive: _selectedTab == 1,
            onTap: () => setState(() => _selectedTab = 1),
          ),
          const SizedBox(width: 10),
          TabButton(
            label: 'Requests',
            isActive: _selectedTab == 2,
            onTap: () => setState(() => _selectedTab = 2),
          ),
          const SizedBox(width: 10),
          TabButton(
            label: 'History',
            isActive: _selectedTab == 3,
            onTap: () => setState(() => _selectedTab = 3),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    // Split the two legs. They read completely differently: one is a job to do
    // now, the other is a receipt this centre is waiting on somebody else for.
    final pendingShipments = _shipments
        .where((shipment) => shipment.isPending && !shipment.isOutbound)
        .toList();
    final outboundShipments = _shipments
        .where((shipment) => shipment.isPending && shipment.isOutbound)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildConnectionHero(),
        const SizedBox(height: 24),
        _sectionHeading('STOCK AT A GLANCE'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OverviewInfo(
                value: _pendingShipmentCount,
                label: 'Incoming\nstocks',
                icon: Icons.inventory_2_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OverviewInfo(
                value: _lowStockItems.length,
                label: 'Low stock\nitems',
                icon: Icons.warning_amber_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OverviewInfo(
                value: _expiryAttentionItems.length,
                label: 'Expiry\nalerts',
                icon: Icons.event_busy_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        _sectionHeading('TODAY\'S STOCK ACTIONS'),
        const SizedBox(height: 12),
        _buildStockActionsCard(),
        const SizedBox(height: 26),
        _sectionHeading('INCOMING STOCKS'),
        const SizedBox(height: 12),
        if (pendingShipments.isEmpty)
          _buildAllCaughtUpCard()
        else
          ...pendingShipments.map(
            (shipment) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildIncomingShipmentCard(shipment),
            ),
          ),
        // Stock this centre has given up and that nobody has confirmed yet.
        // It is already gone from every figure above, so it needs somewhere on
        // this screen to exist — otherwise the count simply drops overnight.
        if (outboundShipments.isNotEmpty) ...[
          const SizedBox(height: 26),
          _sectionHeading('SENT FROM THIS HEALTH CENTER'),
          const SizedBox(height: 12),
          ...outboundShipments.map(
            (shipment) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildIncomingShipmentCard(shipment),
            ),
          ),
        ],
        if (_openVialItems.isNotEmpty) ...[
          const SizedBox(height: 26),
          _sectionHeading(
            'ACTIVE OPEN MULTI-DOSE VIALS',
            actionLabel: 'View batches',
            onAction: () => setState(() => _selectedTab = 1),
          ),
          const SizedBox(height: 12),
          _buildOpenVialsOverviewCard(),
        ],
        const SizedBox(height: 26),
        _sectionHeading(
          'EXPIRY ATTENTION',
          actionLabel: 'Review stock',
          onAction: () => setState(() => _selectedTab = 1),
        ),
        const SizedBox(height: 12),
        if (_expiryAttentionItems.isEmpty)
          _buildExpiryClearCard()
        else
          ..._expiryAttentionItems.take(2).map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _buildExpiryAttentionCard(item),
                ),
              ),
        const SizedBox(height: 26),
        _sectionHeading(
          'LOW-STOCK ATTENTION',
          actionLabel: 'View stock',
          onAction: () => setState(() => _selectedTab = 1),
        ),
        const SizedBox(height: 12),
        if (_lowStockItems.isEmpty)
          _buildAllStockHealthyCard()
        else
          ..._lowStockItems.take(2).map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _buildAttentionCard(item),
                ),
              ),
        const SizedBox(height: 6),
        SecondaryButton(
          label: 'Request stocks from ${_liveContext?.supplierLabel ?? 'your RHU'}',
          leadingIcon: Icons.add_circle_outline_rounded,
          onPressed:
              _workflowAvailable ? _showRequestSheet : _showWorkflowUnavailable,
        ),
        const SizedBox(height: 16),
        _buildLatestRequestCard(),
        const SizedBox(height: 26),
        _sectionHeading(
          'RECENT ACTIVITY',
          actionLabel: 'View all',
          onAction: () => setState(() => _selectedTab = 3),
        ),
        const SizedBox(height: 10),
        _buildRecentActivityCard(),
      ],
    );
  }

  Widget _buildOpenVialsOverviewCard() {
    final openItems = _openVialItems;
    if (openItems.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFA7F3D0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Color(0xFF059669),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.colorize_rounded, size: 14, color: Colors.white),
              ),
              const SizedBox(width: 8),
              const Text(
                'OPEN MULTI-DOSE VIALS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF065F46),
                  letterSpacing: 0.4,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFD1FAE5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${openItems.length} in use',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF047857),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...openItems.map((item) {
            final openBatches = item.batches.where((b) => b.isUsableOn() && b.dosesRemainingInOpenVial > 0);
            return Column(
              children: openBatches.map((b) {
                final dpu = item.dosesPerUnit;
                final dosesLeft = b.dosesRemainingInOpenVial;
                final isExpired = b.isExpiredOpenVial(item.openVialShelfHours);
                final timeLeft = b.openVialTimeLeft(item.openVialShelfHours);
                // Under an hour is when a 6h BCG vial stops being a note and
                // starts being a decision: use it or lose it.
                final isUrgent = !isExpired &&
                    timeLeft != null &&
                    timeLeft <= const Duration(hours: 1);
                // "3 of 10 remaining" is the question, and the trace is the
                // answer: tapping through lists the seven doses that went, who
                // each one went into and when.
                return InkWell(
                  onTap: () => _showDoseTraceSheet(
                    itemId: item.itemId,
                    itemName: item.name,
                    batchId: b.batchId,
                    batchNumber: b.batchNumber,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isExpired ? const Color(0xFFFECACA) : const Color(0xFFD1FAE5),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.brandText,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Batch #${b.batchNumber} • $dosesLeft of $dpu doses remaining',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isExpired ? const Color(0xFFDC2626) : const Color(0xFF059669),
                                ),
                              ),
                              // The shelf-life clock, in the hands of the
                              // person who has to act on it. The portal has
                              // always computed this; the BHC — who holds the
                              // vial — only ever saw "6h limit", which is the
                              // policy, not the answer.
                              if (timeLeft != null) ...[
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Icon(
                                      isExpired
                                          ? Icons.timer_off_outlined
                                          : Icons.timer_outlined,
                                      size: 11,
                                      color: isExpired
                                          ? const Color(0xFFDC2626)
                                          : isUrgent
                                              ? const Color(0xFFB45309)
                                              : const Color(0xFF047857),
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      isExpired
                                          ? 'Overdue by ${_durationLabel(-timeLeft)} — discard now'
                                          : '${_durationLabel(timeLeft)} left of ${item.openVialShelfHours}h',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: isExpired
                                            ? const Color(0xFFDC2626)
                                            : isUrgent
                                                ? const Color(0xFFB45309)
                                                : const Color(0xFF047857),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 3),
                              const Row(
                                children: [
                                  Icon(
                                    Icons.fact_check_outlined,
                                    size: 11,
                                    color: Color(0xFF047857),
                                  ),
                                  SizedBox(width: 3),
                                  Text(
                                    'Tap to see where each dose went',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF047857),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isExpired
                                    ? const Color(0xFFFEE2E2)
                                    : isUrgent
                                        ? const Color(0xFFFEF3C7)
                                        : const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isExpired
                                    ? 'EXPIRED'
                                    : isUrgent
                                        ? 'USE SOON'
                                        : 'Active',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: isExpired
                                      ? const Color(0xFFDC2626)
                                      : isUrgent
                                          ? const Color(0xFFB45309)
                                          : const Color(0xFF059669),
                                ),
                              ),
                            ),
                            if (isExpired) ...[
                              const SizedBox(height: 6),
                              // Until now the app could say EXPIRED and offer
                              // nothing to do about it — the discard RPC was
                              // only ever wired to the portal.
                              TextButton.icon(
                                onPressed: () => _confirmDiscardOpenVial(item, b),
                                icon: const Icon(Icons.delete_outline_rounded, size: 15),
                                label: const Text('Discard'),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.error,
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  textStyle: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildConnectionHero() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandPrimary.withValues(alpha: 0.24),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/inventory_overview_midwife.png',
                fit: BoxFit.cover,
                alignment: Alignment.centerRight,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, __, ___) => const ColoredBox(
                  color: AppColors.brandAccent,
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      const Color(0xFFE14583).withValues(alpha: 0.96),
                      const Color(0xFFE95591).withValues(alpha: 0.68),
                      const Color(0xFFFF8FBA).withValues(alpha: 0.08),
                    ],
                    stops: const [0, 0.48, 1],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      AppColors.brandAccent.withValues(alpha: 0.16),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                        ),
                        child: const Icon(
                          Icons.local_pharmacy_rounded,
                          color: Colors.white,
                          size: 23,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (_liveContext?.facilityName ??
                                      'Barangay Health Center')
                                  .toUpperCase(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_liveContext?.displayName ?? 'Midwife'} • Shared inventory',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.84),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _HeroTag(
                    label: _liveContext?.isDemo == true
                        ? 'LIVE DEMO IDENTITY'
                        : 'VERIFIED MIDWIFE SESSION',
                    icon: _liveContext?.isDemo == true
                        ? Icons.science_outlined
                        : Icons.verified_user_outlined,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'RHU inventory connected',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 7),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Text(
                      _pendingShipmentCount == 0
                          ? 'Your BHC stock is synced. No delivery is waiting for confirmation.'
                          : '$_pendingShipmentCount ${_pendingShipmentCount == 1 ? 'delivery is' : 'deliveries are'} ready for your receipt confirmation.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.sync_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              _lastSyncedAt == null
                                  ? 'RHU issue → Receive → BHC stock update'
                                  : 'Synced ${_dateTimeLabel(_lastSyncedAt!)}${_inventoryRealtimeConnected ? ' • LIVE' : ''}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStockActionsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.bgSecondary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.account_tree_outlined,
                  color: AppColors.brandText,
                  size: 19,
                ),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Choose an action → confirm the batch → review the new balance. Every movement is shared with RHU Main.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildStockActionButton(
            icon: Icons.medication_liquid_outlined,
            color: AppColors.brandPrimary,
            title: 'Dispense stock',
            subtitle: 'Record medicine or vaccine used during a service.',
            badge: 'Earliest-expiring batch selected',
            onTap: _stockActivityAvailable && _dispensableItems.isNotEmpty
                ? _showDispenseSheet
                : null,
          ),
          const SizedBox(height: 10),
          _buildStockActionButton(
            icon: Icons.report_gmailerrorred_rounded,
            color: AppColors.error,
            title: 'Report expired / unusable',
            subtitle: 'Remove affected stock and alert RHU with an audit note.',
            badge:
                '${_expiryAttentionItems.length} expiry alert${_expiryAttentionItems.length == 1 ? '' : 's'}',
            onTap: _stockActivityAvailable && _reportableItems.isNotEmpty
                ? _showUnusableSheet
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildStockActionButton({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String badge,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: color.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: onTap == null ? 0.07 : 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: onTap == null ? AppColors.textSecondary : color,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: onTap == null
                            ? AppColors.textSecondary
                            : AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        badge,
                        style: TextStyle(
                          color:
                              onTap == null ? AppColors.textSecondary : color,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: onTap == null ? AppColors.borderPrimary : color,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpiryClearCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: const Row(
        children: [
          Icon(Icons.event_available_rounded, color: AppColors.success),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'No active batch expires within the next 90 days.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpiryAttentionCard(InventoryItem item) {
    final hasExpired = item.expiredQuantity > 0;
    final color = hasExpired ? AppColors.error : AppColors.warning;
    final message = hasExpired
        ? '${item.expiredQuantity} ${item.unit} must not be dispensed'
        : '${item.expiringSoonQuantity} ${item.unit} expire within 90 days • nearest ${item.nearestExpiryLabel.toLowerCase()}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              hasExpired ? Icons.event_busy_rounded : Icons.timer_outlined,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: hasExpired
                ? _stockActivityAvailable
                    ? () => _showUnusableSheet(item)
                    : null
                : () {
                    setState(() {
                      _stockFilter = 'expiring';
                      _selectedTab = 1;
                    });
                  },
            child: Text(hasExpired ? 'Report' : 'Review'),
          ),
        ],
      ),
    );
  }

  /// One line of plain language for which way the stock went and why.
  ///
  /// A midwife looking at a transfer needs to know two things before anything
  /// else: is this arriving or leaving, and is it mine to act on. Both used to
  /// be assumed — everything arrived, and everything was hers to confirm.
  String _shipmentDirectionCopy(IncomingShipment shipment) {
    final other = shipment.counterpartName ?? 'another facility';
    if (shipment.isOutbound) {
      switch (shipment.direction) {
        case live.TransferDirection.returnUpward:
          return 'Returned by you to $other';
        case live.TransferDirection.lateral:
          return 'Sent by you to $other';
        default:
          return 'Sent from this health center to $other';
      }
    }
    switch (shipment.direction) {
      case live.TransferDirection.returnUpward:
        return 'Returned to you by $other';
      case live.TransferDirection.lateral:
        return 'Shared with you by $other';
      default:
        return 'From $other';
    }
  }

  Widget _buildIncomingShipmentCard(IncomingShipment shipment) {
    final outbound = shipment.isOutbound;
    final accent = shipment.isCancelled
        ? AppColors.error
        : outbound
            ? AppColors.warning
            : AppColors.brandPrimary;

    final String statusLabel;
    final Color statusColor;
    final IconData statusIcon;
    if (shipment.isCancelled) {
      statusLabel = 'Cancelled';
      statusColor = AppColors.error;
      statusIcon = Icons.cancel_rounded;
    } else if (shipment.isPending) {
      // A pending outbound shipment is not "pending YOU" — the other end has to
      // confirm it. Saying so is what stops a midwife hunting for a button that
      // is deliberately not there.
      statusLabel = outbound ? 'Awaiting their receipt' : 'Pending';
      statusColor = AppColors.warning;
      statusIcon = Icons.schedule_rounded;
    } else {
      statusLabel = outbound ? 'Delivered' : 'Received';
      statusColor = AppColors.success;
      statusIcon = Icons.check_circle_rounded;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  outbound
                      ? Icons.outbound_rounded
                      : Icons.inventory_2_rounded,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shipment.itemName,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _shipmentDirectionCopy(shipment),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusChip(
                label: statusLabel,
                color: statusColor,
                icon: statusIcon,
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 15),
            child: Divider(height: 1, color: AppColors.borderPrimary),
          ),
          Row(
            children: [
              Expanded(
                child: _DetailValue(
                  label: 'BATCH',
                  value: shipment.batchNumber,
                ),
              ),
              Expanded(
                child: _DetailValue(
                  label: 'QUANTITY',
                  value: '${shipment.issuedQuantity} ${shipment.unit}',
                ),
              ),
              Expanded(
                child: _DetailValue(
                  label: outbound ? 'SENT' : 'ISSUED',
                  value: _shortDate(shipment.issuedAt),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.bgSecondary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: AppColors.brandText,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    shipment.isCancelled && shipment.cancelReason.isNotEmpty
                        ? '${shipment.remarks}\nCancelled: ${shipment.cancelReason}'
                        : shipment.remarks,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (shipment.canConfirmReceipt)
            MainButton(
              label: _receivingTransferIds.contains(shipment.transferId)
                  ? 'Receiving stock...'
                  : 'Receive ${shipment.issuedQuantity} ${shipment.unit}',
              leftIcon: Icons.check_circle_outline_rounded,
              onPressed: !_workflowAvailable ||
                      _receivingTransferIds.contains(shipment.transferId)
                  ? null
                  : () => _confirmReceive(shipment),
            )
          else if (outbound && shipment.isPending)
            // Nothing to press. What the sending centre needs instead is a
            // straight answer about where its stock currently is, because the
            // units have already left its own count.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.local_shipping_outlined,
                    size: 18,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'These ${shipment.issuedQuantity} ${shipment.unit} have already left your shelf and are not counted here or at '
                      '${shipment.counterpartName ?? 'the receiving facility'} until they confirm receipt. '
                      'Contact your RHU if this stays unconfirmed.',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAllCaughtUpCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: _cardDecoration(),
      child: const Column(
        children: [
          Icon(
            Icons.inventory_rounded,
            color: AppColors.success,
            size: 38,
          ),
          SizedBox(height: 10),
          Text(
            'All caught up',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'There are no issued stocks waiting for your receipt confirmation.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildAllStockHealthyCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: const Row(
        children: [
          Icon(Icons.check_circle_rounded, color: AppColors.success),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'All items are above their re-order levels.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttentionCard(InventoryItem item) {
    final int shortfall = item.minimumStock - item.quantity;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(item.icon, color: AppColors.warning, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${item.quantity} ${item.unit} on hand • $shortfall below re-order level',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed:
                _workflowAvailable ? () => _showRequestSheet(item) : null,
            child: const Text('Request'),
          ),
        ],
      ),
    );
  }

  Widget _buildLatestRequestCard() {
    if (_requests.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(),
        child: const Row(
          children: [
            Icon(Icons.assignment_outlined, color: AppColors.textSecondary),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'No stock requests have been recorded for this BHC.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }
    final request = _requests.first;
    final statusColor = _statusColor(request.status);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(Icons.assignment_outlined, color: statusColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Latest stock request',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  request.isPartiallyApproved
                      ? '${request.itemName} • ${request.approvedQuantity} of '
                          '${request.quantity} ${request.unit}'
                      : '${request.itemName} • ${request.quantity} ${request.unit}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          _StatusChip(
            label: request.status,
            color: statusColor,
            icon: _statusIcon(request.status),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivityCard() {
    final recentEvents = _events.take(3).toList();
    if (recentEvents.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: _cardDecoration(),
        child: const Text(
          'No inventory movements have been logged for this BHC yet.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          for (int index = 0; index < recentEvents.length; index++) ...[
            _ActivityTile(
              event: recentEvents[index],
              dateLabel: _dateTimeLabel,
              onTap: _traceTapFor(recentEvents[index]),
            ),
            if (index != recentEvents.length - 1)
              const Padding(
                padding: EdgeInsets.only(left: 64),
                child: Divider(height: 1, color: AppColors.borderPrimary),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildStockTab() {
    final query = _stockSearchController.text.trim().toLowerCase();
    final visibleItems = _inventory
        .where(
      (item) =>
          item.name.toLowerCase().contains(query) ||
          item.genericName.toLowerCase().contains(query) ||
          item.itemCode.toLowerCase().contains(query) ||
          item.category.toLowerCase().contains(query) ||
          item.batchNumber.toLowerCase().contains(query),
    )
        .where((item) {
      return switch (_stockFilter) {
        'expiring' => item.expiringSoonQuantity > 0,
        'expired' => item.expiredQuantity > 0,
        'low' => item.isLowStock,
        _ => true,
      };
    }).toList()
      ..sort((first, second) {
        if (first.expiredQuantity != second.expiredQuantity) {
          return second.expiredQuantity.compareTo(first.expiredQuantity);
        }
        if ((first.expiringSoonQuantity > 0) !=
            (second.expiringSoonQuantity > 0)) {
          return first.expiringSoonQuantity > 0 ? -1 : 1;
        }
        if (first.isLowStock != second.isLowStock) {
          return first.isLowStock ? -1 : 1;
        }
        return first.name.toLowerCase().compareTo(second.name.toLowerCase());
      });
    final expiringCount =
        _inventory.where((item) => item.expiringSoonQuantity > 0).length;
    final expiredCount =
        _inventory.where((item) => item.expiredQuantity > 0).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'MY BHC STOCK',
          style: TextStyle(
            color: AppColors.brandText,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'Usable totals exclude expired batches. The earliest-expiring stock is selected first (FEFO).',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 18),
        AppInputField(
          controller: _stockSearchController,
          hintText: 'Search item, code, category, or batch',
          leadingIcon: Icons.search_rounded,
          trailingIcon:
              _stockSearchController.text.isEmpty ? null : Icons.close_rounded,
          onTrailingTap: () {
            _stockSearchController.clear();
            setState(() {});
          },
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildStockFilterChip(
                value: 'all',
                label: 'All stock',
                icon: Icons.inventory_2_outlined,
              ),
              const SizedBox(width: 8),
              _buildStockFilterChip(
                value: 'expiring',
                label: 'Expires ≤90d',
                icon: Icons.timer_outlined,
                color: AppColors.warning,
              ),
              const SizedBox(width: 8),
              _buildStockFilterChip(
                value: 'expired',
                label: 'Expired',
                icon: Icons.event_busy_outlined,
                color: AppColors.error,
              ),
              const SizedBox(width: 8),
              _buildStockFilterChip(
                value: 'low',
                label: 'Low stock',
                icon: Icons.warning_amber_rounded,
                color: AppColors.warning,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.bgSecondary,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: AppColors.brandPrimary.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: _InventoryCountLabel(
                  icon: Icons.inventory_2_outlined,
                  value: visibleItems.length,
                  label: 'Items shown',
                  color: AppColors.brandText,
                  compact: true,
                ),
              ),
              Container(
                width: 1,
                height: 34,
                color: AppColors.borderPrimary,
              ),
              Expanded(
                child: _InventoryCountLabel(
                  icon: Icons.timer_outlined,
                  value: expiringCount,
                  label: 'Expiring',
                  color: AppColors.warning,
                  compact: true,
                ),
              ),
              Container(
                width: 1,
                height: 34,
                color: AppColors.borderPrimary,
              ),
              Expanded(
                child: _InventoryCountLabel(
                  icon: Icons.event_busy_outlined,
                  value: expiredCount,
                  label: 'Expired',
                  color: AppColors.error,
                  compact: true,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (visibleItems.isEmpty)
          _buildNoSearchResults()
        else
          ...visibleItems.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildStockCard(item),
            ),
          ),
        const SizedBox(height: 12),
        _sectionHeading(
          'RECENT DISPENSING & UNUSABLE STOCK',
          actionLabel: 'Full history',
          onAction: () => setState(() => _selectedTab = 3),
        ),
        const SizedBox(height: 10),
        _buildStockOutActivityCard(),
        const SizedBox(height: 18),
        MainButton(
          label: 'Request stocks from ${_liveContext?.supplierLabel ?? 'your RHU'}',
          leftIcon: Icons.add_shopping_cart_outlined,
          onPressed: _workflowAvailable ? _showRequestSheet : null,
        ),
      ],
    );
  }

  Widget _buildStockOutActivityCard() {
    final activities = _events
        .where(
          (event) =>
              event.title == 'Stock dispensed' ||
              event.title == 'Unusable stock reported',
        )
        .take(5)
        .toList();
    if (activities.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: _cardDecoration(),
        child: const Row(
          children: [
            Icon(Icons.history_rounded, color: AppColors.textSecondary),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Dispensing and unusable-stock records will remain visible here.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          for (int index = 0; index < activities.length; index++) ...[
            _ActivityTile(
              event: activities[index],
              dateLabel: _dateTimeLabel,
              onTap: _traceTapFor(activities[index]),
            ),
            if (index != activities.length - 1)
              const Padding(
                padding: EdgeInsets.only(left: 64),
                child: Divider(height: 1, color: AppColors.borderPrimary),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildStockFilterChip({
    required String value,
    required String label,
    required IconData icon,
    Color color = AppColors.brandPrimary,
  }) {
    final selected = _stockFilter == value;
    final selectedForeground =
        color == AppColors.warning ? AppColors.textPrimary : Colors.white;
    return FilterChip(
      selected: selected,
      onSelected: (_) => setState(() => _stockFilter = value),
      avatar: Icon(
        icon,
        size: 16,
        color: selected ? selectedForeground : color,
      ),
      label: Text(label),
      labelStyle: TextStyle(
        color: selected ? selectedForeground : AppColors.textPrimary,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
      selectedColor: color,
      backgroundColor: Colors.white,
      side: BorderSide(
        color: selected ? color : color.withValues(alpha: 0.25),
      ),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    );
  }

  Widget _buildStockCard(InventoryItem item) {
    final bool hasExpired = item.expiredQuantity > 0;
    final bool hasExpiring = item.expiringSoonQuantity > 0;
    final Color statusColor = hasExpired
        ? AppColors.error
        : hasExpiring || item.isLowStock
            ? AppColors.warning
            : AppColors.success;
    final String statusLabel = hasExpired
        ? 'Expiry alert'
        : item.quantity == 0
            ? 'Out of stock'
            : hasExpiring
                ? 'Expiring'
                : item.isLowStock
                    ? 'Low stock'
                    : 'Available';
    final int shortfall = item.minimumStock - item.quantity;
    final int progressTarget =
        item.minimumStock > 0 ? item.minimumStock * 2 : 1;
    final double progress =
        (item.quantity / progressTarget).clamp(0.0, 1.0).toDouble();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(item.icon, color: statusColor, size: 23),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    if (item.catalogSubtitle.isNotEmpty) ...[
                      Text(
                        item.catalogSubtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.brandText,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      item.isMultiDose
                          ? '${item.category} • ${item.dosesPerUnit} doses/unit${item.hasOpenVial ? ' • 💉 Open: ${item.openVialDoses} doses' : ''}'
                          : '${item.category} • ${item.usableBatches.length} usable batch${item.usableBatches.length == 1 ? '' : 'es'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusChip(
                label: statusLabel,
                color: statusColor,
                icon: hasExpired
                    ? Icons.event_busy_outlined
                    : hasExpiring || item.isLowStock
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_rounded,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _DetailValue(
                  label: 'ON HAND',
                  value: item.isMultiDose
                      ? (item.hasOpenVial
                          ? '${item.quantity} sealed + ${item.openVialDoses} open (${item.totalAvailableDoses} doses)'
                          : '${item.quantity} ${item.unit} (${item.totalAvailableDoses} doses)')
                      : '${item.quantity} ${item.unit} usable',
                  valueColor: AppColors.textPrimary,
                ),
              ),
              Expanded(
                child: _DetailValue(
                  label: 'NEXT EXPIRY',
                  value: item.nearestExpiryLabel,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'STOCK LEVEL',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            item.isLowStock
                ? '$shortfall ${item.unit} below the re-order level'
                : 'Stock is above the re-order level',
            style: TextStyle(
              color:
                  item.isLowStock ? AppColors.textPrimary : AppColors.success,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              color: statusColor,
              backgroundColor: statusColor.withValues(alpha: 0.14),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: (item.nearestUsableBatch == null
                      ? AppColors.error
                      : AppColors.info)
                  .withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (item.nearestUsableBatch == null
                        ? AppColors.error
                        : AppColors.info)
                    .withValues(alpha: 0.14),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  item.nearestUsableBatch == null
                      ? Icons.block_rounded
                      : Icons.low_priority_rounded,
                  size: 17,
                  color: item.nearestUsableBatch == null
                      ? AppColors.error
                      : AppColors.info,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.nearestUsableBatch == null
                        ? 'No usable batch is available. Expired stock is excluded.'
                        : 'Use first: Batch ${item.nearestUsableBatch!.batchNumber} • ${item.nearestExpiryLabel}',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 11,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (hasExpired) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(
                '${item.expiredQuantity} ${item.unit} in expired batches need reporting and cannot be dispensed.',
                style: const TextStyle(
                  color: AppColors.error,
                  fontSize: 11,
                  height: 1.3,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const Padding(
            padding: EdgeInsets.only(top: 14, bottom: 12),
            child: Divider(height: 1, color: AppColors.borderPrimary),
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _stockActivityAvailable && item.quantity > 0
                      ? () => _showDispenseSheet(item)
                      : null,
                  icon: const Icon(Icons.medication_outlined, size: 17),
                  label: const Text('Dispense'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.brandText,
                    side: BorderSide(
                      color: AppColors.brandPrimary.withValues(alpha: 0.45),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    textStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _stockActivityAvailable &&
                          item.reportableBatches.isNotEmpty
                      ? () => _showUnusableSheet(item)
                      : null,
                  icon: const Icon(Icons.report_outlined, size: 17),
                  label: const Text('Report unusable'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: BorderSide(
                      color: AppColors.error.withValues(alpha: 0.4),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    textStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _showDoseTraceSheet(
                  itemId: item.itemId,
                  itemName: item.name,
                ),
                icon: const Icon(Icons.fact_check_outlined, size: 17),
                label: Text(
                  item.isMultiDose ? 'Dose trace' : 'Movement trace',
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  textStyle: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              if (item.isLowStock)
                TextButton.icon(
                  onPressed:
                      _workflowAvailable ? () => _showRequestSheet(item) : null,
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                  label: const Text('Request this item'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.brandText,
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNoSearchResults() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: _cardDecoration(),
      child: const Column(
        children: [
          Icon(Icons.search_off_rounded,
              color: AppColors.textSecondary, size: 40),
          SizedBox(height: 10),
          Text(
            'No inventory items found',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Try a medicine, vaccine, or category name.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestsTab() {
    final activeRequests = _requests
        .where(
          (request) =>
              request.status == 'Pending' ||
              request.status == 'Approved' ||
              request.status == 'Issued',
        )
        .toList()
      ..sort((first, second) {
        const rank = {'Issued': 0, 'Approved': 1, 'Pending': 2};
        final statusOrder =
            (rank[first.status] ?? 99).compareTo(rank[second.status] ?? 99);
        return statusOrder != 0
            ? statusOrder
            : second.submittedAt.compareTo(first.submittedAt);
      });
    final requestHistory =
        _requests.where((request) => !activeRequests.contains(request)).toList()
          ..sort((first, second) {
            final firstDate = first.completedAt ?? first.submittedAt;
            final secondDate = second.completedAt ?? second.submittedAt;
            return secondDate.compareTo(firstDate);
          });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'STOCK REQUESTS',
          style: TextStyle(
            color: AppColors.brandText,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'Track every request from RHU review to delivery. New requests are created from Overview or a low-stock item in My Stock.',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 18),
        _buildRequestStatusOverview(
          activeRequests: activeRequests,
          history: requestHistory,
        ),
        const SizedBox(height: 14),
        _buildRequestLifecycleCard(),
        const SizedBox(height: 24),
        _buildRequestGroup(
          title: 'ACTIVE REQUESTS',
          requests: activeRequests,
          emptyIcon: Icons.task_alt_rounded,
          emptyTitle: 'No active requests',
          emptyMessage:
              'There are no requests waiting for RHU action or your receipt confirmation.',
        ),
        const SizedBox(height: 24),
        _buildRequestGroup(
          title: 'REQUEST HISTORY',
          requests: requestHistory,
          emptyIcon: Icons.history_rounded,
          emptyTitle: 'No request history yet',
          emptyMessage:
              'Received, rejected, completed, or cancelled requests will remain visible here.',
        ),
      ],
    );
  }

  Widget _buildRequestStatusOverview({
    required List<StockRequest> activeRequests,
    required List<StockRequest> history,
  }) {
    final awaitingRhu = activeRequests
        .where(
          (request) =>
              request.status == 'Pending' || request.status == 'Approved',
        )
        .length;
    final issued =
        activeRequests.where((request) => request.status == 'Issued').length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderPrimary),
      ),
      child: Row(
        children: [
          Expanded(
            child: _InventoryCountLabel(
              icon: Icons.hourglass_top_rounded,
              value: awaitingRhu,
              label: 'With RHU',
              color: AppColors.warning,
              compact: true,
            ),
          ),
          Container(width: 1, height: 38, color: AppColors.borderPrimary),
          Expanded(
            child: _InventoryCountLabel(
              icon: Icons.local_shipping_outlined,
              value: issued,
              label: 'To receive',
              color: AppColors.brandText,
              compact: true,
            ),
          ),
          Container(width: 1, height: 38, color: AppColors.borderPrimary),
          Expanded(
            child: _InventoryCountLabel(
              icon: Icons.task_alt_rounded,
              value: history.length,
              label: 'History',
              color: AppColors.success,
              compact: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestGroup({
    required String title,
    required List<StockRequest> requests,
    required IconData emptyIcon,
    required String emptyTitle,
    required String emptyMessage,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeading('$title (${requests.length})'),
        const SizedBox(height: 10),
        if (requests.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: _cardDecoration(),
            child: Column(
              children: [
                Icon(emptyIcon, color: AppColors.textSecondary, size: 32),
                const SizedBox(height: 9),
                Text(
                  emptyTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  emptyMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          )
        else
          ...requests.map(
            (request) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildRequestCard(request),
            ),
          ),
      ],
    );
  }

  Widget _buildRequestLifecycleCard() {
    const labels = ['Pending', 'Approved', 'Issued', 'Received'];
    const icons = [
      Icons.hourglass_top_rounded,
      Icons.task_alt_rounded,
      Icons.local_shipping_outlined,
      Icons.inventory_2_rounded,
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(18),
        border:
            Border.all(color: AppColors.brandPrimary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.route_outlined,
                color: AppColors.brandText,
                size: 18,
              ),
              SizedBox(width: 7),
              Text(
                'HOW REQUESTS MOVE',
                style: TextStyle(
                  color: AppColors.brandText,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          const Text(
            'The status changes automatically as RHU reviews and releases stock.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (int index = 0; index < labels.length; index++) ...[
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: index == labels.length - 1
                              ? AppColors.success.withValues(alpha: 0.16)
                              : AppColors.brandPrimary.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          icons[index],
                          size: 17,
                          color: index == labels.length - 1
                              ? AppColors.success
                              : AppColors.brandPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        labels[index],
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (index != labels.length - 1)
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.brandPrimary,
                    size: 18,
                  ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: AppColors.borderPrimary),
          const SizedBox(height: 12),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.cancel_outlined, color: AppColors.error, size: 17),
              SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Rejected requests stop before issue and remain in Request History with RHU remarks.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(StockRequest request) {
    final Color statusColor = _statusColor(request.status);
    final bool isIssued = request.status == 'Issued';
    final String date = request.completedAt == null
        ? 'Submitted ${_dateTimeLabel(request.submittedAt)}'
        : '${request.status} ${_dateTimeLabel(request.completedAt!)}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  _statusIcon(request.status),
                  color: statusColor,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.itemName,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      request.isPartiallyApproved
                          ? '${request.approvedQuantity} of ${request.quantity} '
                              '${request.unit} approved'
                          : '${request.quantity} ${request.unit} requested',
                      style: TextStyle(
                        color: request.isPartiallyApproved
                            ? AppColors.warning
                            : AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: request.isPartiallyApproved
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusChip(
                label: request.status,
                color: statusColor,
                icon: _statusIcon(request.status),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.bgPrimary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'REQUEST REASON',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  request.reason,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: statusColor.withValues(alpha: 0.16)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _statusIcon(request.status),
                  color: statusColor,
                  size: 17,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _requestStatusMessage(request.status),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 11,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (request.remarks.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Your remarks: ${request.remarks}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          if (request.adminRemarks.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.bgSecondary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'RHU remarks: ${request.adminRemarks}',
                style: const TextStyle(
                  color: AppColors.brandText,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${request.id} • $date',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                  ),
                ),
              ),
              if (isIssued)
                TextButton(
                  onPressed: () => setState(() => _selectedTab = 0),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.brandText,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                  child: const Text(
                    'View incoming',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // History tab: Stock Movement & Audit Trail
  //
  // Complete transparent ledger of all dispensing, replenishments,
  // expirations, discards, transfers, and adjustments for this BHC.
  // ---------------------------------------------------------------------

  String get _historyDateLabel {
    return switch (_historyDatePreset) {
      'today' => 'Today',
      '7d' => 'Last 7 days',
      '30d' => 'Last 30 days',
      'month' => 'This month',
      'custom' when _historyDateRange != null =>
        '${_shortDate(_historyDateRange!.start)} – ${_shortDate(_historyDateRange!.end)}, ${_historyDateRange!.end.year}',
      'custom' => 'Custom range',
      _ => 'All time',
    };
  }

  String get _historySortLabel {
    return switch (_historySort) {
      'oldest' => 'Oldest first',
      'name_asc' => 'Item A → Z',
      'name_desc' => 'Item Z → A',
      'qty_desc' => 'Qty: Highest',
      'qty_asc' => 'Qty: Lowest',
      _ => 'Newest first',
    };
  }

  Future<void> _pickCustomDateRange() async {
    final now = DateTime.now();
    final picked = await showBrandedDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 2),
      initialDateRange: _historyDateRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 30)),
            end: now,
          ),
      helpText: 'SELECT AUDIT TRAIL DATE RANGE',
    );
    if (picked != null && mounted) {
      setState(() {
        _historyDatePreset = 'custom';
        _historyDateRange = picked;
      });
    }
  }

  void _showHistorySortSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.bgPrimary,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderPrimary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Icon(Icons.sort_rounded, color: AppColors.brandPrimary),
                  SizedBox(width: 8),
                  Text(
                    'SORT MOVEMENTS BY',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: AppColors.brandText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildSortOptionTile(
                sheetContext: sheetContext,
                value: 'newest',
                label: 'Newest first (Default)',
                icon: Icons.schedule_rounded,
              ),
              _buildSortOptionTile(
                sheetContext: sheetContext,
                value: 'oldest',
                label: 'Oldest first',
                icon: Icons.history_rounded,
              ),
              _buildSortOptionTile(
                sheetContext: sheetContext,
                value: 'name_asc',
                label: 'Item name: A to Z',
                icon: Icons.sort_by_alpha_rounded,
              ),
              _buildSortOptionTile(
                sheetContext: sheetContext,
                value: 'name_desc',
                label: 'Item name: Z to A',
                icon: Icons.sort_by_alpha_rounded,
              ),
              _buildSortOptionTile(
                sheetContext: sheetContext,
                value: 'qty_desc',
                label: 'Quantity moved: Largest first',
                icon: Icons.trending_up_rounded,
              ),
              _buildSortOptionTile(
                sheetContext: sheetContext,
                value: 'qty_asc',
                label: 'Quantity moved: Smallest first',
                icon: Icons.trending_down_rounded,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSortOptionTile({
    required BuildContext sheetContext,
    required String value,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _historySort == value;
    return InkWell(
      onTap: () {
        Navigator.pop(sheetContext);
        setState(() => _historySort = value);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.brandPrimary.withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: AppColors.brandPrimary.withValues(alpha: 0.3))
              : Border.all(color: AppColors.borderPrimary),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected
                  ? AppColors.brandPrimary
                  : AppColors.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? AppColors.brandPrimary
                      : AppColors.textPrimary,
                ),
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle_rounded,
                size: 18,
                color: AppColors.brandPrimary,
              ),
          ],
        ),
      ),
    );
  }

  void _showHistoryDateFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.bgPrimary,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderPrimary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Icon(Icons.calendar_month_rounded,
                      color: AppColors.brandPrimary),
                  SizedBox(width: 8),
                  Text(
                    'FILTER BY DATE RANGE',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: AppColors.brandText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildDatePresetTile(
                sheetContext: sheetContext,
                value: 'all',
                label: 'All time (No date filter)',
                icon: Icons.all_inclusive_rounded,
              ),
              _buildDatePresetTile(
                sheetContext: sheetContext,
                value: 'today',
                label: 'Today',
                icon: Icons.today_rounded,
              ),
              _buildDatePresetTile(
                sheetContext: sheetContext,
                value: '7d',
                label: 'Last 7 days',
                icon: Icons.date_range_rounded,
              ),
              _buildDatePresetTile(
                sheetContext: sheetContext,
                value: '30d',
                label: 'Last 30 days',
                icon: Icons.calendar_view_month_rounded,
              ),
              _buildDatePresetTile(
                sheetContext: sheetContext,
                value: 'month',
                label: 'This month',
                icon: Icons.calendar_today_rounded,
              ),
              InkWell(
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickCustomDateRange();
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: _historyDatePreset == 'custom'
                        ? AppColors.brandPrimary.withValues(alpha: 0.08)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _historyDatePreset == 'custom'
                          ? AppColors.brandPrimary.withValues(alpha: 0.3)
                          : AppColors.borderPrimary,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.edit_calendar_rounded,
                        size: 20,
                        color: _historyDatePreset == 'custom'
                            ? AppColors.brandPrimary
                            : AppColors.brandText,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _historyDatePreset == 'custom' &&
                                  _historyDateRange != null
                              ? 'Custom: ${_shortDate(_historyDateRange!.start)} – ${_shortDate(_historyDateRange!.end)}, ${_historyDateRange!.end.year}'
                              : 'Select custom date range...',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: _historyDatePreset == 'custom'
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: _historyDatePreset == 'custom'
                                ? AppColors.brandPrimary
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 14,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDatePresetTile({
    required BuildContext sheetContext,
    required String value,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _historyDatePreset == value;
    return InkWell(
      onTap: () {
        Navigator.pop(sheetContext);
        setState(() {
          _historyDatePreset = value;
          _historyDateRange = null;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.brandPrimary.withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: AppColors.brandPrimary.withValues(alpha: 0.3))
              : Border.all(color: AppColors.borderPrimary),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected
                  ? AppColors.brandPrimary
                  : AppColors.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? AppColors.brandPrimary
                      : AppColors.textPrimary,
                ),
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle_rounded,
                size: 18,
                color: AppColors.brandPrimary,
              ),
          ],
        ),
      ),
    );
  }

  void _showGenerateReportDialog(
      List<live.InventoryTransactionRecord> currentTransactions) {
    String reportPeriod =
        _historyDatePreset == 'all' ? 'this_week' : _historyDatePreset;
    DateTimeRange? reportCustomRange = _historyDateRange;
    String reportCategory = _historyFilter;
    final midwifeNameController = TextEditingController(
      text: _liveContext?.displayName ?? 'Midwife-in-Charge',
    );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (dialogContext, setModalState) {
            final periodLabel = MidwifeInventoryReportService.formatPeriodLabel(
              reportPeriod,
              range: reportPeriod == 'custom'
                  ? reportCustomRange
                  : MidwifeInventoryReportService.resolveDateRange(
                      reportPeriod),
            );

            final resolvedRange = reportPeriod == 'custom'
                ? reportCustomRange
                : MidwifeInventoryReportService.resolveDateRange(
                    reportPeriod);

            final reportTransactions = _transactions.where((t) {
              final type = t.transactionType.toLowerCase();
              final typeMatch = switch (reportCategory) {
                'dispense' => type == 'dispense' || t.isAdministration,
                'replenishment' =>
                  type == 'receipt' ||
                      (type == 'transfer' &&
                          (t.doseQuantity ?? t.quantity) > 0),
                'unusable' =>
                  type == 'expiry_disposal' ||
                      type == 'discard' ||
                      t.referenceType.toLowerCase().contains('unusable') ||
                      t.referenceType.toLowerCase().contains('discard') ||
                      t.referenceType.toLowerCase().contains('expired'),
                'transfer' => type == 'transfer',
                'adjustment' => type == 'adjustment',
                _ => true,
              };
              if (!typeMatch) return false;

              if (resolvedRange != null) {
                if (t.loggedAt.isBefore(resolvedRange.start) ||
                    t.loggedAt.isAfter(resolvedRange.end)) {
                  return false;
                }
              }
              return true;
            }).toList()
              ..sort((a, b) => b.loggedAt.compareTo(a.loggedAt));

            return Container(
              decoration: const BoxDecoration(
                color: AppColors.bgPrimary,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom:
                    MediaQuery.of(dialogContext).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.borderPrimary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.brandPrimary
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.picture_as_pdf_rounded,
                            color: AppColors.brandPrimary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'GENERATE INVENTORY REPORT',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                  color: AppColors.brandText,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Official BHC Stock Movement Audit Report',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'REPORTING PERIOD',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildReportOptionChip(
                          label: 'This Week',
                          isSelected: reportPeriod == 'this_week',
                          onTap: () => setModalState(
                              () => reportPeriod = 'this_week'),
                        ),
                        _buildReportOptionChip(
                          label: 'Last Week',
                          isSelected: reportPeriod == 'last_week',
                          onTap: () => setModalState(
                              () => reportPeriod = 'last_week'),
                        ),
                        _buildReportOptionChip(
                          label: 'This Month',
                          isSelected: reportPeriod == 'this_month',
                          onTap: () => setModalState(
                              () => reportPeriod = 'this_month'),
                        ),
                        _buildReportOptionChip(
                          label: 'Last Month',
                          isSelected: reportPeriod == 'last_month',
                          onTap: () => setModalState(
                              () => reportPeriod = 'last_month'),
                        ),
                        _buildReportOptionChip(
                          label: 'Today',
                          isSelected: reportPeriod == 'today',
                          onTap: () =>
                              setModalState(() => reportPeriod = 'today'),
                        ),
                        _buildReportOptionChip(
                          label: 'All Time',
                          isSelected: reportPeriod == 'all',
                          onTap: () =>
                              setModalState(() => reportPeriod = 'all'),
                        ),
                        _buildReportOptionChip(
                          label: reportPeriod == 'custom' &&
                                  reportCustomRange != null
                              ? 'Custom: ${_shortDate(reportCustomRange!.start)} – ${_shortDate(reportCustomRange!.end)}'
                              : 'Pick Date Range...',
                          isSelected: reportPeriod == 'custom',
                          icon: Icons.calendar_month_rounded,
                          onTap: () async {
                            final now = DateTime.now();
                            final picked = await showBrandedDateRangePicker(
                              context: context,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(now.year + 2),
                              initialDateRange: reportCustomRange ??
                                  DateTimeRange(
                                    start: now.subtract(
                                        const Duration(days: 30)),
                                    end: now,
                                  ),
                              helpText: 'SELECT REPORT PERIOD',
                            );
                            if (picked != null) {
                              setModalState(() {
                                reportPeriod = 'custom';
                                reportCustomRange = picked;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'MOVEMENT CATEGORY',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildReportOptionChip(
                          label: 'All Movements',
                          isSelected: reportCategory == 'all',
                          onTap: () =>
                              setModalState(() => reportCategory = 'all'),
                        ),
                        _buildReportOptionChip(
                          label: 'Dispensed Only',
                          isSelected: reportCategory == 'dispense',
                          onTap: () => setModalState(
                              () => reportCategory = 'dispense'),
                        ),
                        _buildReportOptionChip(
                          label: 'Replenishments Only',
                          isSelected: reportCategory == 'replenishment',
                          onTap: () => setModalState(
                              () => reportCategory = 'replenishment'),
                        ),
                        _buildReportOptionChip(
                          label: 'Expired & Discards',
                          isSelected: reportCategory == 'unusable',
                          onTap: () => setModalState(
                              () => reportCategory = 'unusable'),
                        ),
                        _buildReportOptionChip(
                          label: 'Transfers',
                          isSelected: reportCategory == 'transfer',
                          onTap: () => setModalState(
                              () => reportCategory = 'transfer'),
                        ),
                        _buildReportOptionChip(
                          label: 'Adjustments',
                          isSelected: reportCategory == 'adjustment',
                          onTap: () => setModalState(
                              () => reportCategory = 'adjustment'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'PREPARED BY (MIDWIFE NAME)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    AppInputField(
                      controller: midwifeNameController,
                      hintText: 'Enter Midwife-in-Charge Name',
                      leadingIcon: Icons.person_outline_rounded,
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.bgSecondary,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.borderPrimary),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded,
                              size: 16, color: AppColors.brandPrimary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Report will include ${reportTransactions.length} movement records for $periodLabel.',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textSecondary,
                              side: const BorderSide(
                                  color: AppColors.borderPrimary),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Cancel',
                                style:
                                    TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              Navigator.pop(dialogContext);
                              final facilityName =
                                  _liveContext?.facilityName ??
                                      'Barangay Health Center';
                              final midwifeName = midwifeNameController
                                      .text
                                      .trim()
                                      .isEmpty
                                  ? (_liveContext?.displayName ??
                                      'Midwife-in-Charge')
                                  : midwifeNameController.text.trim();

                              await MidwifeInventoryReportService
                                  .previewAndPrintReport(
                                context: context,
                                facilityName: facilityName,
                                midwifeName: midwifeName,
                                periodLabel: periodLabel,
                                transactions: reportTransactions,
                                categoryFilter: reportCategory,
                              );
                            },
                            icon: const Icon(Icons.print_rounded, size: 18),
                            label: const Text('Generate PDF & Print'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.brandPrimary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              textStyle: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildReportOptionChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.brandPrimary : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? AppColors.brandPrimary
                : AppColors.borderPrimary,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 13,
                color: isSelected ? Colors.white : AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight:
                    isSelected ? FontWeight.w700 : FontWeight.w500,
                color:
                    isSelected ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryTab() {
    final query = _historySearchController.text.trim().toLowerCase();

    final DateTime now = DateTime.now();
    final DateTime todayStart = DateTime(now.year, now.month, now.day);
    final DateTime todayEnd =
        DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

    DateTime? filterStart;
    DateTime? filterEnd;

    switch (_historyDatePreset) {
      case 'today':
        filterStart = todayStart;
        filterEnd = todayEnd;
        break;
      case '7d':
        filterStart = todayStart.subtract(const Duration(days: 7));
        filterEnd = todayEnd;
        break;
      case '30d':
        filterStart = todayStart.subtract(const Duration(days: 30));
        filterEnd = todayEnd;
        break;
      case 'month':
        filterStart = DateTime(now.year, now.month, 1);
        filterEnd = todayEnd;
        break;
      case 'custom':
        if (_historyDateRange != null) {
          filterStart = DateTime(
            _historyDateRange!.start.year,
            _historyDateRange!.start.month,
            _historyDateRange!.start.day,
          );
          filterEnd = DateTime(
            _historyDateRange!.end.year,
            _historyDateRange!.end.month,
            _historyDateRange!.end.day,
            23,
            59,
            59,
            999,
          );
        }
        break;
      case 'all':
      default:
        filterStart = null;
        filterEnd = null;
        break;
    }

    final filteredTransactions = _transactions.where((t) {
      final type = t.transactionType.toLowerCase();
      final typeMatch = switch (_historyFilter) {
        'dispense' => type == 'dispense' || t.isAdministration,
        'replenishment' =>
          type == 'receipt' ||
              (type == 'transfer' && (t.doseQuantity ?? t.quantity) > 0),
        'unusable' =>
          type == 'expiry_disposal' ||
              type == 'discard' ||
              t.referenceType.toLowerCase().contains('unusable') ||
              t.referenceType.toLowerCase().contains('discard') ||
              t.referenceType.toLowerCase().contains('expired'),
        'transfer' => type == 'transfer',
        'adjustment' => type == 'adjustment',
        _ => true,
      };
      if (!typeMatch) return false;

      if (filterStart != null && t.loggedAt.isBefore(filterStart)) {
        return false;
      }
      if (filterEnd != null && t.loggedAt.isAfter(filterEnd)) {
        return false;
      }

      if (query.isEmpty) return true;
      return t.itemName.toLowerCase().contains(query) ||
          t.batchNumber.toLowerCase().contains(query) ||
          (t.patientNumber ?? '').toLowerCase().contains(query) ||
          (t.performedByName ?? '').toLowerCase().contains(query) ||
          t.referenceType.toLowerCase().contains(query) ||
          t.notes.toLowerCase().contains(query) ||
          t.transactionType.toLowerCase().contains(query);
    }).toList();

    filteredTransactions.sort((a, b) {
      return switch (_historySort) {
        'oldest' => a.loggedAt.compareTo(b.loggedAt),
        'name_asc' =>
          a.itemName.toLowerCase().compareTo(b.itemName.toLowerCase()),
        'name_desc' =>
          b.itemName.toLowerCase().compareTo(a.itemName.toLowerCase()),
        'qty_desc' => b.dosesMoved.compareTo(a.dosesMoved),
        'qty_asc' => a.dosesMoved.compareTo(b.dosesMoved),
        'newest' || _ => b.loggedAt.compareTo(a.loggedAt),
      };
    });

    final totalMovements = _transactions.length;
    final dispensedCount = _transactions
        .where(
          (t) =>
              t.transactionType.toLowerCase() == 'dispense' ||
              t.isAdministration,
        )
        .length;
    final replenishedCount = _transactions
        .where(
          (t) =>
              t.transactionType.toLowerCase() == 'receipt' ||
              (t.transactionType.toLowerCase() == 'transfer' &&
                  (t.doseQuantity ?? t.quantity) > 0),
        )
        .length;
    final unusableCount = _transactions
        .where(
          (t) =>
              t.transactionType.toLowerCase() == 'expiry_disposal' ||
              t.transactionType.toLowerCase() == 'discard',
        )
        .length;

    final hasActiveFilter = _historyFilter != 'all' ||
        _historyDatePreset != 'all' ||
        _historySort != 'newest' ||
        _historySearchController.text.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'STOCK MOVEMENT & AUDIT TRAIL',
                    style: TextStyle(
                      color: AppColors.brandText,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'Complete transparent ledger of all dispensing, replenishments, expirations, discards, and adjustments for your health center.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () =>
                  _showGenerateReportDialog(filteredTransactions),
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 15),
              label: const Text('Generate Report'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandPrimary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                textStyle: const TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildHistoryTransparencyBanner(),
        const SizedBox(height: 16),
        _buildHistorySummaryCards(
          total: totalMovements,
          dispensed: dispensedCount,
          replenished: replenishedCount,
          unusable: unusableCount,
        ),
        const SizedBox(height: 18),
        AppInputField(
          controller: _historySearchController,
          hintText: 'Search item, batch, patient ID, performer, or reason',
          leadingIcon: Icons.search_rounded,
          trailingIcon: _historySearchController.text.isEmpty
              ? null
              : Icons.close_rounded,
          onTrailingTap: () {
            _historySearchController.clear();
            setState(() {});
          },
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        // Sort & Date Selection Action Bar
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: _showHistoryDateFilterSheet,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: _historyDatePreset != 'all'
                        ? AppColors.brandPrimary.withValues(alpha: 0.08)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _historyDatePreset != 'all'
                          ? AppColors.brandPrimary
                          : AppColors.borderPrimary,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_month_rounded,
                        size: 16,
                        color: _historyDatePreset != 'all'
                            ? AppColors.brandPrimary
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _historyDateLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: _historyDatePreset != 'all'
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: _historyDatePreset != 'all'
                                ? AppColors.brandPrimary
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.arrow_drop_down_rounded,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                onTap: _showHistorySortSheet,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: _historySort != 'newest'
                        ? AppColors.brandPrimary.withValues(alpha: 0.08)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _historySort != 'newest'
                          ? AppColors.brandPrimary
                          : AppColors.borderPrimary,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.sort_rounded,
                        size: 16,
                        color: _historySort != 'newest'
                            ? AppColors.brandPrimary
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _historySortLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: _historySort != 'newest'
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: _historySort != 'newest'
                                ? AppColors.brandPrimary
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.arrow_drop_down_rounded,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Quick Category Filters
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildHistoryFilterChip(
                value: 'all',
                label: 'All types',
                icon: Icons.list_alt_rounded,
              ),
              const SizedBox(width: 8),
              _buildHistoryFilterChip(
                value: 'dispense',
                label: 'Dispensed',
                icon: Icons.vaccines_rounded,
                color: AppColors.brandPrimary,
              ),
              const SizedBox(width: 8),
              _buildHistoryFilterChip(
                value: 'replenishment',
                label: 'Replenishments',
                icon: Icons.inventory_2_outlined,
                color: AppColors.success,
              ),
              const SizedBox(width: 8),
              _buildHistoryFilterChip(
                value: 'unusable',
                label: 'Expired & Discards',
                icon: Icons.event_busy_outlined,
                color: AppColors.error,
              ),
              const SizedBox(width: 8),
              _buildHistoryFilterChip(
                value: 'transfer',
                label: 'Transfers',
                icon: Icons.local_shipping_outlined,
                color: AppColors.warning,
              ),
              const SizedBox(width: 8),
              _buildHistoryFilterChip(
                value: 'adjustment',
                label: 'Adjustments',
                icon: Icons.tune_rounded,
                color: const Color(0xFF8B5CF6),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.bgSecondary,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.brandPrimary.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.history_rounded,
                size: 16,
                color: AppColors.brandPrimary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Showing ${filteredTransactions.length} of $totalMovements logged movement${totalMovements == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (hasActiveFilter)
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _historyFilter = 'all';
                      _historySort = 'newest';
                      _historyDatePreset = 'all';
                      _historyDateRange = null;
                      _historySearchController.clear();
                    });
                  },
                  child: const Text(
                    'Reset filters',
                    style: TextStyle(
                      color: AppColors.brandPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (filteredTransactions.isEmpty)
          _buildNoHistoryResults()
        else
          ...filteredTransactions.map(
            (transaction) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildHistoryMovementCard(transaction),
            ),
          ),
      ],
    );
  }

  Widget _buildHistoryTransparencyBanner() {
    final facilityName =
        _liveContext?.facilityName ?? 'Barangay Health Center';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              color: AppColors.success,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Audit Trail Active • $facilityName',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Every dose dispensed, shipment received, or expired item is immutably timestamped with the responsible staff account and running batch balance.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistorySummaryCards({
    required int total,
    required int dispensed,
    required int replenished,
    required int unusable,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderPrimary),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _HistoryMetricItem(
              label: 'Total Logs',
              value: '$total',
              icon: Icons.receipt_long_rounded,
              color: AppColors.brandPrimary,
              isActive: _historyFilter == 'all',
              onTap: () => setState(() => _historyFilter = 'all'),
            ),
          ),
          Container(width: 1, height: 36, color: AppColors.borderPrimary),
          Expanded(
            child: _HistoryMetricItem(
              label: 'Dispensed',
              value: '$dispensed',
              icon: Icons.vaccines_rounded,
              color: AppColors.info,
              isActive: _historyFilter == 'dispense',
              onTap: () => setState(() => _historyFilter = 'dispense'),
            ),
          ),
          Container(width: 1, height: 36, color: AppColors.borderPrimary),
          Expanded(
            child: _HistoryMetricItem(
              label: 'Replenished',
              value: '$replenished',
              icon: Icons.inventory_2_outlined,
              color: AppColors.success,
              isActive: _historyFilter == 'replenishment',
              onTap: () => setState(() => _historyFilter = 'replenishment'),
            ),
          ),
          Container(width: 1, height: 36, color: AppColors.borderPrimary),
          Expanded(
            child: _HistoryMetricItem(
              label: 'Expired/Loss',
              value: '$unusable',
              icon: Icons.event_busy_outlined,
              color: AppColors.error,
              isActive: _historyFilter == 'unusable',
              onTap: () => setState(() => _historyFilter = 'unusable'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryFilterChip({
    required String value,
    required String label,
    required IconData icon,
    Color color = AppColors.brandPrimary,
  }) {
    final selected = _historyFilter == value;
    final selectedForeground =
        color == AppColors.warning ? AppColors.textPrimary : Colors.white;
    return FilterChip(
      selected: selected,
      onSelected: (_) => setState(() => _historyFilter = value),
      avatar: Icon(
        icon,
        size: 16,
        color: selected ? selectedForeground : color,
      ),
      label: Text(label),
      labelStyle: TextStyle(
        color: selected ? selectedForeground : AppColors.textPrimary,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
      selectedColor: color,
      backgroundColor: Colors.white,
      side: BorderSide(
        color: selected ? color : color.withValues(alpha: 0.25),
      ),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    );
  }

  Widget _buildHistoryMovementCard(live.InventoryTransactionRecord row) {
    final type = row.transactionType.toLowerCase();
    final isWaste = type == 'expiry_disposal' || type == 'discard';
    final isReplenishment = type == 'receipt' ||
        (type == 'transfer' && (row.doseQuantity ?? row.quantity) > 0);
    final isDispense = type == 'dispense' || row.isAdministration;
    final isOutbound =
        type == 'transfer' && (row.doseQuantity ?? row.quantity) < 0;
    final isIn = (row.doseQuantity ?? row.quantity) > 0;

    final Color accentColor = isWaste
        ? AppColors.error
        : isReplenishment
            ? AppColors.success
            : isOutbound
                ? AppColors.warning
                : isDispense
                    ? AppColors.brandPrimary
                    : type == 'adjustment'
                        ? const Color(0xFF8B5CF6)
                        : (isIn ? AppColors.success : AppColors.brandPrimary);

    final IconData categoryIcon = switch (type) {
      'receipt' => Icons.add_circle_outline_rounded,
      'expiry_disposal' => Icons.event_busy_outlined,
      'discard' => Icons.delete_outline_rounded,
      'adjustment' => Icons.tune_rounded,
      'transfer' =>
        isOutbound ? Icons.outbound_rounded : Icons.south_west_rounded,
      _ when row.isAdministration => Icons.vaccines_rounded,
      _ when isDispense => Icons.medication_rounded,
      _ => isIn
          ? Icons.add_circle_outline_rounded
          : Icons.remove_circle_outline_rounded,
    };

    final String headline = switch (type) {
      'receipt' => 'Stock Replenishment Received',
      'discard' => 'Open Vial Discarded',
      'expiry_disposal' => 'Unusable / Expired Stock Written Off',
      'adjustment' => 'Stock Ledger Adjusted',
      'transfer' => isOutbound
          ? 'Stock Transferred Outward'
          : 'Stock Transferred Inward',
      _ when row.isAdministration => 'Dose Administered to Patient',
      _ => isIn ? 'Stock Added' : 'Stock Dispensed',
    };

    final doses = row.dosesMoved;
    final sign = isIn ? '+' : '−';
    final String measureText = row.isMultiDose
        ? '$sign$doses ${doses == 1 ? 'dose' : 'doses'}'
        : '$sign${row.quantity.abs()} ${row.unit.toLowerCase()}';

    return InkWell(
      onTap: () => _showDoseTraceSheet(
        itemId: row.itemId,
        itemName: row.itemName,
        batchId: row.batchId,
        batchNumber: row.batchNumber,
      ),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(categoryIcon, color: accentColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        headline,
                        style: const TextStyle(
                          color: AppColors.brandText,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _dateTimeLabel(row.loggedAt),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    measureText,
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.borderPrimary),
            const SizedBox(height: 12),
            // Item & Batch info
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.itemName,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        row.batchExpiration == null
                            ? 'Batch ${row.batchNumber}'
                            : 'Batch ${row.batchNumber} • Exp: ${_shortDate(row.batchExpiration!)}, ${row.batchExpiration!.year}',
                        style: const TextStyle(
                          color: AppColors.brandText,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Audit metadata grid
            if (row.resultingQuantityRemaining != null ||
                (row.resultingOpenVialDoses != null && row.isMultiDose))
              _historyDetailRow(
                icon: Icons.warehouse_outlined,
                label: 'Resulting balance',
                value:
                    '${row.resultingQuantityRemaining ?? 0} ${row.unit.toLowerCase()}'
                    '${row.isMultiDose && row.resultingOpenVialDoses != null ? ' (${row.resultingOpenVialDoses} open doses left)' : ''}',
                emphasise: true,
              ),
            if (row.hasPatient)
              _historyDetailRow(
                icon: Icons.badge_outlined,
                label: 'Recipient',
                value:
                    '${row.patientLabel} (${row.patientKind == 'child' ? 'Child' : 'Mother'})',
                emphasise: true,
                badgeColor: AppColors.brandPrimary,
              ),
            if (row.performedByName != null)
              _historyDetailRow(
                icon: Icons.person_outline_rounded,
                label: 'Handled by',
                value:
                    '${row.performedByName}${row.performedByRole != null ? ' • ${_displayRole(row.performedByRole!)}' : ''}',
              ),
            if (row.referenceType.isNotEmpty)
              _historyDetailRow(
                icon: Icons.receipt_outlined,
                label: 'Reference / Reason',
                value: row.referenceType,
              ),
            if (row.notes.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.bgSecondary,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.borderPrimary.withValues(alpha: 0.6),
                  ),
                ),
                child: Text(
                  'Note: "${row.notes}"',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'Tap to inspect batch trace',
                  style: TextStyle(
                    color: AppColors.brandPrimary.withValues(alpha: 0.9),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 11,
                  color: AppColors.brandPrimary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _historyDetailRow({
    required IconData icon,
    required String label,
    required String value,
    bool emphasise = false,
    Color? badgeColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: emphasise ? FontWeight.w700 : FontWeight.w500,
                color: badgeColor ??
                    (emphasise
                        ? AppColors.brandPrimary
                        : AppColors.textPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoHistoryResults() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 42,
            color: AppColors.textSecondary.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 10),
          const Text(
            'No matching inventory records found',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Try adjusting your search terms or filter selection.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _historyFilter = 'all';
                _historySort = 'newest';
                _historyDatePreset = 'all';
                _historyDateRange = null;
                _historySearchController.clear();
              });
            },
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Reset filters'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.brandPrimary,
              side: const BorderSide(color: AppColors.brandPrimary),
            ),
          ),
        ],
      ),
    );
  }

  String _displayRole(String role) {
    return switch (role.toLowerCase()) {
      'midwife' => 'Midwife',
      'admin' => 'RHU Admin',
      'superadmin' => 'MHO Officer',
      'nurse' => 'Nurse',
      'doctor' => 'Physician',
      _ => role,
    };
  }

  // ---------------------------------------------------------------------
  // Dose trace
  //
  // The question this answers is the one a midwife is asked at an audit and
  // could not previously answer from the phone: this vial says 3 doses left of
  // 10 — where did the other 7 go? Each row names the patient, the person who
  // drew the dose, the minute it happened and the level the vial was left at,
  // so the physical vial on the shelf can be reconciled against the record
  // without opening the portal.
  // ---------------------------------------------------------------------

  /// "4h 20m", "45m", "2d 3h" — a duration a midwife can act on.
  ///
  /// Whole hours are not enough resolution here: a 6-hour vial with 40 minutes
  /// on it rounds to "0 hours", which reads as already gone.
  String _durationLabel(Duration d) {
    final abs = d.isNegative ? -d : d;
    if (abs.inDays >= 1) {
      final hours = abs.inHours % 24;
      return hours == 0 ? '${abs.inDays}d' : '${abs.inDays}d ${hours}h';
    }
    if (abs.inHours >= 1) {
      final minutes = abs.inMinutes % 60;
      return minutes == 0 ? '${abs.inHours}h' : '${abs.inHours}h ${minutes}m';
    }
    if (abs.inMinutes >= 1) return '${abs.inMinutes}m';
    return 'under a minute';
  }

  /// Discards the doses left in an expired open vial, from the BHC.
  ///
  /// The wasted doses are recorded against this facility, which is the point:
  /// the DOH wastage rate is only meaningful if spoilage is booked where it
  /// happened rather than quietly left on the shelf as usable stock.
  Future<void> _confirmDiscardOpenVial(
    InventoryItem item,
    live.InventoryBatchRecord batch,
  ) async {
    final contextRecord = _liveContext;
    if (contextRecord == null) {
      AppSnackbar.error(
        context,
        'Your health center session could not be read, so the discard was not recorded.',
      );
      return;
    }

    final doses = batch.dosesRemainingInOpenVial;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ConfirmationDialogBox(
        title: 'Discard $doses open dose${doses == 1 ? '' : 's'}?',
        subtitle:
            'This ${item.name} vial (Batch ${batch.batchNumber}) passed its '
            '${item.openVialShelfHours}-hour open-vial limit, so the remaining '
            '$doses dose${doses == 1 ? '' : 's'} can no longer be given. '
            'They will be recorded as wastage for this health center and the '
            'vial closed. This cannot be undone.',
        confirmText: 'Discard doses',
        cancelText: 'Keep for now',
        accentColor: AppColors.error,
        onCancel: () => Navigator.of(dialogContext).pop(false),
        onConfirm: () => Navigator.of(dialogContext).pop(true),
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final result = await _repository.discardOpenVialDoses(
        context: contextRecord,
        batchId: batch.batchId,
        reason: 'Past the ${item.openVialShelfHours}h open-vial limit',
      );
      if (!mounted) return;

      final discarded = result['doses_discarded'] ?? doses;
      AppSnackbar.success(
        context,
        '$discarded dose(s) of ${item.name} discarded from Batch '
        '${batch.batchNumber} and recorded as wastage.',
      );
      await _loadLiveInventory(refresh: true);
    } on live.InventoryWorkflowUnavailableException catch (error) {
      if (!mounted) return;
      AppSnackbar.warning(context, error.message);
    } on live.InventoryRepositoryException catch (error) {
      if (!mounted) return;
      AppSnackbar.error(context, error.message);
    }
  }

  /// Opens the trace for the batch behind an activity tile, when it has one.
  VoidCallback? _traceTapFor(InventoryEvent event) {
    final row = event.transaction;
    if (row == null) return null;
    return () => _showDoseTraceSheet(
          itemId: row.itemId,
          itemName: row.itemName,
          batchId: row.batchId,
          batchNumber: row.batchNumber,
        );
  }

  /// Ledger rows for one catalogue item, newest first, optionally narrowed to a
  /// single batch.
  List<live.InventoryTransactionRecord> _doseTraceFor({
    required int itemId,
    int? batchId,
  }) {
    return _transactions
        .where(
          (t) =>
              t.itemId == itemId && (batchId == null || t.batchId == batchId),
        )
        .toList()
      ..sort((a, b) => b.loggedAt.compareTo(a.loggedAt));
  }

  void _showDoseTraceSheet({
    required int itemId,
    required String itemName,
    int? batchId,
    String? batchNumber,
  }) {
    final rows = _doseTraceFor(itemId: itemId, batchId: batchId);

    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          final maxHeight = MediaQuery.of(sheetContext).size.height * 0.86;
          final administered =
              rows.where((r) => r.isAdministration).toList();

          return Container(
            constraints: BoxConstraints(maxHeight: maxHeight),
            decoration: const BoxDecoration(
              color: AppColors.bgPrimary,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderPrimary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.brandPrimary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.fact_check_outlined,
                          size: 18,
                          color: AppColors.brandPrimary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              // Only a batch some of which has actually gone
                              // into a patient has a dose trail. One that has
                              // only been received and moved has a delivery
                              // history, and calling that DOSE TRACE sends the
                              // midwife looking for doses that were never given.
                              administered.isEmpty
                                  ? 'BATCH HISTORY'
                                  : 'DOSE TRACE',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              batchNumber == null
                                  ? itemName
                                  : '$itemName • Batch $batchNumber',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppColors.brandText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close_rounded, size: 20),
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                ),
                if (rows.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Row(
                      children: [
                        _doseTraceStat(
                          label: 'Movements',
                          value: '${rows.length}',
                        ),
                        // Both of these can only be zero until a dose has been
                        // given from this batch. Showing "0 doses given, 0 named
                        // patients" on a delivery reads as something missing
                        // rather than something that has not happened yet.
                        if (administered.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          _doseTraceStat(
                            label: 'Doses given',
                            value:
                                '${administered.fold<int>(0, (sum, r) => sum + r.dosesMoved)}',
                          ),
                          const SizedBox(width: 8),
                          _doseTraceStat(
                            label: 'Named patients',
                            value:
                                '${administered.where((r) => r.hasPatient).length}',
                          ),
                        ],
                      ],
                    ),
                  ),
                Flexible(
                  child: rows.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.fromLTRB(20, 8, 20, 40),
                          child: Text(
                            'Nothing has moved for this item at this BHC yet. '
                            'Receipts, doses given and discards all appear here '
                            'as they happen.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          itemCount: rows.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, index) =>
                              _buildDoseTraceRow(rows[index]),
                        ),
                ),
                if (rows.any((r) => r.hasPatient))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.privacy_tip_outlined,
                          size: 13,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Patients are shown by chart number only. Open the '
                            'patient record to see who a number belongs to.',
                            style: const TextStyle(
                              fontSize: 10.5,
                              height: 1.35,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _doseTraceStat({required String label, required String value}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderPrimary),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.brandPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDoseTraceRow(live.InventoryTransactionRecord row) {
    final type = row.transactionType.toLowerCase();
    final isWaste = type == 'expiry_disposal' || type == 'discard';
    final isIn = (row.doseQuantity ?? row.quantity) > 0;
    final accent = isWaste
        ? AppColors.error
        : isIn
            ? AppColors.success
            : AppColors.brandPrimary;

    final headline = switch (type) {
      'receipt' => 'Received into stock',
      'discard' => 'Open vial discarded',
      'expiry_disposal' => 'Written off as unusable',
      'adjustment' => 'Stock adjusted',
      'transfer' => isIn ? 'Transferred in' : 'Transferred out',
      _ when row.isAdministration => 'Dose administered',
      _ => isIn ? 'Stock added' : 'Stock dispensed',
    };

    // Only a multi-dose presentation has an "of N" to report; on a single-dose
    // item the unit and the dose are the same thing and saying so twice reads
    // as a second, different number.
    final doseText = row.isMultiDose
        ? '${row.dosesMoved} ${row.dosesMoved == 1 ? 'dose' : 'doses'} of ${row.dosesPerUnit} per ${row.unit.toLowerCase()}'
        : '${row.quantity.abs()} ${row.unit.toLowerCase()}';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderPrimary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isWaste
                      ? Icons.delete_outline_rounded
                      : row.isAdministration
                          ? Icons.vaccines_rounded
                          : isIn
                              ? Icons.south_west_rounded
                              : Icons.north_east_rounded,
                  size: 15,
                  color: accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.brandText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${isIn ? '+' : '−'}$doseText',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _dateTimeLabel(row.loggedAt),
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _doseTraceField(
            icon: Icons.inventory_2_outlined,
            label: 'Batch',
            value: row.batchExpiration == null
                ? row.batchNumber
                : '${row.batchNumber} · expires ${_shortDate(row.batchExpiration!)}, '
                    '${row.batchExpiration!.year}',
          ),
          // Only an administration has a recipient. A delivery from the RHU
          // does not, and a row reading "Given to: not a patient movement" is
          // answering a question nobody asked -- the movement type at the top
          // of the card already says it arrived.
          if (row.isAdministration)
            _doseTraceField(
              icon: Icons.badge_outlined,
              label: 'Given to',
              // The chart number, never the name — see the note at the foot of
              // this sheet and the comment on inventory_dose_ledger.
              value: row.patientLabel,
              // An administration with no resolvable patient is a genuine gap
              // in the trail and is labelled as one.
              missingText: 'Not linked to a patient record',
              emphasise: row.hasPatient,
            ),
          _doseTraceField(
            icon: Icons.person_outline_rounded,
            label: row.isAdministration ? 'Given by' : 'Recorded by',
            value: row.performedByName,
            missingText: 'System / not recorded',
          ),
          if (row.isMultiDose)
            _doseTraceField(
              icon: Icons.colorize_rounded,
              label: 'Left in vial',
              value: row.resultingOpenVialDoses == null
                  ? null
                  : '${row.resultingOpenVialDoses} '
                      '${row.resultingOpenVialDoses == 1 ? 'dose' : 'doses'}',
              missingText: 'Not recorded for this movement',
            ),
          if (row.resultingQuantityRemaining != null)
            _doseTraceField(
              icon: Icons.warehouse_outlined,
              label: 'Sealed left',
              value: '${row.resultingQuantityRemaining} '
                  '${row.unit.toLowerCase()}',
            ),
          if (row.notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              row.notes,
              style: const TextStyle(
                fontSize: 10.5,
                fontStyle: FontStyle.italic,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _doseTraceField({
    required IconData icon,
    required String label,
    required String? value,
    String missingText = '—',
    bool emphasise = false,
  }) {
    final missing = value == null || value.isEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              missing ? missingText : value,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: emphasise ? FontWeight.w700 : FontWeight.w500,
                fontStyle: missing ? FontStyle.italic : FontStyle.normal,
                color: missing
                    ? AppColors.textSecondary
                    : emphasise
                        ? AppColors.brandPrimary
                        : AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDispenseSheet([InventoryItem? suggestedItem]) {
    unawaited(
      _showStockActivitySheet(
        live.InventoryStockActivityType.dispense,
        suggestedItem,
      ),
    );
  }

  void _showUnusableSheet([InventoryItem? suggestedItem]) {
    unawaited(
      _showStockActivitySheet(
        live.InventoryStockActivityType.unusable,
        suggestedItem,
      ),
    );
  }

  Future<void> _showStockActivitySheet(
    live.InventoryStockActivityType activityType,
    InventoryItem? suggestedItem,
  ) async {
    final isDispense = activityType == live.InventoryStockActivityType.dispense;
    final availableItems = isDispense ? _dispensableItems : _reportableItems;
    if (availableItems.isEmpty) {
      AppSnackbar.warning(
        context,
        isDispense
            ? 'No usable stock is available to dispense.'
            : 'No batch with remaining stock is available to report.',
      );
      return;
    }

    InventoryItem? selectedItem = suggestedItem != null &&
            availableItems.any((item) => item.itemId == suggestedItem.itemId)
        ? suggestedItem
        : null;
    live.InventoryBatchRecord? selectedBatch;
    String? selectedReason;
    String? itemError;
    String? batchError;
    String? quantityError;
    String? reasonError;
    String? notesError;
    bool isSubmitting = false;
    String? operationKey;

    // This sheet is taller than the screen. Setting an errorText on a field that
    // has scrolled out of view made Submit look like it did nothing at all, so
    // the first field with a problem is brought back into view.
    final itemFieldKey = GlobalKey();
    final batchFieldKey = GlobalKey();
    final quantityFieldKey = GlobalKey();
    final reasonFieldKey = GlobalKey();
    final notesFieldKey = GlobalKey();

    const dispenseReasons = <String>[
      'Prenatal service',
      'Immunization',
      'Postpartum service',
      'Family planning',
      'Other service',
    ];
    const unusableReasons = <String>[
      'Expired',
      'Damaged',
      'Broken seal',
      'Cold-chain failure',
      'Contaminated',
      'Recalled',
      'Other',
    ];
    final allReasons = isDispense ? dispenseReasons : unusableReasons;

    List<live.InventoryBatchRecord> batchesFor(InventoryItem? item) {
      if (item == null) return const [];
      return isDispense
          ? item.usableBatches.take(1).toList()
          : item.reportableBatches;
    }

    void chooseDefaultBatch([TextEditingController? quantityController]) {
      final batches = batchesFor(selectedItem);
      selectedBatch = batches.isEmpty ? null : batches.first;
      if (!isDispense && selectedBatch != null) {
        selectedReason = selectedBatch!.isExpiredOn() ? 'Expired' : 'Damaged';
        if (selectedReason == 'Expired') {
          quantityController?.text = '${selectedBatch!.quantityRemaining}';
        }
      }
      operationKey = null;
    }

    if (selectedItem != null) chooseDefaultBatch();
    final initialQuantity = selectedReason == 'Expired' && selectedBatch != null
        ? '${selectedBatch!.quantityRemaining}'
        : '';

    final successMessage = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _InventoryFormControllerHost(
          initialValues: [initialQuantity, ''],
          builder: (sheetContext, controllers) {
            final quantityController = controllers[0];
            final notesController = controllers[1];
            return StatefulBuilder(
              builder: (sheetContext, setModalState) {
                final bottomInset =
                    MediaQuery.viewInsetsOf(sheetContext).bottom;
                final batchOptions = batchesFor(selectedItem);
                final batch = selectedBatch;
                final parsedQuantity =
                    int.tryParse(quantityController.text.trim());
                final afterQuantity = batch == null || parsedQuantity == null
                    ? null
                    : batch.quantityRemaining - parsedQuantity;
                final fullBatchReport = !isDispense &&
                    ((selectedReason == 'Expired' &&
                            batch?.isExpiredOn() == true) ||
                        selectedReason == 'Recalled');
                final reasons = isDispense
                    ? allReasons
                    : batch?.isExpiredOn() == true
                        ? const <String>['Expired']
                        : allReasons
                            .where((reason) => reason != 'Expired')
                            .toList();
                final requiresNotes = selectedReason == 'Other service' ||
                    (!isDispense &&
                        selectedReason != null &&
                        selectedReason != 'Expired');

                Future<void> submitActivity() async {
                  if (isSubmitting || !_stockActivityAvailable) return;
                  final contextRecord = _liveContext;
                  final quantity = int.tryParse(quantityController.text.trim());
                  final itemValid = selectedItem != null;
                  final batchValid = batch != null;
                  final quantityValid = quantity != null &&
                      quantity > 0 &&
                      batch != null &&
                      quantity <= batch.quantityRemaining;
                  final reasonValid = selectedReason != null;
                  final notesValid =
                      !requiresNotes || notesController.text.trim().isNotEmpty;
                  final reportRuleValid = isDispense ||
                      (selectedReason != 'Expired' &&
                          selectedReason != 'Recalled') ||
                      (batch != null &&
                          (selectedReason == 'Expired'
                              ? batch.isExpiredOn() &&
                                  quantity == batch.quantityRemaining
                              : quantity == batch.quantityRemaining));

                  setModalState(() {
                    itemError = itemValid ? null : 'Choose an inventory item.';
                    batchError = batchValid ? null : 'Choose a stock batch.';
                    quantityError = !quantityValid
                        ? batch == null
                            ? 'Choose a batch first.'
                            : 'Enter 1–${batch.quantityRemaining} ${selectedItem?.unit ?? 'units'}.'
                        : !reportRuleValid
                            ? selectedReason == 'Recalled'
                                ? 'A recall must cover the full remaining batch.'
                                : batch.isExpiredOn()
                                    ? 'An expired report must cover the full expired batch.'
                                    : 'This batch has not expired. Choose another reason.'
                            : null;
                    reasonError =
                        reasonValid ? null : 'Choose a purpose or reason.';
                    notesError =
                        notesValid ? null : 'Add a short note for this reason.';
                  });

                  if (contextRecord == null ||
                      !itemValid ||
                      !batchValid ||
                      !quantityValid ||
                      !reasonValid ||
                      !notesValid ||
                      !reportRuleValid) {
                    _revealFirstError([
                      (itemError, itemFieldKey),
                      (batchError, batchFieldKey),
                      (quantityError, quantityFieldKey),
                      (reasonError, reasonFieldKey),
                      (notesError, notesFieldKey),
                    ]);
                    return;
                  }

                  final confirmed = await showDialog<bool>(
                    context: sheetContext,
                    builder: (dialogContext) => ConfirmationDialogBox(
                      title: isDispense
                          ? 'Confirm stock dispense?'
                          : 'Confirm unusable stock report?',
                      subtitle: isDispense
                          ? 'Purpose: $selectedReason. Deduct $quantity ${selectedItem!.unit} of ${selectedItem!.name} from Batch ${batch.batchNumber} (${_batchExpiryLabel(batch)}). Balance: ${batch.quantityRemaining} → $afterQuantity ${selectedItem!.unit}.${notesController.text.trim().isEmpty ? '' : ' Note: ${notesController.text.trim()}'}'
                          : 'Reason: $selectedReason. Remove $quantity ${selectedItem!.unit} of ${selectedItem!.name} from usable stock in Batch ${batch.batchNumber} (${_batchExpiryLabel(batch)}). Balance: ${batch.quantityRemaining} → $afterQuantity.${notesController.text.trim().isEmpty ? '' : ' Note: ${notesController.text.trim()}'}',
                      confirmText: isDispense ? 'Dispense' : 'Submit report',
                      cancelText: 'Review again',
                      onCancel: () => Navigator.of(dialogContext).pop(false),
                      onConfirm: () => Navigator.of(dialogContext).pop(true),
                    ),
                  );
                  if (confirmed != true || !sheetContext.mounted) return;

                  setModalState(() => isSubmitting = true);
                  final requestOperationKey = operationKey ??=
                      'midwife-${contextRecord.accountId}-${batch.batchId}-${activityType.name}-${DateTime.now().microsecondsSinceEpoch}';
                  try {
                    await _repository.recordStockActivity(
                      context: contextRecord,
                      batchId: batch.batchId,
                      activityType: activityType,
                      quantity: quantity,
                      reason: _stockActivityReasonCode(selectedReason!),
                      notes: notesController.text,
                      operationKey: requestOperationKey,
                    );
                    if (!sheetContext.mounted) return;
                    FocusManager.instance.primaryFocus?.unfocus();
                    Navigator.of(sheetContext).pop(
                      isDispense
                          ? '$quantity ${selectedItem!.unit} dispensed from Batch ${batch.batchNumber}. Admin inventory is now synchronized.'
                          : 'Unusable stock reported. RHU Main can see the batch, reason, and updated balance.',
                    );
                  } catch (error) {
                    if (error is live.InventoryWorkflowUnavailableException &&
                        mounted) {
                      setState(() {
                        _stockActivityAvailable = false;
                        _stockActivityMessage = error.message;
                      });
                    }
                    if (mounted) AppSnackbar.error(context, error.toString());
                    if (sheetContext.mounted) {
                      setModalState(() => isSubmitting = false);
                    }
                  }
                }

                return SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: bottomInset),
                    child: FractionallySizedBox(
                      heightFactor: 0.93,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                        decoration: const BoxDecoration(
                          color: AppColors.bgPrimary,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(28),
                          ),
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 42,
                              height: 4,
                              decoration: BoxDecoration(
                                color: AppColors.borderPrimary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: (isDispense
                                            ? AppColors.brandPrimary
                                            : AppColors.error)
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(13),
                                  ),
                                  child: Icon(
                                    isDispense
                                        ? Icons.medication_outlined
                                        : Icons.report_gmailerrorred_rounded,
                                    color: isDispense
                                        ? AppColors.brandPrimary
                                        : AppColors.error,
                                  ),
                                ),
                                const SizedBox(width: 11),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isDispense
                                            ? 'DISPENSE STOCK'
                                            : 'REPORT UNUSABLE STOCK',
                                        style: const TextStyle(
                                          color: AppColors.brandText,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.4,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        isDispense
                                            ? 'Record stock used in a health service — no patient name is needed.'
                                            : 'This immediately removes the affected quantity from usable stock and records the reason for RHU.',
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 11,
                                          height: 1.35,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: isSubmitting
                                      ? null
                                      : () => Navigator.of(sheetContext).pop(),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            _buildActivityFlowSteps(isDispense: isDispense),
                            const SizedBox(height: 14),
                            Expanded(
                              child: ListView(
                                padding: const EdgeInsets.only(bottom: 8),
                                children: [
                                  _FormLabel('1. INVENTORY ITEM', key: itemFieldKey),
                                  const SizedBox(height: 7),
                                  AppDropdownField<InventoryItem>(
                                    value: selectedItem,
                                    hintText: 'Choose an item',
                                    leadingIcon:
                                        Icons.medical_information_outlined,
                                    options: availableItems,
                                    displayStringForOption: (item) =>
                                        '${item.name} • ${item.quantity} ${item.unit} usable',
                                    errorText: itemError,
                                    onSelected: (item) {
                                      setModalState(() {
                                        selectedItem = item;
                                        itemError = null;
                                        batchError = null;
                                        quantityError = null;
                                        quantityController.clear();
                                        chooseDefaultBatch();
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  _FormLabel('2. STOCK BATCH', key: batchFieldKey),
                                  const SizedBox(height: 7),
                                  AppDropdownField<live.InventoryBatchRecord>(
                                    value: selectedBatch,
                                    hintText: selectedItem == null
                                        ? 'Choose an item first'
                                        : isDispense
                                            ? 'Earliest-expiring batch selected'
                                            : 'Choose a batch',
                                    leadingIcon: Icons.qr_code_2_rounded,
                                    options: batchOptions,
                                    displayStringForOption: (option) => selectedItem != null && selectedItem!.isMultiDose
                                        ? 'Batch ${option.batchNumber} • ${option.quantityRemaining} sealed${option.dosesRemainingInOpenVial > 0 ? ' + ${option.dosesRemainingInOpenVial} open doses' : ''} • ${_batchExpiryLabel(option)}'
                                        : 'Batch ${option.batchNumber} • ${option.quantityRemaining} left • ${_batchExpiryLabel(option)}',
                                    errorText: batchError,
                                    onSelected: (value) {
                                      setModalState(() {
                                        selectedBatch = value;
                                        batchError = null;
                                        quantityError = null;
                                        operationKey = null;
                                        quantityController.clear();
                                        if (!isDispense) {
                                          selectedReason = value.isExpiredOn()
                                              ? 'Expired'
                                              : 'Damaged';
                                          if (selectedReason == 'Expired') {
                                            quantityController.text =
                                                '${value.quantityRemaining}';
                                          }
                                        }
                                      });
                                    },
                                  ),
                                  if (batch != null) ...[
                                    const SizedBox(height: 10),
                                    _buildSelectedBatchSummary(
                                      item: selectedItem!,
                                      batch: batch,
                                      isDispense: isDispense,
                                    ),
                                  ],
                                  const SizedBox(height: 16),
                                  _FormLabel(
                                    isDispense
                                        ? '3. SERVICE PURPOSE'
                                        : '3. ISSUE REASON',
                                    key: reasonFieldKey,
                                  ),
                                  const SizedBox(height: 7),
                                  AppDropdownField<String>(
                                    value: selectedReason,
                                    hintText: isDispense
                                        ? 'Choose the health service'
                                        : 'Choose why stock is unusable',
                                    leadingIcon: isDispense
                                        ? Icons.health_and_safety_outlined
                                        : Icons.fact_check_outlined,
                                    options: reasons,
                                    displayStringForOption: (value) => value,
                                    errorText: reasonError,
                                    onSelected: (value) {
                                      setModalState(() {
                                        selectedReason = value;
                                        reasonError = null;
                                        notesError = null;
                                        operationKey = null;
                                        if (!isDispense &&
                                            batch != null &&
                                            ((value == 'Expired' &&
                                                    batch.isExpiredOn()) ||
                                                value == 'Recalled')) {
                                          quantityController.text =
                                              '${batch.quantityRemaining}';
                                        }
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  _FormLabel('4. QUANTITY', key: quantityFieldKey),
                                  const SizedBox(height: 7),
                                  AppInputField(
                                    controller: quantityController,
                                    hintText: batch == null
                                        ? 'Choose a batch first'
                                        : 'Quantity (max ${batch.quantityRemaining})',
                                    leadingIcon: Icons.numbers_rounded,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    readOnly: fullBatchReport,
                                    errorText: quantityError,
                                    onChanged: (_) {
                                      setModalState(() {
                                        quantityError = null;
                                        operationKey = null;
                                      });
                                    },
                                  ),
                                  if (fullBatchReport) ...[
                                    const SizedBox(height: 7),
                                    const Padding(
                                      padding:
                                          EdgeInsets.symmetric(horizontal: 12),
                                      child: Text(
                                        'Expiry and recall apply to the whole batch, so the full remaining quantity is selected.',
                                        style: TextStyle(
                                          color: AppColors.error,
                                          fontSize: 10,
                                          height: 1.35,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 16),
                                  _FormLabel(
                                    requiresNotes
                                        ? '5. NOTE (REQUIRED)'
                                        : '5. NOTE (OPTIONAL)',
                                    key: notesFieldKey,
                                  ),
                                  const SizedBox(height: 7),
                                  AppInputField(
                                    controller: notesController,
                                    hintText: isDispense
                                        ? 'Service note — do not enter a patient name'
                                        : 'What happened? Do not enter patient details',
                                    leadingIcon: Icons.notes_rounded,
                                    inputFormatters: [
                                      LengthLimitingTextInputFormatter(1000),
                                    ],
                                    errorText: notesError,
                                    onChanged: (_) {
                                      setModalState(() {
                                        notesError = null;
                                        operationKey = null;
                                      });
                                    },
                                  ),
                                  if (batch != null &&
                                      parsedQuantity != null &&
                                      parsedQuantity > 0 &&
                                      afterQuantity != null) ...[
                                    const SizedBox(height: 16),
                                    _buildMovementPreview(
                                      item: selectedItem!,
                                      batch: batch,
                                      quantity: parsedQuantity,
                                      remaining: afterQuantity,
                                      isDispense: isDispense,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            MainButton(
                              label: isSubmitting
                                  ? 'Saving activity...'
                                  : isDispense
                                      ? 'Review & dispense'
                                      : 'Review & submit report',
                              leftIcon: isSubmitting
                                  ? Icons.sync_rounded
                                  : Icons.fact_check_outlined,
                              onPressed: isSubmitting ? null : submitActivity,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );

    if (successMessage == null || !mounted) return;
    await _loadLiveInventory(refresh: true);
    if (!mounted) return;
    AppSnackbar.success(context, successMessage);
  }

  /// Bring the first field carrying an error back into view.
  ///
  /// Pairs are checked in the order they appear on the sheet, so the midwife is
  /// taken to the earliest problem rather than the last one set.
  static void _revealFirstError(List<(String?, GlobalKey)> fields) {
    for (final (error, key) in fields) {
      if (error == null) continue;
      final fieldContext = key.currentContext;
      if (fieldContext == null) continue;
      Scrollable.ensureVisible(
        fieldContext,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        alignment: 0.15,
      );
      return;
    }
  }

  Widget _buildActivityFlowSteps({required bool isDispense}) {
    final color = isDispense ? AppColors.brandPrimary : AppColors.error;
    const labels = ['Choose stock', 'Enter details', 'Confirm'];
    const icons = [
      Icons.touch_app_outlined,
      Icons.qr_code_scanner_rounded,
      Icons.check_circle_outline_rounded,
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          for (int index = 0; index < labels.length; index++) ...[
            Expanded(
              child: Column(
                children: [
                  Icon(icons[index], color: color, size: 17),
                  const SizedBox(height: 4),
                  Text(
                    '${index + 1}. ${labels[index]}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            if (index != labels.length - 1)
              Icon(Icons.chevron_right_rounded, color: color, size: 17),
          ],
        ],
      ),
    );
  }

  Widget _buildSelectedBatchSummary({
    required InventoryItem item,
    required live.InventoryBatchRecord batch,
    required bool isDispense,
  }) {
    final expired = batch.isExpiredOn();
    final color = expired ? AppColors.error : AppColors.info;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            expired ? Icons.event_busy_rounded : Icons.low_priority_rounded,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              expired
                  ? '${_batchExpiryLabel(batch)}. This batch is blocked from dispensing.'
                  : isDispense
                      ? (item.isMultiDose
                          ? 'Multi-dose (${item.dosesPerUnit} doses/unit) • ${batch.quantityRemaining} sealed vials${batch.dosesRemainingInOpenVial > 0 ? ' • 💉 ${batch.dosesRemainingInOpenVial} doses in open vial' : ''} • ${_batchExpiryLabel(batch)}.'
                          : 'Earliest-expiring batch • up to ${batch.quantityRemaining} ${item.unit} in this record • ${_batchExpiryLabel(batch)}.${item.quantity > batch.quantityRemaining ? ' Save once, then repeat for the next batch if more is needed.' : ''}')
                      : '${batch.quantityRemaining} ${item.unit} remain in this batch • ${_batchExpiryLabel(batch)}.',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 11,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMovementPreview({
    required InventoryItem item,
    required live.InventoryBatchRecord batch,
    required int quantity,
    required int remaining,
    required bool isDispense,
  }) {
    final color = remaining < 0
        ? AppColors.error
        : isDispense
            ? AppColors.brandPrimary
            : AppColors.error;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            remaining < 0 ? 'QUANTITY TOO HIGH' : 'BALANCE PREVIEW',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: _DetailValue(
                  label: 'BEFORE',
                  value: '${batch.quantityRemaining} ${item.unit}',
                ),
              ),
              Icon(Icons.arrow_forward_rounded, color: color, size: 18),
              Expanded(
                child: _DetailValue(
                  label: isDispense ? 'AFTER DISPENSE' : 'AFTER REPORT',
                  value: '$remaining ${item.unit}',
                  valueColor: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            '$quantity ${item.unit} will be recorded against Batch ${batch.batchNumber}.',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  String _stockActivityReasonCode(String label) {
    return label.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
  }

  String _batchExpiryLabel(live.InventoryBatchRecord batch) {
    final days = batch.daysUntilExpiration();
    if (days == null) return 'Expiry not recorded';
    if (days < 0) return 'Expired ${-days} day${days == -1 ? '' : 's'} ago';
    if (days == 0) return 'Expired today';
    if (days == 1) return 'Expires tomorrow';
    if (days <= 90) return 'Expires in $days days';
    final expiration = batch.expirationDate!;
    return 'Expires ${_shortDate(expiration)}, ${expiration.year}';
  }

  // ── Stock request helpers ──────────────────────────────────────────────
  //
  // The picker used to be the raw catalogue in catalogue order: forty names,
  // no numbers, nothing to say which one you came here about. A midwife opens
  // this sheet *because* something has run low, so the sheet now leads with
  // what has run low and pre-fills the rest from it.

  /// Items at or below their reorder level, worst first.
  List<InventoryItem> _itemsNeedingRestock() {
    final needing = _inventory
        .where((item) => item.quantity <= item.minimumStock)
        .toList()
      ..sort((a, b) {
        // Nothing on the shelf outranks merely low.
        final aOut = a.quantity <= 0 ? 0 : 1;
        final bOut = b.quantity <= 0 ? 0 : 1;
        if (aOut != bOut) return aOut - bOut;
        return _restockShortfall(b).compareTo(_restockShortfall(a));
      });
    return needing;
  }

  /// How far below the reorder level this item sits.
  int _restockShortfall(InventoryItem item) =>
      (item.minimumStock - item.quantity).clamp(0, 1 << 30);

  /// The catalogue, ordered so the items worth requesting come first.
  List<InventoryItem> _requestPickerOptions() {
    final options = List<InventoryItem>.from(_inventory);
    options.sort((a, b) {
      int rank(InventoryItem i) {
        if (i.quantity <= 0) return 0;
        if (i.quantity <= i.minimumStock) return 1;
        return 2;
      }

      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return options;
  }

  /// A quantity that brings the item back to its reorder level, rounded up to
  /// something a person would actually ask for. Never zero.
  int _suggestedRequestQuantity(InventoryItem item) {
    final shortfall = _restockShortfall(item);
    final base = shortfall > 0 ? shortfall : item.minimumStock;
    if (base <= 0) return 10;
    if (base <= 10) return base;
    // Round up to the nearest ten so the request reads as a decision, not a
    // subtraction.
    return ((base + 9) ~/ 10) * 10;
  }

  /// An open request for the same item, if the midwife already raised one.
  StockRequest? _openRequestFor(InventoryItem item) {
    final name = item.name.trim().toLowerCase();
    for (final request in _requests) {
      if (request.isEmpty) continue;
      final status = request.status.toLowerCase();
      if (status != 'pending' && status != 'approved' && status != 'issued') {
        continue;
      }
      if (request.itemName.trim().toLowerCase() == name) return request;
    }
    return null;
  }

  /// Standard reasons, so the RHU reviewing a queue of these can sort them.
  static const List<String> _requestReasonPresets = [
    'Running low on stock',
    'Completely out of stock',
    'Upcoming immunization drive',
    'Replacing an expired batch',
  ];

  /// One line describing where the item stands, for the card under the picker.
  StockStatusCard _requestStockContextCard(InventoryItem item) {
    if (item.quantity <= 0) {
      return StockStatusCard(
        margin: const EdgeInsets.only(top: 10),
        tone: StockTone.blocked,
        message: 'None left at ${_liveContext?.facilityName ?? 'this health center'}. '
            'Reorder level is ${item.minimumStock} ${item.unit}.',
      );
    }
    if (item.quantity <= item.minimumStock) {
      return StockStatusCard(
        margin: const EdgeInsets.only(top: 10),
        tone: StockTone.caution,
        message: '${item.quantity} ${item.unit} on hand — '
            '${_restockShortfall(item)} below the reorder level of '
            '${item.minimumStock}.',
      );
    }
    return StockStatusCard(
      margin: const EdgeInsets.only(top: 10),
      message: '${item.quantity} ${item.unit} on hand, above the reorder level '
          'of ${item.minimumStock}.',
    );
  }

  /// A tappable "this one is low" chip.
  Widget _restockSuggestionChip({
    required InventoryItem item,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isOut = item.quantity <= 0;
    final label = isOut ? 'none left' : '${item.quantity} ${item.unit} left';

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.brandPrimary : AppColors.brandSecondary,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? AppColors.brandPrimary
                  : (isOut
                      ? AppColors.error.withValues(alpha: 0.45)
                      : const Color(0xFFFBCFE8)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.name,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : AppColors.brandText,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.9)
                      : (isOut
                          ? const Color(0xFF9B3B3B)
                          : AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A small "set this value" pill, used for quantities and reasons.
  Widget _requestPresetChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.brandPrimary : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.brandPrimary : AppColors.borderPrimary,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Future<void> _showRequestSheet([InventoryItem? suggestedItem]) async {
    InventoryItem? selectedItem = suggestedItem;
    String? itemError;
    String? quantityError;
    String? reasonError;
    bool isSubmitting = false;

    // See _revealFirstError: this sheet also runs past the bottom of the screen.
    final requestItemKey = GlobalKey();
    final requestQuantityKey = GlobalKey();
    final requestReasonKey = GlobalKey();

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _InventoryFormControllerHost(
          initialValues: const ['', '', ''],
          builder: (sheetContext, controllers) {
            final quantityController = controllers[0];
            final reasonController = controllers[1];
            final remarksController = controllers[2];
            return StatefulBuilder(
              builder: (sheetContext, setModalState) {
                final bottomInset =
                    MediaQuery.viewInsetsOf(sheetContext).bottom;
                final supplierLabel = _liveContext?.supplierLabel ?? 'your RHU';
                final lowStockItems = _itemsNeedingRestock();
                final openRequest = selectedItem == null
                    ? null
                    : _openRequestFor(selectedItem!);

                Future<void> submitRequest() async {
                  if (isSubmitting || !_workflowAvailable) return;
                  final int? quantity =
                      int.tryParse(quantityController.text.trim());
                  final bool isItemValid = selectedItem != null;
                  final bool isQuantityValid = quantity != null && quantity > 0;
                  final bool isReasonValid =
                      reasonController.text.trim().isNotEmpty;

                  setModalState(() {
                    itemError =
                        isItemValid ? null : 'Choose an inventory item.';
                    quantityError = isQuantityValid
                        ? null
                        : 'Enter a quantity greater than zero.';
                    reasonError = isReasonValid
                        ? null
                        : 'Pick a reason above, or write your own.';
                  });

                  if (!isItemValid || !isQuantityValid || !isReasonValid) {
                    _revealFirstError([
                      (itemError, requestItemKey),
                      (quantityError, requestQuantityKey),
                      (reasonError, requestReasonKey),
                    ]);
                    return;
                  }
                  final contextRecord = _liveContext;
                  if (contextRecord == null) return;

                  setModalState(() => isSubmitting = true);
                  try {
                    await _repository.submitStockRequest(
                      context: contextRecord,
                      itemId: selectedItem!.itemId,
                      quantity: quantity,
                      reason: reasonController.text.trim(),
                      remarks: remarksController.text.trim(),
                    );
                    if (!sheetContext.mounted) return;
                    FocusManager.instance.primaryFocus?.unfocus();
                    Navigator.of(sheetContext).pop(true);
                  } catch (error) {
                    if (!sheetContext.mounted) return;
                    setModalState(() => isSubmitting = false);
                    if (error is live.InventoryWorkflowUnavailableException &&
                        mounted) {
                      setState(() {
                        _workflowAvailable = false;
                        _workflowMessage = error.message;
                      });
                    }
                    AppSnackbar.error(sheetContext, error.toString());
                  }
                }

                return SafeArea(
                  top: false,
                  child: Container(
                    padding: EdgeInsets.fromLTRB(20, 12, 20, bottomInset + 22),
                    decoration: const BoxDecoration(
                      color: AppColors.bgPrimary,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 42,
                              height: 4,
                              decoration: BoxDecoration(
                                color: AppColors.borderPrimary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'REQUEST STOCK',
                                      style: TextStyle(
                                        color: AppColors.brandText,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Goes to $supplierLabel for review.',
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: isSubmitting
                                    ? null
                                    : () =>
                                        Navigator.of(sheetContext).pop(false),
                                icon: const Icon(
                                  Icons.close_rounded,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // What is actually low, first. Tapping one fills the
                          // picker, the quantity and the reason in a single go —
                          // which is the whole request for the common case.
                          if (lowStockItems.isNotEmpty) ...[
                            const _FormLabel('Needs restocking'),
                            const SizedBox(height: 7),
                            SizedBox(
                              height: 50,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: lowStockItems.length,
                                itemBuilder: (_, index) {
                                  final item = lowStockItems[index];
                                  return _restockSuggestionChip(
                                    item: item,
                                    isSelected: selectedItem?.itemId == item.itemId,
                                    onTap: () => setModalState(() {
                                      selectedItem = item;
                                      itemError = null;
                                      quantityError = null;
                                      reasonError = null;
                                      quantityController.text =
                                          _suggestedRequestQuantity(item).toString();
                                      reasonController.text = item.quantity <= 0
                                          ? 'Completely out of stock'
                                          : 'Running low on stock';
                                    }),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 18),
                          ],

                          _FormLabel('Medicine or vaccine', key: requestItemKey),
                          const SizedBox(height: 7),
                          AppDropdownField<InventoryItem>(
                            hintText: 'Select from BHC catalog',
                            leadingIcon: Icons.medication_outlined,
                            // Ordered by urgency, not by catalogue id, so what
                            // needs requesting is at the top of the list.
                            options: _requestPickerOptions(),
                            value: selectedItem,
                            displayStringForOption: (item) => item.name,
                            errorText: itemError,
                            onSelected: (item) {
                              setModalState(() {
                                selectedItem = item;
                                itemError = null;
                                if (quantityController.text.trim().isEmpty) {
                                  quantityController.text =
                                      _suggestedRequestQuantity(item).toString();
                                }
                              });
                            },
                          ),

                          if (selectedItem != null) ...[
                            _requestStockContextCard(selectedItem!),
                            if (openRequest != null)
                              StockStatusCard(
                                margin: const EdgeInsets.only(top: 8),
                                tone: StockTone.caution,
                                icon: Icons.history_rounded,
                                message:
                                    'You already have a ${openRequest.status.toLowerCase()} '
                                    'request for this item (${openRequest.quantity} '
                                    '${openRequest.unit}). Send another only if you '
                                    'need more on top of it.',
                              ),
                          ],

                          const SizedBox(height: 16),
                          _FormLabel('Requested quantity', key: requestQuantityKey),
                          const SizedBox(height: 7),
                          AppInputField(
                            controller: quantityController,
                            hintText: selectedItem == null
                                ? 'Enter quantity'
                                : 'Quantity in ${selectedItem!.unit}',
                            isRequired: true,
                            leadingIcon: Icons.numbers_rounded,
                            keyboardType: TextInputType.number,
                            errorText: quantityError,
                            onChanged: (_) {
                              setModalState(() {
                                if (quantityError != null) quantityError = null;
                              });
                            },
                          ),
                          if (selectedItem != null) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 7,
                              runSpacing: 7,
                              children: [
                                for (final preset in <int>{
                                  _suggestedRequestQuantity(selectedItem!),
                                  _suggestedRequestQuantity(selectedItem!) * 2,
                                })
                                  _requestPresetChip(
                                    label: '$preset ${selectedItem!.unit}',
                                    isSelected:
                                        quantityController.text.trim() ==
                                            preset.toString(),
                                    onTap: () => setModalState(() {
                                      quantityController.text = preset.toString();
                                      quantityError = null;
                                    }),
                                  ),
                              ],
                            ),
                          ],

                          const SizedBox(height: 16),
                          _FormLabel('Reason for request', key: requestReasonKey),
                          const SizedBox(height: 7),
                          // Preset first, free text second. A queue of requests
                          // the RHU can group is worth more than forty
                          // differently-worded sentences saying "we ran out".
                          Wrap(
                            spacing: 7,
                            runSpacing: 7,
                            children: [
                              for (final preset in _requestReasonPresets)
                                _requestPresetChip(
                                  label: preset,
                                  isSelected:
                                      reasonController.text.trim() == preset,
                                  onTap: () => setModalState(() {
                                    reasonController.text = preset;
                                    reasonError = null;
                                  }),
                                ),
                            ],
                          ),
                          const SizedBox(height: 9),
                          AppInputField(
                            controller: reasonController,
                            hintText: 'Or describe it in your own words',
                            isRequired: true,
                            leadingIcon: Icons.notes_rounded,
                            errorText: reasonError,
                            onChanged: (_) {
                              setModalState(() {
                                if (reasonError != null) reasonError = null;
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                          const _FormLabel('Remarks (optional)'),
                          const SizedBox(height: 7),
                          AppInputField(
                            controller: remarksController,
                            hintText: 'Add any handling or batch notes',
                            leadingIcon: Icons.chat_bubble_outline_rounded,
                          ),
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.bgSecondary,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.info_outline_rounded,
                                  size: 18,
                                  color: AppColors.brandText,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Your stock does not change yet. It changes when '
                                    '$supplierLabel issues the batch and you confirm '
                                    'receipt here.',
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 11,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          MainButton(
                            label: isSubmitting
                                ? 'Submitting request...'
                                : 'Submit to ${_liveContext?.supplierLabel ?? 'your RHU'}',
                            leftIcon: Icons.send_rounded,
                            onPressed: isSubmitting ? null : submitRequest,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );

    if (submitted != true || !mounted || selectedItem == null) return;
    setState(() => _selectedTab = 2);
    await _loadLiveInventory(refresh: true);
    if (!mounted) return;
    AppSnackbar.success(
      context,
      '${selectedItem!.name} request sent to ${_liveContext?.supplierLabel ?? 'your RHU'}.',
    );
  }

  void _confirmReceive(IncomingShipment shipment) {
    // canConfirmReceipt, not isPending: an outbound shipment is pending on the
    // facility at the other end, and receiving it here would credit the stock
    // straight back to the shelf it just left.
    if (!shipment.canConfirmReceipt ||
        !_workflowAvailable ||
        _receivingTransferIds.contains(shipment.transferId)) {
      return;
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return ConfirmationDialogBox(
          title: 'Receive stocks?',
          subtitle:
              'Confirm that ${shipment.issuedQuantity} ${shipment.unit} of ${shipment.itemName} from ${_liveContext?.supplierLabel ?? 'your RHU'} were received.',
          confirmText: 'Receive',
          cancelText: 'Not yet',
          onCancel: () => Navigator.of(dialogContext).pop(),
          onConfirm: () async {
            Navigator.of(dialogContext).pop();
            final contextRecord = _liveContext;
            if (contextRecord == null || !mounted) return;
            setState(
              () => _receivingTransferIds.add(shipment.transferId),
            );
            try {
              await _repository.receiveTransfer(
                context: contextRecord,
                transferId: shipment.transferId,
              );
              await _loadLiveInventory(refresh: true);
              if (!mounted) return;
              AppSnackbar.success(
                context,
                '${shipment.itemName} received and added to BHC stock.',
              );
            } catch (error) {
              if (!mounted) return;
              if (error is live.InventoryWorkflowUnavailableException) {
                setState(() {
                  _workflowAvailable = false;
                  _workflowMessage = error.message;
                });
              }
              AppSnackbar.error(context, error.toString());
            } finally {
              if (mounted) {
                setState(
                  () => _receivingTransferIds.remove(shipment.transferId),
                );
              }
            }
          },
        );
      },
    );
  }

  Future<void> _logout() async {
    await PushNotificationService.removeToken();
    await AuthStorage.clearAll();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  void _showWorkflowUnavailable() {
    AppSnackbar.warning(
      context,
      _workflowMessage ??
          'Install the Supabase inventory workflow migration to enable requests and receipts.',
    );
  }

  Widget _sectionHeading(
    String label, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.brandText,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.brandText,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              actionLabel,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.borderPrimary),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Pending':
        return AppColors.warning;
      case 'Approved':
        return AppColors.info;
      case 'Issued':
        return AppColors.brandPrimary;
      case 'Received':
      case 'Completed':
        return AppColors.success;
      case 'Rejected':
        return AppColors.error;
      case 'Cancelled':
        return AppColors.textSecondary;
      default:
        return AppColors.textSecondary;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'Pending':
        return Icons.schedule_rounded;
      case 'Approved':
        return Icons.task_alt_rounded;
      case 'Issued':
        return Icons.local_shipping_outlined;
      case 'Received':
      case 'Completed':
        return Icons.check_circle_rounded;
      case 'Rejected':
        return Icons.cancel_rounded;
      case 'Cancelled':
        return Icons.block_rounded;
      default:
        return Icons.info_outline_rounded;
    }
  }

  String _requestStatusMessage(String status) {
    // "RHU Main" is not the name of anything. Pinagbarilan BHC reports to
    // Baliwag RHU III, and supplierLabel already resolves that through
    // health_facilities.parent_facility_id — it just was not used here.
    final rhu = _liveContext?.supplierLabel ?? 'Your RHU';
    final rhuLead = rhu.isEmpty ? rhu : rhu[0].toUpperCase() + rhu.substring(1);
    switch (status) {
      case 'Pending':
        return '$rhuLead is reviewing the requested quantity and available batches.';
      case 'Approved':
        return '$rhuLead approved this request and will prepare an issue.';
      case 'Issued':
        return '$rhuLead has issued the stocks. Confirm the incoming delivery to update your stock.';
      case 'Received':
        return 'Receipt was confirmed and your stock was updated.';
      case 'Completed':
        return 'This request is complete and remains available in your history.';
      case 'Rejected':
        return '$rhuLead did not approve this request. Review the remarks before requesting again.';
      case 'Cancelled':
        return 'This request was cancelled and no stock movement was completed.';
      default:
        return 'Request status updated.';
    }
  }

  String _shortDate(DateTime value) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[value.month - 1]} ${value.day}';
  }

  String _dateTimeLabel(DateTime value) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final int hour12 = value.hour == 0
        ? 12
        : value.hour > 12
            ? value.hour - 12
            : value.hour;
    final String minute = value.minute.toString().padLeft(2, '0');
    final String suffix = value.hour >= 12 ? 'PM' : 'AM';
    return '${months[value.month - 1]} ${value.day}, $hour12:$minute $suffix';
  }
}

class InventoryItem {
  InventoryItem({
    required this.itemId,
    required this.name,
    required this.genericName,
    required this.itemCode,
    required this.strengthDescription,
    required this.dosageForm,
    required this.category,
    required this.unit,
    required this.quantity,
    required this.minimumStock,
    required this.batchNumber,
    required this.batches,
    required this.icon,
    this.dosesPerUnit = 1,
    this.openVialShelfHours = 6,
  });

  final int itemId;
  final String name;
  final String genericName;
  final String itemCode;
  final String strengthDescription;
  final String dosageForm;
  final String category;
  final String unit;
  final int quantity;
  final int minimumStock;
  final String batchNumber;
  final List<live.InventoryBatchRecord> batches;
  final IconData icon;
  final int dosesPerUnit;
  final int openVialShelfHours;

  bool get isMultiDose => dosesPerUnit > 1;

  int get openVialDoses => batches
      .where((b) => b.isUsableOn())
      .fold(0, (sum, b) => sum + b.dosesRemainingInOpenVial);

  int get totalAvailableDoses => (quantity * dosesPerUnit) + openVialDoses;

  bool get hasOpenVial => openVialDoses > 0;

  bool get isLowStock => quantity <= minimumStock;

  List<live.InventoryBatchRecord> get usableBatches {
    final result = batches.where((batch) => batch.isUsableOn()).toList();
    result.sort(_compareBatchesByExpiry);
    return result;
  }

  List<live.InventoryBatchRecord> get reportableBatches {
    final result = batches
        .where(
          (batch) =>
              batch.quantityRemaining > 0 &&
              batch.status.toLowerCase() != 'discarded',
        )
        .toList();
    result.sort((first, second) {
      if (first.isExpiredOn() != second.isExpiredOn()) {
        return first.isExpiredOn() ? -1 : 1;
      }
      return _compareBatchesByExpiry(first, second);
    });
    return result;
  }

  live.InventoryBatchRecord? get nearestUsableBatch {
    final batches = usableBatches;
    return batches.isEmpty ? null : batches.first;
  }

  int get expiredQuantity => batches
      .where(
        (batch) =>
            batch.quantityRemaining > 0 &&
            batch.status.toLowerCase() != 'discarded' &&
            (batch.isExpiredOn() || batch.status.toLowerCase() == 'expired'),
      )
      .fold(0, (total, batch) => total + batch.quantityRemaining);

  int get expiringSoonQuantity => batches
      .where(
        (batch) => batch.isUsableOn() && batch.isExpiringWithin(90),
      )
      .fold(0, (total, batch) => total + batch.quantityRemaining);

  int? get nearestExpiryDays => nearestUsableBatch?.daysUntilExpiration();

  String get nearestExpiryLabel {
    final batch = nearestUsableBatch;
    if (batch == null) return 'No usable batch';
    final days = batch.daysUntilExpiration();
    if (days == null) return 'Expiry not recorded';
    if (days <= 0) return 'Expired';
    if (days == 1) return 'Expires tomorrow';
    if (days <= 90) return 'Expires in $days days';
    return 'Expires ${_shortBatchDate(batch.expirationDate!)}';
  }

  String get catalogSubtitle {
    final details = <String>[
      if (genericName.isNotEmpty &&
          genericName.toLowerCase() != name.toLowerCase())
        genericName,
      if (strengthDescription.isNotEmpty) strengthDescription,
      if (dosageForm.isNotEmpty) dosageForm,
      if (itemCode.isNotEmpty) itemCode,
    ];
    return details.join(' • ');
  }

  static int _compareBatchesByExpiry(
    live.InventoryBatchRecord first,
    live.InventoryBatchRecord second,
  ) {
    final firstExpiry = first.expirationDay;
    final secondExpiry = second.expirationDay;
    if (firstExpiry == null && secondExpiry == null) {
      return first.batchNumber.compareTo(second.batchNumber);
    }
    if (firstExpiry == null) return 1;
    if (secondExpiry == null) return -1;
    final dateOrder = firstExpiry.compareTo(secondExpiry);
    return dateOrder != 0
        ? dateOrder
        : first.batchNumber.compareTo(second.batchNumber);
  }

  static String _shortBatchDate(DateTime value) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[value.month - 1]} ${value.day}, ${value.year}';
  }
}

class IncomingShipment {
  IncomingShipment({
    required this.transferId,
    required this.id,
    required this.itemName,
    required this.batchNumber,
    required this.issuedQuantity,
    required this.unit,
    required this.issuedAt,
    required this.issuedBy,
    required this.status,
    required this.remarks,
    this.requestId,
    this.receivedQuantity,
    this.receivedAt,
    this.isOutbound = false,
    this.direction = live.TransferDirection.allocation,
    this.counterpartName,
    this.cancelReason = '',
  });

  final int transferId;
  final String id;
  final String itemName;
  final String batchNumber;
  final int issuedQuantity;
  final String unit;
  final DateTime issuedAt;
  final String issuedBy;
  final String status;
  final String remarks;
  final String? requestId;
  int? receivedQuantity;
  DateTime? receivedAt;

  /// True when this health centre is the one that GAVE the stock up.
  ///
  /// An outbound shipment is not actionable here — the other end confirms it —
  /// but it is the only record the sending centre has of why its own count
  /// dropped, so it belongs on this screen just as much as an arrival does.
  final bool isOutbound;
  final live.TransferDirection direction;

  /// The facility at the other end: where it came from, or where it went.
  final String? counterpartName;
  final String cancelReason;

  bool get isCancelled => status.toLowerCase() == 'cancelled';

  bool get isPending =>
      status.toLowerCase() == 'pending_receipt' && receivedAt == null;

  /// Only an arrival can be confirmed here.
  bool get canConfirmReceipt => isPending && !isOutbound;
}

class StockRequest {
  StockRequest({
    required this.requestId,
    required this.id,
    required this.itemName,
    required this.quantity,
    required this.unit,
    required this.reason,
    required this.remarks,
    required this.adminRemarks,
    required this.approvedQuantity,
    required this.status,
    required this.submittedAt,
    this.completedAt,
    this.isEmpty = false,
  });

  factory StockRequest.empty() {
    return StockRequest(
      requestId: 0,
      id: '',
      itemName: '',
      quantity: 0,
      unit: '',
      reason: '',
      remarks: '',
      adminRemarks: '',
      approvedQuantity: null,
      status: '',
      submittedAt: DateTime.fromMillisecondsSinceEpoch(0),
      isEmpty: true,
    );
  }

  final int requestId;
  final String id;
  final String itemName;
  final int quantity;
  final String unit;
  final String reason;
  final String remarks;
  final String adminRemarks;
  final int? approvedQuantity;

  /// The reviewing office cut the quantity down.
  ///
  /// A midwife who asked for 100 and was sent 30 otherwise reads "Approved"
  /// beside "100 units" and plans a month around stock that is not coming.
  bool get isPartiallyApproved =>
      approvedQuantity != null && approvedQuantity! < quantity;

  /// What is actually coming, which is the requested amount unless it was cut.
  int get effectiveQuantity => approvedQuantity ?? quantity;
  String status;
  final DateTime submittedAt;
  DateTime? completedAt;
  final bool isEmpty;
}

class InventoryEvent {
  const InventoryEvent({
    required this.title,
    required this.details,
    required this.occurredAt,
    required this.icon,
    required this.color,
    this.transaction,
  });

  final String title;
  final String details;
  final DateTime occurredAt;
  final IconData icon;
  final Color color;

  /// The ledger row behind this tile, when there is one. Transfers and stock
  /// requests are events too but move no dose, so they leave this null and
  /// their tiles are not tappable.
  final live.InventoryTransactionRecord? transaction;
}

class _InventoryCountLabel extends StatelessWidget {
  const _InventoryCountLabel({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    this.compact = false,
  });

  final IconData icon;
  final int value;
  final String label;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final iconWidget = Container(
      width: compact ? 30 : 34,
      height: compact ? 30 : 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: compact ? 17 : 19),
    );
    final textWidget = Column(
      crossAxisAlignment:
          compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );

    if (compact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [iconWidget, const SizedBox(height: 7), textWidget],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        iconWidget,
        const SizedBox(width: 9),
        Flexible(child: textWidget),
      ],
    );
  }
}

class _HeroTag extends StatelessWidget {
  const _HeroTag({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 13),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryMetricItem extends StatelessWidget {
  const _HistoryMetricItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                color: isActive ? color : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final foreground =
        color == AppColors.warning ? const Color(0xFF925000) : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: foreground),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailValue extends StatelessWidget {
  const _DetailValue({
    required this.label,
    required this.value,
    this.valueColor = AppColors.textPrimary,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: valueColor,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    required this.event,
    required this.dateLabel,
    this.onTap,
  });

  final InventoryEvent event;
  final String Function(DateTime) dateLabel;

  /// Opens the dose trace for the item behind this tile. Null for events with
  /// no ledger row, which stay as plain, untappable text.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tile = _buildContent();
    if (onTap == null) return tile;
    return InkWell(onTap: onTap, child: tile);
  }

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: event.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(event.icon, color: event.color, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  event.details,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  dateLabel(event.occurredAt),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

typedef _InventoryFormControllerBuilder = Widget Function(
  BuildContext context,
  List<TextEditingController> controllers,
);

class _InventoryFormControllerHost extends StatefulWidget {
  const _InventoryFormControllerHost({
    required this.initialValues,
    required this.builder,
  });

  final List<String> initialValues;
  final _InventoryFormControllerBuilder builder;

  @override
  State<_InventoryFormControllerHost> createState() =>
      _InventoryFormControllerHostState();
}

class _InventoryFormControllerHostState
    extends State<_InventoryFormControllerHost> {
  late final List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = widget.initialValues
        .map((value) => TextEditingController(text: value))
        .toList(growable: false);
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controllers);
}

class _FormLabel extends StatelessWidget {
  // The key lets a validation failure scroll its own section back into view.
  const _FormLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
