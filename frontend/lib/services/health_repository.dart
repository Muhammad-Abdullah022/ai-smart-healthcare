import 'api_client.dart';

/// Vital kinds the backend accepts, with labels and units.
const vitalKinds = <String, ({String label, String unit})>{
  'bp': (label: 'Blood pressure', unit: 'mmHg'),
  'sugar_fasting': (label: 'Fasting sugar', unit: 'mg/dL'),
  'sugar_random': (label: 'Random sugar', unit: 'mg/dL'),
  'weight': (label: 'Weight', unit: 'kg'),
  'heart_rate': (label: 'Heart rate', unit: 'bpm'),
  'temperature': (label: 'Temperature', unit: '°F'),
  'spo2': (label: 'Oxygen (SpO2)', unit: '%'),
  'steps': (label: 'Steps', unit: 'steps'),
  'sleep': (label: 'Sleep', unit: 'hours'),
};

/// Health record (auto-built), PDF/QR export, vitals, trends and risk.
class HealthRepository {
  HealthRepository(this.api);
  final ApiClient api;

  Future<Map<String, dynamic>> record() async => await api.get('/health-record') as Map<String, dynamic>;

  /// A 24-hour link to the record PDF (locked with the login password). Also used for the QR code.
  Future<({String url, int hours})> share(String password) async {
    final d = await api.post('/health-record/share', body: {'password': password}) as Map<String, dynamic>;
    return (url: d['url'] as String, hours: d['hours'] as int);
  }

  Future<void> stopSharing() => api.delete('/health-record/share');

  Future<void> addVital(String kind, double value, {double? value2, DateTime? at, String source = 'manual'}) =>
      api.post('/vitals', body: {
        'kind': kind,
        'value': value,
        if (value2 != null) 'value2': value2,
        if (at != null) 'at': at.toUtc().toIso8601String(),
        'source': source,
      });

  Future<int> addVitalsBatch(List<Map<String, dynamic>> readings) async {
    final d = await api.post('/vitals/batch', body: {'readings': readings}) as Map<String, dynamic>;
    return d['saved'] as int;
  }

  Future<List<dynamic>> vitals({String? kind, int days = 90}) async =>
      await api.get('/vitals?days=$days${kind == null ? '' : '&kind=$kind'}') as List<dynamic>;

  Future<void> deleteVital(String id) => api.delete('/vitals/$id');

  Future<Map<String, dynamic>> trends({int days = 90}) async =>
      await api.get('/health-trends?days=$days') as Map<String, dynamic>;

  Future<Map<String, dynamic>> risk() async => await api.get('/health-risk') as Map<String, dynamic>;

  Future<Map<String, dynamic>> saveLifestyle(Map<String, dynamic> data) async =>
      await api.put('/health-risk/lifestyle', body: data) as Map<String, dynamic>;
}
