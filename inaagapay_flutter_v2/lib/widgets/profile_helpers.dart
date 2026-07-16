// lib/widgets/profile_helpers.dart
// Shared formatting & utility functions for the mother profile page.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';

// ── Date / value formatters ────────────────────────────────────────────────

String formatProfileDate(dynamic date) {
  if (date == null) return '-';
  try {
    final parsed = DateTime.tryParse(date.toString());
    if (parsed == null) return date.toString();
    return DateFormat('MMM d, yyyy').format(parsed);
  } catch (e) {
    return date.toString();
  }
}

String formatProfileDateTime(dynamic dateTime) {
  if (dateTime == null) return '-';
  try {
    final parsed = DateTime.tryParse(dateTime.toString());
    if (parsed == null) return dateTime.toString();
    return DateFormat('MMM d, yyyy h:mm a').format(parsed);
  } catch (e) {
    return dateTime.toString();
  }
}

double? toDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value.toString());
}

String formatValue(dynamic value) {
  if (value == null) return '-';
  final str = value.toString().trim();
  return str.isEmpty ? '-' : str;
}

String formatOutcome(String? outcome) {
  if (outcome == null) return '-';
  switch (outcome.toLowerCase()) {
    case 'live_birth':
      return 'Live Birth';
    case 'stillbirth':
      return 'Stillbirth';
    case 'miscarriage':
      return 'Miscarriage';
    case 'abortion':
      return 'Abortion';
    case 'ectopic':
      return 'Ectopic';
    default:
      return outcome;
  }
}

// ── BMI helpers ────────────────────────────────────────────────────────────

String getBMIStatus(double bmi) {
  if (bmi < 18.5) return 'Underweight';
  if (bmi < 25) return 'Normal';
  if (bmi < 30) return 'Overweight';
  return 'Obese';
}

/// For pregnant mothers: BMI should use pre-pregnancy weight when available.
/// Falls back to current weight if pre-pregnancy weight is unavailable.
double? computePregnancyBMI({
  double? prePregnancyWeight,
  double? currentWeight,
  double? heightCm,
}) {
  final weight = prePregnancyWeight ?? currentWeight;
  if (weight == null || heightCm == null || heightCm <= 0) return null;
  final heightM = heightCm / 100;
  return weight / (heightM * heightM);
}

/// Returns a human-readable label indicating which weight was used for BMI.
String bmiSourceLabel({
  double? prePregnancyWeight,
  double? currentWeight,
}) {
  if (prePregnancyWeight != null) return 'Pre-Pregnancy BMI';
  if (currentWeight != null) return 'Estimated BMI (current weight)';
  return 'BMI Unavailable';
}

Color getBMIStatusColor(String status) {
  switch (status) {
    case 'Underweight':
      return Colors.amber;
    case 'Normal':
      return AppColors.success;
    case 'Overweight':
      return Colors.orange;
    case 'Obese':
      return const Color(0xFFEF5350);
    default:
      return AppColors.textSecondary;
  }
}

// ── Sorting helpers ────────────────────────────────────────────────────────

DateTime? parseDateForSort(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}

List<Map<String, dynamic>> sortByDate(List list, String field, String order) {
  final sorted = List<Map<String, dynamic>>.from(list);
  sorted.sort((a, b) {
    final dateA = parseDateForSort(a[field]);
    final dateB = parseDateForSort(b[field]);
    if (dateA == null || dateB == null) return 0;
    return order == 'desc' ? dateB.compareTo(dateA) : dateA.compareTo(dateB);
  });
  return sorted;
}

// ── Markdown / AI text helpers ─────────────────────────────────────────────

String safeText(Object? value) => value?.toString() ?? '';

String stripDecorativeDashes(String value) {
  final trimmed = value.trim();
  if (RegExp(r'^[-_=]{2,}$').hasMatch(trimmed)) return '';
  return trimmed.replaceAll(RegExp(r'\s+--+\s+'), ' ').trim();
}

String normalizeMarkdownLine(String input) {
  var line = input;
  line = line.replaceFirst(RegExp(r'^\s*#{1,6}\s*'), '');
  line = line.replaceFirst(RegExp(r'^\s*(?:[-*]|-)\s+'), '');
  return line;
}

