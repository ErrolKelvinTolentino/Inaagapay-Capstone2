// lib/widgets/secondary_header.dart

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class SecondaryHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;

  const SecondaryHeader({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: 56,
        width: double.infinity,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48.0),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandPrimary,
                ),
              ),
            ),
            Positioned(
              left: 0,
              child: onBack != null
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new),
                      color: AppColors.brandPrimary,
                      onPressed: onBack,
                    )
                  : const SizedBox.shrink(),
            ),
            if (trailing != null)
              Positioned(
                right: 8,
                child: trailing!,
              ),
          ],
        ),
      ),
    );
  }
}
