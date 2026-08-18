import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/auth_storage.dart';
import '../../services/notification_service.dart';
import '../../theme/app_colors.dart';
import '../midwife_inventory/inventory_repository.dart';

enum MidwifeAlertCategory {
  all,
  inventory,
  expiries,
  transfers,
  clinical,
}

enum MidwifeAlertSeverity {
  critical, // Red (Out of stock, Expired batch, Open vial expired)
  warning,  // Amber (Low stock, Expiring in 30d, Pending request)
  success,  // Green (Stock request approved, Transfer received)
  info,     // Blue (In-transit transfer, General update)
}

class MidwifeAlertItem {
  final String id;
  final String title;
  final String message;
  final MidwifeAlertCategory category;
  final MidwifeAlertSeverity severity;
  final DateTime timestamp;
  final bool isRead;
  final VoidCallback? onAction;
  final String? actionLabel;

  const MidwifeAlertItem({
    required this.id,
    required this.title,
    required this.message,
    required this.category,
    required this.severity,
    required this.timestamp,
    this.isRead = false,
    this.onAction,
    this.actionLabel,
  });
}

class MidwifeNotificationCenter extends StatefulWidget {
  final VoidCallback? onRefreshRequested;

  const MidwifeNotificationCenter({
    super.key,
    this.onRefreshRequested,
  });

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const MidwifeNotificationCenter(),
    );
  }

  @override
  State<MidwifeNotificationCenter> createState() => _MidwifeNotificationCenterState();
}

class _MidwifeNotificationCenterState extends State<MidwifeNotificationCenter> {
  final InventoryRepository _inventoryRepo = InventoryRepository();
  bool _loading = true;
  MidwifeAlertCategory _selectedCategory = MidwifeAlertCategory.all;
  final List<MidwifeAlertItem> _alerts = [];
  int? _accountId;

  @override
  void initState() {
    super.initState();
    _loadAllAlerts();
  }

