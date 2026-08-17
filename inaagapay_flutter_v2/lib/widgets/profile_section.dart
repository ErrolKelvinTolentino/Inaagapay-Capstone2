// lib/widgets/profile_section.dart
// A consistently-styled card section wrapper and info row used on the Mother Profile page.

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class ProfileCardSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color? iconColor;
  final List<Widget> children;
  final Widget? actionButton;

  const ProfileCardSection({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.iconColor,
    this.actionButton,
  });

  @override
  Widget build(BuildContext context) {
    final accent = iconColor ?? AppColors.brandPrimary;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(
          color: AppColors.brandPrimary.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // The heading treatment used by the weight-gain and blood pressure
            // cards, and now by the record detail screen: a small brand icon,
            // uppercase letterspaced grey, on the card's own white.
            //
            // It was a tinted bar with a tinted icon chip and a pink title —
            // three applications of the brand colour before a single record
            // appeared, on a page that stacks eight of these sections. The
            // heading's job is to be found, not to be looked at.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 4),
              child: Row(
                children: [
                  Icon(icon, color: accent, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: Color(0xFF5A5A5A),
                      ),
                    ),
                  ),
                  if (actionButton != null) actionButton!,
                ],
              ),
            ),
            // Card Content Body
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProfileSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color? iconColor;
  final List<Widget> children;
  final bool initiallyExpanded;
  final Widget? trailing;

  const ProfileSection({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.iconColor,
    this.initiallyExpanded = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final accent = iconColor ?? AppColors.brandPrimary;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
        ),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: EdgeInsets.zero,
          leading: Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accent, size: 18),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          trailing: trailing,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Info row used inside sections ─────────────────────────────────────────

class ProfileInfoRow extends StatelessWidget {
  final String? label;
  final Widget? labelWidget;
  final String? value;
  final Widget? valueWidget;
  final Color? valueColor;
  final IconData? icon;

  const ProfileInfoRow({
    super.key,
    this.label,
    this.labelWidget,
    this.value,
    this.valueWidget,
    this.valueColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: AppColors.brandPrimary),
            const SizedBox(width: 10),
          ],
          Expanded(
            flex: 2,
            child: labelWidget ??
                Text(
                  label ?? '',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
          ),
          Expanded(
            flex: 3,
            child: valueWidget ??
                Text(
                  value ?? '',
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? AppColors.inputText,
                  ),
                ),
          ),
        ],
      ),
    );
  }
}
