// lib/services/chatbot_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import '../models/chatbot_models.dart';
import 'auth_storage.dart';

class ChatbotService {
  static SupabaseClient get client => Supabase.instance.client;

  // Track if we need to fall back to local in-memory storage.
  static bool _useLocalFallback = false;

  // In-memory caches for fallback mode.
  static final List<ChatSession> _localSessions = [];
  static final Map<int, List<ChatMessage>> _localMessages = {};
  static int _nextLocalSessionId = -1;

  // Check if mother ID is available
  static Future<int?> _getMotherId() async {
    return await AuthStorage.getMotherId();
  }

  // Method to check table existence/accessibility
  static Future<void> _checkTableAccessibility() async {
    if (_useLocalFallback) return;
    try {
      final motherId = await _getMotherId();
      if (motherId == null) return;
      // Perform a minimal select query to verify table is present and reachable.
      await client.from('chatbot_sessions').select('session_id').limit(1);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ChatbotService] Supabase tables not found or unreachable. Falling back to local state. Error: $e');
      }
      _useLocalFallback = true;
    }
  }

  // Fetch all chat sessions for current mother
  static Future<List<ChatSession>> fetchSessions() async {
    final motherId = await _getMotherId();
    if (motherId == null) {
      throw Exception('Mother ID not found. Please log in again.');
    }

    await _checkTableAccessibility();

    if (_useLocalFallback) {
      return _localSessions.where((s) => s.motherId == motherId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }

    try {
      final response = await client
          .from('chatbot_sessions')
          .select('*')
          .eq('mother_id', motherId)
          .order('created_at', ascending: false);

      final List<dynamic> data = response;
      return data.map((json) => ChatSession.fromJson(json)).toList();
    } catch (e) {
      if (e.toString().contains('42P01') || e.toString().contains('relation') || e.toString().contains('does not exist')) {
        _useLocalFallback = true;
        return _localSessions.where((s) => s.motherId == motherId).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }
      throw Exception('Failed to load chat sessions: $e');
    }
  }

  // Create a new chat session
  static Future<ChatSession> createSession(String title) async {
    final motherId = await _getMotherId();
    if (motherId == null) {
      throw Exception('Mother ID not found. Please log in again.');
    }

    await _checkTableAccessibility();

    final now = DateTime.now();

    if (_useLocalFallback) {
      final newSession = ChatSession(
        sessionId: _nextLocalSessionId--,
        motherId: motherId,
        title: title,
        createdAt: now,
      );
      _localSessions.add(newSession);
      _localMessages[newSession.sessionId] = [];
      return newSession;
    }

    try {
      final response = await client.from('chatbot_sessions').insert({
        'mother_id': motherId,
        'title': title,
        'created_at': now.toIso8601String(),
      }).select().single();

      return ChatSession.fromJson(response);
    } catch (e) {
      if (e.toString().contains('42P01') || e.toString().contains('relation') || e.toString().contains('does not exist')) {
        _useLocalFallback = true;
        return createSession(title);
      }
      throw Exception('Failed to create chat session: $e');
    }
  }

  // Fetch all messages for a session
  static Future<List<ChatMessage>> fetchMessages(int sessionId) async {
    await _checkTableAccessibility();

    if (_useLocalFallback || sessionId < 0) {
      return _localMessages[sessionId] ?? [];
    }

    try {
      final response = await client
          .from('chatbot_messages')
          .select('*')
          .eq('session_id', sessionId)
          .order('created_at', ascending: true);

      final List<dynamic> data = response;
      return data.map((json) => ChatMessage.fromJson(json)).toList();
    } catch (e) {
      if (e.toString().contains('42P01') || e.toString().contains('relation') || e.toString().contains('does not exist')) {
        _useLocalFallback = true;
        return _localMessages[sessionId] ?? [];
      }
      throw Exception('Failed to load chat messages: $e');
    }
  }

  // Save a new message
  static Future<ChatMessage> saveMessage({
    required int sessionId,
    required String content,
    required bool isUser,
  }) async {
    await _checkTableAccessibility();

    final now = DateTime.now();

    if (_useLocalFallback || sessionId < 0) {
      final newMessage = ChatMessage(
        messageId: null,
        sessionId: sessionId,
        content: content,
        isUser: isUser,
        createdAt: now,
      );
      if (!_localMessages.containsKey(sessionId)) {
        _localMessages[sessionId] = [];
      }
      _localMessages[sessionId]!.add(newMessage);
      return newMessage;
    }

    try {
      final response = await client.from('chatbot_messages').insert({
        'session_id': sessionId,
        'content': content,
        'is_user': isUser,
        'created_at': now.toIso8601String(),
      }).select().single();

      return ChatMessage.fromJson(response);
    } catch (e) {
      if (e.toString().contains('42P01') || e.toString().contains('relation') || e.toString().contains('does not exist')) {
        _useLocalFallback = true;
        return saveMessage(
          sessionId: sessionId,
          content: content,
          isUser: isUser,
        );
      }
      throw Exception('Failed to save chat message: $e');
    }
  }

  // Delete/Clear all conversations for the current mother
  static Future<void> clearAllConversations() async {
    final motherId = await _getMotherId();
    if (motherId == null) return;

    await _checkTableAccessibility();

    if (_useLocalFallback) {
      _localSessions.removeWhere((s) => s.motherId == motherId);
      final keysToRemove = <int>[];
      for (final key in _localMessages.keys) {
        if (key < 0) {
          keysToRemove.add(key);
        }
      }
      for (final key in keysToRemove) {
        _localMessages.remove(key);
      }
      return;
    }

    try {
      await client
          .from('chatbot_sessions')
          .delete()
          .eq('mother_id', motherId);
    } catch (e) {
      if (e.toString().contains('42P01') || e.toString().contains('relation') || e.toString().contains('does not exist')) {
        _useLocalFallback = true;
        clearAllConversations();
        return;
      }
      throw Exception('Failed to clear conversations: $e');
    }
  }
}
