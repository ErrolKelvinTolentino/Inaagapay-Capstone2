// lib/services/export_actions.dart
//
// The four things a person can do with one exported record — save it as a
// PDF, share the PDF, print it, or save it as an Excel workbook — handled the
// same way on every screen that offers them.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../theme/app_colors.dart';
import 'export_file_saver.dart';
import 'language_service.dart';

enum ExportAction { savePdf, sharePdf, printPdf, saveExcel }

class ExportActions {
  const ExportActions._();

  /// Builds only the format the action needs, then hands the file over.
  static Future<void> run(
    BuildContext context,
    ExportAction action, {
    required String fileStem,
    required Future<Uint8List> Function() buildPdf,
    required Future<Uint8List> Function() buildExcel,
  }) async {
    final t = LanguageService.translate;
    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const _Preparing(),
    );
    var open = true;
    void close() {
      if (open) {
        navigator.pop();
        open = false;
      }
    }

    void saved(ExportSaveResult result, String what) {
      if (!result.saved) return;
      messenger.showSnackBar(SnackBar(
        content: Text(result.location == null
            ? t('$what saved.', 'Na-save ang $what.')
            : t('$what saved: ${result.location}',
                'Na-save ang $what: ${result.location}')),
        behavior: SnackBarBehavior.floating,
      ));
    }

    try {
      switch (action) {
        case ExportAction.saveExcel:
          final bytes = await buildExcel();
          close();
          saved(
            await ExportFileSaver.save(
              bytes: bytes,
              fileName: '$fileStem.xlsx',
              mimeType: ExportFileSaver.xlsxMime,
            ),
            'Excel file',
          );
        case ExportAction.savePdf:
          final bytes = await buildPdf();
          close();
          saved(
            await ExportFileSaver.save(
              bytes: bytes,
              fileName: '$fileStem.pdf',
              mimeType: ExportFileSaver.pdfMime,
            ),
            'PDF',
          );
        case ExportAction.sharePdf:
          final bytes = await buildPdf();
          close();
          await Printing.sharePdf(bytes: bytes, filename: '$fileStem.pdf');
        case ExportAction.printPdf:
          final bytes = await buildPdf();
          close();
          await Printing.layoutPdf(
            name: '$fileStem.pdf',
            onLayout: (_) async => bytes,
          );
      }
    } catch (e) {
      close();
      debugPrint('Export failed: $e');
      messenger.showSnackBar(SnackBar(
        content: Text(t('Could not create the file. Please try again.',
            'Hindi nagawa ang file. Pakisubukan muli.')),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  /// "inaagapay_lab-test_dela-cruz-maria_2026-09-24" — safe on every platform.
  static String fileStem(List<String?> parts, {DateTime? on}) {
    final day = on ?? DateTime.now();
    final date = '${day.year}-${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    final slugs = [
      'inaagapay',
      for (final part in parts)
        if ((part ?? '').trim().isNotEmpty)
          part!
              .toLowerCase()
              .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
              .replaceAll(RegExp(r'^-+|-+$'), ''),
      date,
    ];
    return slugs.where((s) => s.isNotEmpty).join('_');
  }
}

class _Preparing extends StatelessWidget {
  const _Preparing();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 20,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              color: AppColors.brandPrimary,
              strokeWidth: 3,
            ),
            const SizedBox(height: 16),
            Text(
              LanguageService.translate(
                  'Preparing the file...', 'Inihahanda ang file...'),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
