// lib/widgets/record_image.dart
//
// One attachment from a record, however it happened to be stored.
//
// Attachments arrive in two shapes. When the upload to Supabase Storage
// succeeds the column holds a public URL; when it fails the save path falls
// back to `base64Encode` and the column holds a `data:image/jpeg;base64,...`
// URI instead — a whole image, inline, often several megabytes of it.
//
// Only the first shape was ever handled. Both viewers called `Image.network`,
// which cannot load a data URI, so every record whose upload had fallen back
// drew a broken-image placeholder. With the upload timeout set to 500ms that
// was very nearly all of them, and the images looked lost when they were in
// fact sitting in the row being asked for over the wrong protocol.
//
// Kept as one widget rather than two lookalikes so the record screen and the
// full-screen viewer cannot disagree about what an attachment is again.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class RecordImage extends StatelessWidget {
  const RecordImage({
    super.key,
    required this.source,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.showLoadingIndicator = true,
  });

  /// Either an http(s) URL or a `data:` URI.
  final String source;

  final double? width;
  final double? height;
  final BoxFit fit;

  /// A network image reports progress; an inline one is already in memory and
  /// has nothing to wait for.
  final bool showLoadingIndicator;

  /// Splits a stored attachment field into individual sources.
  ///
  /// Attachments are saved with `attachmentUrls.join(',')`, and every reader
  /// split that back apart on a bare comma. That works for URLs and destroys
  /// data URIs, because `data:image/jpeg;base64,AAAA...` contains a comma of
  /// its own. One embedded image became two fragments — `data:image/jpeg;base64`
  /// and the payload — and the record reported "2 files", neither loadable.
  ///
  /// So the split happens only at a comma that starts a new attachment: one
  /// followed by an http(s) URL or another data URI. Nothing else is a
  /// boundary. This reads both the rows already saved and anything written
  /// later, without a migration.
  static List<String> splitSources(String? field) {
    final raw = field?.trim() ?? '';
    if (raw.isEmpty) return const [];

    return raw
        .split(RegExp(r',(?=https?://|data:)'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// True when the attachment is embedded in the row rather than linked.
  static bool isInline(String source) =>
      source.trimLeft().toLowerCase().startsWith('data:');

  /// True when the attachment is a PDF rather than an image — a lab result is
  /// as often a scanned document as a photograph, and handing PDF bytes to an
  /// image decoder produces a broken-image icon that reads as data loss.
  static bool isPdf(String source) {
    final head = source.trimLeft().toLowerCase();
    return head.startsWith('data:application/pdf') || head.endsWith('.pdf');
  }

  /// The bytes behind a data URI, or null when it cannot be read.
  ///
  /// Returns null rather than throwing: one unreadable attachment should show
  /// as unreadable, not take down the record around it.
  static Uint8List? decodeInline(String source) {
    try {
      final comma = source.indexOf(',');
      if (comma < 0) return null;
      return base64Decode(source.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  Widget _placeholder(IconData icon, String label) => Container(
        width: width,
        height: height,
        color: AppColors.bgSecondary,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 26),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (isPdf(source)) {
      return _placeholder(Icons.picture_as_pdf_outlined, 'PDF document');
    }

    if (isInline(source)) {
      final bytes = decodeInline(source);
      if (bytes == null || bytes.isEmpty) {
        return _placeholder(Icons.broken_image_outlined, 'Could not be read');
      }
      return Image.memory(
        bytes,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) =>
            _placeholder(Icons.broken_image_outlined, 'Could not be read'),
      );
    }

    return Image.network(
      source,
      width: width,
      height: height,
      fit: fit,
      // A blank square for several seconds reads as a failure. Saying it is
      // loading is the difference between "slow" and "broken".
      loadingBuilder: !showLoadingIndicator
          ? null
          : (context, child, progress) {
              if (progress == null) return child;
              return Container(
                width: width,
                height: height,
                color: AppColors.bgSecondary,
                alignment: Alignment.center,
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.brandPrimary,
                    value: progress.expectedTotalBytes == null
                        ? null
                        : progress.cumulativeBytesLoaded /
                            progress.expectedTotalBytes!,
                  ),
                ),
              );
            },
      errorBuilder: (_, __, ___) =>
          _placeholder(Icons.wifi_off_rounded, 'Could not load'),
    );
  }
}
