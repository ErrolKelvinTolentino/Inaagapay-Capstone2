// lib/widgets/app_dropdown_field.dart

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class AppDropdownField<T extends Object> extends StatefulWidget {
  final String hintText;
  final IconData? leadingIcon;
  final T? value;
  final List<T> options;
  final String Function(T) displayStringForOption;
  final ValueChanged<T> onSelected;
  final String? errorText;

  const AppDropdownField({
    super.key,
    required this.hintText,
    required this.options,
    required this.displayStringForOption,
    required this.onSelected,
    this.leadingIcon,
    this.value,
    this.errorText,
  });

  @override
  State<AppDropdownField<T>> createState() => _AppDropdownFieldState<T>();
}

class _AppDropdownFieldState<T extends Object> extends State<AppDropdownField<T>> {
  final LayerLink _layerLink = LayerLink();
  late final TextEditingController _controller;
  bool _isOpen = false;
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.value == null ? '' : widget.displayStringForOption(widget.value!),
    );
  }

  @override
  void dispose() {
    // Remove overlay without setState (setState is not allowed during dispose)
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AppDropdownField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _controller.text = widget.value == null ? '' : widget.displayStringForOption(widget.value!);
      if (_isOpen) {
        _closeDropdown();
        _openDropdown();
      }
    }
  }

  void _toggleDropdown() {
    if (_isOpen) {
      _closeDropdown();
    } else {
      _openDropdown();
    }
  }

  void _openDropdown() {
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
    setState(() {
      _isOpen = true;
    });
  }

  void _closeDropdown() {
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
    }
    if (mounted) {
      setState(() {
        _isOpen = false;
      });
    }
  }

  OverlayEntry _createOverlayEntry() {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final Size size = renderBox.size;

    return OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Dismiss when clicking outside
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _closeDropdown,
            ),
          ),
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            offset: const Offset(0, 6),
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.hardEdge,
              color: Colors.white,
              shadowColor: Colors.black.withAlpha(20),
              child: Container(
                width: size.width,
                constraints: const BoxConstraints(maxHeight: 250),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.borderPrimary, width: 1.5),
                ),
                child: ListView(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  children: widget.options.map((T option) {
                    final isSelected = widget.value == option;
                    return InkWell(
                      onTap: () {
                        _closeDropdown();
                        widget.onSelected(option);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        color: isSelected ? AppColors.brandPrimary.withAlpha(15) : null,
                        child: Text(
                          widget.displayStringForOption(option),
                          style: TextStyle(
                            color: isSelected ? AppColors.brandPrimary : AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasError = widget.errorText?.isNotEmpty ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _toggleDropdown,
          behavior: HitTestBehavior.opaque,
          child: CompositedTransformTarget(
            link: _layerLink,
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: hasError
                      ? AppColors.error
                      : (_isOpen ? AppColors.brandPrimary : AppColors.borderPrimary),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(15),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  if (widget.leadingIcon != null) ...[
                    Icon(widget.leadingIcon, color: AppColors.brandAccent),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(
                      widget.value == null
                          ? widget.hintText
                          : widget.displayStringForOption(widget.value!),
                      style: TextStyle(
                        color: widget.value == null
                            ? AppColors.textSecondary
                            : AppColors.inputText,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Icon(
                    _isOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
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
    );
  }
}
