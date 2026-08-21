// lib/screens/settings_screen.dart
//
// Shared by midwives and mothers — both account menus route here — so anything
// role-specific is gated on the signed-in account type rather than duplicated
// into a second screen.
//
// Every control on this page does something. A settings screen that offers
// switches which change nothing is worse than a short one: it teaches the user
// that the app's controls are decoration, and the next switch — the one that
// matters — gets the same treatment. Dark mode is the obvious candidate and is
// deliberately absent: `main.dart` pins `themeMode: ThemeMode.light`, so a
// toggle would be a dead switch until the theme is actually wired.

import 'package:flutter/material.dart';

import '../services/auth_storage.dart';
import '../services/language_service.dart';
import '../theme/app_colors.dart';
import '../widgets/profile_section.dart';
import '../widgets/secondary_header.dart';

/// The version shown on this page.
///
/// Held as a constant rather than read through a plugin: the only thing needed
/// is one short string, and a platform plugin added for it is another moving
/// part that can fail silently on one platform and not another.
///
/// `test/app_version_test.dart` asserts this matches `pubspec.yaml`, so it
/// cannot drift without a test failing.
const String kAppVersion = '1.0.0+1';

/// The alert categories a midwife can switch off, matching
/// `MidwifeAlertCategory` in the notification centre.
///
/// Named here as plain strings rather than importing the enum so a settings
/// screen shared with mothers does not pull in a midwife-only screen.
const _alertCategories = <_AlertCategoryOption>[
  _AlertCategoryOption(
    key: 'inventory',
    label: 'Stock levels',
    description: 'Low stock and out-of-stock items at your health centre.',
    icon: Icons.inventory_2_outlined,
  ),
  _AlertCategoryOption(
    key: 'expiries',
    label: 'Expiries',
    description: 'Batches expiring soon and open vials past their shelf limit.',
    icon: Icons.event_busy_outlined,
  ),
  _AlertCategoryOption(
    key: 'transfers',
    label: 'Stock requests & transfers',
    description: 'Requests approved or rejected, and deliveries in transit.',
    icon: Icons.local_shipping_outlined,
  ),
  _AlertCategoryOption(
    key: 'clinical',
    label: 'Clinical follow-ups',
    description: 'Mothers and children flagged for closer monitoring.',
    icon: Icons.medical_information_outlined,
  ),
];

class _AlertCategoryOption {
  final String key;
  final String label;
  final String description;
  final IconData icon;

  const _AlertCategoryOption({
    required this.key,
    required this.label,
    required this.description,
    required this.icon,
  });
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading = true;
  bool _isMidwife = false;
  Set<String> _muted = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final role = await AuthStorage.getUserRole();
      final muted = await AuthStorage.getMutedAlertCategories();

      if (!mounted) return;
      setState(() {
        _isMidwife = role?.toLowerCase() == 'midwife';
        _muted = muted.toSet();
        _loading = false;
      });
    } catch (e) {
      debugPrint('Settings load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setCategoryEnabled(String key, bool enabled) async {
    setState(() {
      if (enabled) {
        _muted.remove(key);
      } else {
        _muted.add(key);
      }
    });
    try {
      await AuthStorage.saveMutedAlertCategories(_muted.toList());
    } catch (e) {
      debugPrint('Could not save alert preferences: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save that preference on this device.'),
          backgroundColor: AppColors.warning,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: SecondaryHeader(
          title: LanguageService.translate('Settings', 'Mga Setting'),
          onBack: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.brandPrimary))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _buildLanguageSection(),
                if (_isMidwife) ...[
                  const SizedBox(height: 14),
                  _buildAlertsSection(),
                ],
                const SizedBox(height: 14),
                _buildAboutSection(),
              ],
            ),
    );
  }

  // ── Language ──────────────────────────────────────────────────────────────

  Widget _buildLanguageSection() {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LanguageService.selectedLanguage,
      builder: (context, language, _) {
        return ProfileCardSection(
          title: LanguageService.translate('Language', 'Wika'),
          icon: Icons.translate_rounded,
          children: [
            Text(
              LanguageService.translate(
                'Used for pregnancy guidance, the baby book and health tips.',
                'Ginagamit sa gabay sa pagbubuntis, baby book at mga health tip.',
              ),
              style: const TextStyle(
                fontSize: 12,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            // Two pills rather than a radio list. The choice is binary and the
            // app states a preference for pills everywhere else it offers one.
            Row(
              children: [
                for (final option in AppLanguage.values) ...[
                  Expanded(
                    child: _ChoicePill(
                      label: LanguageService.displayName(option),
                      selected: language == option,
                      onTap: () =>
                          LanguageService.selectedLanguage.value = option,
                    ),
                  ),
                  if (option != AppLanguage.values.last)
                    const SizedBox(width: 10),
                ],
              ],
            ),
          ],
        );
      },
    );
  }

  // ── Alerts ────────────────────────────────────────────────────────────────

  Widget _buildAlertsSection() {
    final onCount = _alertCategories.length - _muted.length;

    return ProfileCardSection(
      title: 'Alerts',
      icon: Icons.notifications_none_rounded,
      actionButton: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          '$onCount of ${_alertCategories.length} on',
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF475569),
          ),
        ),
      ),
      children: [
        const Text(
          'Choose what appears in your notifications. Switching a category off '
          'hides it from the list — it does not stop the situation itself, and '
          'stock levels still change either way.',
          style: TextStyle(
            fontSize: 12,
            height: 1.45,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        for (final option in _alertCategories)
          _AlertToggle(
            option: option,
            enabled: !_muted.contains(option.key),
            onChanged: (v) => _setCategoryEnabled(option.key, v),
          ),
        if (_muted.length == _alertCategories.length) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 16, color: Color(0xFFD97706)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Every category is off, so your notifications page will be '
                    'empty even when stock runs out.',
                    style: TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: Color(0xFF92400E)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ── About ─────────────────────────────────────────────────────────────────

  Widget _buildAboutSection() {
    return ProfileCardSection(
      title: LanguageService.translate('About', 'Tungkol Dito'),
      icon: Icons.info_outline_rounded,
      children: [
        ProfileInfoRow(
          label: LanguageService.translate('App version', 'Bersyon ng app'),
          value: kAppVersion,
        ),
        const ProfileInfoRow(
          label: 'Clinical standards',
          value: 'DOH · WHO',
        ),
        const SizedBox(height: 8),
        Text(
          LanguageService.translate(
            'InaAgapay supports maternal and child health monitoring at the '
            'barangay health centre. It records and organises what your '
            'midwife enters — it does not diagnose, and it does not replace a '
            'consultation.',
            'Tumutulong ang InaAgapay sa pagsubaybay ng kalusugan ng ina at '
            'bata sa barangay health center. Itinatala at inaayos nito ang '
            'ipinapasok ng iyong midwife — hindi ito nagbibigay ng diagnosis '
            'at hindi kapalit ng konsultasyon.',
          ),
          style: const TextStyle(
            fontSize: 11.5,
            height: 1.5,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ── Pieces ──────────────────────────────────────────────────────────────────

class _ChoicePill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChoicePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.brandPrimary : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? AppColors.brandPrimary
                  : AppColors.borderPrimary,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _AlertToggle extends StatelessWidget {
  final _AlertCategoryOption option;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _AlertToggle({
    required this.option,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: enabled
                  ? AppColors.brandPrimary.withValues(alpha: 0.10)
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              option.icon,
              size: 16,
              color: enabled
                  ? AppColors.brandPrimary
                  : AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  option.label,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  option.description,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: enabled,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: AppColors.brandPrimary,
          ),
        ],
      ),
    );
  }
}
