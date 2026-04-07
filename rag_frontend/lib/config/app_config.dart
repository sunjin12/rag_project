/// 앱 환경 설정 모듈
///
/// 환경(개발/스테이징/프로덕션)에 따라 API 서버 주소 등을 분리합니다.
/// [AppConfig.init]을 main()에서 호출하여 초기화하세요.
library;

import 'package:flutter_dotenv/flutter_dotenv.dart';

/// 실행 환경 종류
enum Environment {
  development,
  staging,
  production,
}

class AppConfig {
  static late Environment _environment;
  static late String _baseUrl;
  static late String _googleClientId;

  /// 환경 설정 초기화 (앱 시작 시 1회 호출)
  ///
  /// [environment]를 지정하지 않으면 개발 환경으로 설정됩니다.
  /// 환경별 기본값:
  ///   - development : http://localhost:8000
  ///   - staging     : https://staging-api.example.com
  ///   - production  : https://api.example.com
  static void init({
    Environment environment = Environment.development,
    String? baseUrl,
    String? googleClientId,
  }) {
    _environment = environment;

    // 환경별 기본 API 서버 주소
    _baseUrl = baseUrl ?? _defaultBaseUrl(environment);

    // Google OAuth Client ID (.env 파일에서 읽음)
    _googleClientId = googleClientId ??
        dotenv.env['GOOGLE_CLIENT_ID'] ?? '';
  }

  /// 환경별 기본 API 서버 주소
  static String _defaultBaseUrl(Environment env) {
    switch (env) {
      case Environment.development:
        return 'http://localhost:8000';
      case Environment.staging:
        return 'https://staging-api.example.com';
      case Environment.production:
        return 'https://api.example.com';
    }
  }

  // --- Getter ---
  static Environment get environment => _environment;
  static String get baseUrl => _baseUrl;
  static String get googleClientId => _googleClientId;
  static bool get isDevelopment => _environment == Environment.development;
  static bool get isProduction => _environment == Environment.production;

  /// OAuth 리디렉션 설정
  static const int redirectPort = 4242;
  static const String redirectUri = 'http://127.0.0.1:4242/callback';
}
