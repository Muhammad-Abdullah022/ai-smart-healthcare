/// Result of the AI Symptom Checker (feature 1) with triage (feature 4).
class PossibleCause {
  const PossibleCause({required this.name, required this.likelihood, required this.reason});

  final String name;
  final String likelihood; // low | medium | high
  final String reason;

  factory PossibleCause.fromJson(Map<String, dynamic> j) => PossibleCause(
        name: j['name'] as String,
        likelihood: j['likelihood'] as String,
        reason: j['reason'] as String,
      );
}

class AssessmentExplanation {
  const AssessmentExplanation({
    required this.method,
    required this.inputsUsed,
    required this.rulesTriggered,
    required this.limitations,
    this.aiProvider,
  });

  final String method;
  final List<String> inputsUsed;
  final List<String> rulesTriggered;
  final String limitations;
  final String? aiProvider;

  factory AssessmentExplanation.fromJson(Map<String, dynamic> j) => AssessmentExplanation(
        method: j['method'] as String,
        inputsUsed: _strings(j['inputs_used']),
        rulesTriggered: _strings(j['rules_triggered']),
        limitations: j['limitations'] as String,
        aiProvider: j['ai_provider'] as String?,
      );
}

class EmergencyNumber {
  const EmergencyNumber(this.name, this.number);
  final String name;
  final String number;
}

class Assessment {
  const Assessment({
    required this.id,
    required this.createdAt,
    required this.emergency,
    required this.triageLevel,
    required this.triageReason,
    required this.symptoms,
    required this.explanation,
    required this.disclaimer,
    this.emergencyNumbers = const [],
    this.possibleCauses = const [],
    this.nextSteps = const [],
    this.followUpQuestions = const [],
    this.ready = true,
    this.otcOptions = const [],
    this.testsToDiscuss = const [],
    this.warningSigns = const [],
    this.specialistType,
    this.answers = const [],
    this.carePath = 'see_doctor',
    this.reportReview,
  });

  final String id;
  final DateTime createdAt;
  final bool emergency;
  final String triageLevel; // critical | urgent | moderate | routine
  final String triageReason;
  final String symptoms;
  final AssessmentExplanation explanation;
  final String disclaimer;
  final List<EmergencyNumber> emergencyNumbers;
  final List<PossibleCause> possibleCauses;
  final List<String> nextSteps;
  final List<String> followUpQuestions;

  /// False while the AI still needs answers to [followUpQuestions].
  final bool ready;

  /// Over-the-counter medicines a pharmacist could suggest (generic names, never doses).
  final List<({String name, String helpsWith, String avoidIf, int days})> otcOptions;
  final List<String> testsToDiscuss;
  final List<String> warningSigns;
  final String? specialistType;

  /// The chat: follow-up questions and the user's answers.
  final List<(String, String)> answers;

  /// What to do next: self_care (medicines only) | tests_first (tests only, then upload the report)
  /// | see_doctor (book a doctor) | emergency.
  final String carePath;

  /// The AI's reading of the report uploaded after "tests_first" (summary, findings, abnormal values).
  final Map<String, dynamic>? reportReview;

  factory Assessment.fromJson(Map<String, dynamic> j) => Assessment(
        id: j['id'] as String,
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
        emergency: j['emergency'] as bool,
        triageLevel: j['triage_level'] as String,
        triageReason: j['triage_reason'] as String,
        symptoms: j['symptoms'] as String,
        explanation: AssessmentExplanation.fromJson(j['explanation'] as Map<String, dynamic>),
        disclaimer: j['disclaimer'] as String,
        emergencyNumbers: [
          for (final n in (j['emergency_numbers'] as List<dynamic>? ?? const []))
            EmergencyNumber((n as Map)['name'] as String, n['number'] as String),
        ],
        possibleCauses: [
          for (final c in (j['possible_causes'] as List<dynamic>? ?? const []))
            PossibleCause.fromJson(c as Map<String, dynamic>),
        ],
        nextSteps: _strings(j['next_steps']),
        followUpQuestions: _strings(j['follow_up_questions']),
        ready: j['ready'] as bool? ?? true,
        otcOptions: [
          for (final o in (j['otc_options'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>())
            (
              name: o['name'] as String? ?? '',
              helpsWith: o['helps_with'] as String? ?? '',
              avoidIf: o['avoid_if'] as String? ?? '',
              days: (o['days'] as num?)?.toInt() ?? 3,
            )
        ],
        testsToDiscuss: _strings(j['tests_to_discuss']),
        warningSigns: _strings(j['warning_signs']),
        specialistType: j['specialist_type'] as String?,
        answers: [
          for (final a in (j['answers'] as List<dynamic>? ?? const []))
            ((a as Map)['question'] as String, a['answer'] as String),
        ],
        carePath: j['care_path'] as String? ?? (j['emergency'] == true ? 'emergency' : 'see_doctor'),
        reportReview: (j['report_review'] as Map?)?.cast<String, dynamic>(),
      );
}

class AssessmentSummary {
  const AssessmentSummary(this.id, this.createdAt, this.symptoms, this.triageLevel);

  final String id;
  final DateTime createdAt;
  final String symptoms;
  final String triageLevel;

  factory AssessmentSummary.fromJson(Map<String, dynamic> j) => AssessmentSummary(
        j['id'] as String,
        DateTime.parse(j['created_at'] as String).toLocal(),
        j['symptoms'] as String,
        j['triage_level'] as String,
      );
}

List<String> _strings(Object? value) => (value as List<dynamic>? ?? const []).cast<String>();
