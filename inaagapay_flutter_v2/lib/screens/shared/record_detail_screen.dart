// lib/screens/midwife/record_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:http/http.dart' as http;

import '../../theme/app_colors.dart';
import '../../services/language_service.dart';
import '../../widgets/full_screen_image_viewer.dart';
import '../../widgets/secondary_header.dart';
import '../../widgets/profile_section.dart';
import '../../widgets/profile_header_card.dart';
import '../../services/blood_pressure_reference.dart';
import '../../services/lab_cbc_interpretation_engine.dart';
import '../../services/ultrasound_interpretation_engine.dart' show MonitoringClassification, Trimester, UltrasoundInterpretationEngine;

/// Who this record belongs to.
///
/// Every clinical record view has to answer "whose is this?" before it answers
/// anything else. None of these screens did: the header said "Ultrasound", the
/// body said 16 weeks, and a midwife with three charts open — or a hospital
/// reading an exported PDF — had nothing to check the record against.
///
/// Two identifiers minimum, which is why [idLabel] is carried alongside
/// [name]: names collide, and in a barangay caseload they collide often.
class RecordPatient {
  const RecordPatient({
    required this.name,
    this.idLabel,
    this.age,
    this.obstetric,
    this.bloodType,
  });

  final String name;
  final String? idLabel;
  final String? age;

  /// G/P at a glance — the shorthand a midwife reads before anything else.
  final String? obstetric;

  /// Carried here rather than left inside a lab record, because an Rh-negative
  /// mother needs anti-D at around 28 weeks and that decision must not depend
  /// on someone remembering to open the right document.
  final String? bloodType;

  bool get isEmpty => name.trim().isEmpty;
}

class RecordDetailScreen extends StatefulWidget {
  const RecordDetailScreen({
    super.key,
    required this.title,
    required this.rows,
    this.icon = Icons.receipt_long,
    this.subtitle,
    this.imageUrls,
    this.aiAnalysis,
    this.useStructuredAiInsights = false,
    this.riskLevel,
    this.riskFactors,
    this.suggestedActions,
    this.weightGainEval,
    this.ultrasoundClassification,
    this.approvedByName,
    this.isMidwifeApproved,
    this.remarksSource,
    this.patient,
  });

  /// `prenatal_checkups.remarks_source` — one of `midwife_authored`,
  /// `ai_generated_approved` or `ai_generated_edited`. Decides how the checkup
  /// summary is labelled. Null on records that do not carry the column, where
  /// the summary is labelled neutrally rather than credited to anyone.
  /// Whose record this is. Pinned above everything else.
  final RecordPatient? patient;

  final String? remarksSource;

  final String title;
  final List<MapEntry<String, String>> rows;
  final IconData icon;
  final String? subtitle;
  final List<String>? imageUrls;
  final String? aiAnalysis;
  final bool useStructuredAiInsights;
  final String? riskLevel;
  final List<String>? riskFactors;
  final List<String>? suggestedActions;
  final Map<String, dynamic>? weightGainEval;
  final String? ultrasoundClassification;

  /// Name of the midwife who reviewed this record's assessment.
  final String? approvedByName;

  /// `clinical_encounters.is_midwife_approved`. Null when the caller does not
  /// know the review state, in which case no attribution line is rendered.
  final bool? isMidwifeApproved;

  @override
  State<RecordDetailScreen> createState() => _RecordDetailScreenState();
}

class _RecordDetailScreenState extends State<RecordDetailScreen> {
  final Set<String> _expandedLabInsightAspects = <String>{};
  bool _showAiInFilipino = LanguageService.isFilipino;

  // Section accents removed. Three near-identical pinks distinguished
  // "Record" from "Health Worker" from "Notes" — a distinction the headings
  // already make, in a colour the reader had to learn to ignore.

  // Visual hierarchy card colors
  // _aiCardBg removed with the tinted AI panel — the summary is a white card
  // like every other section now.
  static const _aiCardBorder = Color(0xFFFF68A5); // brand primary pink border
  // Recommendation card colours removed with the card itself. Green was the
  // fourth tinted panel on one screen, and it carried no meaning the heading
  // did not already carry.
  static const _riskHighCardBg = Color(0xFFFBE9E7); // light red/orange
  static const _riskHighCardBorder = Color(0xFFEF5350); // red border

  String _t(String english, String filipino) {
    return LanguageService.translate(english, filipino);
  }

  String _tAi(String english, String filipino) {
    return _showAiInFilipino ? filipino : english;
  }

  /// Shows which midwife stands behind the assessment above.
  ///
  /// The point of this line is that a mother reading an AI-generated insight
  /// can see a named human reviewed it — so an unreviewed record says so
  /// plainly rather than rendering nothing.
  /// The one line under the header: when this record was taken or added.
  ///
  /// Callers already pass this as [subtitle] ("Added on Aug 15, 2026"), and it
  /// used to sit inside a card that repeated the title above it. It is kept as
  /// a plain line because it is context, not a finding — the findings start
  /// immediately below it.
  String _recordStampLine() => widget.subtitle?.trim() ?? '';

  /// Who this record came from, said plainly.
  ///
  /// "Conducted by" for a checkup the midwife performed herself; "Recorded by"
  /// for an ultrasound or lab result she transcribed from someone else's
  /// document. The distinction is not cosmetic — one is her clinical work, the
  /// other is her entering a sonologist's or a laboratory's findings, and a
  /// record that blurs the two overstates what she examined.
  String _attributionLabel() {
    final t = widget.title.toLowerCase();
    if (t.contains("prenatal") || t.contains("checkup")) {
      return _t("Conducted by", "Isinagawa ni");
    }
    return _t("Recorded by", "Itinala ni");
  }

