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

  /// Whether an option may be chosen. Options that return false are shown
  /// greyed and cannot be tapped — used where the choice exists but is
  /// unavailable right now, such as a vaccine that is out of stock.
  final bool Function(T)? isOptionEnabled;
  final String? errorText;

  const AppDropdownField({
    super.key,
    required this.hintText,
    required this.options,
    required this.displayStringForOption,
    required this.onSelected,
    this.isOptionEnabled,
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
    String searchQuery = '';

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
              child: StatefulBuilder(
                builder: (context, setOverlayState) {
                  final filteredOptions = widget.options.where((T option) {
                    if (searchQuery.trim().isEmpty) return true;
                    final text = widget.displayStringForOption(option).toLowerCase();
                    return text.contains(searchQuery.trim().toLowerCase());
                  }).toList();

                  return Container(
                    width: size.width,
                    constraints: const BoxConstraints(maxHeight: 280),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.borderPrimary, width: 1.5),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.options.length > 4)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                            child: TextField(
                              autofocus: true,
                              style: const TextStyle(fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'Type to search items...',
                                hintStyle: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppColors.brandPrimary),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: AppColors.borderPrimary),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: AppColors.borderPrimary),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: AppColors.brandPrimary),
                                ),
                              ),
                              onChanged: (val) {
                                setOverlayState(() {
                                  searchQuery = val;
                                });
                              },
                            ),
                          ),
                        Flexible(
                          child: filteredOptions.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: Text(
                                    'No matching items found',
                                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                  ),
                                )
                              : ListView.builder(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  itemCount: filteredOptions.length,
                                  itemBuilder: (context, index) {
                                    final T option = filteredOptions[index];
                                    final isSelected = widget.value == option;
                                    // Disabled options stay visible rather
                                    // than being filtered out: a vaccine
                                    // missing from the list looks like a
                                    // system that does not stock it, while a
                                    // greyed one says "we do, but not today".
                                    final isEnabled =
                                        widget.isOptionEnabled?.call(option) ??
                                            true;
                                    return InkWell(
                                      onTap: isEnabled
                                          ? () {
                                              _closeDropdown();
                                              widget.onSelected(option);
                                            }
                                          : null,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                        color: isSelected ? AppColors.brandPrimary.withAlpha(15) : null,
                                        child: Text(
                                          widget.displayStringForOption(option),
                                          style: TextStyle(
                                            color: !isEnabled
                                                ? AppColors.textSecondary
                                                    .withValues(alpha: 0.55)
                                                : (isSelected
                                                    ? AppColors.brandPrimary
                                                    : AppColors.textPrimary),
                                            fontSize: 13,
                                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  );
                },
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
