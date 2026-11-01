import 'api_client.dart';

class Instrument {
  const Instrument(this.key, this.title, this.intro, this.questions, this.options);

  final String key;
  final String title;
  final String intro;
  final List<String> questions;
  final List<String> options;
}

class ScreeningResult {
  const ScreeningResult({
    required this.title,
    required this.score,
    required this.maxScore,
    required this.severity,
    required this.advice,
    required this.crisis,
    required this.note,
    required this.createdAt,
  });

  final String title;
  final int score;
  final int maxScore;
  final String severity;
  final String advice;
  final bool crisis;
  final String note;
  final DateTime createdAt;

  factory ScreeningResult.fromJson(Map<String, dynamic> j) => ScreeningResult(
        title: j['title'] as String,
        score: j['score'] as int,
        maxScore: j['max_score'] as int,
        severity: j['severity'] as String,
        advice: j['advice'] as String,
        crisis: j['crisis'] as bool,
        note: j['note'] as String,
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
      );
}

class MoodEntry {
  const MoodEntry(this.day, this.mood, this.note);

  final DateTime day;
  final int mood;
  final String note;

  factory MoodEntry.fromJson(Map<String, dynamic> j) =>
      MoodEntry(DateTime.parse(j['day'] as String), j['mood'] as int, j['note'] as String? ?? '');
}

class HelpLine {
  const HelpLine(this.name, this.phone, this.hours);

  final String name;
  final String phone;
  final String hours;

  factory HelpLine.fromJson(Map<String, dynamic> j) =>
      HelpLine(j['name'] as String, j['phone'] as String, j['hours'] as String);
}

class CrisisResources {
  const CrisisResources(this.emergency, this.support, this.note, this.checked);

  final List<HelpLine> emergency;
  final List<HelpLine> support;
  final String note;
  final String checked;

  /// Used if the server can't be reached: crisis help must always show something.
  static const offline = CrisisResources(
    [HelpLine('Rescue / Ambulance', '1122', '24/7'), HelpLine('Edhi Ambulance', '115', '24/7')],
    [],
    'If you are in danger right now, call 1122 or go to the nearest hospital emergency department, '
        'and tell someone you trust.',
    'offline copy',
  );

  factory CrisisResources.fromJson(Map<String, dynamic> j) => CrisisResources(
        [for (final e in j['emergency'] as List<dynamic>) HelpLine.fromJson(e as Map<String, dynamic>)],
        [for (final e in j['support'] as List<dynamic>) HelpLine.fromJson(e as Map<String, dynamic>)],
        j['note'] as String,
        j['checked'] as String,
      );
}

/// Mental health endpoints (features 16, 22, 24, 25).
class MentalRepository {
  MentalRepository(this.api);

  final ApiClient api;

  Future<CrisisResources> crisisResources() async {
    try {
      final data = await api.get('/mental/crisis-resources') as Map<String, dynamic>;
      return CrisisResources.fromJson(data);
    } on ApiException {
      return CrisisResources.offline;
    }
  }

  Future<Map<String, Instrument>> instruments() async {
    final data = await api.get('/mental/instruments') as Map<String, dynamic>;
    return data.map((key, value) {
      final v = value as Map<String, dynamic>;
      return MapEntry(
        key,
        Instrument(key, v['title'] as String, v['intro'] as String, (v['questions'] as List).cast<String>(),
            (v['options'] as List).cast<String>()),
      );
    });
  }

  Future<ScreeningResult> submitScreening(String instrument, List<int> answers) async {
    final data = await api.post('/mental/screenings', body: {'instrument': instrument, 'answers': answers})
        as Map<String, dynamic>;
    return ScreeningResult.fromJson(data);
  }

  Future<List<MoodEntry>> moods({int days = 30}) async {
    final data = await api.get('/mental/moods?days=$days') as List<dynamic>;
    return data.map((e) => MoodEntry.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveMood(int mood, String note) => api.put('/mental/moods', body: {'mood': mood, 'note': note});

  Future<void> saveBreathing(String pattern, int seconds) =>
      api.post('/mental/breathing', body: {'pattern': pattern, 'duration_seconds': seconds});
}
