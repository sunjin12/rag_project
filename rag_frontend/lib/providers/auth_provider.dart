/// 인증 상태 관리 Provider
///
/// Google OAuth 로그인, 자동 로그인, 로그아웃 상태를 관리합니다.
/// [AuthService]를 통해 실제 인증 로직을 수행하고,
/// 결과를 UI에 반영합니다.
library;

import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService authService;
  User? _user;
  bool _isLoading = false;
  String? _errorMessage;

  AuthProvider(this.authService);

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _user != null;
  String? get errorMessage => _errorMessage;

  /// 앱 시작 시 호출 — 저장된 토큰으로 자동 로그인 시도
  Future<void> initialize() async {
    await authService.initialize();
    final success = await authService.autoLogin();
    if (success) {
      // SharedPreferences에 저장된 사용자 정보 복원
      _user = authService.getStoredUser();
    }
    notifyListeners();
  }

  /// Google OAuth 로그인 수행
  ///
  /// 로그인 성공 시 [AuthService]에서 반환한 실제 사용자 데이터를 사용합니다.
  /// (기존 하드코딩된 더미 데이터 버그 수정)
  Future<bool> loginWithGoogle() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final success = await authService.loginWithGoogle();
      if (success) {
        // AuthService가 저장한 실제 사용자 정보를 가져옴
        _user = authService.getStoredUser();
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = 'Google sign-in failed. Please try again.';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// 로그아웃 — 저장된 토큰과 사용자 정보 삭제
  Future<void> logout() async {
    _user = null;
    await authService.logout();
    notifyListeners();
  }

  /// 에러 메시지 초기화
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
