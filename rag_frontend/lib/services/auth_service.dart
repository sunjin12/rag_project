/// 인증 서비스
///
/// Google OAuth 2.0 인증 흐름(Authorization Code 방식)을 처리합니다.
/// 로컬 HTTP 서버로 OAuth 콜백을 수신하고, 백엔드에 code를 전달하여
/// JWT 토큰과 사용자 정보를 받아옵니다.
///
/// 토큰과 사용자 정보는 SharedPreferences에 저장하여 자동 로그인에 사용합니다.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/user_model.dart';
import '../config/app_config.dart';
import 'api_service.dart';

class AuthService {
  final ApiService apiService;
  late SharedPreferences _prefs;

  // SharedPreferences 저장 키
  static const String _tokenKey = 'user_token';
  static const String _userKey = 'user_data';
  static const String _stateKey = 'oauth_state';

  AuthService(this.apiService);

  /// SharedPreferences 초기화 (앱 시작 시 호출)
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Google OAuth 로그인 수행
  ///
  /// 1. 브라우저에서 Google 로그인 페이지 열기
  /// 2. 로컬 서버(port 4242)에서 콜백 수신
  /// 3. Authorization Code를 백엔드에 전달
  /// 4. JWT 토큰 + 사용자 정보 저장
  Future<bool> loginWithGoogle() async {
    HttpServer? server;
    try {
      await initialize();

      // CSRF 방지용 랜덤 state 생성
      final state = _generateRandomString(32);
      await _prefs.setString(_stateKey, state);

      final authUrl = _buildGoogleAuthUrl(state);
      final uri = Uri.parse(authUrl);

      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not launch browser for Google login.');
      }

      // 로컬 HTTP 서버로 OAuth 콜백 수신 (2분 타임아웃)
      server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        AppConfig.redirectPort,
      );
      final request = await server
          .where((req) => req.uri.path == '/callback')
          .first
          .timeout(const Duration(minutes: 2));

      final queryParams = request.uri.queryParameters;
      final returnedState = queryParams['state'];
      final authorizationCode = queryParams['code'];
      final error = queryParams['error'];

      // 에러 응답 처리
      if (error != null) {
        request.response
          ..statusCode = 400
          ..headers.contentType = ContentType.html
          ..write(
              '<html><body><h3>Google 로그인 중 오류가 발생했습니다.</h3><p>$error</p></body></html>')
          ..close();
        throw Exception('Google OAuth error: $error');
      }

      // state 검증 (CSRF 방지)
      if (returnedState != state || authorizationCode == null) {
        request.response
          ..statusCode = 400
          ..headers.contentType = ContentType.html
          ..write(
              '<html><body><h3>잘못된 요청입니다.</h3><p>state 또는 authorization code를 확인하세요.</p></body></html>')
          ..close();
        throw Exception('Invalid OAuth callback state or missing code.');
      }

      // 성공 페이지 표시
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(
            '<html><body><h3>로그인 성공!</h3><p>앱으로 돌아가셔도 좋습니다.</p></body></html>')
        ..close();

      // 백엔드에 Authorization Code 전송 → JWT + 사용자 정보 수신
      final user = await apiService.loginWithGoogleAuthorizationCode(
        authorizationCode,
        AppConfig.redirectUri,
      );
      await _saveUser(user);
      apiService.setToken(user.token);
      await _prefs.remove(_stateKey);
      return true;
    } catch (e, st) {
      print('Google OAuth Error: $e');
      print(st);
      rethrow;
    } finally {
      await server?.close(force: true);
    }
  }

  /// Google OAuth 인증 URL 생성
  String _buildGoogleAuthUrl(String state) {
    const googleAuthUrl = 'https://accounts.google.com/o/oauth2/v2/auth';
    final params = {
      'client_id': AppConfig.googleClientId,
      'redirect_uri': AppConfig.redirectUri,
      'response_type': 'code',
      'scope': 'openid email profile',
      'state': state,
      'access_type': 'offline',
      'prompt': 'consent',
    };

    final queryString = params.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');

    return '$googleAuthUrl?$queryString';
  }

  /// 보안 랜덤 문자열 생성 (CSRF state용)
  String _generateRandomString(int length) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(
      length,
      (index) => chars[random.nextInt(chars.length)],
    ).join();
  }

  /// 자동 로그인 시도 — 저장된 토큰이 있으면 API 서비스에 설정
  Future<bool> autoLogin() async {
    try {
      final token = _prefs.getString(_tokenKey);
      if (token != null) {
        apiService.setToken(token);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// 로그아웃 — 저장된 토큰과 사용자 정보 삭제
  Future<void> logout() async {
    await _prefs.remove(_tokenKey);
    await _prefs.remove(_userKey);
    await _prefs.remove(_stateKey);
  }

  /// SharedPreferences에서 저장된 사용자 정보 복원
  User? getStoredUser() {
    try {
      final userJson = _prefs.getString(_userKey);
      final token = _prefs.getString(_tokenKey) ?? '';
      if (userJson != null) {
        final data = jsonDecode(userJson) as Map<String, dynamic>;
        data['token'] = token;
        return User.fromJson(data);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 사용자 정보를 SharedPreferences에 저장
  Future<void> _saveUser(User user) async {
    await _prefs.setString(_tokenKey, user.token);
    // 사용자 정보를 JSON으로 저장 (토큰 제외)
    await _prefs.setString(_userKey, jsonEncode({
      'id': user.id,
      'username': user.username,
      'email': user.email,
    }));
  }

  /// 로그인 여부 확인
  bool get isLoggedIn {
    return _prefs.containsKey(_tokenKey);
  }
}
