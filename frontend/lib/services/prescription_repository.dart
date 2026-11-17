import 'api_client.dart';

/// One medicine line read from a prescription.
class RxMedicine {
  RxMedicine({
    this.name = '',
    this.genericName = '',
    this.strength = '',
    this.form = '',
    this.doseAsWritten = '',
    this.howToTake = '',
    this.timesPerDay,
    this.timing = '',
    this.duration = '',
    this.durationDays,
    this.purpose = '',
    this.confidence = 'medium',
    this.unclearParts = '',
  });

  factory RxMedicine.fromJson(Map<String, dynamic> j) => RxMedicine(
        name: j['name'] as String? ?? '',
        genericName: j['generic_name'] as String? ?? '',
        strength: j['strength'] as String? ?? '',
        form: j['form'] as String? ?? '',
        doseAsWritten: j['dose_as_written'] as String? ?? '',
        howToTake: j['how_to_take'] as String? ?? '',
        timesPerDay: j['times_per_day'] as int?,
        timing: j['timing'] as String? ?? '',
        duration: j['duration'] as String? ?? '',
        durationDays: j['duration_days'] as int?,
        purpose: j['purpose'] as String? ?? '',
        confidence: j['confidence'] as String? ?? 'medium',
        unclearParts: j['unclear_parts'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'generic_name': genericName,
        'strength': strength,
        'form': form,
        'dose_as_written': doseAsWritten,
        'how_to_take': howToTake,
        'times_per_day': timesPerDay,
        'timing': timing,
        'duration': duration,
        'duration_days': durationDays,
        'purpose': purpose,
        'confidence': confidence,
        'unclear_parts': unclearParts,
      };

  String name;
  String genericName;
  String strength;
  String form;
  String doseAsWritten;
  String howToTake;
  int? timesPerDay;
  String timing;
  String duration;
  int? durationDays;
  String purpose;
  String confidence; // high / medium / low
  String unclearParts;

  bool get unsure => confidence == 'low' || unclearParts.isNotEmpty;

  /// Reminder times from the written pattern: "1+0+1" -> 08:00, 21:00; else from times per day.
  List<String> suggestedTimes() {
    final m = RegExp(r'(\d)\s*\+\s*(\d)\s*\+\s*(\d)').firstMatch(doseAsWritten);
    if (m != null) {
      return [
        if (m.group(1) != '0') '08:00',
        if (m.group(2) != '0') '14:00',
        if (m.group(3) != '0') '21:00',
      ];
    }
    return switch (timesPerDay) {
      1 => ['09:00'],
      2 => ['08:00', '21:00'],
      3 => ['08:00', '14:00', '21:00'],
      4 => ['08:00', '12:00', '16:00', '21:00'],
      _ => <String>[],
    };
  }
}

class Prescription {
  Prescription.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        createdAt = DateTime.parse(j['created_at'] as String).toLocal(),
        status = j['status'] as String,
        language = j['language'] as String? ?? 'en',
        error = j['error'] as String?,
        readable = (j['reading'] as Map<String, dynamic>?)?['readable'] as bool? ?? false,
        doctorName = (j['reading'] as Map<String, dynamic>?)?['doctor_name'] as String? ?? '',
        clinic = (j['reading'] as Map<String, dynamic>?)?['clinic'] as String? ?? '',
        date = (j['reading'] as Map<String, dynamic>?)?['date'] as String? ?? '',
        summary = (j['reading'] as Map<String, dynamic>?)?['summary'] as String? ?? '',
        medicines = (((j['reading'] as Map<String, dynamic>?)?['medicines'] as List<dynamic>?) ?? const [])
            .map((m) => RxMedicine.fromJson(m as Map<String, dynamic>))
            .toList(),
        notes = (((j['reading'] as Map<String, dynamic>?)?['notes'] as List<dynamic>?) ?? const []).cast<String>(),
        warnings =
            (((j['reading'] as Map<String, dynamic>?)?['warnings'] as List<dynamic>?) ?? const []).cast<String>(),
        confirmed = ((j['confirmed_medicines'] as List<dynamic>?) ?? const [])
            .map((m) => RxMedicine.fromJson(m as Map<String, dynamic>))
            .toList();

  final String id;
  final DateTime createdAt;
  final String status; // needs_review / verified / unreadable / error
  final String language;
  final String? error;
  final bool readable;
  final String doctorName;
  final String clinic;
  final String date;
  final String summary;
  final List<RxMedicine> medicines;
  final List<String> notes;
  final List<String> warnings;
  final List<RxMedicine> confirmed;

  bool get verified => status == 'verified';

  /// What to show: the user's confirmed list once verified, else what the AI read.
  List<RxMedicine> get shown => verified && confirmed.isNotEmpty ? confirmed : medicines;
}

class PrescriptionSummary {
  PrescriptionSummary.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        createdAt = DateTime.parse(j['created_at'] as String).toLocal(),
        status = j['status'] as String,
        doctorName = j['doctor_name'] as String? ?? '',
        medicines = ((j['medicines'] as List<dynamic>?) ?? const []).cast<String>();

  final String id;
  final DateTime createdAt;
  final String status;
  final String doctorName;
  final List<String> medicines;
}

/// Prescription reader (feature 26) and schedule from a prescription (feature 34).
class PrescriptionRepository {
  PrescriptionRepository(this.api);
  final ApiClient api;

  Future<Prescription> upload(
      {required List<int> bytes, required String fileName, required String mimeType, String language = 'en'}) async {
    final data = await api.postFile('/prescriptions',
        bytes: bytes, filename: fileName, mimeType: mimeType, fields: {'language': language});
    return Prescription.fromJson(data as Map<String, dynamic>);
  }

  Future<List<PrescriptionSummary>> list() async {
    final data = await api.get('/prescriptions') as List<dynamic>;
    return data.map((e) => PrescriptionSummary.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Prescription> get(String id) async =>
      Prescription.fromJson(await api.get('/prescriptions/$id') as Map<String, dynamic>);

  Future<Prescription> readAgain(String id, {String? language}) async => Prescription.fromJson(
      await api.post('/prescriptions/$id/read${language == null ? '' : '?language=$language'}')
          as Map<String, dynamic>);

  Future<Prescription> confirm(String id, List<RxMedicine> medicines) async => Prescription.fromJson(
      await api.put('/prescriptions/$id/confirm',
          body: {'medicines': medicines.map((m) => m.toJson()).toList(), 'checked': true}) as Map<String, dynamic>);

  Future<List<int>> image(String id) => api.getBytes('/prescriptions/$id/file');

  Future<void> delete(String id) => api.delete('/prescriptions/$id');
}
