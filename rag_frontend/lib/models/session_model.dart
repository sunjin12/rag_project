/// 대화 세션 모델
///
/// 페르소나별 대화 스레드를 나타냅니다.
/// 하나의 페르소나에 여러 세션이 존재할 수 있습니다.
import 'package:intl/intl.dart';

class ChatSession {
  final String id;
  final String title;
  final DateTime createdAt;
  final int messageCount;

  ChatSession({
    required this.id,
    required this.title,
    required this.createdAt,
    this.messageCount = 0,
  });

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    return ChatSession(
      id: json['id'] ?? '',
      title: json['title'] ?? 'New Chat',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      messageCount: json['message_count'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'created_at': createdAt.toIso8601String(),
      'message_count': messageCount,
    };
  }

  String get formattedDate => DateFormat('MM/dd HH:mm').format(createdAt);
}
