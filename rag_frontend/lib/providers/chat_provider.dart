/// 채팅 상태 관리 Provider
///
/// 메시지 목록, 전송/수신 상태, 대화 기록 로드, 세션 관리를 담당합니다.
/// SSE 스트리밍을 기본으로 사용하며, 실패 시 일반 HTTP 응답으로 폴백합니다.
library;

import 'package:flutter/material.dart';
import '../models/message_model.dart';
import '../models/session_model.dart';
import '../services/api_service.dart';

class ChatProvider extends ChangeNotifier {
  final ApiService apiService;

  List<Message> _messages = [];
  List<ChatSession> _sessions = [];
  String? _currentSessionId;
  bool _isLoading = false;
  bool _isStreaming = false;
  String? _errorMessage;
  String? _statusMessage;

  ChatProvider(this.apiService);

  List<Message> get messages => _messages;
  List<ChatSession> get sessions => _sessions;
  String? get currentSessionId => _currentSessionId;
  bool get isLoading => _isLoading;
  bool get isStreaming => _isStreaming;
  String? get errorMessage => _errorMessage;
  String? get statusMessage => _statusMessage;

  /// 세션 목록 로드
  Future<void> loadSessions(String personaId) async {
    try {
      _sessions = await apiService.getSessions(personaId);
      notifyListeners();
    } catch (e) {
      _sessions = [];
      notifyListeners();
    }
  }

  /// 대화 기록 로드
  ///
  /// 페르소나의 기존 대화 내용을 서버에서 가져옵니다.
  /// 채팅 화면 진입 시 호출됩니다.
  Future<void> loadChatHistory(String personaId, {String? sessionId}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await apiService.getChatHistory(personaId,
          sessionId: sessionId);
      _messages = result['messages'] as List<Message>;
      _currentSessionId = result['session_id'] as String?;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _messages = [];
      _errorMessage = null;
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 세션 전환
  Future<void> switchSession(String personaId, String sessionId) async {
    _currentSessionId = sessionId;
    await loadChatHistory(personaId, sessionId: sessionId);
  }

  /// 새 세션 생성 및 전환
  Future<void> createNewSession(String personaId, {String? title}) async {
    try {
      final session = await apiService.createSession(personaId, title: title);
      _sessions.insert(0, session);
      _currentSessionId = session.id;
      _messages = [];
      notifyListeners();
    } catch (e) {
      _errorMessage = '세션 생성 실패: $e';
      notifyListeners();
    }
  }

  /// 세션 삭제
  Future<void> deleteSession(String personaId, String sessionId) async {
    try {
      await apiService.deleteSession(personaId, sessionId);
      _sessions.removeWhere((s) => s.id == sessionId);
      // 삭제한 세션이 현재 세션이면 최신 세션으로 전환
      if (_currentSessionId == sessionId) {
        if (_sessions.isNotEmpty) {
          await switchSession(personaId, _sessions.first.id);
        } else {
          _currentSessionId = null;
          _messages = [];
        }
      }
      notifyListeners();
    } catch (e) {
      _errorMessage = '세션 삭제 실패: $e';
      notifyListeners();
    }
  }

  /// 세션 제목 수정
  Future<void> renameSession(
      String personaId, String sessionId, String title) async {
    try {
      final updated =
          await apiService.updateSession(personaId, sessionId, title);
      final idx = _sessions.indexWhere((s) => s.id == sessionId);
      if (idx >= 0) {
        _sessions[idx] = updated;
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = '세션 이름 변경 실패: $e';
      notifyListeners();
    }
  }

  /// 메시지 전송 — SSE 스트리밍 우선, 실패 시 일반 요청 폴백
  ///
  /// 사용자 메시지를 즉시 UI에 추가(낙관적 업데이트)한 뒤,
  /// AI 응답을 토큰 단위로 실시간 수신하여 화면에 표시합니다.
  Future<void> sendMessage(String personaId, String content) async {
    // 사용자 메시지를 즉시 UI에 표시
    final userMessage = Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: content,
      isUser: true,
      timestamp: DateTime.now(),
    );
    _messages.add(userMessage);
    _isStreaming = true;
    _statusMessage = null;
    _errorMessage = null;
    notifyListeners();

    try {
      await _streamMessage(personaId, content);
    } catch (e) {
      // 스트리밍 실패 시 일반 요청으로 폴백
      try {
        final response = await apiService.sendMessage(personaId, content,
            sessionId: _currentSessionId);
        _messages.add(response);
      } catch (fallbackError) {
        _errorMessage = '메시지 전송 실패: $fallbackError';
      }
    }

    _isStreaming = false;
    _statusMessage = null;
    // 세션 목록의 메시지 수 갱신을 위해 리로드
    await loadSessions(personaId);
    notifyListeners();
  }

  /// SSE 스트리밍 수신 — 빈 AI 메시지를 먼저 추가하고 토큰을 누적
  Future<void> _streamMessage(String personaId, String content) async {
    // 빈 AI 메시지 플레이스홀더 추가
    final aiMessage = Message(
      id: 'stream-${DateTime.now().millisecondsSinceEpoch}',
      content: '',
      isUser: false,
      timestamp: DateTime.now(),
    );
    _messages.add(aiMessage);
    notifyListeners();

    final aiIndex = _messages.length - 1;
    final buffer = StringBuffer();

    final stream = await apiService.streamMessage(personaId, content,
        sessionId: _currentSessionId);
    await for (final token in stream) {
      // [STATUS] 이벤트 처리
      if (token.startsWith('[STATUS] ')) {
        _statusMessage = token.substring(9);
        notifyListeners();
        continue;
      }
      // 첫 실제 토큰 도착 시 상태 메시지 제거
      if (_statusMessage != null) {
        _statusMessage = null;
      }
      buffer.write(token);
      // 기존 메시지를 새 내용으로 교체 (immutable 패턴)
      _messages[aiIndex] = Message(
        id: aiMessage.id,
        content: buffer.toString(),
        isUser: false,
        timestamp: aiMessage.timestamp,
      );
      notifyListeners();
    }
  }

  /// 메시지 수동 추가 (외부에서 호출 시)
  void addMessage(Message message) {
    _messages.add(message);
    notifyListeners();
  }

  /// 대화 내용 초기화
  void clearMessages() {
    _messages.clear();
    notifyListeners();
  }

  /// 에러 메시지 초기화
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
