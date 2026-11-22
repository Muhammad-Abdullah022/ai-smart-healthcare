import 'api_client.dart';

class Medicine {
  const Medicine({
    required this.id,
    required this.name,
    required this.salt,
    required this.strength,
    required this.form,
    required this.times,
    required this.instructions,
    this.allergyWarning,
    this.startDate,
    this.endDate,
  });

  final String id;
  final String name;
  final String salt;
  final String strength;
  final String form;
  final List<String> times;
  final String instructions;
  final String? allergyWarning;
  final DateTime? startDate;
  final DateTime? endDate;

  factory Medicine.fromJson(Map<String, dynamic> j) => Medicine(
        id: j['id'] as String,
        name: j['name'] as String,
        salt: j['salt'] as String? ?? '',
        strength: j['strength'] as String? ?? '',
        form: j['form'] as String,
        times: (j['times'] as List).cast<String>(),
        instructions: j['instructions'] as String? ?? '',
        allergyWarning: j['allergy_warning'] as String?,
        startDate: DateTime.tryParse('${j['start_date'] ?? ''}'),
        endDate: DateTime.tryParse('${j['end_date'] ?? ''}'),
      );
}

class Dose {
  const Dose(this.medicineId, this.name, this.strength, this.time, this.status);

  final String medicineId;
  final String name;
  final String strength;
  final String time;
  final String status; // taken | skipped | missed | due | upcoming

  factory Dose.fromJson(Map<String, dynamic> j) => Dose(j['medicine_id'] as String, j['name'] as String,
      j['strength'] as String? ?? '', j['time'] as String, j['status'] as String);
}

/// Medicines, schedule and intake (features 32, 33, 35, 36).
class MedicineRepository {
  MedicineRepository(this.api);

  final ApiClient api;

  /// The device's UTC offset, so "today" and "missed" use local time.
  int get _offset => DateTime.now().timeZoneOffset.inMinutes;

  Future<List<Medicine>> list() async {
    final data = await api.get('/medicines') as List<dynamic>;
    return data.map((e) => Medicine.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Medicine> add(Map<String, dynamic> body, {bool confirmAllergy = false}) async {
    final data = await api.post('/medicines', body: {...body, 'confirm_allergy_override': confirmAllergy})
        as Map<String, dynamic>;
    return Medicine.fromJson(data);
  }

  Future<void> stop(String id) => api.post('/medicines/$id/stop');

  Future<List<Dose>> today() async {
    final data = await api.get('/medicines/today?tz_offset_minutes=$_offset') as List<dynamic>;
    return data.map((e) => Dose.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> logIntake(String medicineId, String time, String status) =>
      api.post('/medicines/$medicineId/intake?tz_offset_minutes=$_offset', body: {'time': time, 'status': status});

  Future<Map<String, dynamic>> adherence() async =>
      await api.get('/medicines/adherence') as Map<String, dynamic>;
}
