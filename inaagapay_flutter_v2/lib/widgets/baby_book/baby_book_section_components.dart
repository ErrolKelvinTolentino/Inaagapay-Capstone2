import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

class BabyBookSectionHeader extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String? description;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  const BabyBookSectionHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.description,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: const TextStyle(
            color: AppColors.brandText,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.25,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: const TextStyle(
            color: AppColors.headingSoft,
            fontSize: 21,
            height: 1.2,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brandPrimary,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              icon: Icon(actionIcon ?? Icons.add_rounded, size: 17),
              label: Text(
                actionLabel!,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
        if (description != null) ...[
          const SizedBox(height: 7),
          Text(
            description!,
            style: const TextStyle(
              color: AppColors.inputText,
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }
}

class BabyBookPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color borderColor;

  const BabyBookPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = Colors.white,
    this.borderColor = const Color(0xFFF5E8ED),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF69243F).withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: child,
    );
  }
}

class BabyBookStatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const BabyBookStatusPill({
    super.key,
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 8,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class BabyBookTwinPregnancyBadge extends StatelessWidget {
  final bool light;

  const BabyBookTwinPregnancyBadge({super.key, required this.light});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: light
            ? Colors.white.withValues(alpha: 0.18)
            : const Color(0xFFF1E8F8),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.child_friendly_rounded,
            color: light ? Colors.white : const Color(0xFF8055A6),
            size: 13,
          ),
          const SizedBox(width: 4),
          Text(
            'Twin Pregnancy',
            style: TextStyle(
              color: light ? Colors.white : const Color(0xFF8055A6),
              fontSize: 8,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class BabyBookPictureCardShell extends StatelessWidget {
  final String assetPath;
  final String semanticLabel;
  final double height;
  final Widget child;
  final AlignmentGeometry imageAlignment;
  final Key? imageKey;

  const BabyBookPictureCardShell({
    super.key,
    required this.assetPath,
    required this.semanticLabel,
    required this.height,
    required this.child,
    this.imageAlignment = Alignment.centerRight,
    this.imageKey,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: semanticLabel,
      child: Container(
        width: double.infinity,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8C3558).withValues(alpha: 0.14),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              assetPath,
              key: imageKey,
              alignment: imageAlignment,
              fit: BoxFit.cover,
              excludeFromSemantics: true,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Color(0xE8C84472),
                    Color(0xA6E45C8C),
                    Color(0x18E45C8C),
                  ],
                  stops: [0, 0.46, 0.8],
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

class BabyBookPictureBanner extends StatelessWidget {
  final String assetPath;
  final String semanticLabel;
  final String eyebrow;
  final String title;
  final String subtitle;
  final AlignmentGeometry imageAlignment;

  const BabyBookPictureBanner({
    super.key,
    required this.assetPath,
    required this.semanticLabel,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.imageAlignment = Alignment.centerRight,
  });

  @override
  Widget build(BuildContext context) {
    return BabyBookPictureCardShell(
      assetPath: assetPath,
      semanticLabel: semanticLabel,
      height: 168,
      imageAlignment: imageAlignment,
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 230),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.86),
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.05,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    height: 1.15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.25,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  subtitle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 9,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String babyBookFormatDate(DateTime date) {
  const months = <String>[
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
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}
