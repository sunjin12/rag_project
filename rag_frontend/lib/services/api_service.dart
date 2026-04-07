/// API 서비스
///
/// 백엔드 FastAPI와의 HTTP 통신을 담당합니다.
/// Dio 클라이언트를 사용하며, JWT 토큰을 자동으로 헤더에 포함합니다.
///
/// 주요 기능:
///   - 인증: Google OAuth 토큰/코드 전송
///   - 페르소나: CRUD
///   - 채팅: 메시지 전송 (일반 + SSE 스트리밍)
///   - 파일: 업로드
///   - 대화 기록: 조회
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../config/app_config.dart';
import '../models/user_model.dart';
import '../models/persona_model.dart';
import '../models/message_model.dart';
import '../models/session_model.dart';

class ApiService {
  late Dio _dio;
  String? _token;

  ApiService(Dio dio) {
    _dio = dio;
    _dio.options.baseUrl = AppConfig.baseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 30);

    // Bearer 토큰 자동 주입 인터셉터
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_token != null) {
            options.headers['Authorization'] = 'Bearer $_token';
          }
          return handler.next(options);
        },
        onError: (DioException e, handler) {
          return handler.next(e);
        },
      ),
    );
  }

  /// JWT 토큰 설정 (로그인 성공 후 호출)
  void setToken(String token) {
    _token = token;
  }

  // ============ 인증 API ============

  /// Google ID 토큰으로 로그인 (모바일용)
  Future<User> loginWithGoogleIdToken(String idToken) async {
    try {
      final response = await _dio.post(
        '/auth/google',
        data: {'id_token': idToken},
      );
      return User.fromJson(response.data);
    } on DioException catch (e) {
      throw Exception('Google Sign-In failed: ${e.message}');
    }
  }

  /// Google Authorization Code로 로그인 (데스크톱용)
  Future<User> loginWithGoogleAuthorizationCode(
      String code, String redirectUri) async {
    try {
      final response = await _dio.post(
        '/auth/code',
        data: {
          'code': code,
          'redirect_uri': redirectUri,
        },
      );
      return User.fromJson(response.data);
    } on DioException catch (e) {
      throw Exception(
          'Google authorization code exchange failed: ${e.message}');
    }
  }

  // ============ 페르소나 API ============

  /// 현재 사용자의 페르소나 목록 조회
  Future<List<Persona>> getPersonas() async {
    try {
      final response = await _dio.get('/personas');
      List<dynamic> data = response.data['personas'] ?? [];
      return data.map((p) => Persona.fromJson(p)).toList();
    } on DioException catch (e) {
      throw Exception('Failed to fetch personas: ${e.message}');
    }
  }

  /// 새 페르소나 생성
  Future<Persona> createPersona(String name, String description) async {
    try {
      final response = await _dio.post(
        '/personas',
        data: {'name': name, 'description': description},
      );
      return Persona.fromJson(response.data);
    } on DioException catch (e) {
      throw Exception('Failed to create persona: ${e.message}');
    }
  }

  /// 페르소나에 파일 업로드
  Future<String> uploadFile(
      String personaId, String filePath, String fileType) async {
    try {
      FormData formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath),
        'file_type': fileType,
      });

      final response = await _dio.post(
        '/personas/$personaId/upload',
        data: formData,
      );
      return response.data['file_id'] ?? '';
    } on DioException catch (e) {
      throw Exception('File upload failed: ${e.message}');
    }
  }

  /// 페르소나의 업로드된 파일 목록 조회
  Future<List<Map<String, dynamic>>> getFiles(String personaId) async {
    try {
      final response = await _dio.get('/personas/$personaId/files');
      final files = response.data['files'] as List;
      return files.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw Exception('Failed to get files: ${e.message}');
    }
  }

  /// 페르소나의 업로드된 파일 삭제
  Future<void> deleteFile(String personaId, String fileId) async {
    try {
      await _dio.delete('/personas/$personaId/files/$fileId');
    } on DioException catch (e) {
      throw Exception('Failed to delete file: ${e.message}');
    }
  }

  // ============ 채팅 API ============

  /// 메시지 전송 (일반 응답 — 전체 응답을 한 번에 받음)
  Future<Message> sendMessage(String personaId, String message,
      {String? sessionId}) async {
    try {
      final data = <String, dynamic>{'question': message};
      if (sessionId != null) data['session_id'] = sessionId;
      final response = await _dio.post(
        '/personas/$personaId/ask',
        data: data,
      );
      return Message.fromJson(response.data);
    } on DioException catch (e) {
      throw Exception('Failed to send message: ${e.message}');
    }
  }

  /// 메시지 전송 (SSE 스트리밍 — 토큰 단위로 실시간 수신)
  ///
  /// 서버에서 Server-Sent Events로 응답을 스트리밍합니다.
  /// "data: 토큰\n\n" 형식의 SSE 이벤트를 파싱하여 토큰만 yield합니다.
  /// [DONE] 수신 시 스트림을 종료합니다.
  Future<Stream<String>> streamMessage(String personaId, String message,
      {String? sessionId}) async {
    try {
      final queryParams = <String, dynamic>{'question': message};
      if (sessionId != null) queryParams['session_id'] = sessionId;
      final response = await _dio.get(
        '/personas/$personaId/ask/stream',
        queryParameters: queryParams,
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: const Duration(minutes: 5),
        ),
      );

      // SSE 파싱: "data: token\n\n" → "token"
      final ResponseBody body = response.data as ResponseBody;
      return body.stream
          .transform<String>(
            StreamTransformer<Uint8List, String>.fromHandlers(
              handleData: (Uint8List data, EventSink<String> sink) {
                sink.add(utf8.decode(data, allowMalformed: true));
              },
            ),
          )
          .transform<String>(
            StreamTransformer<String, String>.fromHandlers(
              handleData: (String chunk, EventSink<String> sink) {
                // SSE 이벤트 라인 파싱
                for (final line in chunk.split('\n')) {
                  final trimmed = line.trim();
                  if (trimmed.startsWith('data: ')) {
                    final payload = trimmed.substring(6);
                    if (payload == '[DONE]') return;
                    if (payload.startsWith('[ERROR]')) {
                      sink.addError(Exception(payload));
                      return;
                    }
                    sink.add(payload);
                  }
                }
              },
            ),
          );
    } on DioException catch (e) {
      throw Exception('Failed to stream message: ${e.message}');
    }
  }

  /// 대화 기록 조회
  Future<Map<String, dynamic>> getChatHistory(String personaId,
      {String? sessionId}) async {
    try {
      final queryParams = <String, dynamic>{};
      if (sessionId != null) queryParams['session_id'] = sessionId;
      final response = await _dio.get(
        '/personas/$personaId/history',
        queryParameters: queryParams,
      );
      List<dynamic> data = response.data['messages'] ?? [];
      return {
        'session_id': response.data['session_id'],
        'messages': data.map((m) => Message.fromJson(m)).toList(),
      };
    } on DioException catch (e) {
      throw Exception('Failed to fetch chat history: ${e.message}');
    }
  }

  // ============ 세션 API ============

  /// 페르소나의 대화 세션 목록 조회
  Future<List<ChatSession>> getSessions(String personaId) async {
    try {
      final response = await _dio.get('/personas/$personaId/sessions');
      List<dynamic> data = response.data['sessions'] ?? [];
      return data.map((s) => ChatSession.fromJson(s)).toList();
    } on DioException catch (e) {
      throw Exception('Failed to fetch sessions: ${e.message}');
    }
  }

  /// 새 대화 세션 생성
  Future<ChatSession> createSession(String personaId, {String? title}) async {
    try {
      final data = <String, dynamic>{};
      if (title != null) data['title'] = title;
      final response = await _dio.post(
        '/personas/$personaId/sessions',
        data: data,
      );
      return ChatSession.fromJson(response.data);
    } on DioException catch (e) {
      throw Exception('Failed to create session: ${e.message}');
    }
  }

  /// 대화 세션 삭제
  Future<void> deleteSession(String personaId, String sessionId) async {
    try {
      await _dio.delete('/personas/$personaId/sessions/$sessionId');
    } on DioException catch (e) {
      throw Exception('Failed to delete session: ${e.message}');
    }
  }

  /// 대화 세션 제목 수정
  Future<ChatSession> updateSession(
      String personaId, String sessionId, String title) async {
    try {
      final response = await _dio.put(
        '/personas/$personaId/sessions/$sessionId',
        data: {'title': title},
      );
      return ChatSession.fromJson(response.data);
    } on DioException catch (e) {
      throw Exception('Failed to update session: ${e.message}');
    }
  }
}
