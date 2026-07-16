import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum AppSnackType { info, success, warning, error }

class AppSnackbar {
  static void show(
    BuildContext context,
    String message, {
    AppSnackType type = AppSnackType.info,
    Duration duration = const Duration(seconds: 4),
    bool showProgress = true,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    final accent = _accentColor(type);

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: duration,
        content: _AppSnackBody(
          message: message,
          accent: accent,
          icon: _icon(type),
          showProgress: showProgress,
          duration: duration,
        ),
      ),
    );
  }

  static void info(BuildContext context, String message) {
    show(context, message, type: AppSnackType.info);
  }

  static void success(BuildContext context, String message) {
    show(context, message, type: AppSnackType.success);
  }

  static void warning(BuildContext context, String message) {
    show(context, message, type: AppSnackType.warning);
  }

  static void error(BuildContext context, String message) {
    show(context, message, type: AppSnackType.error);
  }

  static Color _accentColor(AppSnackType type) {
    switch (type) {
      case AppSnackType.success:
        return AppColors.success;
      case AppSnackType.warning:
        return AppColors.warning;
      case AppSnackType.error:
        return AppColors.error;
      case AppSnackType.info:
        return AppColors.brandPrimary;
    }
  }

  static IconData _icon(AppSnackType type) {
    switch (type) {
      case AppSnackType.success:
        return Icons.check_circle_outline;
      case AppSnackType.warning:
        return Icons.warning_amber_rounded;
      case AppSnackType.error:
        return Icons.close_rounded;
      case AppSnackType.info:
        return Icons.info_outline;
    }
  }
}

class _AppSnackBody extends StatelessWidget {
  const _AppSnackBody({
    required this.message,
    required this.accent,
    required this.icon,
    required this.showProgress,
    required this.duration,
  });

  final String message;
  final Color accent;
  final IconData icon;
  final bool showProgress;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderPrimary),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 1),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 18, color: accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        message,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () =>
                        ScaffoldMessenger.of(context).hideCurrentSnackBar(),
                    splashRadius: 18,
                    tooltip: 'Dismiss',
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (showProgress)
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(14)),
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 1, end: 0),
                  duration: duration,
                  builder: (context, value, _) {
                    return LinearProgressIndicator(
                      value: value,
                      minHeight: 2,
                      color: accent,
                      backgroundColor: AppColors.borderPrimary,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