  Future<void> _loadAllAlerts() async {
    setState(() => _loading = true);
    final alerts = <MidwifeAlertItem>[];

    try {
      final accountId = await AuthStorage.getUserId();
      _accountId = accountId;

      // 1. Load Real-time Inventory Snapshot for this Midwife's BHC
      try {
        final invContext = await _inventoryRepo.resolveContext();
        final snapshot = await _inventoryRepo.loadSnapshot(invContext);
        final bhcId = invContext.facilityId;

        // (A) Low Stock & Out of Stock Alerts
        for (final stock in snapshot.inventory) {
          final available = stock.quantity;
          final min = stock.catalog.minimumStock;
          final name = stock.catalog.name;
          final unit = stock.catalog.unit;

          if (available == 0) {
            alerts.add(MidwifeAlertItem(
              id: 'out_stock_${stock.catalog.itemId}',
              title: 'Out of Stock Alert',
              message: '$name is completely OUT OF STOCK at your BHC (0 $unit available).',
              category: MidwifeAlertCategory.inventory,
              severity: MidwifeAlertSeverity.critical,
              timestamp: DateTime.now(),
              actionLabel: 'Request Stock',
              onAction: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/midwife-inventory');
              },
            ));
          } else if (available <= min) {
            alerts.add(MidwifeAlertItem(
              id: 'low_stock_${stock.catalog.itemId}',
              title: 'Low Stock Warning',
              message: '$name is low: $available $unit remaining (safety threshold: $min $unit).',
              category: MidwifeAlertCategory.inventory,
              severity: MidwifeAlertSeverity.warning,
              timestamp: DateTime.now(),
              actionLabel: 'Request Stock',
              onAction: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/midwife-inventory');
              },
            ));
          }

          // (B) Open Multi-Dose Vial Shelf-Life & Expiry Alerts
          for (final batch in stock.batches) {
            final openDoses = batch.dosesRemainingInOpenVial;
            final dpu = stock.catalog.dosesPerUnit;
            final shelfHours = stock.catalog.openVialShelfHours;

            if (dpu > 1 && openDoses > 0) {
              if (batch.isExpiredOpenVial(shelfHours)) {
                alerts.add(MidwifeAlertItem(
                  id: 'open_vial_exp_${batch.batchId}',
                  title: 'Open Vial Expired',
                  message: 'Open vial for $name (Batch #${batch.batchNumber}, $openDoses doses) exceeded ${shelfHours}h shelf limit. Please discard.',
                  category: MidwifeAlertCategory.expiries,
                  severity: MidwifeAlertSeverity.critical,
                  timestamp: batch.vialOpenedAt ?? DateTime.now(),
                  actionLabel: 'View Inventory',
                  onAction: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/midwife-inventory');
                  },
                ));
              } else {
                alerts.add(MidwifeAlertItem(
                  id: 'open_vial_act_${batch.batchId}',
                  title: 'Active Open Multi-Dose Vial',
                  message: '$name (Batch #${batch.batchNumber}) has $openDoses of $dpu doses ready in opened vial (${shelfHours}h shelf limit).',
                  category: MidwifeAlertCategory.expiries,
                  severity: MidwifeAlertSeverity.info,
                  timestamp: batch.vialOpenedAt ?? DateTime.now(),
                  actionLabel: 'View Batches',
                  onAction: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/midwife-inventory');
                  },
                ));
              }
            }

            // (C) Batch Expiry Alerts (Expired or Expiring soon)
            if (batch.isExpiredOn()) {
              alerts.add(MidwifeAlertItem(
                id: 'batch_exp_${batch.batchId}',
                title: 'Batch Expired',
                message: 'Batch #${batch.batchNumber} ($name) has expired (${batch.quantityRemaining} sealed vials). Do not administer.',
                category: MidwifeAlertCategory.expiries,
                severity: MidwifeAlertSeverity.critical,
                timestamp: batch.expirationDate ?? DateTime.now(),
                actionLabel: 'Review Stock',
                onAction: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/midwife-inventory');
                },
              ));
            } else if (batch.isExpiringWithin(30)) {
              final days = batch.daysUntilExpiration() ?? 0;
              alerts.add(MidwifeAlertItem(
                id: 'batch_exp_soon_${batch.batchId}',
                title: 'Batch Expiring Soon',
                message: 'Batch #${batch.batchNumber} ($name) will expire in $days day${days == 1 ? '' : 's'} (${batch.quantityRemaining} $unit left).',
                category: MidwifeAlertCategory.expiries,
                severity: MidwifeAlertSeverity.warning,
                timestamp: batch.expirationDate ?? DateTime.now(),
                actionLabel: 'Prioritize Stock',
                onAction: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/midwife-inventory');
                },
              ));
            }
          }
        }

        // (D) Stock Requests Updates
        for (final req in snapshot.requests) {
          final item = snapshot.inventory.where((i) => i.catalog.itemId == req.itemId).firstOrNull;
          final itemName = item?.catalog.name ?? 'Item #${req.itemId}';

          if (req.status == 'approved') {
            alerts.add(MidwifeAlertItem(
              id: 'req_app_${req.requestId}',
              title: 'Stock Request Approved',
              message: 'RHU Main approved your request for ${req.quantity} ${item?.catalog.unit ?? "units"} of $itemName.',
              category: MidwifeAlertCategory.transfers,
              severity: MidwifeAlertSeverity.success,
              timestamp: req.completedAt ?? req.requestedAt,
              actionLabel: 'View Requests',
              onAction: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/midwife-inventory');
              },
            ));
          } else if (req.status == 'rejected') {
            final remarks = req.adminRemarks.isNotEmpty ? req.adminRemarks : (req.remarks.isNotEmpty ? req.remarks : 'No remarks');
            alerts.add(MidwifeAlertItem(
              id: 'req_rej_${req.requestId}',
              title: 'Stock Request Rejected',
              message: 'Your request for $itemName was rejected: $remarks.',
              category: MidwifeAlertCategory.transfers,
              severity: MidwifeAlertSeverity.warning,
              timestamp: req.completedAt ?? req.requestedAt,
              actionLabel: 'Review Request',
              onAction: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/midwife-inventory');
              },
            ));
          } else if (req.status == 'pending') {
            alerts.add(MidwifeAlertItem(
              id: 'req_pend_${req.requestId}',
              title: 'Stock Request Pending Approval',
              message: 'Request #${req.requestId} for ${req.quantity} units of $itemName is awaiting review by Central RHU.',
              category: MidwifeAlertCategory.transfers,
              severity: MidwifeAlertSeverity.info,
              timestamp: req.requestedAt,
              actionLabel: 'Track Status',
              onAction: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/midwife-inventory');
              },
            ));
          }
        }

        // (E) In-Transit Transfers
        for (final trf in snapshot.transfers) {
          if (trf.status == 'in_transit' || trf.status == 'dispatched') {
            alerts.add(MidwifeAlertItem(
              id: 'trf_transit_${trf.transferId}',
              title: 'Incoming Stock Shipment In-Transit',
              message: 'Shipment #${trf.transferId} (${trf.quantityIssued} units) is on its way from Central Warehouse. Ready for receiving.',
              category: MidwifeAlertCategory.transfers,
              severity: MidwifeAlertSeverity.info,
              timestamp: trf.issuedAt,
              actionLabel: 'Confirm Receipt',
              onAction: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/midwife-inventory');
              },
            ));
          }
        }

        // (F) Load Clinical High-Risk Mother Alerts in this BHC
        try {
          final highRiskMothers = await Supabase.instance.client
              .from('mothers')
              .select('mother_id, account:account_id(first_name, last_name), pregnancies(status, risk_level, risk_factors)')
              .eq('assigned_bhc_id', bhcId)
              .eq('status', 'active');

          for (final m in (highRiskMothers as List)) {
            final acc = m['account'] as Map<String, dynamic>?;
            final name = '${acc?['first_name'] ?? ''} ${acc?['last_name'] ?? ''}'.trim();
            final pregnancies = m['pregnancies'] as List?;
            final activePreg = pregnancies?.where((p) => p['status'] == 'active').firstOrNull;

            if (activePreg != null && (activePreg['risk_level'] == 'high' || activePreg['risk_level'] == 'very_high')) {
              alerts.add(MidwifeAlertItem(
                id: 'high_risk_mother_${m['mother_id']}',
                title: 'High-Risk Mother Follow-up',
                message: '$name has an active high-risk pregnancy (${activePreg['risk_factors'] ?? "Monitored case"}).',
                category: MidwifeAlertCategory.clinical,
                severity: MidwifeAlertSeverity.critical,
                timestamp: DateTime.now(),
                actionLabel: 'View Profile',
                onAction: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/mother-profile', arguments: m['mother_id']);
                },
              ));
            }
          }
        } catch (clinErr) {
          debugPrint('Error loading clinical alerts: $clinErr');
        }
      } catch (invErr) {
        debugPrint('Error loading inventory alerts in notification center: $invErr');
      }

      // 2. Load Push & Account Notifications
      if (accountId != null) {
        final notifications = await NotificationService.getNotifications(accountId, limit: 30);
        for (final n in notifications) {
          final title = n['title']?.toString() ?? 'Notification';
          final msg = n['message']?.toString() ?? '';
          final type = n['type']?.toString() ?? 'general';
          final isRead = n['is_read'] == true;
          final dtStr = n['created_at']?.toString();
          final dt = dtStr != null ? DateTime.tryParse(dtStr) ?? DateTime.now() : DateTime.now();

          MidwifeAlertCategory cat = MidwifeAlertCategory.clinical;
          MidwifeAlertSeverity sev = MidwifeAlertSeverity.info;

          if (type.contains('stock') || type.contains('inventory')) {
            cat = MidwifeAlertCategory.inventory;
            sev = MidwifeAlertSeverity.warning;
          } else if (type.contains('vaccine')) {
            cat = MidwifeAlertCategory.clinical;
            sev = MidwifeAlertSeverity.success;
          } else if (type.contains('risk') || type.contains('urgent')) {
            cat = MidwifeAlertCategory.clinical;
            sev = MidwifeAlertSeverity.critical;
          }

          alerts.add(MidwifeAlertItem(
            id: 'db_notif_${n['notification_id']}',
            title: title,
            message: msg,
            category: cat,
            severity: sev,
            timestamp: dt,
            isRead: isRead,
          ));
        }
      }

      // Sort alerts: critical first, then newest
      alerts.sort((a, b) {
        final sevA = _severityOrder(a.severity);
        final sevB = _severityOrder(b.severity);
        if (sevA != sevB) return sevA.compareTo(sevB);
        return b.timestamp.compareTo(a.timestamp);
      });

      if (mounted) {
        setState(() {
          _alerts.clear();
          _alerts.addAll(alerts);
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading midwife alerts: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  int _severityOrder(MidwifeAlertSeverity s) {
    switch (s) {
      case MidwifeAlertSeverity.critical: return 0;
      case MidwifeAlertSeverity.warning: return 1;
      case MidwifeAlertSeverity.info: return 2;
      case MidwifeAlertSeverity.success: return 3;
    }
  }

  Future<void> _markAllAsRead() async {
    if (_accountId != null) {
      await NotificationService.markAllAsRead(_accountId!);
    }
    _loadAllAlerts();
  }

  List<MidwifeAlertItem> get _filteredAlerts {
    if (_selectedCategory == MidwifeAlertCategory.all) return _alerts;
    return _alerts.where((a) => a.category == _selectedCategory).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredAlerts;

    return SafeArea(
      top: false,
      child: FractionallySizedBox(
        heightFactor: 0.85,
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              // Header Drag Handle
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Title Row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.brandPrimary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.notifications_active_rounded,
                        color: AppColors.brandPrimary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'NOTIFICATIONS & ALERTS',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.brandText,
                              letterSpacing: 0.4,
                            ),
                          ),
                          Text(
                            'Live stocks, transfers, expiries, and clinical alerts',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.done_all_rounded, color: AppColors.brandPrimary, size: 20),
                      onPressed: _markAllAsRead,
                      tooltip: 'Mark All as Read',
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
                      onPressed: _loadAllAlerts,
                      tooltip: 'Refresh Alerts',
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Filter Category Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _buildCategoryChip('All Alerts', MidwifeAlertCategory.all, _alerts.length),
                    const SizedBox(width: 8),
                    _buildCategoryChip(
                      'Stock & Inventory',
                      MidwifeAlertCategory.inventory,
                      _alerts.where((a) => a.category == MidwifeAlertCategory.inventory).length,
                    ),
                    const SizedBox(width: 8),
                    _buildCategoryChip(
                      'Expiries & Vials',
                      MidwifeAlertCategory.expiries,
                      _alerts.where((a) => a.category == MidwifeAlertCategory.expiries).length,
                    ),
                    const SizedBox(width: 8),
                    _buildCategoryChip(
                      'Requests & Transfers',
                      MidwifeAlertCategory.transfers,
                      _alerts.where((a) => a.category == MidwifeAlertCategory.transfers).length,
                    ),
                    const SizedBox(width: 8),
                    _buildCategoryChip(
                      'Clinical',
                      MidwifeAlertCategory.clinical,
                      _alerts.where((a) => a.category == MidwifeAlertCategory.clinical).length,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, color: Color(0xFFE2E8F0)),

              // Content List
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.brandPrimary,
                        ),
                      )
                    : filtered.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.grey.shade200),
                                    ),
                                    child: Icon(
                                      Icons.done_all_rounded,
                                      size: 36,
                                      color: Colors.teal.shade500,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  const Text(
                                    'All Clear!',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'No pending inventory warnings, expired vials, or critical alerts for this category.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (ctx, i) => _buildAlertCard(filtered[i]),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryChip(String label, MidwifeAlertCategory cat, int count) {
    final isSelected = _selectedCategory == cat;
    return GestureDetector(
      onTap: () => setState(() => _selectedCategory = cat),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.brandPrimary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.brandPrimary : const Color(0xFFCBD5E1),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.brandPrimary.withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected ? Colors.white : AppColors.textPrimary,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.25)
                      : (cat == MidwifeAlertCategory.expiries || cat == MidwifeAlertCategory.inventory
                          ? const Color(0xFFFEE2E2)
                          : const Color(0xFFF1F5F9)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: isSelected
                        ? Colors.white
                        : (cat == MidwifeAlertCategory.expiries || cat == MidwifeAlertCategory.inventory
                            ? const Color(0xFFDC2626)
                            : const Color(0xFF475569)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAlertCard(MidwifeAlertItem alert) {
    Color bg;
    Color border;
    Color iconColor;
    IconData icon;

    switch (alert.severity) {
      case MidwifeAlertSeverity.critical:
        bg = const Color(0xFFFEF2F2);
        border = const Color(0xFFFECACA);
        iconColor = const Color(0xFFDC2626);
        icon = Icons.error_rounded;
        break;
      case MidwifeAlertSeverity.warning:
        bg = const Color(0xFFFFFBEB);
        border = const Color(0xFFFDE68A);
        iconColor = const Color(0xFFD97706);
        icon = Icons.warning_rounded;
        break;
      case MidwifeAlertSeverity.success:
        bg = const Color(0xFFECFDF5);
        border = const Color(0xFFA7F3D0);
        iconColor = const Color(0xFF059669);
        icon = Icons.check_circle_rounded;
        break;
      case MidwifeAlertSeverity.info:
        bg = const Color(0xFFEFF6FF);
        border = const Color(0xFFBFDBFE);
        iconColor = const Color(0xFF2563EB);
        icon = Icons.info_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
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
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: border),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alert.title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: alert.severity == MidwifeAlertSeverity.critical
                            ? const Color(0xFF991B1B)
                            : (alert.severity == MidwifeAlertSeverity.warning
                                ? const Color(0xFF92400E)
                                : AppColors.brandText),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      alert.message,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: Color(0xFF334155),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (alert.onAction != null && alert.actionLabel != null) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: alert.onAction,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: iconColor.withValues(alpha: 0.5)),
                      boxShadow: [
                        BoxShadow(
                          color: iconColor.withValues(alpha: 0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          alert.actionLabel!,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: iconColor,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_forward_rounded, size: 13, color: iconColor),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