String cleanResidualMarkdown(String input) {
  var text = input;
  text = text.replaceAll('**', '');
  text = text.replaceAll('##', '');
  text = text.replaceAll(RegExp(r'(?<!\*)\*(?!\*)'), '');
  return text;
}

List<TextSpan> parseInlineMarkdown(String input) {
  final spans = <TextSpan>[];
  final pattern = RegExp(r'\*\*(.+?)\*\*');
  int current = 0;

  for (final match in pattern.allMatches(input)) {
    if (match.start > current) {
      spans.add(TextSpan(
          text: cleanResidualMarkdown(input.substring(current, match.start))));
    }
    spans.add(TextSpan(
      text: match.group(1) ?? '',
      style: const TextStyle(fontWeight: FontWeight.bold),
    ));
    current = match.end;
  }

  if (current < input.length) {
    spans.add(TextSpan(text: cleanResidualMarkdown(input.substring(current))));
  }

  if (spans.isEmpty) {
    spans.add(TextSpan(text: cleanResidualMarkdown(input)));
  }

  return spans;
}

Widget buildFormattedAiText(String text) {
  if (text.isEmpty) return const SizedBox.shrink();

  final lines = text.trimRight().split('\n');
  final List<Widget> children = [];
  final defaultStyle = const TextStyle(
    color: Colors.black87,
    fontSize: 15,
    height: 1.5,
  );

  int index = 0;
  while (index < lines.length) {
    if (_isMarkdownTableLine(lines[index])) {
      final tableLines = <String>[];
      while (index < lines.length && _isMarkdownTableLine(lines[index])) {
        tableLines.add(lines[index]);
        index += 1;
      }
      children.add(_buildMarkdownTable(tableLines));
      continue;
    }

    final normalizedLine = normalizeMarkdownLine(lines[index]);
    final spans = parseInlineMarkdown(normalizedLine);
    children.add(RichText(
      text: TextSpan(style: defaultStyle, children: spans),
    ));

    if (index < lines.length - 1) {
      children.add(const SizedBox(height: 8));
    }
    index += 1;
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: children,
  );
}

bool _isMarkdownTableLine(String line) {
  final trimmed = line.trim();
  if (!trimmed.contains('|')) return false;
  final segments = trimmed.split('|');
  return segments.length > 2 &&
      segments.any((segment) => segment.trim().isNotEmpty);
}

List<String> _splitTableRow(String line) {
  var raw = line.trim();
  if (raw.startsWith('|')) raw = raw.substring(1);
  if (raw.endsWith('|')) raw = raw.substring(0, raw.length - 1);
  return raw.split('|').map((cell) => cell.trim()).toList();
}

bool _isTableDividerRow(String line) {
  final cells = _splitTableRow(line);
  if (cells.isEmpty) return false;
  return cells.every((cell) => RegExp(r'^[:\-\s]+$').hasMatch(cell));
}

Widget _buildMarkdownTable(List<String> lines) {
  final rows = lines
      .where((line) => !_isTableDividerRow(line))
      .map(_splitTableRow)
      .toList();

  if (rows.isEmpty) {
    return const SizedBox.shrink();
  }

  return Container(
    margin: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.black12),
    ),
    child: Table(
      defaultColumnWidth: const FlexColumnWidth(),
      border: TableBorder.symmetric(
        inside: const BorderSide(color: Colors.black12, width: 1),
      ),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: const BoxDecoration(color: Color(0xFFF7F7F7)),
          children: rows.first
              .map((cell) => _buildTableCell(cell, isHeader: true))
              .toList(),
        ),
        ...rows.skip(1).map((row) => TableRow(
              children: row.map((cell) => _buildTableCell(cell)).toList(),
            )),
      ],
    ),
  );
}

Widget _buildTableCell(String content, {bool isHeader = false}) {
  final textStyle = TextStyle(
    fontSize: isHeader ? 14 : 13,
    fontWeight: isHeader ? FontWeight.w700 : FontWeight.w500,
    color: Colors.black87,
    height: 1.4,
  );

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
    child: Text.rich(
      TextSpan(
        style: textStyle,
        children: parseInlineMarkdown(content),
      ),
      softWrap: true,
      overflow: TextOverflow.visible,
    ),
  );
}

String normalizeAspectKey(String input) =>
    input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
