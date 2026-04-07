/// AI 페르소나 모델
///
/// 사용자가 생성한 AI 캐릭터의 정보를 담습니다.
/// 각 페르소나는 독립적인 RAG 컨텍스트(업로드 파일, 대화 기록)를 가집니다.
import 'package:intl/intl.dart';

class Persona {
  final String id;
  final String name;
  final String description;
  final List<String> uploadedFileIds;
  final DateTime createdAt;
  final int messageCount;

  Persona({
    required this.id,
    required this.name,
    required this.description,
    required this.uploadedFileIds,
    required this.createdAt,
    this.messageCount = 0,
  });

  factory Persona.fromJson(Map<String, dynamic> json) {
    return Persona(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unnamed Persona',
      description: json['description'] ?? '',
      uploadedFileIds: List<String>.from(json['uploaded_file_ids'] ?? []),
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : DateTime.now(),
      messageCount: json['message_count'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'uploaded_file_ids': uploadedFileIds,
      'created_at': createdAt.toIso8601String(),
      'message_count': messageCount,
    };
  }

  String get formattedDate => DateFormat('MM/dd/yyyy').format(createdAt);
}
