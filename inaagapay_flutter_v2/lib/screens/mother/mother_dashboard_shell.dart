// lib/screens/mother/mother_dashboard_shell.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_colors.dart';
import '../../services/auth_storage.dart';
import '../../services/language_service.dart';
import '../../services/maternal_td_alert.dart';
import '../../services/supabase_service.dart';
import '../../services/notification_service.dart';
import '../../services/push_notification_service.dart';
import 'mother_dashboard.dart';
import 'mother_journal_screen.dart';
import 'mother_children_screen.dart';
import 'records_screen.dart';
import 'mother_self_profile_page.dart';
import 'notifications_screen.dart';
import 'help_support_screen.dart';
import '../../widgets/main_button.dart';

/// The mother's bottom-navigation destinations.
///
/// Children and Records are the two that need a health centre behind them:
/// child records, immunisations, checkups, ultrasounds and lab results are all
/// entered by a midwife, so before a mother is assigned to a BHC those tabs
/// open onto nothing. Hiding them is kinder than showing her two permanently
/// empty pages, and it makes the reason she cannot see them a single fact
/// rather than five separate empty states.
///
/// Hotlines is no longer a tab: it opens from a card on Home. Home is never
/// gated, so the numbers stay reachable for an unregistered mother, who is
/// precisely the one with no midwife to call.
enum _MotherTab {
  home(
    icon: Icons.home_outlined,
    activeIcon: Icons.home,
    labelEnglish: 'Home',
    labelFilipino: 'Bahay',
  ),
  journal(
    icon: Icons.menu_book_outlined,
    activeIcon: Icons.menu_book,
    labelEnglish: 'Journal',
    labelFilipino: 'Journal',
  ),
  children(
    icon: Icons.child_care_outlined,
    activeIcon: Icons.child_care,
    labelEnglish: 'Children',
    labelFilipino: 'Mga Anak',
    requiresBhc: true,
  ),
  records(
    icon: Icons.folder_outlined,
    activeIcon: Icons.folder,
    labelEnglish: 'Records',
    labelFilipino: 'Mga Tala',
    requiresBhc: true,
  );

  const _MotherTab({
    required this.icon,
    required this.activeIcon,
    required this.labelEnglish,
    required this.labelFilipino,
    this.requiresBhc = false,
  });

  final IconData icon;
  final IconData activeIcon;
  final String labelEnglish;
  final String labelFilipino;
  final bool requiresBhc;
}

class MotherDashboardShell extends StatefulWidget {
  const MotherDashboardShell({super.key});

  @override
  State<MotherDashboardShell> createState() => _MotherDashboardShellState();
}

class _MotherDashboardShellState extends State<MotherDashboardShell> {
  int _currentIndex = 0;
  String? _profilePictureUrl;
  int? _motherId;
  int _unreadCount = 0;
  RealtimeChannel? _notifChannel;
  String _riskLevel = '';
  List<String> _riskFactors = [];

  final bool _showBHCRequiredDialog = false;
  bool _isOffline = false;
  Timer? _connectivityTimer;

  /// Whether she is assigned to a health centre. Drives which tabs exist.
  bool _isBhcRegistered = false;

  /// The tabs she can currently reach, in order.
  ///
  /// `_currentIndex` indexes into *this*, not into [_MotherTab.values] — which
  /// is the whole reason the tabs are modelled rather than written out one by
  /// one. With hardcoded positions, hiding Children would silently turn
  /// index 2 from Children into Records and index 3 into a range error.
  List<_MotherTab> get _visibleTabs => _MotherTab.values
      .where((tab) => !tab.requiresBhc || _isBhcRegistered)
      .toList();

  Widget _screenFor(_MotherTab tab) {
    switch (tab) {
      case _MotherTab.home:
        return const MotherDashboard();
      case _MotherTab.journal:
        return const MotherJournalScreen();
      case _MotherTab.children:
        return const MotherChildrenScreen();
      case _MotherTab.records:
        return const RecordsScreen();
    }
  }

