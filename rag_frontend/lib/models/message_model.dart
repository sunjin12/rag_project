/// 채팅 메시지 모델
///
/// 사용자 질문과 AI 응답을 동일한 구조로 표현합니다.
/// [isUser]가 true이면 사용자 메시지, false이면 AI 응답입니다.
/// [retrievedDocuments]는 RAG 검색 결과 문서 목록입니다 (추후 활용).
import 'package:intl/intl.dart';

class Message {
  final String id;
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final List<String>? retrievedDocuments;

  Message({
    required this.id,
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.retrievedDocuments,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] ?? '',
      content: json['content'] ?? '',
      isUser: json['is_user'] ?? false,
      timestamp: json['timestamp'] != null ? DateTime.parse(json['timestamp']) : DateTime.now(),
      retrievedDocuments: json['retrieved_documents'] != null
          ? List<String>.from(json['retrieved_documents'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'is_user': isUser,
      'timestamp': timestamp.toIso8601String(),
      'retrieved_documents': retrievedDocuments,
    };
  }

  String get formattedTime => DateFormat('HH:mm').format(timestamp);
}
