// lib/widgets/records_display_card.dart

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class RecordsDisplayCard extends StatelessWidget {
  final String title;
  final IconData headerIcon;
  final List<RecordItem> items;

  const RecordsDisplayCard({
    super.key,
    required this.title,
    required this.headerIcon,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
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
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            // Gradient Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    AppColors.brandPrimary.withValues(alpha: 0.12),
                    AppColors.brandPrimary.withValues(alpha: 0.05),
                  ],
                ),
                border: Border(
                  bottom: BorderSide(color: AppColors.brandPrimary.withValues(alpha: 0.2), width: 1),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.brandPrimary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(headerIcon, color: AppColors.brandPrimary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    title.toUpperCase(),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandPrimary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            
            // Content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: items.map((item) => item.build()).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RecordItem {
  final IconData leadingIcon;
  final String label;
  final String? subLabel;
  final String value;
  final Widget? trailingWidget;
  final VoidCallback? onTap;

  const RecordItem({
    required this.leadingIcon,
    required this.label,
    this.subLabel,
    required this.value,
    this.trailingWidget,
    this.onTap,
  });

  Widget build() {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Icon(leadingIcon, size: 18, color: AppColors.brandPrimary),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (subLabel != null && subLabel!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subLabel!,
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.right,
              ),
            ),
            if (trailingWidget != null) ...[
              const SizedBox(width: 8),
              trailingWidget!,
            ],
          ],
        ),
      ),
    );
  }
}