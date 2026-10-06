import 'package:flutter/material.dart';
import '../services/child_record_export.dart';
import '../services/export_actions.dart';
import '../services/report_export_service.dart';
import 'export_menu_button.dart';

class ChildExportButton extends StatelessWidget {
  const ChildExportButton(
      {super.key, required this.childId, required this.kind});
  final int childId;
  final ChildExportKind kind;

  @override
  Widget build(BuildContext context) => ExportMenuButton(onSelected: (action) {
        // Fetch all records at export time, including immunizations beyond the
        // profile's five-row preview. A failed query fails the export visibly.
        Future<ReportDocument> document() =>
            ChildRecordExport.load(childId, kind);
        ExportActions.run(context, action,
            fileStem: 'child-$childId-${kind.name}',
            buildPdf: () async => ReportExportService.toPdf(await document()),
            buildExcel: () async =>
                ReportExportService.toXlsx(await document()));
      });
}
