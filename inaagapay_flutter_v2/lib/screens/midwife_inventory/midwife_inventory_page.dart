import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_storage.dart';
import '../../services/push_notification_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/app_input_field.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/confirmation_dialog_box.dart';
import '../../widgets/main_button.dart';
import '../../widgets/main_header.dart';
import '../../widgets/overview_info.dart';
import '../../widgets/secondary_button.dart';
import '../../widgets/tab_button.dart';
import 'inventory_models.dart' as live;
import 'inventory_repository.dart';

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
  final InventoryRepository _repository = InventoryRepository();
  final List<InventoryItem> _inventory = [];
  final List<IncomingShipment> _shipments = [];
  final List<StockRequest> _requests = [];
  final List<InventoryEvent> _events = [];
  final List<live.InventoryNotificationRecord> _inventoryNotifications = [];

  int _selectedTab = 0;
  String _stockFilter = 'all';
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
  bool _notificationRealtimeConnected = false;
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
          status: _displayStatus(request.status),
          submittedAt: request.requestedAt,
          completedAt: request.completedAt,
        );
      }).toList();

      final shipments = snapshot.transfers.map((transfer) {
        final item = itemsById[transfer.itemId];
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
          requestId: transfer.requestId == null
              ? null
              : _requestCode(transfer.requestId!),
          remarks: transfer.remarks.isEmpty
              ? 'Issued by RHU Main for this health center.'
              : transfer.remarks,
          receivedQuantity: transfer.quantityReceived,
          receivedAt: transfer.receivedAt,
        );
      }).toList();

      final events = <InventoryEvent>[
        ...snapshot.transactions.map(_eventFromTransaction),
        ...snapshot.transfers.map((transfer) {
          final item = itemsById[transfer.itemId];
          final isCancelled = transfer.status.toLowerCase() == 'cancelled';
          return InventoryEvent(
            title: transfer.isPending
                ? 'Stock issued by RHU Main'
                : isCancelled
                    ? 'Stock transfer cancelled'
                    : 'Stocks received from RHU Main',
            details:
                '${transfer.quantityIssued} ${item?.unit.toLowerCase() ?? 'units'} of ${item?.name ?? 'Inventory item'} • ${transfer.batchNumber}',
            occurredAt: transfer.receivedAt ?? transfer.issuedAt,
            icon: transfer.isPending
                ? Icons.local_shipping_outlined
                : isCancelled
                    ? Icons.cancel_outlined
                    : Icons.inventory_2_rounded,
            color: transfer.isPending
                ? AppColors.brandPrimary
                : isCancelled
                    ? AppColors.error
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
    final isIncoming = transaction.quantity > 0;
    final title = switch (type) {
      'receipt' => 'Stock receipt recorded',
      'dispense' => 'Stock dispensed',
      'expiry_disposal' => 'Unusable stock reported',
      'adjustment' => 'Stock adjusted',
      _ => isIncoming ? 'Stock added' : 'Stock deducted',
    };
    return InventoryEvent(
      title: title,
      details:
          '${transaction.quantity > 0 ? '+' : ''}${transaction.quantity} ${transaction.unit.toLowerCase()} • ${transaction.itemName} • ${transaction.batchNumber}${transaction.referenceType.isEmpty ? '' : ' • ${transaction.referenceType}'}',
      occurredAt: transaction.loggedAt,
      icon: type == 'expiry_disposal'
          ? Icons.report_outlined
          : isIncoming
              ? Icons.add_circle_outline_rounded
              : Icons.remove_circle_outline_rounded,
      color: type == 'expiry_disposal'
          ? AppColors.error
          : isIncoming
              ? AppColors.success
              : AppColors.info,
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

  int get _pendingShipmentCount =>
      _shipments.where((shipment) => shipment.isPending).length;

  int get _unreadNotificationCount => _inventoryNotifications
      .where((notification) => !notification.isRead)
      .length;

  List<InventoryItem> get _lowStockItems =>
      _inventory.where((item) => item.isLowStock).toList();

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
    _notificationRealtimeConnected = false;

    _notificationChannel = _repository.subscribeToInventoryNotifications(
      context: context,
      onNotification: _handleRealtimeInventoryNotification,
      onConnectionChanged: (connected) {
        if (!mounted || _notificationAccountId != context.accountId) return;
        setState(() => _notificationRealtimeConnected = connected);
      },
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
    }

    _notificationRefreshDebounce?.cancel();
    _notificationRefreshDebounce = Timer(
      const Duration(milliseconds: 450),
      () {
        if (mounted) unawaited(_loadLiveInventory(refresh: true));
      },
    );
  }

  Future<void> _markInventoryNotificationsRead(
    List<live.InventoryNotificationRecord> notifications,
  ) async {
    final unreadIds = notifications
        .where((notification) => !notification.isRead)
        .map((notification) => notification.notificationId)
        .toSet();
    if (unreadIds.isEmpty) return;

    if (mounted) {
      setState(() {
        for (var index = 0; index < _inventoryNotifications.length; index++) {
          final notification = _inventoryNotifications[index];
          if (unreadIds.contains(notification.notificationId)) {
            _inventoryNotifications[index] =
                notification.copyWith(isRead: true);
          }
        }
      });
    }

    try {
      await _repository.markInventoryNotificationsRead(unreadIds);
    } catch (_) {
      // Reading the feed should not be blocked by a transient sync failure.
    }
  }

  Widget _buildInventoryHeader() {
    final topInset = MediaQuery.paddingOf(context).top;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        MainHeader(
          title: 'Inventory',
          onNotificationTap: _showNotificationSheet,
          onSettings: () => Navigator.pushNamed(context, '/settings'),
          onLogout: _logout,
        ),
        if (_unreadNotificationCount > 0)
          Positioned(
            top: topInset + 9,
            right: 61,
            child: IgnorePointer(
              child: Container(
                constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: AppColors.brandAccent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  _unreadNotificationCount > 99
                      ? '99+'
                      : '$_unreadNotificationCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
      ],
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
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    final pendingShipments =
        _shipments.where((shipment) => shipment.isPending).toList();

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
        _sectionHeading('INCOMING FROM RHU MAIN'),
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
          label: 'Request stocks from RHU Main',
          leadingIcon: Icons.add_circle_outline_rounded,
          onPressed:
              _workflowAvailable ? _showRequestSheet : _showWorkflowUnavailable,
        ),
        const SizedBox(height: 16),
        _buildLatestRequestCard(),
        const SizedBox(height: 26),
        _sectionHeading('RECENT ACTIVITY'),
        const SizedBox(height: 10),
        _buildRecentActivityCard(),
      ],
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

  Widget _buildIncomingShipmentCard(IncomingShipment shipment) {
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
                  color: AppColors.brandPrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.inventory_2_rounded,
                  color: AppColors.brandPrimary,
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
                      'From ${shipment.issuedBy}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusChip(
                label: shipment.isPending ? 'Pending' : 'Received',
                color:
                    shipment.isPending ? AppColors.warning : AppColors.success,
                icon: shipment.isPending
                    ? Icons.schedule_rounded
                    : Icons.check_circle_rounded,
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
                  label: 'ISSUED',
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
                    shipment.remarks,
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
          MainButton(
            label: _receivingTransferIds.contains(shipment.transferId)
                ? 'Receiving stock...'
                : 'Receive ${shipment.issuedQuantity} ${shipment.unit}',
            leftIcon: Icons.check_circle_outline_rounded,
            onPressed: !_workflowAvailable ||
                    _receivingTransferIds.contains(shipment.transferId)
                ? null
                : () => _confirmReceive(shipment),
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
                  '${request.itemName} • ${request.quantity} ${request.unit}',
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
                event: recentEvents[index], dateLabel: _dateTimeLabel),
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
        _sectionHeading('RECENT DISPENSING & UNUSABLE STOCK'),
        const SizedBox(height: 10),
        _buildStockOutActivityCard(),
        const SizedBox(height: 18),
        MainButton(
          label: 'Request stocks from RHU Main',
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
                      '${item.category} • ${item.usableBatches.length} usable batch${item.usableBatches.length == 1 ? '' : 'es'}',
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
                  value: '${item.quantity} ${item.unit} usable',
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
          if (item.isLowStock) ...[
            const SizedBox(height: 5),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed:
                    _workflowAvailable ? () => _showRequestSheet(item) : null,
                icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                label: const Text('Request this item'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.brandText,
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
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
                      '${request.quantity} ${request.unit} requested',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
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
                                  const _FormLabel('1. INVENTORY ITEM'),
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
                                  const _FormLabel('2. STOCK BATCH'),
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
                                    displayStringForOption: (option) =>
                                        'Batch ${option.batchNumber} • ${option.quantityRemaining} left • ${_batchExpiryLabel(option)}',
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
                                  const _FormLabel('4. QUANTITY'),
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
                      ? 'Earliest-expiring batch • up to ${batch.quantityRemaining} ${item.unit} in this record • ${_batchExpiryLabel(batch)}.${item.quantity > batch.quantityRemaining ? ' Save once, then repeat for the next batch if more is needed.' : ''}'
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

  Future<void> _showRequestSheet([InventoryItem? suggestedItem]) async {
    InventoryItem? selectedItem = suggestedItem;
    String? itemError;
    String? quantityError;
    String? reasonError;
    bool isSubmitting = false;

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
                        : 'Tell RHU Main why this is needed.';
                  });

                  if (!isItemValid || !isQuantityValid || !isReasonValid) {
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
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'REQUEST STOCK',
                                      style: TextStyle(
                                        color: AppColors.brandText,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Send a replenishment request to RHU Main.',
                                      style: TextStyle(
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
                          const SizedBox(height: 22),
                          const _FormLabel('Medicine or vaccine'),
                          const SizedBox(height: 7),
                          AppDropdownField<InventoryItem>(
                            hintText: 'Select from BHC catalog',
                            leadingIcon: Icons.medication_outlined,
                            options: _inventory,
                            value: selectedItem,
                            displayStringForOption: (item) => item.name,
                            errorText: itemError,
                            onSelected: (item) {
                              setModalState(() {
                                selectedItem = item;
                                itemError = null;
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                          const _FormLabel('Requested quantity'),
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
                              if (quantityError != null) {
                                setModalState(() => quantityError = null);
                              }
                            },
                          ),
                          const SizedBox(height: 16),
                          const _FormLabel('Reason for request'),
                          const SizedBox(height: 7),
                          AppInputField(
                            controller: reasonController,
                            hintText: 'Why is this stock needed?',
                            isRequired: true,
                            leadingIcon: Icons.notes_rounded,
                            errorText: reasonError,
                            onChanged: (_) {
                              if (reasonError != null) {
                                setModalState(() => reasonError = null);
                              }
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
                            child: const Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  size: 18,
                                  color: AppColors.brandText,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'RHU Main will review this as Pending. Your BHC stock changes only after RHU issues the stock and you confirm receipt.',
                                    style: TextStyle(
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
                                : 'Submit request to RHU Main',
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
      '${selectedItem!.name} request sent to RHU Main.',
    );
  }

  void _confirmReceive(IncomingShipment shipment) {
    if (!shipment.isPending ||
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
              'Confirm that ${shipment.issuedQuantity} ${shipment.unit} of ${shipment.itemName} from RHU Main were received.',
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

  Future<void> _showNotificationSheet() async {
    final visibleNotifications =
        List<live.InventoryNotificationRecord>.from(_inventoryNotifications);
    final sheetFuture = showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: FractionallySizedBox(
            heightFactor: 0.76,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
              decoration: const BoxDecoration(
                color: AppColors.bgPrimary,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
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
                      const Expanded(
                        child: Text(
                          'INVENTORY NOTIFICATIONS',
                          style: TextStyle(
                            color: AppColors.brandText,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: (_notificationRealtimeConnected
                                  ? AppColors.success
                                  : AppColors.warning)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: _notificationRealtimeConnected
                                    ? AppColors.success
                                    : AppColors.warning,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _notificationRealtimeConnected
                                  ? 'LIVE'
                                  : 'AUTO-CHECK',
                              style: TextStyle(
                                color: _notificationRealtimeConnected
                                    ? AppColors.success
                                    : AppColors.warning,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'RHU request updates and low-stock changes appear here automatically.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        if (visibleNotifications.isEmpty)
                          const _NotificationTile(
                            icon: Icons.notifications_none_rounded,
                            color: AppColors.info,
                            title: 'No RHU request updates yet',
                            message:
                                'New approvals, rejections, and stock issues will appear here.',
                          )
                        else
                          ...visibleNotifications.map(
                            (notification) => _NotificationTile(
                              icon: _notificationIcon(notification.kind),
                              color: _notificationColor(notification.kind),
                              title: notification.displayTitle,
                              message: notification.message,
                              timestamp: _dateTimeLabel(notification.createdAt),
                              isUnread: !notification.isRead,
                              onTap: () {
                                Navigator.pop(sheetContext);
                                setState(() {
                                  _selectedTab = switch (notification.kind) {
                                    live.InventoryNotificationKind.issued => 0,
                                    live.InventoryNotificationKind.lowStock =>
                                      1,
                                    _ => 2,
                                  };
                                });
                              },
                            ),
                          ),
                        const SizedBox(height: 8),
                        const Text(
                          'CURRENT ATTENTION',
                          style: TextStyle(
                            color: AppColors.brandText,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 9),
                        if (_pendingShipmentCount > 0)
                          _NotificationTile(
                            icon: Icons.inventory_2_rounded,
                            color: AppColors.brandPrimary,
                            title: 'Incoming stock needs your confirmation',
                            message:
                                '$_pendingShipmentCount issue ${_pendingShipmentCount == 1 ? 'is' : 'are'} waiting from RHU Main.',
                            onTap: () {
                              Navigator.pop(sheetContext);
                              setState(() => _selectedTab = 0);
                            },
                          ),
                        if (_lowStockItems.isNotEmpty)
                          _NotificationTile(
                            icon: Icons.warning_amber_rounded,
                            color: AppColors.warning,
                            title:
                                '${_lowStockItems.length} item${_lowStockItems.length == 1 ? '' : 's'} need replenishing',
                            message:
                                'Open My Stock to review supplies below the re-order level.',
                            onTap: () {
                              Navigator.pop(sheetContext);
                              setState(() => _selectedTab = 1);
                            },
                          ),
                        if (_pendingShipmentCount == 0 &&
                            _lowStockItems.isEmpty)
                          const _NotificationTile(
                            icon: Icons.check_circle_outline_rounded,
                            color: AppColors.success,
                            title: 'Nothing needs attention',
                            message:
                                'Your current deliveries and stock levels are clear.',
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    unawaited(_markInventoryNotificationsRead(visibleNotifications));
    await sheetFuture;
  }

  IconData _notificationIcon(live.InventoryNotificationKind kind) {
    return switch (kind) {
      live.InventoryNotificationKind.approved =>
        Icons.check_circle_outline_rounded,
      live.InventoryNotificationKind.rejected => Icons.cancel_outlined,
      live.InventoryNotificationKind.issued => Icons.local_shipping_outlined,
      live.InventoryNotificationKind.lowStock => Icons.warning_amber_rounded,
    };
  }

  Color _notificationColor(live.InventoryNotificationKind kind) {
    return switch (kind) {
      live.InventoryNotificationKind.approved => AppColors.success,
      live.InventoryNotificationKind.rejected => AppColors.error,
      live.InventoryNotificationKind.issued => AppColors.brandPrimary,
      live.InventoryNotificationKind.lowStock => AppColors.warning,
    };
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
    switch (status) {
      case 'Pending':
        return 'RHU Main is reviewing the requested quantity and available batches.';
      case 'Approved':
        return 'RHU Main approved this request and will prepare an issue.';
      case 'Issued':
        return 'RHU Main has issued the stocks. Confirm the incoming delivery to update BHC stock.';
      case 'Received':
        return 'Receipt was confirmed and the BHC stock was updated.';
      case 'Completed':
        return 'This request is complete and remains available in your history.';
      case 'Rejected':
        return 'RHU Main did not approve this request. Review the RHU remarks before requesting again.';
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

  bool get isPending =>
      status.toLowerCase() == 'pending_receipt' && receivedAt == null;
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
  });

  final String title;
  final String details;
  final DateTime occurredAt;
  final IconData icon;
  final Color color;
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
  const _ActivityTile({required this.event, required this.dateLabel});

  final InventoryEvent event;
  final String Function(DateTime) dateLabel;

  @override
  Widget build(BuildContext context) {
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
  const _FormLabel(this.label);

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

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
    this.timestamp,
    this.isUnread = false,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final String? timestamp;
  final bool isUnread;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: isUnread
            ? AppColors.brandPrimary.withValues(alpha: 0.055)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isUnread
                    ? AppColors.brandPrimary.withValues(alpha: 0.3)
                    : AppColors.borderPrimary,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: color, size: 19),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (isUnread) ...[
                            const SizedBox(width: 8),
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(top: 4),
                              decoration: const BoxDecoration(
                                color: AppColors.brandAccent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
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
                      if (timestamp != null) ...[
                        const SizedBox(height: 7),
                        Text(
                          timestamp!,
                          style: TextStyle(
                            color: color,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 6),
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
