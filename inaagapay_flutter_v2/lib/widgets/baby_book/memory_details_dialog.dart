import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../app_input_field.dart';
import '../main_button.dart';

/// What a mother typed about a photo she is adding.
class MemoryDetails {
  final String title;
  final String caption;

  const MemoryDetails({required this.title, required this.caption});
}

/// Asks for a title and a caption for a photo that has just been picked.
///
/// Its own widget rather than a closure inside the Baby Book page so the
/// thing that broke can be exercised: this dialog is where the photo flow
/// failed. A 130px preview above two text fields, one of them three lines
/// tall, is more than an `AlertDialog` is given on a short window, and an
/// overflowing unscrollable Column throws during layout on every frame. Once
/// layout throws, pointer handling starts asserting too, which is why the
/// page ended up dimmed by a barrier with nothing usable on top of it and the
/// console filled with mouse-tracker assertions.
class MemoryDetailsDialog extends StatefulWidget {
  final Uint8List imageBytes;

  const MemoryDetailsDialog({super.key, required this.imageBytes});

  @override
  State<MemoryDetailsDialog> createState() => _MemoryDetailsDialogState();
}

class _MemoryDetailsDialogState extends State<MemoryDetailsDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _captionController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _captionController = TextEditingController();
  }

  @override
  void dispose() {
    // Owned by the dialog's own State, so they are disposed whether she saves,
    // cancels, or the route is torn down under her — a browser back button
    // used to leave them to the garbage collector.
    _titleController.dispose();
    _captionController.dispose();
    super.dispose();
  }

  /// How wide the dialog body should be on this screen.
  ///
  /// Capped at 420 so it does not stretch across a tablet, and kept inside the
  /// window less the dialog's own inset padding so it cannot overflow
  /// sideways on a narrow phone.
  double _contentWidth(BuildContext context) {
    const insets = 20.0 * 2;
    const dialogPadding = 22.0 * 2;
    final available =
        MediaQuery.sizeOf(context).width - insets - dialogPadding;
    return available.clamp(180.0, 420.0);
  }

  void _save() {
    // The fields start empty rather than pre-filled with "A beautiful
    // memory": a placeholder in the box reads as something she has to clear
    // before typing, and half of them get saved as-is. The fallback still
    // applies here, so leaving it blank is allowed and never saves a nameless
    // photo.
    Navigator.of(context).pop(
      MemoryDetails(
        title: _titleController.text.trim().isEmpty
            ? 'A beautiful memory'
            : _titleController.text.trim(),
        caption: _captionController.text.trim().isEmpty
            ? 'A special moment in Baby’s growing story.'
            : _captionController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey<String>('memory-details-dialog'),
      // The tinted ground the midwife forms use. White inputs need something
      // to sit on; on a white dialog they disappeared into it and the fields
      // read as flat lines rather than boxes.
      backgroundColor: const Color(0xFFFFF7FA),
      surfaceTintColor: const Color(0xFFFFF7FA),
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(22, 6, 22, 0),
      titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 10),
      actionsPadding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      title: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[Color(0xFFFF8FBC), AppColors.brandPrimary],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: AppColors.brandPrimary.withValues(alpha: 0.28),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.photo_camera_rounded,
              color: Colors.white,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Add this memory',
              style: TextStyle(
                color: AppColors.headingSoft,
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ),
        ],
      ),
      // A definite width, not a maximum.
      //
      // `scrollable: true` measures its content's intrinsic width, and an
      // intrinsic pass hands the subtree an unbounded width — under which
      // `width: double.infinity` on the preview asserts `width.isFinite`.
      // Giving the column a real width means the intrinsic pass stops here
      // and never asks the image how wide it would like to be.
      content: SizedBox(
        width: _contentWidth(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.memory(
                widget.imageBytes,
                height: 150,
                fit: BoxFit.cover,
                // A file the engine cannot decode — HEIC from an iPhone, a
                // renamed file — must not take the dialog down with it. She
                // still gets to name the photo and save it.
                errorBuilder: (context, error, stack) => Container(
                  height: 150,
                  color: const Color(0xFFFFEDF4),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.image_not_supported_outlined,
                    color: AppColors.brandPrimary,
                    size: 34,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            AppInputField(
              key: const ValueKey<String>('memory-title-field'),
              hintText: 'Name this photo',
              controller: _titleController,
              leadingIcon: Icons.favorite_outline_rounded,
            ),
            const SizedBox(height: 12),
            _StoryField(controller: _captionController),
          ],
        ),
      ),
      actions: [
        Column(
          children: [
            MainButton(
              key: const ValueKey<String>('memory-save'),
              label: 'Save memory',
              showIcons: false,
              onPressed: _save,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                minimumSize: const Size.fromHeight(44),
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The multi-line caption box.
///
/// [AppInputField] is fixed at 56 high and single-line, so it cannot hold a
/// short story. This matches it exactly — same white fill, same 28 radius,
/// same soft shadow, same brandAccent leading icon, same focus ring — rather
/// than dropping a bare Material TextField in beside it.
class _StoryField extends StatefulWidget {
  final TextEditingController controller;

  const _StoryField({required this.controller});

  @override
  State<_StoryField> createState() => _StoryFieldState();
}

class _StoryFieldState extends State<_StoryField> {
  bool _isHovered = false;
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    Color borderColor() {
      if (_isFocused) return AppColors.brandPrimary;
      if (_isHovered) return AppColors.brandPrimary.withValues(alpha: 0.4);
      return Colors.transparent;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Focus(
        onFocusChange: (focused) => setState(() => _isFocused = focused),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor(), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.notes_rounded,
                  color: AppColors.brandAccent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const ValueKey<String>('memory-caption-field'),
                  controller: widget.controller,
                  maxLines: 3,
                  minLines: 3,
                  style: const TextStyle(
                    color: AppColors.inputText,
                    fontSize: 14,
                    height: 1.4,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'What made this moment special?',
                    hintStyle: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
