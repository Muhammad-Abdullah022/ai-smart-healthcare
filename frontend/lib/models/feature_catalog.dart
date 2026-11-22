import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Where a feature currently stands. Shown honestly on its tile.
enum FeatureStatus { available, inDevelopment, prototype }

class HealthFeature {
  const HealthFeature(this.number, this.title, this.icon,
      {this.status = FeatureStatus.inDevelopment, this.note});

  final int number;
  final String title;
  final IconData icon;
  final FeatureStatus status;

  /// Why a feature is a prototype (e.g. no verified data source yet).
  final String? note;
}

class HealthModule {
  const HealthModule({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.tint,
    required this.features,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color tint;
  final List<HealthFeature> features;
}

const _labData = 'Sourced Punjab lab data (PHC directory and labs\' own price lists); coverage is partial.';

/// All 50 features from the project brief, grouped into the 4 modules.
const List<HealthModule> healthModules = [
  HealthModule(
    id: 'diagnosis',
    title: 'AI Diagnosis & Medical Assistance',
    subtitle: 'Symptoms, triage, reports, doctors, SOS',
    icon: Icons.medical_services_outlined,
    color: AppColors.diagnosis,
    tint: AppColors.diagnosisTint,
    features: [
      HealthFeature(1, 'AI Symptom Checker', Icons.sick_outlined, status: FeatureStatus.available),
      HealthFeature(2, 'Adaptive Cross-Questioning', Icons.quiz_outlined, status: FeatureStatus.available),
      HealthFeature(3, 'Disease Prediction & Risk Assessment', Icons.analytics_outlined, status: FeatureStatus.available),
      HealthFeature(4, 'Patient Triage', Icons.priority_high, status: FeatureStatus.available),
      HealthFeature(5, 'Medical Test Recommendation', Icons.biotech_outlined, status: FeatureStatus.available),
      HealthFeature(6, 'Nearby Laboratory Finder', Icons.location_on_outlined,
          status: FeatureStatus.available, note: _labData),
      HealthFeature(7, 'Lab Test Price Comparison', Icons.price_check,
          status: FeatureStatus.available, note: _labData),
      HealthFeature(8, 'Medical Report Scanner & Analyzer', Icons.document_scanner_outlined,
          status: FeatureStatus.available),
      HealthFeature(9, 'Report Comparison (Previous vs Current)', Icons.compare_arrows,
          status: FeatureStatus.available),
      HealthFeature(10, 'Doctor & Specialist Recommendation', Icons.person_search_outlined,
          status: FeatureStatus.available),
      HealthFeature(11, 'Appointment Booking & Email', Icons.event_available_outlined,
          status: FeatureStatus.prototype,
          note: 'Uses doctors added and verified by an admin; no live clinic availability.'),
      HealthFeature(12, 'Emergency Detection & SOS', Icons.sos_outlined, status: FeatureStatus.available),
      HealthFeature(13, 'AI Health Assistant (Voice: Urdu / English / Roman Urdu)', Icons.mic_none,
          status: FeatureStatus.available),
      HealthFeature(14, 'Recovery Monitoring & Follow-Up', Icons.healing_outlined),
      HealthFeature(15, 'Medical Second Opinion Support', Icons.fact_check_outlined),
    ],
  ),
  HealthModule(
    id: 'mental',
    title: 'Mental Health & Stress',
    subtitle: 'MindEase chat, PHQ-9/GAD-7 check, wellness plan, mood tracker',
    icon: Icons.self_improvement,
    color: AppColors.mind,
    tint: AppColors.mindTint,
    features: [
      HealthFeature(16, 'Depression & Anxiety Check (PHQ-9 / GAD-7)', Icons.psychology_outlined, status: FeatureStatus.available),
      HealthFeature(17, 'MindEase Companion Chat', Icons.chat_bubble_outline, status: FeatureStatus.available),
      HealthFeature(18, 'Stress, Anxiety & Mood Assessment', Icons.mood_outlined, status: FeatureStatus.available),
      HealthFeature(19, 'Personalized Stress Relief', Icons.spa_outlined, status: FeatureStatus.available),
      HealthFeature(20, 'Camera Exercise Monitoring', Icons.fitness_center,
          status: FeatureStatus.prototype, note: 'On-device prototype; accuracy depends on phone and lighting.'),
      HealthFeature(21, 'Posture Detection & Correction', Icons.accessibility_new,
          status: FeatureStatus.prototype, note: 'On-device prototype.'),
      HealthFeature(22, 'Guided Breathing & Relaxation', Icons.air, status: FeatureStatus.available),
      HealthFeature(23, 'Meditation & Wellness Plan', Icons.self_improvement, status: FeatureStatus.available),
      HealthFeature(24, 'Daily Mood Tracking Dashboard', Icons.insights_outlined, status: FeatureStatus.available),
      HealthFeature(25, 'Crisis Support & Professional Referral', Icons.support_agent, status: FeatureStatus.available),
    ],
  ),
  HealthModule(
    id: 'medicine',
    title: 'Medicine & Pharmacy',
    subtitle: 'Prescriptions, reminders, safety checks',
    icon: Icons.medication_outlined,
    color: AppColors.medicine,
    tint: AppColors.medicineTint,
    features: [
      HealthFeature(26, 'Prescription & Handwriting Reader', Icons.receipt_long_outlined,
          status: FeatureStatus.available),
      HealthFeature(27, 'Medicine Identification from Image', Icons.camera_alt_outlined,
          status: FeatureStatus.available),
      HealthFeature(28, 'Nearby Pharmacy & Availability', Icons.local_pharmacy_outlined,
          status: FeatureStatus.available),
      HealthFeature(29, 'Medicine Price Comparison', Icons.sell_outlined,
          status: FeatureStatus.available),
      HealthFeature(30, 'Medicine Search & Same-Salt Alternatives', Icons.swap_horiz,
          status: FeatureStatus.available),
      HealthFeature(31, 'Drug Interaction & Safety Checker', Icons.warning_amber_outlined),
      HealthFeature(32, 'Allergy & Contraindication Warning', Icons.do_not_disturb_on_outlined, status: FeatureStatus.available),
      HealthFeature(33, 'Smart Medicine Reminders', Icons.alarm, status: FeatureStatus.available),
      HealthFeature(34, 'Schedule from Prescription Image', Icons.schedule, status: FeatureStatus.available),
      HealthFeature(35, 'Manual Medicine Entry & Schedule', Icons.edit_calendar_outlined, status: FeatureStatus.available),
      HealthFeature(36, 'Intake Tracking & Missed-Dose Alerts', Icons.task_alt, status: FeatureStatus.available),
      HealthFeature(37, 'Medicine Info & Side Effects', Icons.info_outline),
    ],
  ),
  HealthModule(
    id: 'records',
    title: 'Health Records & Patient Care',
    subtitle: 'Health record, risk, trends, smartwatch',
    icon: Icons.folder_shared_outlined,
    color: AppColors.records,
    tint: AppColors.recordsTint,
    features: [
      HealthFeature(38, 'My Health Record (history, PDF & QR)', Icons.folder_open_outlined,
          status: FeatureStatus.available),
      HealthFeature(39, 'Medical History', Icons.history_edu_outlined),
      HealthFeature(40, 'Future Health Risk & Recommendations', Icons.trending_up,
          status: FeatureStatus.available),
      HealthFeature(41, 'Health Trends & Analytics', Icons.show_chart, status: FeatureStatus.available),
      HealthFeature(42, 'Smartwatch (Bluetooth)', Icons.watch_outlined, status: FeatureStatus.available),
      HealthFeature(43, 'Family & Caregiver Management', Icons.family_restroom),
      HealthFeature(44, 'Emergency Medical Passport (QR)', Icons.qr_code_2, status: FeatureStatus.available),
      HealthFeature(45, 'Personalized Health Recommendations', Icons.recommend_outlined),
      HealthFeature(46, 'Explainable AI Decisions', Icons.lightbulb_outline, status: FeatureStatus.available),
      HealthFeature(47, 'Doctor Verification & AI Approval', Icons.verified_user_outlined),
      HealthFeature(48, 'Data Security & Consent', Icons.lock_outline, status: FeatureStatus.available),
      HealthFeature(49, 'Decision History & Audit Trail', Icons.manage_history, status: FeatureStatus.available),
      HealthFeature(50, 'Health Summary PDF Report', Icons.picture_as_pdf_outlined),
    ],
  ),
];

HealthModule? moduleById(String id) {
  for (final module in healthModules) {
    if (module.id == id) return module;
  }
  return null;
}

/// The module a feature belongs to.
HealthModule moduleOf(int featureNumber) {
  for (final m in healthModules) {
    if (m.features.any((f) => f.number == featureNumber)) return m;
  }
  return healthModules.first;
}

HealthFeature? featureByNumber(int number) {
  for (final f in allFeatures) {
    if (f.number == number) return f;
  }
  return null;
}


/// Shown as one item ("AI Symptom Checker") because they are one chat screen.
const Set<int> mergedIntoSymptomChecker = {2, 3, 4, 5};

/// The Mental Health section now shows only the MindEase module (feature 17). These features are
/// hidden from lists and search; breathing (22) and crisis help (25) stay reachable inside MindEase,
/// and nothing is deleted, so any of them can be shown again by removing it from this set.
// Shown: MindEase (17), PHQ-9/GAD-7 screening (16), wellness plan (23), mood dashboard (24).
const Set<int> hiddenMentalFeatures = {18, 19, 20, 21, 22, 25};

/// Whether a feature appears in section lists and search.
/// Appointment booking (11) now happens from the chat result and the doctor list, so it has no row.
const Set<int> hiddenOtherFeatures = {11, 14, 15, 27, 32, 34, 35, 36, 37, 39, 43, 45, 46, 47, 49, 50};

bool isListedFeature(HealthFeature f) =>
    !mergedIntoSymptomChecker.contains(f.number) &&
    !hiddenMentalFeatures.contains(f.number) &&
    !hiddenOtherFeatures.contains(f.number);

List<HealthFeature> get allFeatures => [for (final m in healthModules) ...m.features];
