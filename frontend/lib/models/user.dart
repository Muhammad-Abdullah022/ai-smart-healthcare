/// The logged-in user, as returned by GET /auth/me.
class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.roles,
    required this.emailVerified,
  });

  final String id;
  final String email;
  final String fullName;
  final List<String> roles;
  final bool emailVerified;

  String get firstName => fullName.trim().split(' ').first;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: json['full_name'] as String,
      roles: (json['roles'] as List<dynamic>? ?? const []).cast<String>(),
      emailVerified: json['email_verified'] as bool? ?? false,
    );
  }
}
