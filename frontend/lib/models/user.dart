/// The logged-in user, as returned by GET /auth/me.
class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.roles,
    required this.emailVerified,
    this.mustChangePassword = false,
  });

  final String id;
  final String email;
  final String fullName;
  final List<String> roles;
  final bool emailVerified;

  /// Doctor accounts made by the admin start with a temporary password.
  final bool mustChangePassword;

  bool get isAdmin => roles.contains('admin');
  bool get isDoctor => roles.contains('doctor');

  String get firstName => fullName.trim().split(' ').first;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: json['full_name'] as String,
      roles: (json['roles'] as List<dynamic>? ?? const []).cast<String>(),
      emailVerified: json['email_verified'] as bool? ?? false,
      mustChangePassword: json['must_change_password'] as bool? ?? false,
    );
  }
}
