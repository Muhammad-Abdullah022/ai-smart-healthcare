import 'api_client.dart';

class Doctor {
  Doctor.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String,
        specialty = j['specialty'] as String,
        qualification = j['qualification'] as String? ?? '',
        city = j['city'] as String? ?? '',
        clinic = j['clinic'] as String? ?? '',
        address = j['address'] as String? ?? '',
        fee = (j['fee_pkr'] as num?)?.toDouble(),
        phone = j['phone'] as String? ?? '',
        timings = j['timings'] as String? ?? '',
        canEmail = j['can_email'] as bool? ?? false,
        sourceUrl = j['source_url'] as String? ?? '',
        checked = j['checked'] as String? ?? '',
        experienceYears = j['experience_years'] as int?,
        gender = j['gender'] as String? ?? '',
        about = j['about'] as String? ?? '',
        demo = j['demo'] as bool? ?? false,
        government = j['government'] as bool? ?? false,
        online = j['online'] as bool? ?? false;

  final String id;
  final String name;
  final String specialty;
  final String qualification;
  final String city;
  final String clinic;
  final String address;
  final double? fee;
  final String phone;
  final String timings;
  final bool canEmail;
  final String sourceUrl;
  final String checked;
  final int? experienceYears;
  final String gender;
  final String about;

  /// Made-up profile for the demo (shown with a "Demo profile" label).
  final bool demo;

  /// From the official Punjab government consultants list.
  final bool government;

  /// Joined the app's doctor panel: live chat, fee by screenshot, online prescription.
  final bool online;

  String get initials {
    final parts = name.replaceAll(RegExp(r'^(Dr\.?|Prof\.?)\s+', caseSensitive: false), '').split(' ');
    return parts.where((p) => p.isNotEmpty).take(2).map((p) => p[0].toUpperCase()).join();
  }
}

class BookingResult {
  BookingResult.fromJson(Map<String, dynamic> j)
      : status = j['status'] as String,
        message = j['message'] as String;

  final String status; // emailed / saved / email_not_configured / email_failed
  final String message;

  bool get emailed => status == 'emailed';
}

/// Doctor directory and appointment requests (features 10 and 11).
class DoctorRepository {
  DoctorRepository(this.api);

  final ApiClient api;

  Future<List<({String name, int doctors})>> specialties({String? city}) async {
    final q = city == null ? '' : '?city=${Uri.encodeQueryComponent(city)}';
    final data = await api.get('/doctors/specialties$q') as List<dynamic>;
    return [
      for (final s in data.cast<Map<String, dynamic>>()) (name: s['name'] as String, doctors: s['doctors'] as int? ?? 0)
    ];
  }

  /// Only doctors of the specialty the AI recommended (user's city first), ready to book.
  Future<RecommendedDoctors> recommended(String specialty, {String? city, int limit = 3}) async {
    final q = [
      'specialty=${Uri.encodeQueryComponent(specialty)}',
      if (city != null) 'city=${Uri.encodeQueryComponent(city)}',
      'limit=$limit',
    ].join('&');
    final data = await api.get('/doctors/recommended?$q') as Map<String, dynamic>;
    return RecommendedDoctors(
      specialty: data['specialty'] as String? ?? specialty,
      city: data['city'] as String?,
      backup: data['backup'] as bool? ?? false,
      totalInCity: data['total_in_city'] as int? ?? 0,
      doctors: [for (final d in data['doctors'] as List) Doctor.fromJson(d as Map<String, dynamic>)],
      otherCity: {
        for (final d in data['doctors'] as List)
          if ((d as Map)['other_city'] == true) '${d['id']}'
      },
    );
  }

  Future<List<Doctor>> doctors({String? city, String? specialty, String? search}) async {
    final q = [
      if (city != null) 'city=${Uri.encodeQueryComponent(city)}',
      if (specialty != null) 'specialty=${Uri.encodeQueryComponent(specialty)}',
      if (search != null && search.trim().isNotEmpty) 'q=${Uri.encodeQueryComponent(search.trim())}',
      'limit=300',
    ].join('&');
    final data = await api.get('/doctors${q.isEmpty ? '' : '?$q'}') as Map<String, dynamic>;
    return (data['doctors'] as List<dynamic>).map((d) => Doctor.fromJson(d as Map<String, dynamic>)).toList();
  }

  Future<BookingResult> book({
    required String doctorId,
    required DateTime date,
    required String timeOfDay,
    required String reason,
    String? phone,
    String source = 'doctor_list',
  }) async {
    final d = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final data = await api.post('/appointments/request', body: {
      'doctor_id': doctorId,
      'preferred_date': d,
      'time_of_day': timeOfDay,
      'reason': reason,
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      'source': source,
    });
    return BookingResult.fromJson(data as Map<String, dynamic>);
  }
}


class RecommendedDoctors {
  RecommendedDoctors({
    required this.specialty,
    required this.city,
    required this.backup,
    required this.totalInCity,
    required this.doctors,
    required this.otherCity,
  });

  final String specialty;
  final String? city;

  /// True when no doctor of the main specialty exists and the AI's backup (e.g. General Physician) is shown.
  final bool backup;
  final int totalInCity;
  final List<Doctor> doctors;

  /// Ids of doctors outside the user's city.
  final Set<String> otherCity;
}
