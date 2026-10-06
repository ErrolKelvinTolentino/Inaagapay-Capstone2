/// Text shared by hosted and device speech engines. Display text is untouched.
class SpeechText {
  const SpeechText._();

  static String clean(String text) {
    final plain = text
        .replaceAll(RegExp(r'\[(?:CALL_HOTLINE|SUGGEST|NAVIGATE):[^\]]*\]'), '')
        .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m[1]!)
        .replaceAll(RegExp(r'https?://\S+'), '')
        .replaceAll(RegExp(r'[*_`#]'), '')
        .replaceAll(RegExp(r'^\s*[-•]\s+', multiLine: true), '')
        .replaceAll(RegExp(r'\n+'), ' ');
    // Remove emoji bases, modifiers, keycaps and joiners, preserving accents,
    // numbers and punctuation used in clinical explanations.
    final runes = plain.runes.where((r) =>
        !(r >= 0x1F000 && r <= 0x1FAFF) &&
        !(r >= 0x2600 && r <= 0x27BF) &&
        !(r >= 0xFE00 && r <= 0xFE0F) &&
        !(r >= 0xE0020 && r <= 0xE007F) &&
        r != 0x200D &&
        r != 0x20E3);
    return String.fromCharCodes(runes).replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
