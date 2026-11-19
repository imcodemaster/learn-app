import 'json.dart';

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.role,
    required this.hasPassword,
    required this.googleLinked,
    this.email,
    this.phone,
    this.avatarUrl,
  });

  final int id;
  final String name;
  final String? email;
  final String? phone;
  final String role;
  final String? avatarUrl;
  final bool hasPassword;
  final bool googleLinked;

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: jInt(json['id']),
        name: jStr(json['name']),
        email: jStrOrNull(json['email']),
        phone: jStrOrNull(json['phone']),
        role: jStr(json['role'], 'student'),
        avatarUrl: jStrOrNull(json['avatar_url']),
        hasPassword: jBool(json['has_password']),
        googleLinked: jBool(json['google_linked']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'email': email,
        'phone': phone,
        'role': role,
        'avatar_url': avatarUrl,
        'has_password': hasPassword,
        'google_linked': googleLinked,
      };

  bool get needsName => name.trim().isEmpty;

  String get displayName {
    if (name.trim().isNotEmpty) return name.trim();
    return email ?? phone ?? 'Student';
  }

  String get firstName => displayName.split(' ').first;

  String get initials {
    final parts = displayName.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'S';
    String first(String s) => String.fromCharCode(s.runes.first).toUpperCase();
    return parts.length == 1 ? first(parts.first) : first(parts.first) + first(parts.last);
  }

  String get contactLine => [if (email != null) email!, if (phone != null) phone!].join(' · ');
}

class AuthResult {
  AuthResult({required this.token, required this.user, required this.isNew});

  final String token;
  final AppUser user;
  final bool isNew;

  factory AuthResult.fromJson(Map<String, dynamic> json) => AuthResult(
        token: jStr(json['token']),
        user: AppUser.fromJson(jMap(json['user'])),
        isNew: jBool(json['is_new']),
      );
}

class OtpSent {
  OtpSent({required this.phone, required this.expiresIn, required this.resendIn, this.debugCode});

  final String phone;
  final int expiresIn;
  final int resendIn;

  /// Only present when the server runs in test mode without an SMS provider.
  final String? debugCode;

  factory OtpSent.fromJson(Map<String, dynamic> json) => OtpSent(
        phone: jStr(json['phone']),
        expiresIn: jInt(json['expires_in'], 300),
        resendIn: jInt(json['resend_in'], 60),
        debugCode: jStrOrNull(json['debug_code']),
      );
}
