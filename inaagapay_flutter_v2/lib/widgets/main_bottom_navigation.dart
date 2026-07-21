// lib/widgets/main_bottom_navigation.dart

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class MainBottomNavigation extends StatelessWidget {
  final int currentIndex;
  final Function(int)? onTap;
  final List<String>? labels;
  final List<IconData>? icons;
  final List<IconData>? activeIcons;

  const MainBottomNavigation({
    super.key,
    required this.currentIndex,
    this.onTap,
    this.labels,
    this.icons,
    this.activeIcons,
  })  : assert(labels == null || labels.length == 4),
        assert(icons == null || icons.length == 4),
        assert(activeIcons == null || activeIcons.length == 4);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: Colors.white,
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
          _NavItem(
            icon: icons?[0] ?? Icons.home_outlined,
            activeIcon: activeIcons?[0] ?? Icons.home,
            label: labels?[0] ?? 'Home',
            isActive: currentIndex == 0,
            onTap: () => onTap?.call(0),
          ),
          _NavItem(
            icon: icons?[1] ?? Icons.menu_book_outlined,
            activeIcon: activeIcons?[1] ?? Icons.menu_book,
            label: labels?[1] ?? 'Journal',
            isActive: currentIndex == 1,
            onTap: () => onTap?.call(1),
          ),
          _NavItem(
            icon: icons?[2] ?? Icons.child_care_outlined,
            activeIcon: activeIcons?[2] ?? Icons.child_care,
            label: labels?[2] ?? 'Children',
            isActive: currentIndex == 2,
            onTap: () => onTap?.call(2),
          ),
          _NavItem(
            icon: icons?[3] ?? Icons.folder_outlined,
            activeIcon: activeIcons?[3] ?? Icons.folder,
            label: labels?[3] ?? 'Records',
            isActive: currentIndex == 3,
            onTap: () => onTap?.call(3),
          ),
        ],
      ),
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
    final Color color =
        isActive ? AppColors.brandPrimary : AppColors.textSecondary;

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
                color: AppColors.brandPrimary,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }
}
