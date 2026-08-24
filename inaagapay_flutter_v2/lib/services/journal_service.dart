// lib/services/journal_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/journal_model.dart';
import 'auth_storage.dart';

class JournalService {
  static SupabaseClient get client => Supabase.instance.client;

  // Get current mother ID from storage
  static Future<int?> _getMotherId() async {
    return await AuthStorage.getMotherId();
  }

  // Fetch all journal entries for the current mother
  static Future<List<JournalEntry>> fetchJournals() async {
    final motherId = await _getMotherId();
    if (motherId == null) {
      throw Exception('Mother ID not found. Please log in again.');
    }

    try {
      final response = await client
          .from('journal_entries')
          .select('*')
          .eq('mother_id', motherId)
          .order('created_at', ascending: false);

      final List<dynamic> data = response;
      return data.map((json) => JournalEntry.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Failed to load journals: $e');
    }
  }

  // Create a new journal entry
  static Future<bool> createJournal(CreateJournalEntry entry) async {
    final motherId = await _getMotherId();
    if (motherId == null) {
      throw Exception('Mother ID not found. Please log in again.');
    }

    try {
      await client.from('journal_entries').insert({
        'mother_id': motherId,
        'title': entry.title.isEmpty ? null : entry.title,
        'content': entry.content,
        // `mood` and `entry_date` have been in this table since the first
        // schema and were never written to. The mood is the part a mother who
        // does not write can still leave.
        'mood': entry.mood?.name,
        'entry_date': DateTime.now().toIso8601String().split('T').first,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      return true;
    } catch (e) {
      throw Exception('Failed to create journal entry: $e');
    }
  }

  // Update an existing journal entry
  static Future<bool> updateJournal(int entryId, UpdateJournalEntry entry) async {
    final motherId = await _getMotherId();
    if (motherId == null) {
      throw Exception('Mother ID not found. Please log in again.');
    }

    try {
      // First verify the entry belongs to this mother
      final existing = await client
          .from('journal_entries')
          .select('entry_id')
          .eq('entry_id', entryId)
          .eq('mother_id', motherId)
          .maybeSingle();

      if (existing == null) {
        throw Exception('Journal entry not found or access denied');
      }

      await client
          .from('journal_entries')
          .update({
            'title': entry.title.isEmpty ? null : entry.title,
            'content': entry.content,
            'mood': entry.mood?.name,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('entry_id', entryId);

      return true;
    } catch (e) {
      throw Exception('Failed to update journal entry: $e');
    }
  }

  // Delete a journal entry
  static Future<bool> deleteJournal(int entryId) async {
    final motherId = await _getMotherId();
    if (motherId == null) {
      throw Exception('Mother ID not found. Please log in again.');
    }

    try {
      // First verify the entry belongs to this mother
      final existing = await client
          .from('journal_entries')
          .select('entry_id')
          .eq('entry_id', entryId)
          .eq('mother_id', motherId)
          .maybeSingle();

      if (existing == null) {
        throw Exception('Journal entry not found or access denied');
      }

      await client
          .from('journal_entries')
          .delete()
          .eq('entry_id', entryId);

      return true;
    } catch (e) {
      throw Exception('Failed to delete journal entry: $e');
    }
  }

  // Get a single journal entry by ID
  static Future<JournalEntry> getJournal(int entryId) async {
    final motherId = await _getMotherId();
    if (motherId == null) {
      throw Exception('Mother ID not found. Please log in again.');
    }

    try {
      final response = await client
          .from('journal_entries')
          .select('*')
          .eq('entry_id', entryId)
          .eq('mother_id', motherId)
          .maybeSingle();

      if (response == null) {
        throw Exception('Journal entry not found');
      }

      return JournalEntry.fromJson(response);
    } catch (e) {
      throw Exception('Failed to load journal entry: $e');
    }
  }
}