// lib/widgets/export_menu_button.dart
//
// The export control on a single record: PDF to save, share or print, or an
// Excel workbook. See ExportActions for what each does.

import 'package:flutter/material.dart';

import '../services/export_actions.dart';
import '../services/language_service.dart';
import '../theme/app_colors.dart';

class ExportMenuButton extends StatelessWidget {
  const ExportMenuButton({super.key, required this.onSelected});

  final ValueChanged<ExportAction> onSelected;

  @override
  Widget build(BuildContext context) {
    String t(String en, String fil) => LanguageService.translate(en, fil);

    PopupMenuItem<ExportAction> item(
            ExportAction value, IconData icon, String label) =>
        PopupMenuItem(
          value: value,
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.brandText),
              const SizedBox(width: 12),
              Text(label, style: const TextStyle(fontSize: 14)),
            ],
          ),
        );

    return PopupMenuButton<ExportAction>(
      tooltip: t('Export', 'I-export'),
      icon: const Icon(Icons.file_download_outlined,
          color: AppColors.brandPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: onSelected,
      itemBuilder: (_) => [
        item(ExportAction.savePdf, Icons.picture_as_pdf_outlined,
            t('Save as PDF', 'I-save bilang PDF')),
        item(ExportAction.saveExcel, Icons.table_chart_outlined,
            t('Save as Excel', 'I-save bilang Excel')),
        item(ExportAction.sharePdf, Icons.share_outlined,
            t('Share PDF', 'Ibahagi ang PDF')),
        item(ExportAction.printPdf, Icons.print_outlined, t('Print', 'I-print')),
      ],
    );
  }
}
