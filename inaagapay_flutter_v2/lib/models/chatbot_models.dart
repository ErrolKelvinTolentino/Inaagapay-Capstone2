// lib/models/chatbot_models.dart

class ChatSession {
  final int sessionId;
  final int motherId;
  final String title;
  final DateTime createdAt;

  ChatSession({
    required this.sessionId,
    required this.motherId,
    required this.title,
    required this.createdAt,
  });

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    return ChatSession(
      sessionId: _toInt(json['session_id']),
      motherId: _toInt(json['mother_id']),
      title: json['title'] ?? 'Kausap si Ate Assistant',
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'session_id': sessionId,
      'mother_id': motherId,
      'title': title,
      'created_at': createdAt.toIso8601String(),
    };
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    if (value is double) return value.toInt();
    return 0;
  }
}

class ChatMessage {
  final int? messageId;
  final int sessionId;
  final String content;
  final bool isUser;
  final DateTime createdAt;

  ChatMessage({
    this.messageId,
    required this.sessionId,
    required this.content,
    required this.isUser,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      messageId: json['message_id'] != null ? _toInt(json['message_id']) : null,
      sessionId: _toInt(json['session_id']),
      content: json['content'] as String? ?? '',
      isUser: json['is_user'] as bool? ?? false,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (messageId != null) 'message_id': messageId,
      'session_id': sessionId,
      'content': content,
      'is_user': isUser,
      'created_at': createdAt.toIso8601String(),
    };
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    if (value is double) return value.toInt();
    return 0;
  }
}
