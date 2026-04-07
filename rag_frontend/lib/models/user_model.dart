/// 사용자 모델
///
/// 백엔드 /auth 응답에서 받은 사용자 정보를 담습니다.
/// [token]은 JWT 액세스 토큰으로, API 호출 시 Bearer 헤더에 사용됩니다.
class User {
  final String id;
  final String username;
  final String email;
  final String token;

  User({
    required this.id,
    required this.username,
    required this.email,
    required this.token,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? '',
      username: json['username'] ?? '',
      email: json['email'] ?? '',
      token: json['token'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'token': token,
    };
  }
}
