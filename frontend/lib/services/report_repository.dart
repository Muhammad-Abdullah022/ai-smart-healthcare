import 'api_client.dart';

class ReportValue {
  ReportValue(
      {required this.name,
      required this.value,
      required this.unit,
      required this.range,
      required this.flag,
      this.flagSource = 'ai',
      this.standardRange = '',
      this.about = '',
      this.critical = false});

  factory ReportValue.fromJson(Map<String, dynamic> j) => ReportValue(
        name: j['name'] as String? ?? '',
        value: j['value'] as String? ?? '',
        unit: j['unit'] as String? ?? '',
        range: j['reference_range'] as String? ?? '',
        flag: j['flag'] as String? ?? 'unknown',
        flagSource: j['flag_source'] as String? ?? 'ai',
        standardRange: j['standard_range'] as String? ?? '',
        about: j['about'] as String? ?? '',
        critical: j['critical'] as bool? ?? false,
      );

  final String name;
  final String value;
  final String unit;
  final String range;
  final String flag; // low / normal / high / unknown
  /// Where low/normal/high came from: "report" (range printed on the report, checked by code),
  /// "standard" (standard adult range, checked by code) or "ai".
  final String flagSource;
  final String standardRange;
  final String about;
  final bool critical;

  bool get abnormal => flag == 'low' || flag == 'high';
}

class ReportAnalysis {
  ReportAnalysis.fromJson(Map<String, dynamic> j)
      : reportType = j['report_type'] as String? ?? 'Medical report',
        reportDate = j['report_date'] as String?,
        values = (j['values'] as List<dynamic>? ?? [])
            .map((v) => ReportValue.fromJson(v as Map<String, dynamic>))
            .toList(),
        summary = j['summary'] as String? ?? '',
        doctorType = j['doctor_type'] as String? ?? '',
        urgency = j['urgency'] as String? ?? 'routine',
        nextSteps = (j['next_steps'] as List<dynamic>? ?? []).cast<String>();

  final String reportType;
  final String? reportDate;
  final List<ReportValue> values;
  final String summary;
  final String doctorType;
  final String urgency; // routine / soon / urgent
  final List<String> nextSteps;
}

class MedicalReport {
  MedicalReport.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        createdAt = DateTime.parse(j['created_at'] as String).toLocal(),
        fileName = j['file_name'] as String? ?? 'report',
        analysis = j['analysis'] == null ? null : ReportAnalysis.fromJson(j['analysis'] as Map<String, dynamic>),
        error = j['error'] as String?;

  final String id;
  final DateTime createdAt;
  final String fileName;
  final ReportAnalysis? analysis;
  final String? error;
}

class ReportSummary {
  ReportSummary.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        createdAt = DateTime.parse(j['created_at'] as String).toLocal(),
        fileName = j['file_name'] as String? ?? 'report',
        reportType = j['report_type'] as String?,
        reportDate = j['report_date'] as String?,
        urgency = j['urgency'] as String?,
        abnormalCount = j['abnormal_count'] as int? ?? 0;

  final String id;
  final DateTime createdAt;
  final String fileName;
  final String? reportType;
  final String? reportDate;
  final String? urgency;
  final int abnormalCount;

  bool get analyzed => reportType != null;
  String get title => reportType ?? fileName;
}

class CompareRow {
  CompareRow.fromJson(Map<String, dynamic> j)
      : name = j['name'] as String,
        unit = j['unit'] as String? ?? '',
        oldValue = j['old_value'] as String,
        newValue = j['new_value'] as String,
        oldFlag = j['old_flag'] as String? ?? 'unknown',
        newFlag = j['new_flag'] as String? ?? 'unknown',
        change = j['change'] as String? ?? 'na',
        nowNormal = j['now_normal'] as bool? ?? false,
        nowAbnormal = j['now_abnormal'] as bool? ?? false;

  final String name;
  final String unit;
  final String oldValue;
  final String newValue;
  final String oldFlag;
  final String newFlag;
  final String change; // up / down / same / na
  final bool nowNormal;
  final bool nowAbnormal;
}

class ReportComparison {
  ReportComparison.fromJson(Map<String, dynamic> j)
      : rows = (j['rows'] as List<dynamic>).map((r) => CompareRow.fromJson(r as Map<String, dynamic>)).toList(),
        note = j['note'] as String? ?? '';

  final List<CompareRow> rows;
  final String note;
}

/// Calls the backend's /reports endpoints (features 8 and 9).
class ReportRepository {
  ReportRepository(this.api);

  final ApiClient api;

  Future<MedicalReport> upload(
      {required List<int> bytes, required String fileName, required String mimeType, String language = 'en'}) async {
    final data = await api.postFile('/reports',
        bytes: bytes, filename: fileName, mimeType: mimeType, fields: {'language': language});
    return MedicalReport.fromJson(data as Map<String, dynamic>);
  }

  Future<List<ReportSummary>> list() async {
    final data = await api.get('/reports') as List<dynamic>;
    return data.map((e) => ReportSummary.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<MedicalReport> get(String id) async =>
      MedicalReport.fromJson(await api.get('/reports/$id') as Map<String, dynamic>);

  Future<MedicalReport> reanalyze(String id) async =>
      MedicalReport.fromJson(await api.post('/reports/$id/analyze') as Map<String, dynamic>);

  Future<ReportComparison> compare(String oldId, String newId) async =>
      ReportComparison.fromJson(await api.get('/reports/compare?old=$oldId&new=$newId') as Map<String, dynamic>);
}

/// Guess the file type from its name (the picker does not always give one).
String mimeTypeFor(String fileName) {
  final n = fileName.toLowerCase();
  if (n.endsWith('.pdf')) return 'application/pdf';
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}
