// lib/widgets/main_header.dart

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'confirmation_dialog_box.dart';

class MainHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onNotificationTap;
  final ImageProvider? avatarImage;
  final VoidCallback? onViewProfile;
  final VoidCallback? onSettings;
  final VoidCallback? onHelp;
  final VoidCallback? onLogout;
  final String viewProfileLabel;
  final String settingsLabel;
  final String helpLabel;
  final String logoutLabel;
  final String logoutQuestion;
  final String cancelLabel;

  const MainHeader({
    super.key,
    required this.title,
    this.onNotificationTap,
    this.avatarImage,
    this.onViewProfile,
    this.onSettings,
    this.onHelp,
    this.onLogout,
    this.viewProfileLabel = 'View Profile',
    this.settingsLabel = 'Settings',
    this.helpLabel = 'Help',
    this.logoutLabel = 'Log out',
    this.logoutQuestion = 'Are you sure you want to log out of your account?',
    this.cancelLabel = 'Cancel',
  });

  void _showProfileMenu(BuildContext context) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          /// FULLSCREEN OVERLAY
          GestureDetector(
            onTap: () => entry.remove(),
            child: Container(
              color: Colors.black.withValues(alpha: 0.35),
            ),
          ),

          /// PROFILE MENU
          Positioned(
            top: 80,
            right: 16,
            child: _ProfileMenu(
              onClose: () => entry.remove(),
              onViewProfile: onViewProfile,
              onSettings: onSettings,
              onHelp: onHelp,
              viewProfileLabel: viewProfileLabel,
              settingsLabel: settingsLabel,
              helpLabel: helpLabel,
              logoutLabel: logoutLabel,
              onLogout: () {
                entry.remove();
                _confirmLogout(context);
              },
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
      builder: (_) => ConfirmationDialogBox(
        title: logoutLabel,
        subtitle: logoutQuestion,
        confirmText: logoutLabel,
        cancelText: cancelLabel,
        accentColor: AppColors.error,
        onCancel: () => Navigator.pop(context),
        onConfirm: () {
          Navigator.pop(context);
          onLogout?.call();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.bgPrimary,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            /// LOGO
            Image.asset(
              'assets/images/logo.png',
              height: 40,
              errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.favorite,
                  color: AppColors.brandPrimary,
                  size: 30),
            ),

            const SizedBox(width: 12),

            /// TITLE
            Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.brandText,
                letterSpacing: 0.4,
              ),
            ),

            const Spacer(),

            /// NOTIFICATIONS
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: onNotificationTap,
              icon: const Icon(
                Icons.notifications_none_rounded,
                size: 24,
                color: AppColors.textPrimary,
              ),
            ),

            const SizedBox(width: 14),

            /// AVATAR
            GestureDetector(
              onTap: () => _showProfileMenu(context),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.brandPrimary,
                  image: avatarImage != null
                      ? DecorationImage(
                          image: avatarImage!,
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: avatarImage == null
                    ? const Icon(
                        Icons.person,
                        size: 18,
                        color: Colors.white,
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                               PROFILE MENU                                 */
/* -------------------------------------------------------------------------- */

class _ProfileMenu extends StatelessWidget {
  final VoidCallback onClose;
  final VoidCallback? onViewProfile;
  final VoidCallback? onSettings;
  final VoidCallback? onHelp;
  final VoidCallback? onLogout;
  final String viewProfileLabel;
  final String settingsLabel;
  final String helpLabel;
  final String logoutLabel;

  const _ProfileMenu({
    required this.onClose,
    this.onViewProfile,
    this.onSettings,
    this.onHelp,
    this.onLogout,
    required this.viewProfileLabel,
    required this.settingsLabel,
    required this.helpLabel,
    required this.logoutLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 200,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
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
          children: [
            _MenuItem(
              icon: Icons.person_outline,
              label: viewProfileLabel,
              onTap: () {
                onClose();
                onViewProfile?.call();
              },
            ),
            _MenuItem(
              icon: Icons.settings_outlined,
              label: settingsLabel,
              onTap: () {
                onClose();
                onSettings?.call();
              },
            ),
            _MenuItem(
              icon: Icons.help_outline,
              label: helpLabel,
              onTap: () {
                onClose();
                onHelp?.call();
              },
            ),
            const Divider(height: 8, color: AppColors.borderPrimary),
            _MenuItem(
              icon: Icons.logout_rounded,
              label: logoutLabel,
              isDanger: true,
              onTap: () {
                onLogout?.call();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDanger;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDanger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDanger ? AppColors.error : AppColors.textPrimary;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
