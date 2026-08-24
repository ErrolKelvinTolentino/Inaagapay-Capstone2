// lib/models/journal_model.dart

import 'journal_mood.dart';

class JournalEntry {
  final int entryId;
  final int motherId;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// How she felt that day, when she chose one.
  final JournalMood? mood;

  JournalEntry({
    required this.entryId,
    required this.motherId,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.mood,
  });

  factory JournalEntry.fromJson(Map<String, dynamic> json) {
    return JournalEntry(
      entryId: json['entry_id'] as int,
      motherId: json['mother_id'] as int,
      title: json['title']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      mood: JournalMood.fromStored(json['mood']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'entry_id': entryId,
      'mother_id': motherId,
      'title': title,
      'content': content,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'mood': mood?.name,
    };
  }
}

class CreateJournalEntry {
  final String title;
  final String content;
  final JournalMood? mood;

  CreateJournalEntry({
    required this.title,
    required this.content,
    this.mood,
  });

  Map<String, dynamic> toJson() {
    return {
      'title': title.isEmpty ? null : title,
      'content': content,
      'mood': mood?.name,
    };
  }
}

class UpdateJournalEntry {
  final String title;
  final String content;
  final JournalMood? mood;

  UpdateJournalEntry({
    required this.title,
    required this.content,
    this.mood,
  });

  Map<String, dynamic> toJson() {
    return {
      'title': title.isEmpty ? null : title,
      'content': content,
      'mood': mood?.name,
    };
  }
}