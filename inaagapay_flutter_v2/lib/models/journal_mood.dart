// lib/models/journal_mood.dart

import 'package:flutter/material.dart';

import '../services/language_service.dart';

/// How a mother felt on the day she wrote.
///
/// Stored in `journal_entries.mood`, a column that has existed since the first
/// schema and was never written to. It matters most for the mothers this app
/// is hardest for: writing a paragraph asks for literacy, time and privacy,
/// while tapping a face asks for none of those. A mother who never types a
/// word can still leave a record of how her pregnancy felt week to week — and
/// that record is something her midwife can actually read.
///
/// The stored value is the enum name, never the label, so switching the app to
/// Filipino does not write a different string into the database.
enum JournalMood {
  great(
    emoji: '😊',
    english: 'Great',
    filipino: 'Masaya',
    color: Color(0xFF68CBB8),
  ),
  okay(
    emoji: '🙂',
    english: 'Okay',
    filipino: 'Ayos lang',
    color: Color(0xFF7FB3E8),
  ),
  tired(
    emoji: '😴',
    english: 'Tired',
    filipino: 'Pagod',
    color: Color(0xFFB8A4D4),
  ),
  unwell(
    emoji: '🤢',
    english: 'Unwell',
    filipino: 'Masama ang pakiramdam',
    color: Color(0xFFFFB562),
  ),
  worried(
    emoji: '😟',
    english: 'Worried',
    filipino: 'Nag-aalala',
    color: Color(0xFFE89BA8),
  );

  const JournalMood({
    required this.emoji,
    required this.english,
    required this.filipino,
    required this.color,
  });

  final String emoji;
  final String english;
  final String filipino;
  final Color color;

  String get label => LanguageService.translate(english, filipino);

  /// Reads a stored value back, tolerating anything unexpected rather than
  /// throwing — an unreadable mood must never cost a mother her entry.
  static JournalMood? fromStored(Object? value) {
    final raw = value?.toString().trim().toLowerCase();
    if (raw == null || raw.isEmpty) return null;
    for (final mood in JournalMood.values) {
      if (mood.name == raw) return mood;
    }
    return null;
  }
}