  /// Reads her assignment and rebuilds the tab set around it.
  ///
  /// Clamps the selection: if she is viewing Records when the set shrinks,
  /// leaving `_currentIndex` where it is would point past the end of the list.
  Future<void> _refreshBhcRegistration() async {
    final cached = await AuthStorage.wasBhcRegistered();
    if (mounted && cached != _isBhcRegistered) {
      setState(() {
        _isBhcRegistered = cached;
        _currentIndex = _currentIndex.clamp(0, _visibleTabs.length - 1);
      });
    }

    final motherId = await AuthStorage.getMotherId();
    if (motherId == null) return;
    try {
      final row = await SupabaseService.client
          .from('mothers')
          .select('assigned_bhc_id')
          .eq('mother_id', motherId)
          .maybeSingle();
      final registered = row != null && row['assigned_bhc_id'] != null;
      await AuthStorage.saveBhcRegistered(registered);
      if (mounted && registered != _isBhcRegistered) {
        setState(() {
          _isBhcRegistered = registered;
          _currentIndex = _currentIndex.clamp(0, _visibleTabs.length - 1);
        });
      }
    } catch (e) {
      // On a failed read she keeps whatever she had. Guessing "registered"
      // would show her tabs that cannot load; guessing the opposite would take
      // records away from someone who has them.
      debugPrint('Could not refresh BHC registration: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _loadMotherData();
    _refreshBhcRegistration();
    _setupNotifications();
    _checkConnectivity();
    // Re-check connectivity every 30 seconds
    _connectivityTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkConnectivity(),
    );
  }

  @override
  void dispose() {
    _notifChannel?.unsubscribe();
    _connectivityTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkConnectivity() async {
    // Skip connectivity check on web (dart:io not available)
    // On mobile, this would use InternetAddress.lookup
    // For now, assume online — Supabase client handles errors gracefully
    if (mounted && _isOffline) setState(() => _isOffline = false);
  }

  Future<void> _setupNotifications() async {
    _notifChannel?.unsubscribe();
    final accountId = await AuthStorage.getUserId();
    if (accountId == null || !mounted) return;

    // Same fact the tabs are built from, so the badge and the navigation can
    // never disagree about whether she is assigned to a health centre.
    await _refreshBhcRegistration();
    final unlinked = !_isBhcRegistered;

    // The unlinked notice counts only while she has not read it.
    //
    // This added 1 unconditionally, so an unlinked mother's bell carried a
    // badge she could never clear — she could open the page, read the notice,
    // and come back to the same red dot for the rest of her pregnancy.
    //
    // The Td notice follows the same rule, keyed per dose and level (see
    // MaternalTdAlert.noticeType), so reading "Td 2 is due" does not silence
    // the Td 3 notice that comes later.
    final motherId = await AuthStorage.getMotherId();
    final tdAlert =
        motherId == null ? null : await MaternalTdAlert.loadFor(motherId);
    var localUnread = 0;
    if (unlinked || tdAlert != null) {
      Set<String> readIds;
      try {
        readIds = (await AuthStorage.getReadAlertIds(accountId)).toSet();
      } catch (e) {
        debugPrint('Could not read notice state: $e');
        readIds = <String>{};
      }
      if (unlinked && !readIds.contains('mother_notice_unlinked_bhc')) {
        localUnread++;
      }
      if (tdAlert != null &&
          !readIds.contains('mother_notice_${tdAlert.noticeType}')) {
        localUnread++;
      }
    }

    final count = await NotificationService.getUnreadCount(accountId);
    if (mounted) {
      setState(() {
        _unreadCount = count + localUnread;
      });
    }

    _notifChannel =
        NotificationService.subscribeToNotifications(accountId, (payload) {
      if (mounted) setState(() => _unreadCount++);
    });
  }

  Future<void> _loadMotherData() async {
    _motherId = await AuthStorage.getMotherId();
    if (_motherId != null) {
      final url = await SupabaseService.getProfilePictureUrl(_motherId!);
      if (mounted) {
        setState(() {
          _profilePictureUrl = url;
        });
      }
    } else {
      _checkAndShowBHCRequiredDialog();
    }
  }

  Future<void> _checkAndShowBHCRequiredDialog() async {
    if (_showBHCRequiredDialog) return;

    final accountId = await AuthStorage.getUserId();
    if (accountId == null) return;

    try {
      final motherResponse = await SupabaseService.client
          .from('mothers')
          .select(
              'mother_id, assigned_bhc_id, pregnancies(status, risk_level, risk_factors)')
          .eq('account_id', accountId)
          .maybeSingle();

      if (motherResponse != null) {
        final motherId = motherResponse['mother_id'] as int;
        await AuthStorage.saveMotherId(motherId);

        String riskLevel = '';
        List<String> riskFactors = [];
        final pregnancies = motherResponse['pregnancies'] as List?;
        if (pregnancies != null && pregnancies.isNotEmpty) {
          final activePregnancy = pregnancies.firstWhere(
            (p) => p['status'] == 'active',
            orElse: () => null,
          );
          if (activePregnancy != null) {
            riskLevel = activePregnancy['risk_level']?.toString() ?? '';
            final rf = activePregnancy['risk_factors']?.toString() ?? '';
            if (rf.isNotEmpty) {
              riskFactors = rf
                  .split(';')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList();
            }
          }
        }

        setState(() {
          _motherId = motherId;
          _riskLevel = riskLevel;
          _riskFactors = riskFactors;
        });
      }
    } catch (e) {
      debugPrint('Error checking mother record: $e');
    }
  }

  Future<void> _logout() async {
    await PushNotificationService.removeToken();
    await AuthStorage.clearAll();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  Color _getRiskColor(String riskLevel) {
    switch (riskLevel.toUpperCase().trim()) {
      case 'HIGH':
        return AppColors.error;
      case 'MODERATE':
        return AppColors.warning;
      case 'LOW':
        return AppColors.success;
      default:
        return AppColors.textSecondary;
    }
  }

  void _showRiskSummaryBottomSheet() {
    final badgeColor = _getRiskColor(_riskLevel);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.68,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (_, controller) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.all(24),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.shield_outlined,
                            color: badgeColor, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              LanguageService.translate(
                                  'Prenatal Risk Summary', 'Buod ng Panganib'),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _riskLevel.toUpperCase(),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: badgeColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (_riskFactors.isNotEmpty) ...[
                    Text(
                      LanguageService.translate(
                          'Risk Factors', 'Mga Salik ng Panganib'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._riskFactors.map((f) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Icon(Icons.circle,
                                    size: 8, color: badgeColor),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  f,
                                  style: const TextStyle(
                                      fontSize: 15, height: 1.4),
                                ),
                              ),
                            ],
                          ),
                        )),
                  ] else ...[
                    Text(
                      LanguageService.translate(
                          'No active risk factors detected.',
                          'Walang nakitang aktibong salik ng panganib.'),
                      style: const TextStyle(
                          fontSize: 15, color: AppColors.textSecondary),
                    ),
                  ],
                  const SizedBox(height: 32),
                  MainButton(
                    label: LanguageService.translate('Close', 'Isara'),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showProfileMenu(BuildContext context) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          GestureDetector(
            onTap: () => entry.remove(),
            child: Container(
              color: Colors.black.withValues(alpha: 0.35),
            ),
          ),
          Positioned(
            top: 80,
            right: 16,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 220, // ← FIXED: Increased width slightly
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.cardColorOf(context),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min, // ← FIXED: Use min size
                  children: [
                    _MenuItem(
                      icon: Icons.person_outline,
                      label: LanguageService.translate(
                          'View Profile', 'Tingnan ang Profile'),
                      onTap: () {
                        entry.remove();
                        if (_motherId != null && mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  MotherSelfProfilePage(motherId: _motherId!),
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                LanguageService.translate(
                                  'Please complete your account setup with a midwife first.',
                                  'Kumpletuhin muna ang pag-setup ng account kasama ang midwife.',
                                ),
                              ),
                              backgroundColor: AppColors.warning,
                            ),
                          );
                        }
                      },
                    ),
                    if (_riskLevel.isNotEmpty) ...[
                      _MenuItem(
                        icon: Icons.shield_outlined,
                        label: LanguageService.translate(
                            'Risk Summary', 'Buod ng Panganib'),
                        iconColor: _getRiskColor(_riskLevel),
                        onTap: () {
                          entry.remove();
                          _showRiskSummaryBottomSheet();
                        },
                      ),
                    ],
                    _MenuItem(
                      icon: Icons.settings_outlined,
                      label:
                          LanguageService.translate('Settings', 'Mga Setting'),
                      onTap: () {
                        entry.remove();
                        Navigator.pushNamed(context, '/settings');
                      },
                    ),
                    _MenuItem(
                      icon: Icons.help_outline,
                      label: LanguageService.translate('Help', 'Tulong'),
                      onTap: () {
                        entry.remove();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const HelpSupportScreen(),
                          ),
                        );
                      },
                    ),
                    const Divider(
                        height: 1,
                        thickness: 1,
                        color: AppColors.borderPrimary),
                    _MenuItem(
                      icon: Icons.logout_rounded,
                      label: LanguageService.translate('Log out', 'Mag-logout'),
                      isDanger: true,
                      onTap: () {
                        entry.remove();
                        _confirmLogout(context);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    overlay.insert(entry);
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        // The tinted ground the rest of the mother's dialogs use, so this does
        // not read as a system alert dropped into the app.
        backgroundColor: const Color(0xFFFFF7FA),
        surfaceTintColor: const Color(0xFFFFF7FA),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  size: 30,
                  color: AppColors.error,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                LanguageService.translate('Log out', 'Mag-logout'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  // Soft dark grey, not the bold near-black the default
                  // dialog title used.
                  color: AppColors.headingSoft,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                LanguageService.translate(
                  'Are you sure you want to log out of your account?',
                  'Sigurado ka bang mag-logout sa iyong account?',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.inputText,
                  fontSize: 14.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              // Stacked, not side by side.
              //
              // Two buttons sharing a row have to fit the longest label in
              // either language, and "Kanselahin" beside "Mag-logout" leaves
              // each of them a little over a hundred pixels on a small phone.
              // Full width also gives the destructive action a target she is
              // not going to hit by accident reaching for the other one.
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    _logout();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    elevation: 3,
                    shadowColor: AppColors.error.withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(27),
                    ),
                  ),
                  child: Text(
                    LanguageService.translate('Log out', 'Mag-logout'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: Text(
                    LanguageService.translate('Cancel', 'Kanselahin'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LanguageService.selectedLanguage,
      builder: (context, language, _) {
        // Driven off the same list as the tabs. As a fixed array indexed by
        // _currentIndex, this would have captioned Records "CHILDREN" the
        // moment a tab was hidden — the header and the page disagreeing with
        // no error to notice.
        final tabs = _visibleTabs;
        final titles = tabs
            .map((tab) => LanguageService.translate(
                tab.labelEnglish.toUpperCase(), tab.labelFilipino))
            .toList();
        final safeIndex =
            tabs.isEmpty ? 0 : _currentIndex.clamp(0, tabs.length - 1);

        return Scaffold(
          backgroundColor: AppColors.bgPrimaryOf(context),
          body: SafeArea(
            child: Column(
              children: [
                // Header
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.cardColorOf(context),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Image.asset(
                          'assets/images/logo.png',
                          height: 36,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(Icons.favorite,
                                  color: AppColors.brandPrimary, size: 30),
                        ),
                      ),
                      Text(
                        titles[safeIndex],
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brandText,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const NotificationsScreen()),
                          );
                          _setupNotifications();
                        },
                        // The midwife's bell, with one change: at rest it uses
                        // the softer ink rather than near-black, which is the
                        // standing rule on the mother's side.
                        icon: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(
                              _unreadCount > 0
                                  ? Icons.notifications_active_rounded
                                  : Icons.notifications_none_rounded,
                              size: 24,
                              color: _unreadCount > 0
                                  ? AppColors.brandPrimary
                                  : AppColors.inputText,
                            ),
                            if (_unreadCount > 0)
                              Positioned(
                                top: -2,
                                right: -2,
                                child: IgnorePointer(
                                  child: Container(
                                    constraints: const BoxConstraints(
                                        minWidth: 16, minHeight: 16),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEF4444),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: Colors.white, width: 1.5),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      _unreadCount > 99
                                          ? '99+'
                                          : '$_unreadCount',
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
                        ),
                      ),
                      const SizedBox(width: 14),
                      GestureDetector(
                        onTap: () => _showProfileMenu(context),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.brandPrimary,
                            image: _profilePictureUrl != null
                                ? DecorationImage(
                                    image: NetworkImage(_profilePictureUrl!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: _profilePictureUrl == null
                              ? const Icon(
                                  Icons.person,
                                  size: 20,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),

                // Offline banner
                if (_isOffline)
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    color: AppColors.error,
                    child: Row(
                      children: const [
                        Icon(Icons.wifi_off, size: 16, color: Colors.white),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'No internet connection — some features may not work.',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Content
                Expanded(
                  child: IndexedStack(
                    index: safeIndex,
                    children: tabs.map(_screenFor).toList(),
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: Container(
            height: 70,
            decoration: BoxDecoration(
              color: AppColors.cardColorOf(context),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (final (index, tab) in tabs.indexed)
                  _NavItem(
                    icon: tab.icon,
                    activeIcon: tab.activeIcon,
                    label: LanguageService.translate(
                        tab.labelEnglish, tab.labelFilipino),
                    isActive: safeIndex == index,
                    onTap: () => setState(() => _currentIndex = index),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color color = isActive
        ? AppColors.brandPrimaryOf(context)
        : AppColors.textSecondaryOf(context);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isActive ? activeIcon : icon,
            size: 26,
            color: color,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          if (isActive)
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.brandPrimaryOf(context),
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDanger;
  final Color? iconColor;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDanger = false,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDanger ? AppColors.error : AppColors.textPrimaryOf(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor ?? color),
            const SizedBox(width: 12),
            Expanded(
              // ← FIXED: Added Expanded to prevent overflow
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
