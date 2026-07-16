// lib/widgets/clickable_text.dart
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class ClickableText extends StatefulWidget {
  final String text;
  final VoidCallback onTap;
  final bool underline;
  final Color? color;
  final double? fontSize;
  final FontWeight? fontWeight;

  const ClickableText({
    super.key,
    required this.text,
    required this.onTap,
    this.underline = false,
    this.color,
    this.fontSize,
    this.fontWeight,
  });

  @override
  State<ClickableText> createState() => _ClickableTextState();
}

class _ClickableTextState extends State<ClickableText> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final Color baseColor = widget.color ?? AppColors.brandPrimary;

    Color textColor() {
      if (_pressed) return AppColors.brandAccent;
      if (_hovered) return baseColor.withValues(alpha: 0.85);
      return baseColor;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            style: TextStyle(
              fontSize: widget.fontSize ?? 14,
              fontWeight: widget.fontWeight ?? FontWeight.w600,
              color: textColor(),
              decoration: widget.underline
                  ? TextDecoration.underline
                  : TextDecoration.none,
            ),
            child: Text(widget.text),
          ),
        ),
      ),
    );
  }
}