  /// The patient banner. First thing on the screen, before the record itself.
  ///
  /// Name and identifier on one line, then age, obstetric score and blood type
  /// on the next. It is deliberately plain rather than branded: this is the
  /// line a clinician checks against the chart in their other hand, and it has
  /// to be readable at a glance and legible when printed in monochrome.
  Widget _buildPatientHeader() {
    final patient = widget.patient;
    if (patient == null || patient.isEmpty) return _buildRecordStamp();

    // The same header the profile overview uses, reused rather than imitated.
    //
    // What changes is the pill row: a record has nothing to say about phone
    // numbers. It carries when it was taken, who took it, and the two facts a
    // clinician reads before anything else — her age and her blood type.
    final who = widget.approvedByName?.trim() ?? "";
    final when = _recordStampLine();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ProfileHeaderCard(
        fullName: patient.name,
        patientNumber: patient.idLabel,
        chips: [
          if (when.isNotEmpty)
            ProfileHeaderChip(icon: widget.icon, text: when),
          if (who.isNotEmpty && who != "—")
            ProfileHeaderChip(
              icon: Icons.person_outline_rounded,
              text: "${_attributionLabel()}: $who",
            ),
          if ((patient.age ?? "").isNotEmpty)
            ProfileHeaderChip(
                icon: Icons.cake_outlined, text: patient.age!),
          if ((patient.bloodType ?? "").isNotEmpty)
            ProfileHeaderChip(
                icon: Icons.bloodtype_outlined, text: patient.bloodType!),
        ],
      ),
    );
  }

  /// The two facts a clinician checks before reading any record: when, and by
  /// whom. Kept as one quiet block directly under the header, each line led by
  /// a symbol so the eye can find either without reading both.
  Widget _buildRecordStamp() {
    final when = _recordStampLine();
    final who = widget.approvedByName?.trim() ?? "";
    final hasWho = who.isNotEmpty && who != "—";

    if (when.isEmpty && !hasWho) return const SizedBox.shrink();

    Widget line(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 7),
              if (label.isNotEmpty) ...[
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    fontWeight:
                        label.isEmpty ? FontWeight.w400 : FontWeight.w600,
                    color: label.isEmpty
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (when.isNotEmpty) line(widget.icon, "", when),
          if (hasWho)
            line(Icons.person_outline_rounded, "${_attributionLabel()}:", who),
        ],
      ),
    );
  }

  Widget _buildApprovalAttribution() {
    final approved = widget.isMidwifeApproved;
    if (approved == null) return const SizedBox.shrink();

    // Nothing in this app ever writes `is_midwife_approved`. It is selected in
    // five places and set in none, so the flag is false on every record ever
    // saved and this banner could only ever read "Pending midwife review".
    //
    // A permanent "pending" is worse than silence in both directions: on the
    // midwife's own screen it tells her that the record she just wrote is
    // awaiting her review, and on the mother's screen it tells her that not
    // one document in her file has been looked at. Neither is true — the
    // workflow simply does not exist yet.
    //
    // So the badge appears only when a record is genuinely approved. If an
    // approval step is added later, give it a write path and this starts
    // working on its own; until then it says nothing rather than something
    // false.
    if (!approved) return const SizedBox.shrink();

    final name = widget.approvedByName?.trim();
    final hasName = name != null && name.isNotEmpty;

    final String label;
    if (approved) {
      label = hasName
          ? _t('Assessed and approved by $name',
              'Sinuri at inaprubahan ni $name')
          : _t('Assessed and approved by your midwife',
              'Sinuri at inaprubahan ng iyong midwife');
    } else {
      label = _t('Pending midwife review', 'Hinihintay ang pagsusuri ng midwife');
    }

    final Color accent =
        approved ? const Color(0xFF2E7D32) : AppColors.brandAccent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              approved ? Icons.verified_user_outlined : Icons.schedule_outlined,
              size: 14,
              color: accent,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _localizedSectionTitle(String title) {
    switch (title) {
      case 'Vitals':
        return _t('Vitals', 'Vital Signs');
      case 'Fetal Assessment':
        return _t('Fetal Assessment', 'Pagsusuri sa Sanggol');
      case 'Symptoms':
        return _t('Symptoms', 'Mga Sintomas');
      case 'Medications & Supplements':
        return _t('Medications & Supplements', 'Mga Gamot at Supplements');
      case 'Schedule & Remarks':
        return _t('Schedule & Remarks', 'Schedule at Mga Tala');
      case 'Ultrasound Information':
        return _t('Ultrasound Information', 'Impormasyon ng Ultrasound');
      case 'Checkup Information':
        return _t('Checkup Information', 'Impormasyon ng Checkup');
      case 'Lab Test Information':
        return _t('Lab Test Information', 'Impormasyon ng Lab Test');
      case 'Health Worker Information':
        return _t('Health Worker Information',
            'Impormasyon ng Health Worker');
      case 'Notes':
        return _t('Notes', 'Mga Tala');
      default:
        return title;
    }
  }

  void _exportReport() {
    final buf = StringBuffer();
    final divider = String.fromCharCodes(List.filled(43, 0x2550)); // ═

    buf.writeln(divider);
    buf.writeln('INAAGAPAY — ${widget.title.toUpperCase()} REPORT');
    buf.writeln(divider);

    // Patient first, before anything clinical.
    //
    // An exported report is the copy that leaves this app — handed to a
    // referral hospital, printed for a chart, forwarded in a message. It
    // previously carried a record type and a date and no patient at all,
    // which makes it unfileable at best and attachable to the wrong chart at
    // worst. The banner on screen is worthless if the export drops it.
    final patient = widget.patient;
    if (patient != null && !patient.isEmpty) {
      buf.writeln("PATIENT: ${patient.name}");
      if ((patient.idLabel ?? "").isNotEmpty) {
        buf.writeln("ID: ${patient.idLabel}");
      }
      final facts = <String>[
        if ((patient.age ?? "").isNotEmpty) patient.age!,
        if ((patient.obstetric ?? "").isNotEmpty) patient.obstetric!,
        if ((patient.bloodType ?? "").isNotEmpty) "Blood type ${patient.bloodType}",
      ];
      if (facts.isNotEmpty) buf.writeln(facts.join("  |  "));
      buf.writeln(divider);
    }

    // Subtitle (often contains date / mother info)
    if (widget.subtitle != null && widget.subtitle!.trim().isNotEmpty) {
      buf.writeln(widget.subtitle!.trim());
    }
    final who = widget.approvedByName?.trim() ?? "";
    if (who.isNotEmpty && who != "—") {
      buf.writeln("${_attributionLabel()}: $who");
    }
    buf.writeln();

    // Grouped rows
    final rows = _normalizedDisplayRows();
    final sections = _groupRows(rows);
    for (final entry in sections.entries) {
      buf.writeln(entry.key.toUpperCase());
      for (final row in entry.value) {
        buf.writeln('${row.key}: ${row.value}');
      }
      buf.writeln();
    }

    // Weight gain evaluation
    if (widget.weightGainEval != null) {
      final eval = widget.weightGainEval!;
      buf.writeln('WEIGHT GAIN MONITOR');
      if (eval['status'] != null) buf.writeln('Status: ${eval['status']}');
      if (eval['bmi_category'] != null) {
        buf.writeln('BMI Category: ${eval['bmi_category']}');
      }
      if (eval['message'] != null) buf.writeln(eval['message']);
      buf.writeln();
    }

    // Risk level / factors
    if (widget.riskLevel != null && widget.riskLevel!.trim().isNotEmpty) {
      buf.writeln('RISK LEVEL: ${widget.riskLevel!.toUpperCase()}');
    }
    if (widget.riskFactors != null && widget.riskFactors!.isNotEmpty) {
      buf.writeln('Risk Factors:');
      for (final f in widget.riskFactors!) {
        buf.writeln('- $f');
      }
      buf.writeln();
    }
    if (widget.suggestedActions != null &&
        widget.suggestedActions!.isNotEmpty) {
      buf.writeln('Suggested Actions:');
      for (final a in widget.suggestedActions!) {
        buf.writeln('- $a');
      }
      buf.writeln();
    }

    // AI analysis
    if (widget.aiAnalysis != null && widget.aiAnalysis!.trim().isNotEmpty) {
      buf.writeln('AI ASSESSMENT');
      buf.writeln(widget.aiAnalysis!.trim());
      buf.writeln();
    }

    buf.writeln(divider);
    buf.writeln('Generated by InaAgapay Health System');
    buf.writeln('This is not a medical prescription.');
    buf.writeln(divider);

    Clipboard.setData(ClipboardData(text: buf.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t(
              'Report copied to clipboard!',
              'Nakopya ang report sa clipboard!')),
          backgroundColor: AppColors.brandPrimary,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Future<void> _exportToPdf() async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
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
                _t('Generating PDF report...', 'Gumagawa ng PDF report...'),
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
      ),
    );

    try {
      // ── Brand colors for PDF ──
      const brandPink = PdfColor.fromInt(0xFFFF68A5);
      const brandAccent = PdfColor.fromInt(0xFFE6398D);
      const brandText = PdfColor.fromInt(0xFFC73578);
      const textPrimary = PdfColor.fromInt(0xFF2D2D2D);
      const textSecondary = PdfColor.fromInt(0xFF8A8A8A);
      const bgSecondary = PdfColor.fromInt(0xFFFFF5F8);
      const successColor = PdfColor.fromInt(0xFF68CBB8);
      const warningColor = PdfColor.fromInt(0xFFFFB562);
      const errorColor = PdfColor.fromInt(0xFFE57373);
      const borderLight = PdfColor.fromInt(0xFFF0F0F0);

      // ── Download images from network ──
      final List<Uint8List> imageDataList = [];
      if (widget.imageUrls != null && widget.imageUrls!.isNotEmpty) {
        for (final url in widget.imageUrls!) {
          try {
            final response = await http.get(Uri.parse(url));
            if (response.statusCode == 200) {
              imageDataList.add(response.bodyBytes);
            }
          } catch (_) {
            // Skip images that fail to download
          }
        }
      }

      // ── Build the PDF document ──
      final pdf = pw.Document();

      // Helper: Section Title widget
      pw.Widget pdfSectionTitle(String title, {PdfColor color = brandAccent}) {
        return pw.Container(
          margin: const pw.EdgeInsets.only(top: 14, bottom: 6),
          padding: const pw.EdgeInsets.only(left: 8, bottom: 4),
          decoration: pw.BoxDecoration(
            border: pw.Border(
              left: pw.BorderSide(color: color, width: 3),
            ),
          ),
          child: pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),
        );
      }

      // Helper: Detail row (label: value)
      pw.Widget pdfDetailRow(String label, String value) {
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: 160,
                child: pw.Text(
                  label,
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: textSecondary,
                  ),
                ),
              ),
              pw.Expanded(
                child: pw.Text(
                  value,
                  style: const pw.TextStyle(
                    fontSize: 11,
                    color: textPrimary,
                  ),
                ),
              ),
            ],
          ),
        );
      }

      // Helper: Info box
      pw.Widget pdfInfoBox(String text, {PdfColor bg = bgSecondary, PdfColor border = brandPink}) {
        return pw.Container(
          width: double.infinity,
          margin: const pw.EdgeInsets.only(top: 4, bottom: 4),
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: bg,
            border: pw.Border.all(color: border, width: 0.5),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Text(
            text,
            style: const pw.TextStyle(fontSize: 10, color: textPrimary),
          ),
        );
      }

      // Helper: Risk chip
      pw.Widget pdfRiskChip(String label, PdfColor color) {
        return pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          margin: const pw.EdgeInsets.only(right: 6, bottom: 4),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: color, width: 0.8),
            borderRadius: pw.BorderRadius.circular(12),
          ),
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),
        );
      }

      // ── Collect all content widgets ──
      final List<pw.Widget> content = [];

      // ── HEADER ──
      content.add(
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(
            color: bgSecondary,
            borderRadius: pw.BorderRadius.circular(8),
            border: pw.Border.all(color: brandPink, width: 1),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'INAAGAPAY',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                  color: brandAccent,
                  letterSpacing: 2,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Maternal & Child Health Information System',
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: textSecondary,
                ),
              ),
              pw.Divider(color: brandPink, thickness: 0.5, height: 16),
              pw.Text(
                widget.title.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 15,
                  fontWeight: pw.FontWeight.bold,
                  color: brandText,
                ),
              ),
              if (widget.subtitle != null && widget.subtitle!.trim().isNotEmpty) ...[
                pw.SizedBox(height: 4),
                pw.Text(
                  widget.subtitle!.trim(),
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      );

      // ── ATTACHED IMAGES ──
      if (imageDataList.isNotEmpty) {
        content.add(pdfSectionTitle(_t('Attached Images', 'Mga Kalakip na Larawan')));

        final List<pw.Widget> imageWidgets = [];
        for (final imgBytes in imageDataList) {
          try {
            final image = pw.MemoryImage(imgBytes);
            imageWidgets.add(
              pw.Container(
                width: 160,
                height: 160,
                margin: const pw.EdgeInsets.only(right: 8, bottom: 8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: borderLight, width: 0.5),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.ClipRRect(
                  horizontalRadius: 6,
                  verticalRadius: 6,
                  child: pw.Image(image, fit: pw.BoxFit.cover),
                ),
              ),
            );
          } catch (_) {
            // Skip invalid images
          }
        }

        if (imageWidgets.isNotEmpty) {
          content.add(
            pw.Wrap(
              spacing: 8,
              runSpacing: 8,
              children: imageWidgets,
            ),
          );
        }
      }

      // ── RECORD DETAILS (grouped) ──
      final rows = _normalizedDisplayRows();
      final sections = _groupRows(rows);
      for (final entry in sections.entries) {
        if (entry.value.isEmpty) continue;
        content.add(pdfSectionTitle(_localizedSectionTitle(entry.key)));
        for (final row in entry.value) {
          content.add(pdfDetailRow(row.key, row.value));
        }
      }

      // ── WEIGHT GAIN EVALUATION ──
      if (widget.weightGainEval != null) {
        final eval = widget.weightGainEval!;
        content.add(pdfSectionTitle(
          _t('Weight Gain Monitor', 'Pagsubaybay sa Timbang'),
          color: const PdfColor.fromInt(0xFF4CAF50),
        ));
        final weightBuf = StringBuffer();
        if (eval['status'] != null) weightBuf.writeln('Status: ${eval['status']}');
        if (eval['bmi_category'] != null) weightBuf.writeln('BMI Category: ${eval['bmi_category']}');
        if (eval['message'] != null) weightBuf.writeln(eval['message']);
        content.add(pdfInfoBox(
          weightBuf.toString().trim(),
          bg: const PdfColor.fromInt(0xFFE8F5E9),
          border: const PdfColor.fromInt(0xFF66BB6A),
        ));
      }

      // ── PRENATAL RISK SUMMARY ──
      if (widget.riskLevel != null && widget.riskLevel!.trim().isNotEmpty) {
        final isHighRisk = widget.riskLevel!.toLowerCase().contains('high');
        final riskColor = isHighRisk ? errorColor : successColor;
        content.add(pdfSectionTitle(
          _t('Prenatal Risk Summary', 'Buod ng Prenatal Risk'),
          color: riskColor,
        ));

        content.add(
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(10),
            margin: const pw.EdgeInsets.only(bottom: 6),
            decoration: pw.BoxDecoration(
              color: isHighRisk
                  ? const PdfColor.fromInt(0xFFFBE9E7)
                  : const PdfColor.fromInt(0xFFE8F5E9),
              border: pw.Border.all(color: riskColor, width: 0.5),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  '${_t("Risk Level", "Antas ng Panganib")}: ${widget.riskLevel!.toUpperCase()}',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: riskColor,
                  ),
                ),
              ],
            ),
          ),
        );
      }

      if (widget.riskFactors != null && widget.riskFactors!.isNotEmpty) {
        content.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 8, bottom: 4),
            child: pw.Text(
              _t('Risk Factors:', 'Mga Salik ng Panganib:'),
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: textSecondary,
              ),
            ),
          ),
        );
        content.add(
          pw.Wrap(
            spacing: 6,
            runSpacing: 4,
            children: widget.riskFactors!.map((f) {
              final isHigh = f.toLowerCase().contains('high');
              return pdfRiskChip(f, isHigh ? errorColor : warningColor);
            }).toList(),
          ),
        );
      }

      if (widget.suggestedActions != null && widget.suggestedActions!.isNotEmpty) {
        content.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 8, top: 8, bottom: 4),
            child: pw.Text(
              _t('Suggested Actions:', 'Mga Iminumungkahing Aksyon:'),
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: textSecondary,
              ),
            ),
          ),
        );
        for (int i = 0; i < widget.suggestedActions!.length; i++) {
          content.add(
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 16, bottom: 2),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    '${i + 1}. ',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: brandAccent,
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      widget.suggestedActions![i],
                      style: const pw.TextStyle(fontSize: 10, color: textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      }

      // ── AI ANALYSIS ──
      if (widget.aiAnalysis != null && widget.aiAnalysis!.trim().isNotEmpty) {
        final aiText = _getAiTextForLanguage(widget.aiAnalysis!.trim());
        content.add(pdfSectionTitle(
          _tAi('AI Analysis', 'AI na Pagsusuri'),
          color: brandText,
        ));

        // AI badge
        content.add(
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            margin: const pw.EdgeInsets.only(bottom: 6),
            decoration: pw.BoxDecoration(
              color: bgSecondary,
              border: pw.Border.all(
                color: const PdfColor.fromInt(0xFFFF68A5),
                width: 0.5,
              ),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  margin: const pw.EdgeInsets.only(bottom: 8),
                  decoration: pw.BoxDecoration(
                    color: const PdfColor.fromInt(0xFFFFE4EE),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Text(
                    _tAi('AI Generated', 'Gawa ng AI'),
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      color: brandText,
                    ),
                  ),
                ),
                pw.Text(
                  aiText,
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: textPrimary,
                    lineSpacing: 4,
                  ),
                ),
              ],
            ),
          ),
        );

        // Recommendations
        final recommendations = _extractRecommendations(aiText);
        if (recommendations.isNotEmpty) {
          content.add(pdfSectionTitle(
            _tAi('Recommendations', 'Mga Rekomendasyon'),
            color: const PdfColor.fromInt(0xFF2E7D32),
          ));
          content.add(
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: const PdfColor.fromInt(0xFFE8F5E9),
                border: pw.Border.all(
                  color: const PdfColor.fromInt(0xFF66BB6A),
                  width: 0.5,
                ),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: recommendations.asMap().entries.map((entry) {
                  return pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 4),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          '${entry.key + 1}. ',
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: const PdfColor.fromInt(0xFF2E7D32),
                          ),
                        ),
                        pw.Expanded(
                          child: pw.Text(
                            entry.value,
                            style: const pw.TextStyle(
                              fontSize: 10,
                              color: textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          );
        }
      }

      // ── DISCLAIMER ──
      content.add(pw.SizedBox(height: 12));
      content.add(
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: const PdfColor.fromInt(0xFFFFF8E1),
            border: pw.Border.all(
              color: const PdfColor.fromInt(0xFFFFB562),
              width: 0.5,
            ),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Text(
            _tAi(
              'Disclaimer: This AI-assisted explanation restates the findings recorded by the sonologist in simpler words, adds nothing of its own, and is intended only for healthcare monitoring support and does not replace professional medical consultation. This document is not a medical prescription.',
              'Paunawa: Ang AI-assisted na paliwanag na ito ay muling isinasalaysay lamang ang natuklasan ng sonologist at gabay lamang para sa pagsubaybay sa kalusugan at hindi pamalit sa konsultasyon sa doktor o midwife. Ang dokumentong ito ay hindi medikal na reseta.',
            ),
            style: const pw.TextStyle(
              fontSize: 8.5,
              color: textSecondary,
            ),
          ),
        ),
      );

      // ── Build Multi-Page PDF ──
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          footer: (pw.Context ctx) {
            return pw.Container(
              alignment: pw.Alignment.center,
              padding: const pw.EdgeInsets.only(top: 8),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  top: pw.BorderSide(color: borderLight, width: 0.5),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Generated by InaAgapay Health System',
                    style: const pw.TextStyle(fontSize: 8, color: textSecondary),
                  ),
                  pw.Text(
                    'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                    style: const pw.TextStyle(fontSize: 8, color: textSecondary),
                  ),
                ],
              ),
            );
          },
          build: (pw.Context context) => content,
        ),
      );

      // ── Share / Save the PDF ──
      final pdfBytes = await pdf.save();

      if (mounted) {
        Navigator.of(context).pop(); // dismiss loading dialog
      }

      final sanitizedTitle = widget.title
          .replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), '')
          .replaceAll(RegExp(r'\s+'), '_')
          .toLowerCase();
      final fileName = 'inaagapay_${sanitizedTitle}_report.pdf';

      await Printing.sharePdf(bytes: pdfBytes, filename: fileName);
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // dismiss loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_t(
              'Failed to generate PDF. Please try again.',
              'Hindi nagawa ang PDF. Pakisubukan muli.',
            )),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasAi =
        widget.aiAnalysis != null && widget.aiAnalysis!.trim().isNotEmpty;
    final isPrenatal = widget.title.toLowerCase().contains('prenatal');

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: Column(
        children: [
          SecondaryHeader(
            title: widget.title,
            onBack: () => Navigator.pop(context),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.copy_all_rounded),
                  tooltip: _t('Copy Report', 'Kopyahin ang Report'),
                  onPressed: _exportReport,
                  color: AppColors.brandPrimary,
                ),
                IconButton(
                  icon: const Icon(Icons.picture_as_pdf_rounded),
                  tooltip: _t('Export to PDF', 'I-export sa PDF'),
                  onPressed: _exportToPdf,
                  color: AppColors.brandPrimary,
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // A single quiet line, not a second title.
                  //
                  // The header above already names the record and carries its
                  // icon; repeating both in a card 40px below said nothing new
                  // and pushed the first actual finding further down the
                  // screen. What was missing from the header is the part a
                  // midwife checks first — when it was taken, and whether a
                  // human has approved it.
                  _buildPatientHeader(),
                  _buildApprovalAttribution(),
                  if (widget.imageUrls != null && widget.imageUrls!.isNotEmpty) ...[
                    _buildImageGallery(widget.imageUrls!),
                    const SizedBox(height: 14),
                  ],
                  _buildDetailsCard(),
                  if (isPrenatal && _shouldShowPrenatalRiskSummary()) ...[
                    const SizedBox(height: 14),
                    _buildPrenatalRiskSummaryCard(),
                  ],
                  // Prenatal keeps a written summary, because a checkup
                  // produces one — the midwife's own remarks, sometimes
                  // AI-drafted, and the card says which.
                  //
                  // Ultrasound and lab records do not. What arrives with them
                  // is a document, and what belongs on the record is what the
                  // document said: the values, plus whatever interpretation
                  // the sonologist or laboratory wrote. The model's own
                  // assessment of those values was a third voice on a record
                  // that already has two, and it is no longer shown.
                  if (hasAi) ...[
                    if (isPrenatal) ...[
                      const SizedBox(height: 14),
                      _buildAiCard(widget.aiAnalysis!.trim()),
                    ] else
                      _buildExtractedFindings(widget.aiAnalysis!.trim()),
                  ],
                  _buildClinicalDisclaimerAndReferences(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageGallery(List<String> imageUrls) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFF0F5), Color(0xFFFFE4EE)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.photo_library_outlined,
                    size: 16, color: AppColors.brandAccent),
              ),
              const SizedBox(width: 10),
              Text(
                _t('Attached Images', 'Mga Kalakip na Larawan'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                LanguageService.isFilipino
                    ? '${imageUrls.length} file'
                    : '${imageUrls.length} file${imageUrls.length > 1 ? 's' : ''}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 180,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: imageUrls.length,
              itemBuilder: (context, index) {
                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FullScreenImageViewer(
                          imageUrls: imageUrls,
                          initialIndex: index,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    width: 180,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.borderPrimary),
                    ),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(9),
                          child: Image.network(
                            imageUrls[index],
                            width: 180,
                            height: 180,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: AppColors.bgSecondary,
                              alignment: Alignment.center,
                              child: const Icon(Icons.broken_image_outlined,
                                  color: AppColors.textSecondary, size: 28),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.zoom_in,
                                size: 14, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Removed: _sectionAccent, _sectionCardBackground, _sectionCardBorderColor.
  //
  // They gave each section its own colour — five near-identical pinks for a
  // prenatal checkup, an orange card for Symptoms — none of which encoded
  // anything. Sections are told apart by their heading and their icon, which
  // is what headings and icons are for. Colour is reserved for the finding
  // strips and risk chips, where it means severity.

  IconData _sectionIcon(String title) {
    if (widget.title.toLowerCase().contains('prenatal checkup')) {
      final t = title.toLowerCase();
      if (t == 'vitals') return Icons.favorite_border;
      if (t == 'fetal assessment') return Icons.child_care;
      if (t == 'symptoms') return Icons.healing;
      if (t == 'medications & supplements') return Icons.medication_outlined;
      if (t == 'schedule & remarks') return Icons.event_note;
    }

    // One symbol per section, chosen so the shape alone identifies it when
    // scrolling — a stethoscope for the record itself, a person for whoever
    // produced it, a note for what they wrote, a ruler for measurements read
    // off the document.
    final t = title.toLowerCase();
    if (t.contains('performed by') || t.contains('health worker')) {
      return Icons.badge_outlined;
    }
    if (t.contains('interpretation') || t.contains('notes')) {
      return Icons.sticky_note_2_outlined;
    }
    if (t.contains('measurement') || t.contains('biometry')) {
      return Icons.straighten_rounded;
    }
    if (t.contains('result') || t.contains('laboratory')) {
      return Icons.science_outlined;
    }
    if (t.contains('anatom')) return Icons.child_care_outlined;
    if (t.contains('ultrasound')) return Icons.monitor_heart_outlined;
    if (t.contains('checkup')) return Icons.medical_services_outlined;
    return Icons.biotech_outlined;
  }

  Widget _buildDetailsCard() {
    final rows = _normalizedDisplayRows();
    final sections = _groupRows(rows);
    final sectionEntries =
        sections.entries.where((e) => e.value.isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (rows.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              _t('No additional details available.',
                  'Walang karagdagang detalye.'),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          )
        else
          for (int i = 0; i < sectionEntries.length; i++) ...[
            _buildDetailSection(sectionEntries[i].key, sectionEntries[i].value),
            if (i < sectionEntries.length - 1) const SizedBox(height: 10),
          ],
      ],
    );
  }

  /// Names the section after what it holds rather than after the record.
  ///
  /// "Ultrasound Information" on a screen already titled Ultrasound says only
  /// that the rows below concern the ultrasound, which the reader knew.
  String _recordInfoTitle() {
    final t = widget.title.toLowerCase();
    if (t.contains('ultrasound')) return 'Scan Details';
    if (t.contains('checkup')) return 'Visit Details';
    return 'Test Details';
  }

  String _labelKey(String label) {
    final normalized = _normalizeForCompare(label);
    const aliases = {
      'petsa': 'date',
      'bilangngsanggol': 'fetalcount',
      'edadngpagbubuntis': 'ageofgestation',
      'timbangkg': 'weight(kg)',
      'posisyonngsanggol': 'fetalposition',
      'tonongtibokngsanggol': 'fetalhearttone',
      'tibokngpusongsanggol': 'fetalheartbeat',
      'mgasintomas': 'symptoms',
      'planosagamot': 'medicationplans',
      'mgagamotnaibinigay': 'givenmedications',
      'bakunangtd': 'tdvaccine',
      'pamamaga': 'edema',
      'mgatala': 'remarks',
      'susunodnaschedule': 'nextschedule',
      'lokasyon': 'location',
      'buongpangalan': 'fullname',
      'institusyon': 'institution',
      'propesyon': 'profession',
      'ur nglabtest': 'labtesttype',
      'uringlabtest': 'labtesttype',
      'petsanglabtest': 'labtestdate',
      'petsangultrasound': 'ultrasounddate',
    };
    return aliases[normalized] ?? normalized;
  }

  Map<String, List<MapEntry<String, String>>> _groupRows(
      List<MapEntry<String, String>> rows) {
    if (widget.title.toLowerCase().contains('prenatal checkup')) {
      final vitals = <MapEntry<String, String>>[];
      final fetal = <MapEntry<String, String>>[];
      final symptoms = <MapEntry<String, String>>[];
      final meds = <MapEntry<String, String>>[];
      final schedule = <MapEntry<String, String>>[];

      for (final row in rows) {
        final key = _labelKey(row.key);
        // Shown in the header, the stamp line and the attribution — not
        // repeated as a row inside Vitals, where "Conducted by" sat above the
        // mother's weight as though it were one of her measurements.
        if (key == 'date' || key == 'conductedby' || key == 'recordedby') {
          continue;
        }

        // Vitals: weight, height, BMI, blood pressure, AOG
        if ([
          'ageofgestation',
          'weight',
          'weight(kg)',
          'height',
          'bmi',
          'bloodpressure'
        ].contains(key)) {
          vitals.add(row);
        }
        // Fetal Assessment: fetal count, position, heart rate, heart tone (NOT edema)
        else if ([
          'fetalcount',
          'fetalposition',
          'fetalheartrate',
          'fetalheartbeat',
          'fetalhearttone'
        ].contains(key)) {
          fetal.add(row);
        }
        // Symptoms: symptoms list + edema
        else if (['symptoms', 'edema'].contains(key)) {
          symptoms.add(row);
        }
        // Medications & Supplements: plans, given meds, ferrous, calcium, TD vaccine
        // `_labelKey` strips punctuation, so the old 'ferrous+fa' entry could
        // never match anything and Ferrous fell through to Vitals — listed
        // among the mother's measurements rather than with the supplements
        // she was given.
        else if ([
          'medicationplans',
          'givenmedications',
          'ferrousfa',
          'ferrous',
          'calcium',
          'tdvaccine',
          'tddose'
        ].contains(key)) {
          meds.add(row);
        }
        // Schedule & Remarks: next schedule, remarks
        else if (['nextschedule', 'nextvisit', 'remarks'].contains(key)) {
          schedule.add(row);
        }
        // Skip risk level and factors (they go to the risk summary card)
        else if (['risklevel', 'riskfactors', 'suggestedactions']
            .contains(key)) {
          continue;
        } else {
          vitals.add(row); // fallback
        }
      }

      // Every section conditional, including Vitals. A checkup shows the
      // containers it has content for and no others — an empty "Fetal
      // Assessment" card announced that nothing was measured, which is not
      // information the record needs a container for.
      //
      // `meds` was being collected and then dropped from this map entirely,
      // so supplements and the TD dose never appeared under a heading of
      // their own however carefully they were sorted into one.
      return {
        if (vitals.isNotEmpty) 'Vitals': vitals,
        if (fetal.isNotEmpty) 'Fetal Assessment': fetal,
        if (symptoms.isNotEmpty) 'Symptoms': symptoms,
        if (meds.isNotEmpty) 'Medications & Supplements': meds,
        if (schedule.isNotEmpty) 'Schedule & Remarks': schedule,
      };
    }

    final record = <MapEntry<String, String>>[];
    final worker = <MapEntry<String, String>>[];
    final notes = <MapEntry<String, String>>[];

    for (final row in rows) {
      final key = _labelKey(row.key);

      // Shown by the attribution line under the header. Repeating it as a row
      // put "Recorded by" between the test type and the test date, where it
      // read like a property of the specimen.
      if (key == 'conductedby' || key == 'recordedby') continue;

      if (key.contains('remarks') || key.contains('notes')) {
        notes.add(row);
        continue;
      }

      if (key.contains('healthworker') ||
          key == 'fullname' ||
          key == 'name' ||
          key == 'institution' ||
          key == 'profession') {
        worker.add(row);
        continue;
      }

      record.add(row);
    }

    // "Performed by" rather than "Health Worker Information": these rows are
    // the sonologist or the laboratory that produced the document, which is a
    // different person from the midwife who entered it. Naming the section
    // after the role keeps that separation visible.
    return {
      if (record.isNotEmpty) _recordInfoTitle(): record,
      if (worker.isNotEmpty) 'Performed by': worker,
      if (notes.isNotEmpty) 'Interpretation': notes,
    };
  }


  Widget _buildDetailSection(
      String title, List<MapEntry<String, String>> rows) {
    final icon = _sectionIcon(title);

    // One card, one shape, one weight — for every section of every record type.
    //
    // Each section used to carry its own accent on a 3.5px left border, its
    // icon chip and its title, and Symptoms additionally sat on an orange
    // card. A four-section record was therefore a four-colour page, and none
    // of those colours meant anything: they distinguished "Vitals" from
    // "Fetal Assessment", which are not different in kind or in urgency.
    //
    // Colour in this app has a job — it carries clinical severity, on the
    // blood pressure finding strip and the risk chips. Spending it on section
    // headings devalues it there, and on a record a midwife reads twenty times
    // a day it is noise she has to look past to reach a number.
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderPrimary),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 15, color: AppColors.brandPrimary),
                  const SizedBox(width: 8),
                  Expanded(
                    // Same heading treatment as the weight-gain and blood
                    // pressure cards on the mother's profile: uppercase,
                    // letterspaced, quiet. A record and a chart of the same
                    // pregnancy should not be wearing two different designs.
                    child: Text(
                      _localizedSectionTitle(title).toUpperCase(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: Color(0xFF5A5A5A),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (int i = 0; i < rows.length; i++) ...[
                if (title == 'Symptoms' && _labelKey(rows[i].key) == 'symptoms') ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rows[i].key,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: rows[i].value
                            .split(',')
                            .map((s) => s.trim())
                            .where((s) => s.isNotEmpty)
                            .map((symptom) {
                          final isNone = symptom.toLowerCase() == 'none' ||
                              symptom.toLowerCase() == 'no symptoms' ||
                              symptom.toLowerCase() == 'walang sintomas' ||
                              symptom.toLowerCase() == 'hindi nailagay' ||
                              symptom.toLowerCase() == 'not provided';
                          // Reported, not graded. This row is a comma-joined
                          // string; nothing here knows which symptoms were
                          // marked as danger signs, so colouring them amber
                          // asserted a severity the screen cannot see. A
                          // recorded symptom reads as recorded — the risk
                          // summary above is where severity is stated.
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isNone
                                  ? Colors.transparent
                                  : AppColors.bgSecondary,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isNone
                                    ? AppColors.borderPrimary
                                    : Colors.transparent,
                              ),
                            ),
                            child: Text(
                              symptom,
                              style: TextStyle(
                                color: isNone
                                    ? AppColors.textSecondary
                                    : AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight:
                                    isNone ? FontWeight.w500 : FontWeight.w600,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ] else ...[
                  _buildDetailRow(rows[i].key, rows[i].value),
                ],
                // No rules between rows. ProfileInfoRow carries its own
                // spacing, and a full-width divider after every field was
                // drawing more lines than there were facts.
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _normalizeForCompare(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  /// Gestational age as completed weeks and days.
  ///
  /// It is stored as `weeks + days/7`, and was being printed straight through
  /// — a checkup at 18 weeks 1 day read "18.142857142857142". Completed weeks
  /// is the obstetric convention and matches how gestation is stated
  /// everywhere else in the app.
  String _formatGestationValue(String raw) {
    final numeric = double.tryParse(raw.replaceAll(RegExp(r'[^0-9.]'), ''));
    if (numeric == null || numeric <= 0 || numeric > 45) return raw;

    final totalDays = (numeric * 7).round();
    final weeks = totalDays ~/ 7;
    final days = totalDays % 7;

    final weekText = weeks == 1 ? '1 week' : '$weeks weeks';
    if (days == 0) return weekText;
    return '$weekText ${days == 1 ? '1 day' : '$days days'}';
  }

  /// A value that says nothing was recorded.
  ///
  /// A checkup only captures what the midwife actually did, and a row reading
  /// "Not provided" is a line of screen spent saying so. Fields left blank are
  /// dropped instead, so a container holds what was recorded and nothing else,
  /// and a section with nothing in it does not appear at all.
  bool _isBlankValue(String value) {
    const blanks = {
      '', '-', '—', 'n/a', 'na', 'none', 'notgiven', 'notprovided',
      'notrecorded', 'norecord', 'hindinailagay', 'walang', 'wala',
      'nonerecorded', 'notdocumented', 'unknown', 'null',
    };
    return blanks.contains(_normalizeForCompare(value));
  }

  List<MapEntry<String, String>> _normalizedDisplayRows() {
    final filtered = <MapEntry<String, String>>[];

    for (final row in widget.rows) {
      var label = row.key.trim();
      var value = row.value.trim();
      if (label.isEmpty) continue;

      final labelKey = _normalizeForCompare(label);
      final valueKey = _normalizeForCompare(value);

      // Nothing recorded is not a finding. Every blank row dropped here is a
      // row the reader no longer has to scan past to reach a real one.
      if (_isBlankValue(value)) continue;

      if ((labelKey == 'location' || labelKey == 'labtestlocation') &&
          valueKey == 'mobileupload') {
        continue;
      }

      if (labelKey.contains('ageofgestation') || labelKey == 'aog') {
        value = _formatGestationValue(value);
      }

      // "Weight (kg)" + "52" reads as "Weight" + "52 kg".
      //
      // A unit is a property of the measurement, not of the field name. Kept
      // in the label it padded the left column — enough that a status pill
      // beside it wrapped onto a second line — and left the value looking
      // like a bare number the reader had to go back and qualify.
      //
      // Only applied when the value is bare digits: a label like
      // "Ferrous + FA (tablets)" with a value of "Not given" keeps its label.
      final unitInLabel =
          RegExp(r'^(.*?)\s*\(([^)]{1,10})\)\s*$').firstMatch(label);
      if (unitInLabel != null) {
        final bare = unitInLabel.group(1)!.trim();
        final unit = unitInLabel.group(2)!.trim();
        if (bare.isNotEmpty &&
            RegExp(r"^[0-9]+([.,][0-9]+)?$").hasMatch(value) &&
            !value.toLowerCase().contains(unit.toLowerCase())) {
          label = bare;
          value = "$value $unit";
        }
      }

      filtered.add(MapEntry(label, value));
    }

    return filtered;
  }

  /// A symbol for a field, so a row can be found by shape before it is read.
  ///
  /// A midwife looking for a blood pressure on a screen of fifteen rows should
  /// not have to read fifteen labels to find it.
  IconData _rowIcon(String label) {
    final k = _labelKey(label);
    if (k.contains("bloodpressure")) return Icons.monitor_heart_outlined;
    if (k.contains("bloodtype")) return Icons.bloodtype_outlined;
    if (k.contains("weight")) return Icons.monitor_weight_outlined;
    if (k.contains("height")) return Icons.straighten_rounded;
    if (k.contains("bmi")) return Icons.speed_rounded;
    if (k.contains("ageofgestation") || k == "aog") return Icons.pregnant_woman_outlined;
    if (k.contains("fetalcount")) return Icons.child_care_outlined;
    if (k.contains("fetalheart")) return Icons.favorite_border;
    if (k.contains("fetalposition")) return Icons.rotate_right_rounded;
    if (k.contains("edema")) return Icons.water_drop_outlined;
    if (k.contains("symptom")) return Icons.healing_outlined;
    if (k.contains("vaccine") || k.contains("tddose")) return Icons.vaccines_outlined;
    if (k.contains("ferrous") || k.contains("calcium") || k.contains("medication")) {
      return Icons.medication_outlined;
    }
    if (k.contains("schedule") || k.contains("nextvisit")) return Icons.event_outlined;
    if (k.contains("remarks") || k.contains("notes")) return Icons.sticky_note_2_outlined;
    if (k.contains("labtesttype")) return Icons.science_outlined;
    if (k.contains("date")) return Icons.calendar_today_outlined;
    if (k.contains("location")) return Icons.place_outlined;
    if (k.contains("institution")) return Icons.apartment_rounded;
    if (k.contains("profession")) return Icons.badge_outlined;
    if (k.contains("name")) return Icons.person_outline_rounded;
    return Icons.remove_rounded;
  }

  /// The weight-gain reading, as a pill beside the weight it describes.
  ///
  /// Weight alone says nothing — 43 kg is unremarkable or concerning entirely
  /// depending on where she started and how far along she is. The engine
  /// already computes that against the IOM target; this puts the answer next
  /// to the number instead of leaving the reader to hold both in their head.
  ///
  /// Colour is earned here: amber means the gain is off target and is the same
  /// amber the blood pressure card uses for "repeat this". Paired with a word,
  /// never colour alone.
  Widget? _weightGainChip() {
    final eval = widget.weightGainEval;
    if (eval == null) return null;

    final raw = (eval["status"] ?? "").toString().toLowerCase();
    if (raw.isEmpty) return null;

    final bool below = raw.contains("low") || raw.contains("below");
    final bool above = raw.contains("high") || raw.contains("above");

    final String label;
    final Color tone;
    if (below) {
      label = _t("Below expected", "Kulang sa inaasahan");
      tone = AppColors.warning;
    } else if (above) {
      label = _t("Above expected", "Lampas sa inaasahan");
      tone = AppColors.warning;
    } else {
      label = _t("Within expected", "Nasa inaasahan");
      tone = AppColors.success;
    }

    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: tone,
        ),
      ),
    );
  }

  /// Where a recorded blood pressure sits, as a pill beside the reading.
  ///
  /// The wording comes from [BloodPressureReference] rather than being written
  /// here. "Elevated" would have been the natural word for a pill, and it is
  /// exactly the word this project spent two rounds removing: it belongs to
  /// the non-pregnancy AHA scale, and a record that says "elevated" where the
  /// rule says "at or above the 140/90 threshold" is a second opinion wearing
  /// a shorter label.
  Widget? _bloodPressureChip(String value) {
    final parts = value.split("/");
    if (parts.length < 2) return null;
    final sys = int.tryParse(parts[0].replaceAll(RegExp(r"[^0-9]"), ""));
    final dia = int.tryParse(parts[1].replaceAll(RegExp(r"[^0-9]"), ""));

    final category = BloodPressureReference.categorise(sys, dia);

    final String label;
    final Color tone;
    switch (category) {
      case BpCategory.unreadable:
        return null;
      case BpCategory.severe:
        label = _t("Severe range", "Malubhang antas");
        tone = AppColors.error;
      case BpCategory.raised:
        label = _t("At threshold", "Nasa threshold");
        tone = AppColors.warning;
      case BpCategory.low:
        label = _t("Below range", "Mababa sa saklaw");
        tone = AppColors.info;
      case BpCategory.normal:
        label = _t("Within range", "Nasa saklaw");
        tone = AppColors.success;
    }
    return _statusPill(label, tone);
  }

  Widget _statusPill(String label, Color tone) => Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: tone.withValues(alpha: 0.35)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: tone,
          ),
        ),
      );

  /// One row, in the same shape the Medical Information card uses.
  ///
  /// Built on [ProfileInfoRow] rather than a lookalike, so the two surfaces
  /// cannot drift apart. It also halves the vertical cost: label-above-value
  /// with a full-width divider between every pair is the most expensive
  /// pattern available, and it was fitting about six fields on a screen. Label
  /// left, value right, no rules — roughly twice the density with less ink.
  Widget _buildDetailRow(String label, String value) {
    final isNotProvided = value.toLowerCase() == "not provided" ||
        value.toLowerCase() == "hindi nailagay";

    final key = _labelKey(label);
    final chip = key.contains("weight")
        ? _weightGainChip()
        : key.contains("bloodpressure")
            ? _bloodPressureChip(value)
            : null;

    return ProfileInfoRow(
      icon: label.isEmpty ? null : _rowIcon(label),
      label: label,
      // A label carrying a pill needs more of the row than the default 2:3
      // split allows, or "Weight (kg)" breaks across two lines and leaves the
      // pill hanging under it.
      labelFlex: chip == null ? 2 : 4,
      labelWidget: chip == null
          ? null
          : Row(
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                Flexible(child: chip),
              ],
            ),
      valueWidget: Text(
        value,
        textAlign: TextAlign.end,
        style: TextStyle(
          fontSize: 13,
          fontWeight: isNotProvided ? FontWeight.w400 : FontWeight.w600,
          height: 1.35,
          fontStyle: isNotProvided ? FontStyle.italic : FontStyle.normal,
          color: isNotProvided ? AppColors.textSecondary : AppColors.inputText,
        ),
      ),
    );
  }

  /// How this summary came to exist, in the midwife's terms.
  ///
  /// `prenatal_checkups.remarks_source` records one of three states when the
  /// checkup is saved. The card used to be headed "AI Analysis" with an
  /// "AI Generated" badge regardless — which is wrong twice over: it claims
  /// authorship of text the midwife wrote herself, and it hides the case that
  /// matters most, where a midwife read the AI's draft and corrected it.
  ({String label, IconData icon}) _summaryProvenance() {
    switch (_normalizeForCompare(widget.remarksSource ?? '')) {
      case 'aigeneratedapproved':
        return (
          label: _t('AI-assisted', 'Tulong ng AI'),
          icon: Icons.auto_awesome_rounded
        );
      case 'aigeneratededited':
        return (
          label: _t('AI-assisted, edited by midwife',
              'Tulong ng AI, inayos ng midwife'),
          icon: Icons.edit_note_rounded
        );
      case 'midwifeauthored':
        return (
          label: _t('Written by midwife', 'Isinulat ng midwife'),
          icon: Icons.person_outline_rounded
        );
      default:
        // Nothing recorded about how the remarks were written. The header
        // already says REMARKS; echoing a label beside it
        // told the reader the same thing twice and looked like a value.
        return (label: "", icon: Icons.notes_rounded);
    }
  }

  Widget _buildAiCard(String aiText) {
    final isPrenatal = widget.title.toLowerCase().contains('prenatal');
    final provenance = _summaryProvenance();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The same white card as every other section. It was a tinted, bordered
        // panel that announced itself as different from the record it
        // summarises — and the tint was doing the work a label should do.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderPrimary),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(provenance.icon,
                      size: 15, color: AppColors.brandPrimary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _t('REMARKS', 'MGA TALA'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: Color(0xFF5A5A5A),
                      ),
                    ),
                  ),
                  if (provenance.label.isNotEmpty)
                    Text(
                      provenance.label,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // Language toggle for AI insights
              Align(
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                        color: _aiCardBorder.withValues(alpha: 0.25), width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _showAiInFilipino = false;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: !_showAiInFilipino
                                ? AppColors.brandPrimary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'English',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: !_showAiInFilipino
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: !_showAiInFilipino
                                  ? Colors.white
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _showAiInFilipino = true;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: _showAiInFilipino
                                ? AppColors.brandPrimary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Filipino',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: _showAiInFilipino
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: _showAiInFilipino
                                  ? Colors.white
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (isPrenatal)
                _buildPrenatalAiInsights(_getAiTextForLanguage(aiText))
              else if (widget.useStructuredAiInsights)
                _buildStructuredAiInsights(_getAiTextForLanguage(aiText))
              else
                _buildFormattedAiText(_getAiTextForLanguage(aiText)),
              const SizedBox(height: 12),
              // Disclaimer removed.
              //
              // It said the text "restates the findings recorded by the
              // sonologist" — on a prenatal checkup, where there is no
              // sonologist and the words are the midwife's own. And where she
              // has edited the draft, the sentence is simply false: the text
              // is hers, which is exactly what the label in the header now
              // says. A disclaimer that has to be ignored to be understood
              // teaches people to ignore disclaimers.
              //
              // Provenance is stated once, plainly, at the top of the card.
            ],
          ),
        ),

        // Recommendations card removed. It re-listed lines already present in
        // the summary directly above it — "Monitor maternal warning signs"
        // appeared twice on one screen, once as prose and once as a numbered
        // item — and its first entry was often just the next visit date, which
        // the Schedule section already states.
      ],
    );
  }

  /// Extract the language-appropriate section from AI text.
  /// If the text has ## English / ## Filipino sections, returns the appropriate one.
  /// Otherwise returns the full text.
  String _getAiTextForLanguage(String fullText) {
    final normalized = fullText.replaceAll('\r\n', '\n');

    // Matches both "=== ENGLISH ===" and "## English" style headings
    final englishMatch = RegExp(
      r'(?:===|##)\s*English\s*(?:===)?\s*([\s\S]*?)(?=(?:===|##)\s*Filipino\s*(?:===)?|$)',
      caseSensitive: false,
    ).firstMatch(normalized);
    
    final filipinoMatch = RegExp(
      r'(?:===|##)\s*Filipino\s*(?:===)?\s*([\s\S]*?)(?=(?:===|##)\s*English\s*(?:===)?|$)',
      caseSensitive: false,
    ).firstMatch(normalized);

    final englishText = englishMatch?.group(1)?.trim();
    final filipinoText = filipinoMatch?.group(1)?.trim();

    // If no language sections found, return full text
    if (englishText == null && filipinoText == null) return fullText;

    if (_showAiInFilipino) {
      return filipinoText ?? englishText ?? fullText;
    }
    return englishText ?? filipinoText ?? fullText;
  }

  /// Extract recommendation lines from AI text
  List<String> _extractRecommendations(String aiText) {
    final lines = aiText.split('\n');
    final recommendations = <String>[];
    bool inRecommendations = false;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final upper = trimmed.toUpperCase();
      if (upper.contains('RECOMMENDATION') ||
          upper.contains('SUGGESTED ACTION') ||
          upper.contains('NEXT STEPS') ||
          upper.contains('FOLLOW-UP')) {
        inRecommendations = true;
        // If there's content after the header on the same line
        final colonIdx = trimmed.indexOf(':');
        if (colonIdx != -1 && colonIdx < trimmed.length - 1) {
          final after = trimmed.substring(colonIdx + 1).trim();
          if (after.isNotEmpty) recommendations.add(after);
        }
        continue;
      }

      if (inRecommendations) {
        // Stop if we hit another section header
        if (RegExp(r'^[A-Z][A-Z\s]{3,}:').hasMatch(trimmed)) break;
        final cleaned = trimmed
            .replaceFirst(RegExp(r'^[\-\*\d.]+\s*'), '')
            .trim();
        if (cleaned.isNotEmpty) recommendations.add(cleaned);
      }
    }

    return recommendations;
  }


  // In record_detail_screen.dart, replace _buildPrenatalAiInsights with:

  Widget _buildPrenatalAiInsights(String aiText) {
    if (aiText.isEmpty) {
      return Text(
        _tAi('No AI insights available.', 'Walang available na AI analysis.'),
        style: const TextStyle(color: AppColors.textSecondary),
      );
    }

    // Strip common prefixes that AI might add
    String displayText = aiText;
    final prefixesToStrip = [
      'AI INSIGHTS:',
      'OVERALL ASSESSMENT:',
      'OVERALL HEALTH STATUS:',
      'KEY OBSERVATIONS:',
      'RECOMMENDATIONS:',
      'RECOMMENDED NEXT ACTIONS:',
      'CLINICAL IMPRESSION:',
      'FOLLOW-UP SUGGESTIONS:',
      'DETAILED MEASUREMENTS ASSESSMENT:',
      'ANATOMICAL ASSESSMENT:',
      'GESTATIONAL AGE ASSESSMENT:',
      'LABORATORY RESULTS:',
      'ABNORMAL FINDINGS:',
      'NORMAL RANGES:',
      'SUMMARY:',
    ];

    for (final prefix in prefixesToStrip) {
      if (displayText.toUpperCase().startsWith(prefix)) {
        displayText = displayText.substring(prefix.length).trim();
        break;
      }
    }

    // Strip any duplicate disclaimers from the text itself
    final disclaimersToStrip = [
      'This AI-assisted explanation restates the findings recorded by the sonologist in simpler words, adds nothing of its own, and is intended only for healthcare monitoring support and does not replace professional medical consultation.',
      'Ang AI-assisted na paliwanag na ito ay muling isinasalaysay lamang ang natuklasan ng sonologist at gabay lamang para sa pagsubaybay sa kalusugan at hindi pamalit sa konsultasyon sa doktor o midwife.',
      'Ang AI-assisted na paliwanag na ito ay muling isinasalaysay lamang ang natuklasan ng sonologist at gabay lamang para sa pagsubaybay sa kalusugan at hindi pamalit sa konsultasyon sa inyong doktor o midwife.',
      'Ang AI-assisted na paliwanag na ito ay muling isinasalaysay lamang ang natuklasan ng sonologist at gabay lamang para sa pagsubaybay sa kalusugan at hindi pamalit sa konsultasyon sa inyong doktor o midwife',
      'This AI-assisted explanation restates the findings recorded by the sonologist in simpler words, adds nothing of its own, and is intended only for healthcare monitoring support and does not replace professional medical consultation',
      'This AI-assisted explanation restates the findings recorded by the sonologist and is a guide for health monitoring only and is not a substitute for consultation with a doctor or midwife.',
      'This AI-assisted explanation restates the findings recorded by the sonologist and is a guide for health monitoring only and is not a substitute for consultation with a doctor or midwife'
    ];

    for (final disc in disclaimersToStrip) {
      final reg = RegExp(RegExp.escape(disc), caseSensitive: false);
      displayText = displayText.replaceAll(reg, '').trim();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _aiCardBorder.withValues(alpha: 0.15)),
      ),
      child: Text(
        _translateLine(displayText, _showAiInFilipino),
        style: const TextStyle(
          fontSize: 13,
          color: AppColors.textPrimary,
          height: 1.6,
        ),
      ),
    );
  }

  String _normalizeMarkdownLine(String input) {
    var line = input;
    line = line.replaceFirst(RegExp(r'^\s*#{1,6}\s*'), '');
    line = line.replaceFirst(RegExp(r'^\s*(?:[-*])\s+'), '');
    return line;
  }

  String _cleanResidualMarkdown(String input) {
    var text = input;
    text = text.replaceAll('**', '');
    text = text.replaceAll('##', '');
    text = text.replaceAll(RegExp(r'(?<!\*)\*(?!\*)'), '');
    return text;
  }

  List<TextSpan> _parseInlineMarkdown(String input) {
    final spans = <TextSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*');
    int current = 0;

    for (final match in pattern.allMatches(input)) {
      if (match.start > current) {
        spans.add(TextSpan(
          text: _cleanResidualMarkdown(input.substring(current, match.start)),
        ));
      }

      final boldText = match.group(1) ?? '';
      spans.add(TextSpan(
        text: boldText,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ));
      current = match.end;
    }

    if (current < input.length) {
      spans.add(TextSpan(
        text: _cleanResidualMarkdown(input.substring(current)),
      ));
    }

    if (spans.isEmpty) {
      spans.add(TextSpan(text: _cleanResidualMarkdown(input)));
    }

    return spans;
  }

  Widget _buildFormattedAiText(String text) {
    if (text.isEmpty) {
      return Text(
        _tAi('No AI insights available.', 'Walang available na AI analysis.'),
        style: const TextStyle(color: AppColors.textSecondary),
      );
    }

    final lines = text.split('\n');
    final spans = <TextSpan>[];

    for (int i = 0; i < lines.length; i++) {
      final normalizedLine = _normalizeMarkdownLine(lines[i]);
      final translatedLine = _translateLine(normalizedLine, _showAiInFilipino);
      spans.addAll(_parseInlineMarkdown(translatedLine));
      if (i < lines.length - 1) {
        spans.add(const TextSpan(text: '\n'));
      }
    }

    return RichText(
      text: TextSpan(
        style:
            const TextStyle(color: Colors.black87, fontSize: 14, height: 1.45),
        children: spans,
      ),
    );
  }

  Map<String, List<String>> _extractAiSections(String rawText) {
    final lines = rawText
        .split('\n')
        .map((l) => _cleanResidualMarkdown(_normalizeMarkdownLine(l)).trim())
        .toList();

    final sections = <String, List<String>>{};
    String currentSection = 'SUMMARY';
    sections[currentSection] = [];

    final headingPattern = RegExp(
      r'^(?:\d+\.\s*)?(RELEVANCE CHECK|RELEVANCE REASON|LABORATORY RESULTS|ABNORMAL FINDINGS|NORMAL RANGES|REFERENCE RANGES|OVERALL ASSESSMENT|OVERALL HEALTH STATUS|RECOMMENDATIONS|RECOMMENDED NEXT ACTIONS|KEY OBSERVATIONS|DETAILED MEASUREMENTS ASSESSMENT|ANATOMICAL ASSESSMENT|GESTATIONAL AGE ASSESSMENT|CLINICAL IMPRESSION|FOLLOW-UP SUGGESTIONS)\s*:?\s*(.*)$',
      caseSensitive: false,
    );

    for (final line in lines) {
      if (line.isEmpty) continue;
      if (line.toUpperCase() == 'COMPREHENSIVE LABORATORY ANALYSIS') continue;
      if (RegExp(r'^[-_=]{2,}$').hasMatch(line.replaceAll(' ', ''))) {
        continue;
      }

      final heading = headingPattern.firstMatch(line);
      if (heading != null) {
        currentSection = heading.group(1)!.toUpperCase();
        if (currentSection == 'REFERENCE RANGES') {
          currentSection = 'NORMAL RANGES';
        }
        sections.putIfAbsent(currentSection, () => []);
        final inlineContent = heading.group(2)?.trim() ?? '';
        if (inlineContent.isNotEmpty) {
          sections[currentSection]!.add(inlineContent);
        }
        continue;
      }

      sections.putIfAbsent(currentSection, () => []);
      sections[currentSection]!.add(line);
    }

    sections.removeWhere((_, value) => value.isEmpty);
    return sections;
  }

  String _safeText(Object? value) => value?.toString() ?? '';

  String _stripDecorativeDashes(String value) {
    final trimmed = value.trim();
    if (RegExp(r'^[-_=]{2,}$').hasMatch(trimmed)) {
      return '';
    }
    return trimmed.replaceAll(RegExp(r'\s+--+\s+'), ' ').trim();
  }

  bool _isConcerningAnalyte(String text) {
    final t = text.toLowerCase();
    return RegExp(
      r'protein|glucose|ketone|nitrite|leukocyte|blood|pus|bacteria|bilirubin|hiv|hbsag|vdrl|rpr|syphilis|infection|pathogen',
      caseSensitive: false,
    ).hasMatch(t);
  }

  String _classifyLabStatus(String testName, String rawValue) {
    final test = testName.toLowerCase();
    final value = rawValue.toLowerCase();
    final merged = '$test $value';

    final hasWithinNormal = RegExp(
      r'within normal limits|within normal range|normal range|wnl',
      caseSensitive: false,
    ).hasMatch(value);
    if (hasWithinNormal) return 'WITHIN NORMAL LIMITS';

    final isColorFinding = test.contains('color') || test.contains('colour');
    if (isColorFinding) {
      if (RegExp(r'\byellow\b|\bstraw\b|\bpale\b|\bclear\b',
              caseSensitive: false)
          .hasMatch(value)) {
        return 'WITHIN NORMAL LIMITS';
      }
      if (RegExp(r'\bdark\b|\bamber\b|\bbrown\b|\bred\b|\bbloody\b',
              caseSensitive: false)
          .hasMatch(value)) {
        return 'ABNORMAL (REVIEW)';
      }
      return 'OBSERVE';
    }

    if (RegExp(r'\bpositive\b', caseSensitive: false).hasMatch(value)) {
      if (_isConcerningAnalyte(merged)) return 'POSITIVE (REVIEW)';
      if (RegExp(r'pregnancy|hcg', caseSensitive: false).hasMatch(test)) {
        return 'POSITIVE (EXPECTED)';
      }
      return 'POSITIVE';
    }

    if (RegExp(r'\bnegative\b', caseSensitive: false).hasMatch(value)) {
      if (RegExp(r'pregnancy|hcg', caseSensitive: false).hasMatch(test)) {
        return 'NEGATIVE (REVIEW)';
      }
      if (_isConcerningAnalyte(merged)) return 'NEGATIVE (REASSURING)';
      return 'NEGATIVE';
    }

    if (RegExp(r'\btrace\b|\bfew\b|\bslight\b|\bmild\b|\bborderline\b',
            caseSensitive: false)
        .hasMatch(value)) {
      return 'BORDERLINE';
    }

    if (RegExp(
      r'\babnormal\b|\bcritical\b|outside normal range|higher than normal|lower than normal|\belevated\b|\bdecreased\b|\bincreased\b|!',
      caseSensitive: false,
    ).hasMatch(value)) {
      return 'ABNORMAL (REVIEW)';
    }

    if (RegExp(r'\bnormal\b', caseSensitive: false).hasMatch(value)) {
      return 'NORMAL';
    }

    return 'OBSERVE';
  }

  bool _isConcerningStatus(String status) {
    final s = status.toUpperCase();
    return s.contains('REVIEW') ||
        s.contains('ABNORMAL') ||
        s.contains('CONCERNING');
  }

  bool _isCautionStatus(String status) {
    final s = status.toUpperCase();
    return s == 'OBSERVE' ||
        s == 'BORDERLINE' ||
        s == 'POSITIVE' ||
        s == 'MONITOR';
  }

  Color _statusChipBackground(String status) {
    if (_isConcerningStatus(status)) return AppColors.error.withValues(alpha: 0.08);
    if (_isCautionStatus(status)) return AppColors.warning.withValues(alpha: 0.08);
    return AppColors.success.withValues(alpha: 0.08);
  }

  Color _statusChipBorder(String status) {
    if (_isConcerningStatus(status)) return AppColors.error.withValues(alpha: 0.25);
    if (_isCautionStatus(status)) return AppColors.warning.withValues(alpha: 0.25);
    return AppColors.success.withValues(alpha: 0.25);
  }

  Color _statusChipTextColor(String status) {
    if (_isConcerningStatus(status)) return AppColors.error;
    if (_isCautionStatus(status)) return AppColors.warning;
    return AppColors.success;
  }

  String _statusMeaning(String status) {
    switch (status.toUpperCase()) {
      case 'WITHIN NORMAL LIMITS':
        return 'Consistent with expected findings for this test.';
      case 'NORMAL':
        return 'Within expected range for this parameter.';
      case 'ABNORMAL (REVIEW)':
      case 'ABNORMAL':
        return 'May benefit from continued monitoring and clinician follow-up.';
      case 'BORDERLINE':
        return 'Near expected range threshold. Monitor trends in coordination with your healthcare provider.';
      case 'OBSERVE':
        return 'Observe and compare with expected values over time.';
      case 'POSITIVE (REVIEW)':
        return 'Positive finding that may warrant further observation.';
      case 'POSITIVE (EXPECTED)':
        return 'Positive finding is expected for this test context.';
      case 'NEGATIVE (REASSURING)':
        return 'No concerning marker detected for this parameter.';
      case 'NEGATIVE (REVIEW)':
        return 'Verify result in coordination with your healthcare provider.';
      case 'POSITIVE':
      case 'NEGATIVE':
        return 'Observe this result based on the specific test context.';
      default:
        return 'Observe this result together with expected ranges and overall assessment.';
    }
  }

  ({String testName, String value, String status}) _parseLabResultLine(
      String line) {
    final cleaned =
        _safeText(line).replaceFirst(RegExp(r'^[•\-*]\s*'), '').trim();
    final colonIndex = cleaned.indexOf(':');
    if (colonIndex == -1) {
      return (testName: cleaned, value: '', status: 'UNKNOWN');
    }

    final testName = cleaned.substring(0, colonIndex).trim();
    final rawValue = _safeText(cleaned.substring(colonIndex + 1)).trim();
    final status = _classifyLabStatus(testName, rawValue);

    final value = rawValue
        .replaceAll('!', '')
        .replaceAll('⚠️', '')
        .replaceAll('⚠', '')
        .replaceAll(RegExp(r'\[\s*(NORMAL|ABNORMAL|EXPECTED|MONITOR|REVIEW|CONCERNING|OBSERVE|INFO|UNKNOWN)\s*\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\b(NORMAL|ABNORMAL|EXPECTED|MONITOR|REVIEW|CONCERNING|OBSERVE)\b', caseSensitive: false), '')
        .trim();

    return (
      testName: _stripDecorativeDashes(testName),
      value: _stripDecorativeDashes(value),
      status: status
    );
  }

  String _normalizeAspectKey(String input) {
    return input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  String _extractAnalyteFromLine(String line) {
    var normalized = _safeText(line)
        .replaceFirst(RegExp(r'^[•\-*]\s*'), '')
        .replaceFirst(RegExp(r'^Reference\s*:\s*', caseSensitive: false), '')
        .trim();

    if (normalized.isEmpty) return '';

    final colonMatch =
        RegExp(r'^([A-Za-z0-9()/%+\-.]+)\s*:').firstMatch(normalized);
    if (colonMatch != null) {
      return (colonMatch.group(1) ?? '').trim();
    }

    final isMatch =
        RegExp(r'^([A-Za-z0-9()/%+\-.]+)\s+is\b', caseSensitive: false)
            .firstMatch(normalized);
    if (isMatch != null) {
      return (isMatch.group(1) ?? '').trim();
    }

    return '';
  }

  List<String> _aspectCandidates(String aspect) {
    final raw = _safeText(aspect).trim();
    if (raw.isEmpty) return const <String>[];

    final candidates = <String>{raw};
    final withoutParen = raw.replaceAll(RegExp(r'\(.*?\)'), '').trim();
    if (withoutParen.isNotEmpty) {
      candidates.add(withoutParen);
    }
    final firstToken = withoutParen.split(RegExp(r'\s+')).first.trim();
    if (firstToken.isNotEmpty) {
      candidates.add(firstToken);
    }

    return candidates.toList();
  }

  bool _lineMatchesAspect(String line, String aspect) {
    final lineAnalyte = _extractAnalyteFromLine(line);
    if (lineAnalyte.isNotEmpty) {
      final lineKey = _normalizeAspectKey(lineAnalyte);
      for (final candidate in _aspectCandidates(aspect)) {
        if (_normalizeAspectKey(candidate) == lineKey) {
          return true;
        }
      }
      return false;
    }

    final source = _safeText(line);
    for (final candidate in _aspectCandidates(aspect)) {
      final escaped = RegExp.escape(candidate);
      final bounded = RegExp(
        '(^|[^A-Za-z0-9])$escaped([^A-Za-z0-9]|\$)',
        caseSensitive: false,
      );
      if (bounded.hasMatch(source)) {
        return true;
      }
    }
    return false;
  }

  String _buildAspectDetails(
      String aspect, List<String> abnormalLines, List<String> rangeLines) {
    final matches = <String>[];
    for (final line in abnormalLines) {
      if (_lineMatchesAspect(line, aspect)) {
        matches.add(line);
      }
    }
    for (final line in rangeLines) {
      if (_lineMatchesAspect(line, aspect)) {
        matches.add('Reference: $line');
      }
    }
    return matches.join('\n\n').trim();
  }

  Widget _buildLabResultsSummaryCard(Map<String, List<String>> sections) {
    final labLines = sections['LABORATORY RESULTS'] ?? const <String>[];
    final abnormalLines = sections['ABNORMAL FINDINGS'] ?? const <String>[];
    final rangeLines = sections['NORMAL RANGES'] ?? const <String>[];

    final rows = labLines
        .map(_parseLabResultLine)
        .where((r) => r.testName.isNotEmpty && r.status != 'UNKNOWN')
        .toList();

    if (rows.isEmpty) {
      return _buildAiSectionCard('LABORATORY RESULTS', labLines);
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderPrimary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.science_outlined,
                  size: 18, color: AppColors.brandPrimary),
              const SizedBox(width: 8),
              Text(
                _tAi('Laboratory Results', 'Mga Resulta ng Lab Test'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...rows.map((row) {
            final details = _buildAspectDetails(
              row.testName,
              abnormalLines,
              rangeLines,
            );
            final aspectKey = _normalizeAspectKey(row.testName);
            final isExpanded = _expandedLabInsightAspects.contains(aspectKey);
            final hasDetails = details.isNotEmpty;

            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.borderPrimary),
                color: Colors.white,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _translateLine(row.testName, _showAiInFilipino),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (hasDetails)
                        IconButton(
                          padding: EdgeInsets.zero,
                          splashRadius: 16,
                          constraints: const BoxConstraints.tightFor(
                              width: 24, height: 24),
                          onPressed: () {
                            setState(() {
                              if (isExpanded) {
                                _expandedLabInsightAspects.remove(aspectKey);
                              } else {
                                _expandedLabInsightAspects.add(aspectKey);
                              }
                            });
                          },
                          icon: Icon(
                            isExpanded ? Icons.expand_less : Icons.expand_more,
                            size: 18,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _statusChipBackground(row.status),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: _statusChipBorder(row.status),
                          ),
                        ),
                        child: Text(
                          _friendlyStatusLabel(row.status, false, true),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _statusChipTextColor(row.status),
                          ),
                        ),
                      ),
                      if (row.value.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.bgSecondary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _translateLine(row.value, _showAiInFilipino),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _translateLine(_statusMeaning(row.status), _showAiInFilipino),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                  if (isExpanded && hasDetails) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.only(top: 10),
                      child: _buildFormattedAiText(details),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  ({String testName, String value, String status, String remark})
      _parseUltrasoundMetricLine(String line) {
    final cleaned =
        _safeText(line).replaceFirst(RegExp(r'^[-\*•]\s*'), '').trim();

    String testName = '';
    String value = '';
    String status = 'UNKNOWN';
    String remark = '';

    final bracketMatch = RegExp(r'\[(.*?)\]').firstMatch(cleaned);

    if (bracketMatch != null) {
      status = bracketMatch.group(1)!.trim().toUpperCase();
      testName = cleaned.substring(0, bracketMatch.start).trim();

      final colonIdx = testName.indexOf(':');
      if (colonIdx != -1) {
        value = testName.substring(colonIdx + 1).trim();
        testName = testName.substring(0, colonIdx).trim();
      }

      remark = cleaned.substring(bracketMatch.end).trim();
      remark = remark.replaceFirst(RegExp(r'^[-:]\s*'), '').trim();
    } else {
      final colonIndex = cleaned.indexOf(':');
      if (colonIndex != -1) {
        testName = cleaned.substring(0, colonIndex).trim();
        String rest = cleaned.substring(colonIndex + 1).trim();

        final parenMatch = RegExp(r'\(([^)]+)\)$').firstMatch(rest);
        if (parenMatch != null) {
          remark = parenMatch.group(1)!.trim();
          rest = rest.substring(0, parenMatch.start).trim();
        }

        if (rest.startsWith('✓') ||
            rest.toLowerCase() == 'normal' ||
            rest.toLowerCase() == 'present') {
          value = 'Present / Normal';
          status = 'NORMAL';
          if (rest.startsWith('✓')) rest = rest.substring(1).trim();
        } else if (rest.startsWith('X') ||
            rest.startsWith('✗') ||
            rest.toLowerCase() == 'abnormal' ||
            rest.toLowerCase() == 'absent') {
          value = 'Absent / Abnormal';
          status = 'ABNORMAL';
          if (rest.startsWith('X') || rest.startsWith('✗')) {
            rest = rest.substring(1).trim();
          }
        } else {
          final dashIndex = rest.lastIndexOf('-');
          if (dashIndex != -1) {
            final possibleStatus =
                rest.substring(dashIndex + 1).trim().toUpperCase();
            if (possibleStatus == 'NORMAL' ||
                possibleStatus == 'ABNORMAL' ||
                possibleStatus == 'REVIEW' ||
                possibleStatus == 'MONITOR' ||
                possibleStatus == 'BORDERLINE' ||
                possibleStatus == 'CONCERNING') {
              status = possibleStatus;
              value = rest.substring(0, dashIndex).trim();
            } else {
              value = rest;
            }
          } else {
            value = rest;
          }
        }
      } else {
        return (testName: cleaned, value: '', status: 'UNKNOWN', remark: '');
      }
    }

    if (status == 'CONCERNING') status = 'ABNORMAL';

    if (status == 'UNKNOWN' || status.isEmpty) {
      if (RegExp(r'\bnormal\b', caseSensitive: false).hasMatch(value)) {
        status = 'NORMAL';
      } else if (RegExp(
              r'\babnormal\b|\bcritical\b|outside normal range|concerning',
              caseSensitive: false)
          .hasMatch(value)) {
        status = 'ABNORMAL';
      } else {
        status = 'INFO';
      }
    }

    return (testName: testName, value: value, status: status, remark: remark);
  }

  Widget _buildUltrasoundMetricsSummaryCard(String title, List<String> lines) {
    final isUltrasound = widget.title.toLowerCase().contains('ultrasound');
    if (lines.isEmpty) return _buildAiSectionCard(title, lines);

    final rows = lines
        .map(_parseUltrasoundMetricLine)
        .where((r) => r.testName.isNotEmpty)
        .toList();

    if (rows.isEmpty) {
      return _buildAiSectionCard(title, lines);
    }

    IconData headerIcon = Icons.article_outlined;
    Color headerColor = AppColors.brandPrimary;

    final normalized = title.trim().toUpperCase();
    if (normalized == 'DETAILED MEASUREMENTS ASSESSMENT') {
      headerColor = Colors.teal;
      headerIcon = Icons.straighten;
    } else if (normalized == 'ANATOMICAL ASSESSMENT') {
        headerColor = AppColors.success;
      headerIcon = Icons.child_care_outlined;
    } else if (normalized == 'ABNORMAL FINDINGS') {
        headerColor = AppColors.error;
      headerIcon = Icons.warning_amber_rounded;
    } else if (normalized.contains('NORMAL RANGES')) {
      headerIcon = Icons.analytics_outlined;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: headerColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: headerColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(headerIcon, size: 18, color: headerColor),
              const SizedBox(width: 8),
              Text(
                _friendlyAiSectionTitle(title),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: headerColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...rows.map((row) {
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.borderPrimary),
                color: Colors.white,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _translateLine(row.testName, _showAiInFilipino),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (row.status != 'UNKNOWN' && row.status != 'INFO')
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _statusChipBackground(row.status),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: _statusChipBorder(row.status),
                            ),
                          ),
                          child: Text(
                            _friendlyStatusLabel(row.status, isUltrasound, !isUltrasound),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _statusChipTextColor(row.status),
                            ),
                          ),
                        ),
                      if (row.value.isNotEmpty &&
                          row.value != 'Present / Normal' &&
                          row.value != 'Absent / Abnormal')
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.bgSecondary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _translateLine(row.value, _showAiInFilipino),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (row.remark.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      _translateLine(row.remark, _showAiInFilipino),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAiSectionCard(String title, List<String> lines) {
    final friendlyTitle = _friendlyAiSectionTitle(title);
    Color color = AppColors.brandPrimary;
    IconData icon = Icons.article_outlined;

    final normalized = title.trim().toUpperCase();
    if (normalized.contains('HEALTH STATUS')) {
      final hasHealthy = lines.any((v) => v.toLowerCase().contains('healthy'));
        color = hasHealthy ? AppColors.success : AppColors.warning;
      icon = Icons.monitor_heart_outlined;
    } else if (normalized == 'DETAILED MEASUREMENTS ASSESSMENT') {
      color = Colors.teal;
      icon = Icons.straighten;
    } else if (normalized == 'ANATOMICAL ASSESSMENT') {
        color = AppColors.success;
      icon = Icons.child_care_outlined;
    } else if (normalized == 'ABNORMAL FINDINGS') {
        color = AppColors.error;
      icon = Icons.warning_amber_rounded;
    } else if (normalized.contains('RECOMMENDED')) {
      color = Colors.blue;
      icon = Icons.lightbulb_outline;
    } else if (normalized == 'OVERALL ASSESSMENT') {
      icon = Icons.summarize_outlined;
    } else if (normalized == 'KEY OBSERVATIONS') {
      icon = Icons.visibility_outlined;
    } else if (normalized == 'CLINICAL IMPRESSION') {
      icon = Icons.medical_information_outlined;
      color = Colors.indigo;
    } else if (normalized == 'FOLLOW-UP SUGGESTIONS') {
      icon = Icons.follow_the_signs;
      color = Colors.blue;
    } else if (normalized == 'SUMMARY') {
      icon = Icons.analytics_outlined;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  friendlyTitle,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildFormattedAiText(lines.map((line) {
            String cleaned = line.trim();
            if (RegExp(r'^[A-Z_]+$').hasMatch(cleaned)) {
              cleaned = cleaned
                  .replaceAll('_', ' ')
                  .split(' ')
                  .map((word) => word.isEmpty
                      ? ''
                      : '${word[0]}${word.substring(1).toLowerCase()}')
                  .join(' ');
            }
            return _translateLine(cleaned, _showAiInFilipino);
          }).join('\n')),
        ],
      ),
    );
  }

  Widget _buildMotherFriendlyCard({
    required String title,
    required IconData icon,
    required CbcComponentStatus status,
    required String description,
  }) {
    final statusColor = status == CbcComponentStatus.expected
        ? AppColors.success
        : (status == CbcComponentStatus.monitor
            ? AppColors.warning
            : AppColors.error);

    final statusText = _showAiInFilipino
        ? (status == CbcComponentStatus.expected
            ? '✅ Maayos (Normal na Antas)'
            : (status == CbcComponentStatus.monitor
                ? '⚠️ Iminumungkahi ang Pagsubaybay'
                : '🚨 Nangangailangan ng Pagsusuri'))
        : (status == CbcComponentStatus.expected
            ? '✅ Within Expected Monitoring Range'
            : (status == CbcComponentStatus.monitor
                ? '⚠️ Monitoring Recommended'
                : '🚨 Clinical Follow-Up Recommended'));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderPrimary),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: statusColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUltrasoundMotherFriendlyCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required bool isWarning,
    required String desc,
  }) {
    final statusColor = isWarning ? AppColors.warning : AppColors.success;
    final statusText = _showAiInFilipino
        ? (isWarning ? 'Para sa Dagdag na Pagsubaybay' : 'Nasa Inaasahang Kondisyon')
        : (isWarning ? 'Closer Monitoring Recommended' : 'Within Expected Range');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderPrimary),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.015),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor.withValues(alpha: 0.2), width: 1),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: AppColors.borderPrimary, height: 1),
          const SizedBox(height: 10),
          Text(
            desc,
            style: const TextStyle(
              fontSize: 12,
              height: 1.45,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUltrasoundStructuredInsights(String text, Map<String, List<String>> sections) {
    // 1. Resolve Gestational Age & Monitoring Classification

    final classificationStr = widget.ultrasoundClassification?.toLowerCase() ?? '';
    MonitoringClassification classification = MonitoringClassification.withinExpectedRange;
    if (classificationStr.contains('closer') || classificationStr.contains('monitor')) {
      classification = MonitoringClassification.requiresCloserMonitoring;
    } else if (classificationStr.contains('follow') || classificationStr.contains('recommend')) {
      classification = MonitoringClassification.followUpRecommended;
    }

    // Dynamic Fallback: Scan approved AI text for bracketed statuses if classification is default
    if (classification == MonitoringClassification.withinExpectedRange) {
      final statuses = <String>[];
      final regExp = RegExp(r'\[(.*?)\]');
      for (final match in regExp.allMatches(text)) {
        statuses.add(match.group(1)!);
      }
      final computed = UltrasoundInterpretationEngine.classifyMonitoring(statuses);
      if (computed != MonitoringClassification.withinExpectedRange) {
        classification = computed;
      }
    }

    // Helper to search keywords
    bool hasKeywords(List<String> keywords) {
      final lower = text.toLowerCase();
      return keywords.any((kw) => lower.contains(kw));
    }

    final isFilipino = _showAiInFilipino;

    // Resolve statuses
    final growthWarning = (classification != MonitoringClassification.withinExpectedRange &&
            hasKeywords(['growth', 'size', 'bpd', 'hc', 'ac', 'fl', 'weight', 'efw', 'restricted', 'iugr', 'lga', 'sga', 'sukat', 'laki', 'timbang'])) ||
        hasKeywords(['growth restriction', 'iugr', 'small for gestational', 'large for gestational', 'abnormal growth']);

    final heartWarning = (classification != MonitoringClassification.withinExpectedRange &&
            hasKeywords(['heart', 'fhr', 'cardiac', 'beat', 'tibok', 'puso', 'bpm'])) ||
        hasKeywords(['bradycardia', 'tachycardia', 'irregular heart rate', 'fetal distress', 'abnormal heartbeat']);

    final envWarning = (classification != MonitoringClassification.withinExpectedRange &&
            hasKeywords(['fluid', 'amniotic', 'afi', 'oligo', 'poly', 'placenta', 'previa', 'praevia', 'tubig', 'inunan'])) ||
        hasKeywords(['oligohydramnios', 'polyhydramnios', 'placenta previa', 'low-lying placenta', 'placental abruption']);

    // Colors & Text based on classification
    final Color overallColor = classification == MonitoringClassification.withinExpectedRange
        ? AppColors.success
        : (classification == MonitoringClassification.requiresCloserMonitoring
            ? AppColors.warning
            : AppColors.error);

    final String overallTitle = isFilipino
        ? (classification == MonitoringClassification.withinExpectedRange
            ? 'Nasa Inaasahang Kondisyon'
            : (classification == MonitoringClassification.requiresCloserMonitoring
                ? 'Kailangan ng Masusing Pagsubaybay'
                : 'Inirerekomenda ang Konsultasyon'))
        : (classification == MonitoringClassification.withinExpectedRange
            ? 'Within Expected Monitoring Range'
            : (classification == MonitoringClassification.requiresCloserMonitoring
                ? 'Requires Closer Monitoring'
                : 'Clinical Follow-Up Recommended'));

    final String overallDesc = isFilipino
        ? (classification == MonitoringClassification.withinExpectedRange
            ? 'Ang iyong ultrasound ay umaayon sa inaasahang kondisyon sa yugtong ito ng pagbubuntis. Ipagpatuloy ang iyong nakasanayang pangangalaga!'
            : (classification == MonitoringClassification.requiresCloserMonitoring
                ? 'May mga obserbasyon sa iyong ultrasound na nangangailangan ng karagdagang atensyon sa susunod na checkup. Huwag mag-alala, ito ay para sa tamang gabay.'
                : 'May mga natuklasang obserbasyon na nangangailangan ng konsultasyon sa doktor o espesyalista upang masigurong ligtas kayo ni baby.'))
        : (classification == MonitoringClassification.withinExpectedRange
            ? 'Your recorded ultrasound results generally appear consistent with the expected range for this stage of pregnancy. Continue your regular prenatal care!'
            : (classification == MonitoringClassification.requiresCloserMonitoring
                ? 'Some observations in your ultrasound suggest closer attention in upcoming checkups. There is no cause for alarm; this is for standard prenatal guidance.'
                : 'Certain findings suggest that a clinical follow-up or consultation is recommended to ensure both you and your baby remain healthy and safe.'));

    final List<Widget> summaryWidgets = [];

    // 1. Overall Summary Card
    summaryWidgets.add(
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: overallColor.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: overallColor.withValues(alpha: 0.25), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  classification == MonitoringClassification.withinExpectedRange
                      ? Icons.check_circle_outline_rounded
                      : (classification == MonitoringClassification.requiresCloserMonitoring
                          ? Icons.info_outline_rounded
                          : Icons.warning_amber_rounded),
                  color: overallColor,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isFilipino ? 'Pangkalahatang Katayuan' : 'Overall Pregnancy Status',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        overallTitle,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: overallColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              overallDesc,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );

    // 2. Simple Monitoring Notes Header
    summaryWidgets.add(
      Row(
        children: [
          const Icon(Icons.favorite_rounded, color: Colors.pinkAccent, size: 18),
          const SizedBox(width: 8),
          Text(
            isFilipino ? 'Mga Gabay Para sa Ina' : 'Simple Monitoring Notes',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
    summaryWidgets.add(const SizedBox(height: 12));

    // Card 1: Baby's Growth
    summaryWidgets.add(
      _buildUltrasoundMotherFriendlyCard(
        title: isFilipino ? 'Suporta sa Paglaki at Sukat ng Baby' : "Baby's Growth & Size Support",
        subtitle: isFilipino ? 'BPD, HC, AC, FL, gestational age, at fetal weight' : 'Body metrics, weight, and general size',
        icon: Icons.child_care_rounded,
        iconColor: Colors.teal.shade500,
        isWarning: growthWarning,
        desc: isFilipino
            ? (growthWarning
                ? 'May kaunting pagkakaiba sa sukat ni baby kumpara sa karaniwang sukat sa kanyang yugto. Ipinapayo ang patuloy na pagsubaybay sa kanyang paglaki.'
                : 'Ang sukat ng ulo, tiyan, at hita ni baby ay umaayon sa kanyang linggo sa sinapupunan. Ito ay nagpapakita ng malusog na paglaki.')
            : (growthWarning
                ? "Some measurements show minor variations from the average size for this stage. Continued monitoring of your baby's growth is recommended."
                : "Your baby's head, tummy, and thigh measurements are matching up beautifully with the expected growth for this week of pregnancy."),
      ),
    );
    summaryWidgets.add(const SizedBox(height: 12));

    // Card 2: Baby's Heart Activity
    summaryWidgets.add(
      _buildUltrasoundMotherFriendlyCard(
        title: isFilipino ? 'Tibok ng Puso ni Baby' : "Baby's Heart Activity",
        subtitle: isFilipino ? 'Tibok ng puso o Fetal Heart Rate (FHR)' : 'Fetal Heart Rate (FHR) & cardiac rhythm',
        icon: Icons.favorite_border_rounded,
        iconColor: Colors.redAccent.shade200,
        isWarning: heartWarning,
        desc: isFilipino
            ? (heartWarning
                ? 'May nakitang kaunting pagkakaiba sa bilis o ritmo ng tibok ng puso ni baby. Inirerekomenda ang regular na pag-monitor.'
                : 'Ang tibok ng puso ni baby ay malakas at nasa ligtas at normal na bilis. Ito ay napakagandang senyales.')
            : (heartWarning
                ? "A minor variation in your baby's heart rhythm or rate was observed. We recommend keeping a close watch during your next visits."
                : "Your baby's heartbeat is strong and beating at a safe, healthy rate. This is a wonderful sign of a thriving baby."),
      ),
    );
    summaryWidgets.add(const SizedBox(height: 12));

    // Card 3: Baby's Environment & Placenta
    summaryWidgets.add(
      _buildUltrasoundMotherFriendlyCard(
        title: isFilipino ? 'Placenta at Tubig sa Sinapupunan' : "Baby's Environment & Placenta Support",
        subtitle: isFilipino ? 'Amniotic fluid at posisyon ng inunan' : 'Amniotic fluid level and placental position',
        icon: Icons.water_drop_outlined,
        iconColor: Colors.blue.shade400,
        isWarning: envWarning,
        desc: isFilipino
            ? (envWarning
                ? 'May nakitang indikasyon ng mababa o mataas na antas ng tubig o mababang posisyon ng inunan. Kailangan ng masusing paggabay at pag-iingat.'
                : 'Sapat ang dami ng tubig (amniotic fluid) sa iyong sinapupunan para malayang makagalaw si baby, at ang inunan ay nasa tamang posisyon.')
            : (envWarning
                ? "There is a slight variation in the fluid level or the placement of the placenta. Rest and guidance on safe movements are advised."
                : "Your baby has plenty of amniotic fluid to swim safely, and the placenta is securely positioned to deliver oxygen and nutrients."),
      ),
    );

    summaryWidgets.add(const SizedBox(height: 16));

    // Detailed Ultrasound Findings Expansion Tile
    final detailedWidgets = <Widget>[];
    const sectionOrder = [
      'GESTATIONAL AGE ASSESSMENT',
      'DETAILED MEASUREMENTS ASSESSMENT',
      'ANATOMICAL ASSESSMENT',
      'ABNORMAL FINDINGS',
      'NORMAL RANGES',
      'KEY OBSERVATIONS',
      'SUMMARY',
    ];

    for (final key in sectionOrder) {
      if (sections.containsKey(key)) {
        detailedWidgets.add(_buildUltrasoundMetricsSummaryCard(key, sections[key]!));
      }
    }

    if (detailedWidgets.isNotEmpty) {
      summaryWidgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: Row(
                children: [
                  const Icon(Icons.settings_outlined, color: AppColors.brandPrimary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isFilipino
                          ? 'Detalyadong Resulta ng Ultrasound (Para sa Midwife)'
                          : 'Detailed Ultrasound Findings (Healthcare Personnel View)',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.brandPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(top: 8),
              children: detailedWidgets,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: summaryWidgets,
    );
  }

  Widget _buildLabStructuredInsights(String text, Map<String, List<String>> sections) {
    // 1. Determine Trimester from AI text
    Trimester trimester = Trimester.third;
    final lowerText = text.toLowerCase();
    if (lowerText.contains('1st trimester') || lowerText.contains('first trimester')) {
      trimester = Trimester.first;
    } else if (lowerText.contains('2nd trimester') || lowerText.contains('second trimester')) {
      trimester = Trimester.second;
    } else if (lowerText.contains('3rd trimester') || lowerText.contains('third trimester')) {
      trimester = Trimester.third;
    }

    // 2. Extract laboratory results
    final labLines = sections['LABORATORY RESULTS'] ?? const <String>[];
    final Map<String, double> parsedValues = {};
    final Map<String, String> parsedValueStrs = {};
    for (final line in labLines) {
      final parsed = _parseLabResultLine(line);
      if (parsed.testName.isNotEmpty && parsed.value.isNotEmpty) {
        final val = double.tryParse(parsed.value.replaceAll(RegExp(r'[^\d.]'), ''));
        if (val != null) {
          parsedValues[parsed.testName] = val;
          parsedValueStrs[parsed.testName] = parsed.value;
        }
      }
    }

    // 3. Interpret using LabCbcInterpretationEngine
    final cbcResults = LabCbcInterpretationEngine.interpretAll(
      values: parsedValues,
      valueStrs: parsedValueStrs,
      trimester: trimester,
    );

    // If we could not parse any supported CBC results, fall back to default formatted text
    if (cbcResults.isEmpty) {
      return _buildFormattedAiText(text);
    }

    // 4. Group results
    CbcComponentResult? findResult(String name) {
      for (final res in cbcResults) {
        if (res.componentName.toLowerCase() == name.toLowerCase()) {
          return res;
        }
      }
      return null;
    }

    CbcComponentStatus getGroupStatus(List<String> names) {
      var finalStatus = CbcComponentStatus.expected;
      for (final name in names) {
        final res = findResult(name);
        if (res != null) {
          if (res.status == CbcComponentStatus.review) {
            return CbcComponentStatus.review;
          } else if (res.status == CbcComponentStatus.monitor) {
            finalStatus = CbcComponentStatus.monitor;
          }
        }
      }
      return finalStatus;
    }

    final oxygenStatus = getGroupStatus(['Hemoglobin', 'Hematocrit', 'MCV']);
    final immuneStatus = getGroupStatus(['WBC']);
    final clottingStatus = getGroupStatus(['Platelets']);

    // 5. Overall Monitoring Classification
    final overallClassification = LabCbcInterpretationEngine.classifyOverall(cbcResults);

    final overallColor = overallClassification == MonitoringClassification.withinExpectedRange
        ? AppColors.success
        : (overallClassification == MonitoringClassification.requiresCloserMonitoring
            ? AppColors.warning
            : AppColors.error);

    final overallTitle = _showAiInFilipino
        ? 'Pangkalahatang Buod ng Pagsusuri sa Dugo'
        : 'Blood Monitoring Summary';

    final overallBadge = _showAiInFilipino
        ? (overallClassification == MonitoringClassification.withinExpectedRange
            ? '✅ Maayos at Normal na Antas'
            : (overallClassification == MonitoringClassification.requiresCloserMonitoring
                ? '⚠️ Iminumungkahi ang Masusing Pagsubaybay'
                : '🚨 Konsultasyon sa Doktor ay Iminumungkahi'))
        : (overallClassification == MonitoringClassification.withinExpectedRange
            ? '✅ Within Expected Monitoring Range'
            : (overallClassification == MonitoringClassification.requiresCloserMonitoring
                ? '⚠️ Monitoring Recommended'
                : '🚨 Clinical Follow-Up Recommended'));

    final overallDesc = _showAiInFilipino
        ? (overallClassification == MonitoringClassification.withinExpectedRange
            ? 'Ang iyong kabuuang resulta ng pagsusuri sa dugo ay maayos at angkop para sa iyong yugto ng pagbubuntis.'
            : (overallClassification == MonitoringClassification.requiresCloserMonitoring
                ? 'Iminumungkahi ang masusing pagsubaybay sa ilang antas ng iyong dugo kasama ang iyong midwife o doktor.'
                : 'Lubhang iminumungkahi ang agarang konsultasyon sa iyong doktor o midwife upang masuri ang mga antas ng iyong dugo.'))
        : (overallClassification == MonitoringClassification.withinExpectedRange
            ? 'Your overall blood monitoring results generally appear consistent with the expected range for this stage of pregnancy.'
            : (overallClassification == MonitoringClassification.requiresCloserMonitoring
                ? 'A closer monitoring of certain blood levels is recommended in coordination with your midwife or doctor.'
                : 'A prompt follow-up consultation with your doctor or midwife is highly recommended to evaluate your blood levels.'));

    final oxygenDesc = _showAiInFilipino
        ? (oxygenStatus == CbcComponentStatus.expected
            ? 'Ang iyong mga antas na may kinalaman sa pagdadala ng oxygen sa dugo (tulad ng Hemoglobin at Hematocrit) ay maayos at nasa normal na antas para sa iyong yugto ng pagbubuntis.'
            : (oxygenStatus == CbcComponentStatus.monitor
                ? 'May kaunting pagbabago sa iyong mga resulta para sa oxygen support. Ipagpatuloy ang pag-inom ng prenatal vitamins at kumonsulta sa iyong midwife.'
                : 'May mga antas sa oxygen support na nangangailangan ng masusing pagsusuri ng midwife o doktor upang maiwasan ang anemia o matinding pagkapagod.'))
        : (oxygenStatus == CbcComponentStatus.expected
            ? 'Your blood monitoring results related to oxygen support (such as Hemoglobin and Hematocrit) appear generally consistent and within the expected range for this stage of pregnancy.'
            : (oxygenStatus == CbcComponentStatus.monitor
                ? 'Your blood monitoring results related to oxygen support show some slight variations. It is recommended to observe these and correlate them with your midwife.'
                : 'Your oxygen support levels indicate variations that require clinical review by your midwife or doctor to prevent anemia.'));

    final immuneDesc = _showAiInFilipino
        ? (immuneStatus == CbcComponentStatus.expected
            ? 'Ang mga naitalang antas na may kinalaman sa immune response o paglaban sa impeksyon (WBC o White Blood Cells) ay maayos at nagpapakita ng malusog na proteksyon.'
            : (immuneStatus == CbcComponentStatus.monitor
                ? 'May katamtamang pagbabago sa immune monitoring. Ito ay karaniwang reaksyon ng katawan habang nagbubuntis, ngunit iminumungkahi ang patuloy na pagsubaybay.'
                : 'Nangangailangan ng karagdagang pagsusuri ang iyong immune response levels upang masigurong ligtas ka at si baby sa anumang impeksyon.'))
        : (immuneStatus == CbcComponentStatus.expected
            ? 'The recorded blood monitoring values related to immune response and infection monitoring (WBC) appear generally reassuring and expected.'
            : (immuneStatus == CbcComponentStatus.monitor
                ? 'The immune monitoring results show moderate variations. While often normal during pregnancy, continued monitoring is recommended.'
                : 'Your immune response levels indicate a need for further clinical review to ensure safety from any infection.'));

    final clottingDesc = _showAiInFilipino
        ? (clottingStatus == CbcComponentStatus.expected
            ? 'Ang mga naitalang antas na may kinalaman sa pagpigil sa pagdurugo (Platelets) ay maayos, ligtas, at handa para sa iyong panganganak.'
            : (clottingStatus == CbcComponentStatus.monitor
                ? 'May kaunting pagbabago sa platelet count. Subaybayan ito sa tulong ng iyong midwife upang manatiling ligtas at malusog.'
                : 'Ang mga antas para sa pagpigil sa pagdurugo ay nangangailangan ng pagsusuri ng doktor upang masigurong ligtas ang iyong panganganak at maiwasan ang komplikasyon.'))
        : (clottingStatus == CbcComponentStatus.expected
            ? 'The recorded blood monitoring values related to platelet activity and blood clotting support (Platelets) appear stable and within expected ranges.'
            : (clottingStatus == CbcComponentStatus.monitor
                ? 'There are minor variations in your platelet levels. Continued observation with your midwife is recommended.'
                : 'Your blood clotting support levels indicate variations that require professional medical review for a safe delivery.'));

    // 6. Build Detailed Widgets (Healthcare Personnel View)
    final abnormalLines = sections['ABNORMAL FINDINGS'] ?? const <String>[];
    final rangeLines = sections['NORMAL RANGES'] ?? const <String>[];
    final detailedWidgets = <Widget>[];

    final highPriorityComponents = {'Hemoglobin', 'Hematocrit', 'WBC', 'Platelets', 'MCV'};
    final highPriorityWidgets = <Widget>[];
    final secondaryWidgets = <Widget>[];

    for (final result in cbcResults) {
      final statusColor = result.status == CbcComponentStatus.expected
          ? AppColors.success
          : (result.status == CbcComponentStatus.monitor
              ? AppColors.warning
              : AppColors.error);

      final statusLabel = LabCbcInterpretationEngine.statusLabel(result.status);

      final componentDetails = _buildAspectDetails(
        result.componentName,
        abnormalLines,
        rangeLines,
      );
      final aspectKey = _normalizeAspectKey(result.componentName);
      final isExpanded = _expandedLabInsightAspects.contains(aspectKey);
      final hasDetails = componentDetails.isNotEmpty;

      final widget = Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: statusColor.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _translateLine(result.componentName, _showAiInFilipino),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (hasDetails)
                  IconButton(
                    padding: EdgeInsets.zero,
                    splashRadius: 16,
                    constraints: const BoxConstraints.tightFor(width: 24, height: 24),
                    onPressed: () {
                      setState(() {
                        if (isExpanded) {
                          _expandedLabInsightAspects.remove(aspectKey);
                        } else {
                          _expandedLabInsightAspects.add(aspectKey);
                        }
                      });
                    },
                    icon: Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    statusLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${result.value} ${result.unit}',
                    style: TextStyle(
                      fontSize: 13,
                      color: statusColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _translateLine(result.contextPhrase, _showAiInFilipino),
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            if (isExpanded && hasDetails) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.only(top: 10),
                child: _buildFormattedAiText(componentDetails),
              ),
            ],
          ],
        ),
      );

      if (highPriorityComponents.contains(result.componentName)) {
        highPriorityWidgets.add(widget);
      } else {
        secondaryWidgets.add(widget);
      }
    }

    if (highPriorityWidgets.isNotEmpty) {
      detailedWidgets.addAll(highPriorityWidgets);
    }
    if (secondaryWidgets.isNotEmpty) {
      detailedWidgets.add(const SizedBox(height: 8));
      detailedWidgets.add(const Divider(color: AppColors.borderPrimary, height: 1));
      detailedWidgets.add(const SizedBox(height: 16));
      detailedWidgets.add(Text(
        _showAiInFilipino ? 'Pang-sekundaryang Antas ng Dugo' : 'Secondary CBC Indices',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: AppColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ));
      detailedWidgets.add(const SizedBox(height: 12));
      detailedWidgets.addAll(secondaryWidgets);
    }

    // 7. Assemble summaryWidgets
    final summaryWidgets = <Widget>[];

    // Blood Monitoring Summary overall banner
    summaryWidgets.add(
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: overallColor.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: overallColor.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              overallTitle,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: overallColor,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              overallBadge,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: overallColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              overallDesc,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textPrimary,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );

    // Simple Monitoring Notes header
    summaryWidgets.add(
      Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.brandAccent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.favorite_rounded, color: AppColors.brandAccent, size: 20),
          ),
          const SizedBox(width: 12),
          Text(
            _showAiInFilipino ? 'Gabay sa Pagsusuri' : 'Simple Monitoring Notes',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
    summaryWidgets.add(const SizedBox(height: 12));

    // Blood Oxygen Support card
    summaryWidgets.add(
      _buildMotherFriendlyCard(
        title: _showAiInFilipino ? 'Suporta sa Oxygen ng Dugo (Blood Oxygen Support)' : 'Blood Oxygen Support',
        icon: Icons.air_rounded,
        status: oxygenStatus,
        description: oxygenDesc,
      ),
    );

    // Infection & Immune Monitoring card
    summaryWidgets.add(
      _buildMotherFriendlyCard(
        title: _showAiInFilipino ? 'Pagsubaybay sa Impeksyon at Imunidad' : 'Infection & Immune Monitoring',
        icon: Icons.shield_outlined,
        status: immuneStatus,
        description: immuneDesc,
      ),
    );

    // Blood Clotting Support card
    summaryWidgets.add(
      _buildMotherFriendlyCard(
        title: _showAiInFilipino ? 'Suporta sa Pag-ampat ng Dugo (Blood Clotting Support)' : 'Blood Clotting Support',
        icon: Icons.water_drop_outlined,
        status: clottingStatus,
        description: clottingDesc,
      ),
    );

    summaryWidgets.add(const SizedBox(height: 16));

    // Collapsible detailed findings (Midwife view)
    if (detailedWidgets.isNotEmpty) {
      summaryWidgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: Row(
                children: [
                  const Icon(Icons.settings_outlined, color: AppColors.brandPrimary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _showAiInFilipino
                          ? 'Detalyadong Resulta ng Lab Test (Para sa Midwife)'
                          : 'Detailed Laboratory Findings (Healthcare Personnel View)',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.brandPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(top: 8),
              children: detailedWidgets,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: summaryWidgets,
    );
  }

  /// Sections that are the model talking rather than the document saying.
  ///
  /// Extraction and narration were doing two different jobs in one block of
  /// text. The values came off the page the mother handed over; the assessment
  /// and recommendations were written about them. Only the first belongs on a
  /// record of what the lab or the sonologist reported.
  static const _narrativeSections = {
    'OVERALL ASSESSMENT',
    'RECOMMENDATIONS',
    'RELEVANCE CHECK',
    'RELEVANCE REASON',
    'SUMMARY',
    'EXPLANATION',
    'WHAT THIS MEANS',
    'KEY OBSERVATIONS',
  };

  /// What was read off the document, rendered exactly like every other
  /// section of every other record.
  ///
  /// Deliberately built from [_buildDetailSection] rather than a lookalike:
  /// cohesion that comes from sharing the widget cannot drift, and this screen
  /// has eleven separate builders that each reinvented the same card.
  ///
  /// Returns an empty box when nothing survives the filter — a heading with no
  /// values under it is worse than no heading.
  Widget _buildExtractedFindings(String text) {
    final sections = _extractAiSections(_getAiTextForLanguage(text));
    if (sections.isEmpty) return const SizedBox.shrink();

    final cards = <Widget>[];

    for (final entry in sections.entries) {
      if (_narrativeSections.contains(entry.key.toUpperCase().trim())) continue;

      final rows = <MapEntry<String, String>>[];
      for (final raw in entry.value) {
        final line = raw.replaceFirst(RegExp(r'^[-•*\s]+'), '').trim();
        if (line.isEmpty) continue;

        // "Hemoglobin: 11.2 g/dL" is a measurement and reads as a labelled
        // row. A line with no colon is a statement, and forcing a label onto
        // it would invent one.
        final split = line.indexOf(':');
        if (split > 0 && split < line.length - 1) {
          rows.add(MapEntry(
            line.substring(0, split).trim(),
            line.substring(split + 1).trim(),
          ));
        } else {
          rows.add(MapEntry('', line));
        }
      }

      if (rows.isEmpty) continue;
      if (cards.isNotEmpty) cards.add(const SizedBox(height: 10));
      cards.add(_buildDetailSection(_titleCase(entry.key), rows));
    }

    if (cards.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [const SizedBox(height: 10), ...cards],
    );
  }

  String _titleCase(String value) => value
      .toLowerCase()
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  Widget _buildStructuredAiInsights(String text) {
    final sections = _extractAiSections(text);
    if (sections.isEmpty) return _buildFormattedAiText(text);

    final isPrenatal = widget.title.toLowerCase().contains('prenatal');
    final isUltrasound = widget.title.toLowerCase().contains('ultrasound');
    final isLab = !isPrenatal && !isUltrasound;

    if (isLab) {
      return _buildLabStructuredInsights(text, sections);
    }

    if (isUltrasound) {
      return _buildUltrasoundStructuredInsights(text, sections);
    }

    // Eliminate redundancy between measurements and anatomical findings
    if (sections.containsKey('ANATOMICAL ASSESSMENT') &&
        sections.containsKey('DETAILED MEASUREMENTS ASSESSMENT')) {
      final measurements = sections['DETAILED MEASUREMENTS ASSESSMENT']!;
      final anatomical = sections['ANATOMICAL ASSESSMENT']!;

      final normalizedMeasurements =
          measurements.map((m) => m.trim().toLowerCase()).toSet();
      final filteredAnatomical = anatomical
          .where(
              (a) => !normalizedMeasurements.contains(a.trim().toLowerCase()))
          .toList();

      if (filteredAnatomical.isEmpty) {
        sections.remove('ANATOMICAL ASSESSMENT');
      } else {
        sections['ANATOMICAL ASSESSMENT'] = filteredAnatomical;
      }
    }

    const sectionOrder = [
      'OVERALL ASSESSMENT',
      'OVERALL HEALTH STATUS',
      'GESTATIONAL AGE ASSESSMENT',
      'DETAILED MEASUREMENTS ASSESSMENT',
      'ANATOMICAL ASSESSMENT',
      'CLINICAL IMPRESSION',
      'LABORATORY RESULTS',
      'ABNORMAL FINDINGS',
      'NORMAL RANGES',
      'KEY OBSERVATIONS',
      'RECOMMENDATIONS',
      'RECOMMENDED NEXT ACTIONS',
      'FOLLOW-UP SUGGESTIONS',
      'SUMMARY',
    ];

    final orderedEntries = <MapEntry<String, List<String>>>[];
    for (final key in sectionOrder) {
      if (sections.containsKey(key)) {
        orderedEntries.add(MapEntry(key, sections[key]!));
      }
    }
    for (final entry in sections.entries) {
      if (!sectionOrder.contains(entry.key)) {
        orderedEntries.add(entry);
      }
    }

    final summaryWidgets = <Widget>[];
    final detailedWidgets = <Widget>[];

    for (final entry in orderedEntries) {
      if (entry.key == 'RELEVANCE CHECK' || entry.key == 'RELEVANCE REASON') {
        continue;
      }

      // Skip recommendations here — they are rendered as a separate card
      // by _buildAiCard to avoid duplication.
      if (entry.key == 'RECOMMENDATIONS' ||
          entry.key == 'RECOMMENDED NEXT ACTIONS' ||
          entry.key == 'FOLLOW-UP SUGGESTIONS') {
        continue;
      }

      if (entry.key == 'LABORATORY RESULTS') {
        final card = _buildLabResultsSummaryCard(sections);
        if (isLab) {
          detailedWidgets.add(card);
        } else {
          summaryWidgets.add(card);
        }
        continue;
      }

      final keyUpper = entry.key.toUpperCase();
      final isDetailedData = keyUpper == 'DETAILED MEASUREMENTS ASSESSMENT' ||
          keyUpper == 'ANATOMICAL ASSESSMENT' ||
          keyUpper == 'ABNORMAL FINDINGS' ||
          keyUpper == 'NORMAL RANGES';

      if (isDetailedData) {
        if ((keyUpper == 'ABNORMAL FINDINGS' || keyUpper == 'NORMAL RANGES') &&
            sections.containsKey('LABORATORY RESULTS')) {
          continue;
        }
        final card = _buildUltrasoundMetricsSummaryCard(entry.key, entry.value);
        if (isUltrasound || isLab) {
          detailedWidgets.add(card);
        } else {
          summaryWidgets.add(card);
        }
      } else {
        summaryWidgets.add(_buildAiSectionCard(entry.key, entry.value));
      }
    }

    if (isUltrasound && detailedWidgets.isNotEmpty) {
      summaryWidgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: Row(
                children: [
                  const Icon(Icons.settings_outlined, color: AppColors.brandPrimary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _tAi(
                        'Detailed Ultrasound Findings (Healthcare Personnel View)',
                        'Detalyadong Resulta ng Ultrasound (Para sa Midwife)',
                      ),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.brandPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(top: 8),
              children: detailedWidgets,
            ),
          ),
        ),
      );
    }

    if (isLab && detailedWidgets.isNotEmpty) {
      summaryWidgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: Row(
                children: [
                  const Icon(Icons.settings_outlined, color: AppColors.brandPrimary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _tAi(
                        'Detailed Laboratory Findings (Healthcare Personnel View)',
                        'Detalyadong Resulta ng Lab Test (Para sa Midwife)',
                      ),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.brandPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(top: 8),
              children: detailedWidgets,
            ),
          ),
        ),
      );
    }

    if (summaryWidgets.isEmpty) return _buildFormattedAiText(text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: summaryWidgets,
    );
  }

  String _translateLine(String line, bool toFilipino) {
    if (!toFilipino) return line;
    var result = line;

    // Apply clinical softening first for both languages if present
    final polyReg = RegExp(r'\bmild\s+polyhydramnios\b|\bpolyhydramnios\b', caseSensitive: false);
    result = result.replaceAll(polyReg, 'Ang naitalang sukat ng amniotic fluid ay mukhang mas mataas nang bahagya sa karaniwang inaasahang saklaw at maaaring makinabang sa patuloy na pagsubaybay.');

    final translations = {
      // Ultrasound common phrases
      'recorded fetal measurements appear generally consistent for this stage':
          'ang mga naitalang sukat ng baby ay pangkalahatang tugma para sa yugtong ito',
      'recorded fetal measurements appear generally consistent':
          'ang mga naitalang sukat ng baby ay pangkalahatang tugma',
      'recorded measurements appear generally consistent for this stage':
          'ang mga naitalang sukat ay pangkalahatang tugma para sa yugtong ito',
      'recorded measurements appear generally consistent':
          'ang mga naitalang sukat ay pangkalahatang tugma',
      'pregnancy monitoring measurements':
          'mga sukat sa pagsubaybay ng pagbubuntis',
      'growth measurements appear generally consistent for this stage':
          'ang mga sukat ng paglaki ng baby ay pangkalahatang tugma para sa yugtong ito',
      'continued healthcare monitoring may help support pregnancy health':
          'ang patuloy na pagsubaybay sa kalusugan ay makakatulong sa iyong pagbubuntis',
      'This AI-assisted explanation restates the findings recorded by the sonologist in simpler words, adds nothing of its own, and is intended only for healthcare monitoring support and does not replace professional medical consultation.':
          'Ang AI-assisted na paliwanag na ito ay muling isinasalaysay lamang sa simpleng salita ang natuklasan ng sonologist at suporta lamang sa pagsubaybay at hindi pumapalit sa propesyonal na payong medikal.',
      'Continued prenatal checkups and healthcare consultation may help support pregnancy health':
          'Ang patuloy na prenatal checkup at konsultasyon sa doktor ay makakatulong upang maging ligtas ang iyong pagbubuntis.',
      
      // Ultrasound anatomical organs
      'skull': 'ulo / bungo',
      'brain': 'utak',
      'face': 'mukha',
      'heart': 'puso',
      'spine': 'gulugod / spine',
      'limbs': 'mga braso at binti',
      'hands': 'mga kamay',
      'feet': 'mga paa',
      'stomach': 'tiyan',
      'bladder': 'pantog',
      'kidneys': 'bato / kidneys',
      'cervix': 'sipit-sipitan / cervix',
      'placenta': 'plasenta / inunan',

      // Clinical softening for monitoring/referrals (English & Tagalog alignment)
      'requires closer monitoring': 'kailangan ng masusing pagsubaybay',
      'requires monitoring': 'kailangan ng pagsubaybay',
      'within expected monitoring range': 'nasa inaasahang saklaw ng pagsubaybay',
      'within expected range': 'nasa inaasahang saklaw',
      'within normal limits': 'nasa normal na limitasyon',
      'monitoring': 'pagsubaybay',
      'monitor': 'subaybayan',
      'requires': 'kailangan',
      
      // Lab test results status meanings
      'Consistent with expected findings for this test.':
          'Naaayon sa inaasahang mga resulta para sa test na ito.',
      'Within expected range for this parameter.':
          'Nasa inaasahang antas para sa test na ito.',
      'Within expected range for this test.':
          'Nasa inaasahang antas para sa test na ito.',
      'Reported as normal for this parameter.':
          'Nasa inaasahang antas para sa test na ito.',
      'May benefit from continued monitoring and clinician follow-up.':
          'Maaaring maging kapaki-pakinabang ang patuloy na pagsubaybay at follow-up sa doktor.',
      'May need clinician review with symptoms and history.':
          'Maaaring kailanganin ng pagsusuri ng doktor kasama ang mga sintomas at kasaysayan.',
      'Near expected range threshold. Monitor trends in coordination with your healthcare provider.':
          'Malapit sa limitasyon ng inaasahang antas. Subaybayan ang mga takbo kasama ang iyong midwife o doktor.',
      'Near threshold. Monitor trends and correlate clinically.':
          'Malapit sa limitasyon ng inaasahang antas. Subaybayan ang mga takbo kasama ang iyong midwife o doktor.',
      'Observe and compare with expected values over time.':
          'Subaybayan at ihambing sa mga inaasahang antas sa paglipas ng panahon.',
      'Not clearly high-risk. Observe and compare with references.':
          'Subaybayan at ihambing sa mga inaasahang antas sa paglipas ng panahon.',
      'Positive finding that may warrant further observation.':
          'Positibong resulta na maaaring mangailangan ng karagdagang pagsubaybay.',
      'Positive finding that may be clinically significant.':
          'Positibong resulta na maaaring mangailangan ng karagdagang pagsubaybay.',
      'Positive finding is expected for this test context.':
          'Positibong resulta na inaasahan para sa test na ito.',
      'Positive finding can be expected for this test context.':
          'Positibong resulta na inaasahan para sa test na ito.',
      'No concerning marker detected for this parameter.':
          'Walang nakitang nakakabahalang marker para sa parameter na ito.',
      'Verify result in coordination with your healthcare provider.':
          'I-verify ang resulta kasama ang iyong midwife o doktor.',
      'Negative may be unexpected for this context; verify clinically.':
          'I-verify ang resulta kasama ang iyong midwife o doktor.',
      'Observe this result based on the specific test context.':
          'Subaybayan ang resultang ito batay sa konteksto ng test.',
      'Interpret this result based on the specific test context.':
          'Subaybayan ang resultang ito batay sa konteksto ng test.',
      'Observe this result together with expected ranges and overall assessment.':
          'Subaybayan ang resultang ito kasama ang mga inaasahang saklaw at pangkalahatang pagsusuri.',
      'Interpret this result together with reference ranges and overall assessment.':
          'Subaybayan ang resultang ito kasama ang mga inaasahang saklaw at pangkalahatang pagsusuri.',

      // Lab test status labels
      'EXPECTED': 'INAASAHAN',
      'MONITOR': 'SUBAYBAYAN',
      'REVIEW': 'SURIIN',
      'NORMAL': 'INAASAHAN',
      'ABNORMAL': 'SUBAYBAYAN',
      'POSITIVE': 'POSITIBO',
      'NEGATIVE': 'NEGATIBO',

      // Other common adjectives
      'Underweight BMI': 'Mababa ang BMI (Underweight)',
      'Overweight BMI': 'Mataas ang BMI (Overweight)',
      'Obese BMI': 'Sobrang Taas ng BMI (Obese)',
      'Multiple Pregnancy': 'Kambal o Higit Pa (Multiple Pregnancy)',
      'AOG Discrepancy (LMP vs AI)': 'May Pagkakaiba sa Edad ng Baby (AOG Discrepancy)',
      'Patient Name Mismatch': 'Hindi Tugma ang Pangalan sa Ultrasound',
      'No high-risk complications detected': 'Walang nakitang kumplikasyon o mataas na panganib',
    };

    translations.forEach((eng, fil) {
      final pattern = RegExp.escape(eng);
      final startBoundary = RegExp(r'^\w').hasMatch(eng) ? r'\b' : '';
      final endBoundary = RegExp(r'\w$').hasMatch(eng) ? r'\b' : '';
      final reg = RegExp('$startBoundary$pattern$endBoundary', caseSensitive: false);
      result = result.replaceAll(reg, fil);
    });

    return result;
  }

  String _friendlyAiSectionTitle(String raw) {
    final title = _friendlyAiSectionTitleRaw(raw);
    if (_showAiInFilipino) {
      switch (title) {
        case 'Overall Assessment':
          return 'Pangkalahatang Pagsusuri';
        case 'Overall Health Status':
          return 'Pangkalahatang Kalagayan ng Kalusugan';
        case 'Laboratory Results':
          return 'Mga Resulta ng Laboratoryo';
        case 'Abnormal Findings':
          return 'Mga Nakitang Di-karaniwang Resulta';
        case 'Reference Ranges':
          return 'Mga Reference Range';
        case 'Key Observations':
          return 'Mga Pangunahing Obserbasyon';
        case 'Recommendations':
          return 'Mga Rekomendasyon';
        case 'Recommended Next Actions':
          return 'Mga Inirerekomendang Aksyon';
        case 'Clinical Impression':
          return 'Klinikal na Impresyon';
        case 'Follow-up Suggestions':
          return 'Mga Mungkahi para sa Follow-up';
        case 'Measurements':
          return 'Mga Sukat';
        case 'Anatomical Assessment':
          return 'Pagsusuri sa Anatomya ng Sanggol';
        case 'Gestational Age':
          return 'Edad ng Pagbubuntis (AOG)';
      }
    }
    return title;
  }

  String _friendlyAiSectionTitleRaw(String raw) {
    final normalized = raw.trim().toUpperCase();
    switch (normalized) {
      case 'OVERALL ASSESSMENT':
        return 'Overall Assessment';
      case 'OVERALL HEALTH STATUS':
        return 'Overall Health Status';
      case 'LABORATORY RESULTS':
        return 'Laboratory Results';
      case 'ABNORMAL FINDINGS':
        return 'Abnormal Findings';
      case 'NORMAL RANGES':
        return 'Reference Ranges';
      case 'KEY OBSERVATIONS':
        return 'Key Observations';
      case 'RECOMMENDATIONS':
        return 'Recommendations';
      case 'RECOMMENDED NEXT ACTIONS':
        return 'Recommended Next Actions';
      case 'CLINICAL IMPRESSION':
        return 'Clinical Impression';
      case 'FOLLOW-UP SUGGESTIONS':
        return 'Follow-up Suggestions';
      case 'DETAILED MEASUREMENTS ASSESSMENT':
        return 'Measurements';
      case 'ANATOMICAL ASSESSMENT':
        return 'Anatomical Assessment';
      case 'GESTATIONAL AGE ASSESSMENT':
        return 'Gestational Age';
      default:
        return raw
            .toLowerCase()
            .split(' ')
            .map(
                (w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
            .join(' ');
    }
  }

  bool _shouldShowPrenatalRiskSummary() {
    final title = widget.title.toLowerCase();
    if (!title.contains('prenatal')) return false;
    return widget.riskLevel != null ||
        (widget.riskFactors != null && widget.riskFactors!.isNotEmpty) ||
        (widget.suggestedActions != null &&
            widget.suggestedActions!.isNotEmpty);
  }

  Color _riskLevelBadgeColor(String riskLevel) {
    final normalized = riskLevel.toLowerCase();
    if (normalized.contains('high')) return AppColors.error;
    if (normalized.contains('low')) return AppColors.success;
    return AppColors.brandPrimary;
  }

  String _checkupAssessmentLabel(String val) {
    final lower = val.toLowerCase().trim();
    if (lower == 'low') {
      return _t('Within Expected Monitoring Range', 'Nasa Inaasahang Saklaw');
    } else if (lower == 'high') {
      return _t('Requires Closer Monitoring', 'Kailangan ng Masusing Pagsubaybay');
    }
    return val.toUpperCase();
  }

  String _friendlyStatusLabel(String status, bool isUltrasound, bool isLab) {
    final s = status.toUpperCase().trim();
    if (isUltrasound || isLab) {
      if (s == 'NORMAL' || s == 'WITHIN NORMAL LIMITS' || s == 'EXPECTED') {
        return _tAi('Within Expected Range', 'Nasa Inaasahang Saklaw');
      }
      if (s.contains('ABNORMAL') ||
          s.contains('REVIEW') ||
          s.contains('CONCERNING') ||
          s == 'MONITOR' ||
          s == 'BORDERLINE' ||
          s == 'OBSERVE') {
        return _tAi('Requires Monitoring', 'Kailangan ng Pagsubaybay');
      }
    }
    return status;
  }

  Widget _buildPrenatalRiskSummaryCard() {
    final riskLevel = widget.riskLevel ?? '';
    final riskFactors = widget.riskFactors ?? [];
    final suggestedActions = widget.suggestedActions ?? [];

    final isHighRisk = riskLevel.toLowerCase().contains('high');
    final cardBg = isHighRisk ? _riskHighCardBg : Colors.white;
    final cardBorder = isHighRisk ? _riskHighCardBorder.withValues(alpha: 0.3) : Colors.transparent;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: isHighRisk ? Border.all(color: cardBorder) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFF0F5), Color(0xFFFFE4EE)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.psychology_alt_outlined,
                    size: 16, color: AppColors.brandText),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _t('Prenatal Risk Summary', 'Buod ng Prenatal Risk'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Risk Level Section
          if (riskLevel.isNotEmpty) ...[
            _buildRiskSubSection(
              title: _t('Checkup Assessment', 'Pagsusuri ng Checkup'),
              icon: Icons.flag_outlined,
              child: Row(
                children: [
                  _buildRiskChip(
                    label: _checkupAssessmentLabel(riskLevel),
                    color: _riskLevelBadgeColor(riskLevel),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Risk Factors Section
          if (riskFactors.isNotEmpty) ...[
            _buildRiskSubSection(
              title: _t('Risk Factors', 'Mga Salik ng Panganib'),
              icon: Icons.warning_amber_rounded,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: riskFactors.map((factor) {
                  // Resolve "Condition" showing by stripping generic prefixes.
                  String factorName = factor;
                  if (factor.contains(':')) {
                    final parts = factor.split(':');
                    final prefix = parts[0].trim().toLowerCase();
                    if (prefix == 'condition' || prefix == 'severe symptom') {
                      factorName = parts.sublist(1).join(':').trim();
                    } else {
                      factorName = parts[0].trim();
                    }
                  }

                  final isHigh = factor.toLowerCase().contains('high');
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isHigh
                          ? AppColors.error.withValues(alpha: 0.1)
                          : AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isHigh
                            ? AppColors.error.withValues(alpha: 0.3)
                            : AppColors.warning.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      factorName,
                      style: TextStyle(
                        fontSize: 12,
                        color: isHigh ? AppColors.error : AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Suggested Actions Section
          if (suggestedActions.isNotEmpty) ...[
            _buildRiskSubSection(
              title: _t('Suggested Actions', 'Mga Iminumungkahing Aksyon'),
              icon: Icons.lightbulb_outline,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: suggestedActions.asMap().entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color:
                                AppColors.brandPrimary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${entry.key + 1}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.brandPrimary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            entry.value,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textPrimary,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRiskSubSection({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _buildRiskChip({
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _buildClinicalDisclaimerAndReferences() {
    final isPrenatal = widget.title.toLowerCase().contains('prenatal');
    final isUltrasound = widget.title.toLowerCase().contains('ultrasound');

    final title = _tAi(
      'Clinical Reference Basis',
      'Batayan ng Sanggunian (Clinical Reference Basis)',
    );

    final List<String> citations = [];
    if (isPrenatal) {
      citations.addAll([
        _tAi(
          'Department of Health (DOH) Administrative Order No. 2016-0035: Guidelines on the Provision of Quality Antenatal Care.',
          'Kagawaran ng Kalusugan (DOH) Administrative Order No. 2016-0035: Mga Gabay sa Pagbibigay ng Dekalidad na Antenatal Care.',
        ),
        _tAi(
          'World Health Organization (WHO) Recommendations on Antenatal Care for a Positive Pregnancy Experience (2016).',
          'Mga Rekomendasyon ng World Health Organization (WHO) ukol sa Antenatal Care para sa Positibong Karanasan sa Pagbubuntis (2016).',
        ),
      ]);
    } else if (isUltrasound) {
      citations.addAll([
        _tAi(
          'INTERGROWTH-21st Project Fetal Growth Standards (2014): Gestational age estimation and fetal measurement reference charts.',
          'INTERGROWTH-21st Project Fetal Growth Standards (2014): Pagtatantya ng edad ng pagbubuntis at mga tsart ng sanggunian para sa sukat ng sanggol.',
        ),
        _tAi(
          'World Health Organization (WHO) Fetal Growth Charts (2017): Reference standards for estimated fetal weight percentiles.',
          'World Health Organization (WHO) Fetal Growth Charts (2017): Mga pamantayang sanggunian para sa percentiles ng tinatayang timbang ng sanggol.',
        ),
      ]);
    } else {
      citations.addAll([
        _tAi(
          'World Health Organization (WHO) Haemoglobin Concentrations for the Diagnosis of Anaemia and Assessment of Severity (2011).',
          'World Health Organization (WHO) Haemoglobin Concentrations para sa Pagsusuri ng Anemia at Pagtukoy ng Kalubhaan nito (2011).',
        ),
        _tAi(
          'Pregnancy Laboratory Reference Interval Guidelines (Abbassi-Ghanavati, M., et al., 2009): Standard reference ranges for physiological changes in pregnancy.',
          'Pregnancy Laboratory Reference Interval Guidelines (Abbassi-Ghanavati, M., et al., 2009): Karaniwang saklaw ng sanggunian para sa mga pisikal na pagbabago sa pagbubuntis.',
        ),
      ]);
    }

    return Container(
      margin: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderPrimary),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: const Icon(Icons.menu_book_outlined, color: AppColors.brandPrimary, size: 20),
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            const Divider(height: 1, color: AppColors.borderPrimary),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.bgSecondary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 16, color: AppColors.brandPrimary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _tAi(
                        'Clinical Reference Disclaimer: The references listed below represent standard guidelines used to establish normal ranges and monitoring thresholds. They do not constitute diagnostic opinions or active medical prescriptions.',
                        'Paunawa sa Sanggunian (Clinical Reference Disclaimer): Ang mga sangguniang nakalista sa ibaba ay mga karaniwang gabay na ginagamit para sa mga normal na saklaw at antas ng pagsubaybay. Hindi ito katumbas ng medikal na diagnosis o reseta ng doktor.',
                      ),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ...citations.map((citation) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.arrow_right, size: 18, color: AppColors.brandPrimary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          citation,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textPrimary,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
