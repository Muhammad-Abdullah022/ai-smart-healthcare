/// One emergency contact saved in the user's profile.
class EmergencyContact {
  const EmergencyContact({required this.name, required this.phone, this.relation = ''});

  final String name;
  final String phone;
  final String relation;

  factory EmergencyContact.fromJson(Map<String, dynamic> json) => EmergencyContact(
        name: json['name'] as String,
        phone: json['phone'] as String,
        relation: json['relation'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'name': name, 'phone': phone, 'relation': relation};
}

/// The user's personal and basic medical details (GET /profile).
class Profile {
  const Profile({
    required this.fullName,
    required this.email,
    this.dateOfBirth,
    this.gender,
    this.phone,
    this.bloodGroup = 'Unknown',
    this.allergies = const [],
    this.conditions = const [],
    this.emergencyContacts = const [],
    this.language = 'en',
  });

  final String fullName;
  final String email;
  final String? dateOfBirth; // "YYYY-MM-DD"
  final String? gender;
  final String? phone;
  final String bloodGroup;
  final List<String> allergies;
  final List<String> conditions;
  final List<EmergencyContact> emergencyContacts;
  final String language;

  static const bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'Unknown'];

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        fullName: json['full_name'] as String,
        email: json['email'] as String,
        dateOfBirth: json['date_of_birth'] as String?,
        gender: json['gender'] as String?,
        phone: json['phone'] as String?,
        bloodGroup: json['blood_group'] as String? ?? 'Unknown',
        allergies: (json['allergies'] as List<dynamic>? ?? const []).cast<String>(),
        conditions: (json['conditions'] as List<dynamic>? ?? const []).cast<String>(),
        emergencyContacts: (json['emergency_contacts'] as List<dynamic>? ?? const [])
            .map((e) => EmergencyContact.fromJson(e as Map<String, dynamic>))
            .toList(),
        language: json['language'] as String? ?? 'en',
      );
}
