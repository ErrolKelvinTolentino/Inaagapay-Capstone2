// lib/widgets/app_input_field.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';

class AppInputField extends StatefulWidget {
  final String hintText;
  final TextEditingController controller;
  final bool isRequired;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final VoidCallback? onTrailingTap;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final bool obscureText;
  final TextInputType keyboardType;
  final bool readOnly;
  final List<TextInputFormatter>? inputFormatters;
  final String? errorText;

  const AppInputField({
    super.key,
    required this.hintText,
    required this.controller,
    this.isRequired = false,
    this.leadingIcon,
    this.trailingIcon,
    this.onTrailingTap,
    this.onTap,
    this.onChanged,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.readOnly = false,
    this.inputFormatters,
    this.errorText,
  });

  @override
  State<AppInputField> createState() => _AppInputFieldState();
}

class _AppInputFieldState extends State<AppInputField> {
  bool _isHovered = false;
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final bool hasError = widget.errorText != null;

    Color borderColor() {
      if (hasError) return AppColors.error;
      if (_isFocused) return AppColors.brandPrimary;
      if (_isHovered) return AppColors.brandPrimary.withValues(alpha: 0.4);
      return Colors.transparent;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Focus(
        onFocusChange: (focused) => setState(() => _isFocused = focused),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: borderColor(),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  if (widget.leadingIcon != null) ...[
                    Icon(
                      widget.leadingIcon,
                      color: hasError ? AppColors.error : AppColors.brandAccent,
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      obscureText: widget.obscureText,
                      keyboardType: widget.keyboardType,
                      readOnly: widget.readOnly,
                      inputFormatters: widget.inputFormatters,
                      onTap: widget.onTap,
                      onChanged: widget.onChanged,
                      style: const TextStyle(
                        color: AppColors.inputText,
                        fontSize: 16,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        floatingLabelBehavior: widget.controller.text.isNotEmpty
                            ? FloatingLabelBehavior.always
                            : FloatingLabelBehavior.auto,
                        label: RichText(
                          text: TextSpan(
                            text: widget.hintText,
                            style: TextStyle(
                              color: hasError
                                  ? AppColors.error.withValues(alpha: 0.7)
                                  : AppColors.textSecondary,
                              fontSize: 14,
                            ),
                            children: widget.isRequired
                                ? const [
                                    TextSpan(
                                      text: ' *',
                                      style: TextStyle(
                                        color: AppColors.error,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ]
                                : [],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.trailingIcon != null)
                    GestureDetector(
                      onTap: widget.onTrailingTap,
                      child: Icon(
                        widget.trailingIcon,
                        color:
                            hasError ? AppColors.error : AppColors.brandAccent,
                      ),
                    ),
                ],
              ),
            ),
            if (hasError)
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 6),
                child: Text(
                  widget.errorText!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
