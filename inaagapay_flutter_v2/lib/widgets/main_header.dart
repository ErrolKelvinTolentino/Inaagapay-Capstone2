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
  final bool showBackButton;
  final VoidCallback? onBack;
  final int notificationCount;

  const MainHeader({
    super.key,
    required this.title,
    this.onNotificationTap,
    this.avatarImage,
    this.onViewProfile,
    this.onSettings,
    this.onHelp,
    this.onLogout,
    this.showBackButton = false,
    this.onBack,
    this.notificationCount = 0,
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
        title: 'Log out',
        subtitle: 'Are you sure you want to log out of your account?',
        confirmText: 'Log out',
        cancelText: 'Cancel',
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
        padding: const EdgeInsets.symmetric(horizontal: 16),
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
            if (showBackButton) ...[
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 20,
                  color: AppColors.brandText,
                ),
                tooltip: 'Back',
              ),
              const SizedBox(width: 4),
            ] else ...[
              /// LOGO
              Image.asset(
                'assets/images/logo.png',
                height: 40,
                errorBuilder: (context, error, stackTrace) => 
                  const Icon(Icons.favorite, color: AppColors.brandPrimary, size: 30),
              ),
              const SizedBox(width: 12),
            ],

            /// TITLE
            Expanded(
              child: Text(
                title.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandText,
                  letterSpacing: 0.4,
                ),
              ),
            ),

            /// NOTIFICATIONS
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  onPressed: onNotificationTap,
                  icon: Icon(
                    notificationCount > 0
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_none_rounded,
                    size: 24,
                    color: notificationCount > 0
                        ? AppColors.brandPrimary
                        : AppColors.textPrimary,
                  ),
                ),
                if (notificationCount > 0)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: IgnorePointer(
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          notificationCount > 99 ? '99+' : '$notificationCount',
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

            const SizedBox(width: 10),

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

  const _ProfileMenu({
    required this.onClose,
    this.onViewProfile,
    this.onSettings,
    this.onHelp,
    this.onLogout,
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
              label: 'View Profile',
              onTap: () {
                onClose();
                onViewProfile?.call();
              },
            ),
            _MenuItem(
              icon: Icons.settings_outlined,
              label: 'Settings',
              onTap: () {
                onClose();
                onSettings?.call();
              },
            ),
            _MenuItem(
              icon: Icons.help_outline,
              label: 'Help',
              onTap: () {
                onClose();
                onHelp?.call();
              },
            ),
            const Divider(height: 8, color: AppColors.borderPrimary),
            _MenuItem(
              icon: Icons.logout_rounded,
              label: 'Log out',
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
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}