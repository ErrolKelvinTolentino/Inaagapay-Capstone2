import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

/// Bundled Unicode fonts keep ranges (20–24), Filipino names and symbols
/// readable in offline exports. No font download is needed at export time.
class PdfFonts {
  const PdfFonts._();
  static Future<pw.ThemeData>? _theme;
  static Future<pw.ThemeData> theme() =>
      _theme ??= _load().catchError((Object error, StackTrace stack) {
        _theme = null;
        Error.throwWithStackTrace(error, stack);
      });

  static Future<pw.ThemeData> _load() async {
    final regular = await rootBundle.load('assets/fonts/roboto-regular.ttf');
    final bold = await rootBundle.load('assets/fonts/roboto-bold.ttf');
    final italic = await rootBundle.load('assets/fonts/roboto-italic.ttf');
    final boldItalic =
        await rootBundle.load('assets/fonts/roboto-bolditalic.ttf');
    return pw.ThemeData.withFont(
        base: pw.Font.ttf(regular),
        bold: pw.Font.ttf(bold),
        italic: pw.Font.ttf(italic),
        boldItalic: pw.Font.ttf(boldItalic));
  }
}
