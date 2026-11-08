import '../models/assessment.dart';
import 'api_client.dart';

/// Calls the backend's /assessments endpoints (AI runs on the backend, never in the app).
class AssessmentRepository {
  AssessmentRepository(this.api);

  final ApiClient api;

  Future<Assessment> checkSymptoms({
    required String symptoms,
    String? duration,
    int? severity,
    int? age,
    String? sex,
    List<Map<String, String>> answers = const [],
  }) async {
    final data = await api.post('/assessments/symptoms', body: {
      'symptoms': symptoms,
      if (duration != null) 'duration': duration,
      if (severity != null) 'severity': severity,
      if (age != null) 'age': age,
      if (sex != null) 'sex': sex,
      'answers': answers,
    }) as Map<String, dynamic>;
    return Assessment.fromJson(data);
  }

  Future<List<AssessmentSummary>> history() async {
    final data = await api.get('/assessments/symptoms') as List<dynamic>;
    return data.map((e) => AssessmentSummary.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Assessment> getById(String id) async {
    final data = await api.get('/assessments/symptoms/$id') as Map<String, dynamic>;
    return Assessment.fromJson(data);
  }
}
