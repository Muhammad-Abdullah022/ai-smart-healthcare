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

const _noData = 'Needs a verified data source. Will use clearly labelled sample data until then.';

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
          status: FeatureStatus.prototype, note: _noData),
      HealthFeature(7, 'Lab Test Price Comparison', Icons.price_check,
          status: FeatureStatus.prototype, note: _noData),
      HealthFeature(8, 'Medical Report Scanner & Analyzer', Icons.document_scanner_outlined),
      HealthFeature(9, 'Report Comparison (Previous vs Current)', Icons.compare_arrows),
      HealthFeature(10, 'Doctor & Specialist Recommendation', Icons.person_search_outlined),
      HealthFeature(11, 'Appointment Booking & Email', Icons.event_available_outlined,
          status: FeatureStatus.prototype,
          note: 'Uses doctors added and verified by an admin; no live clinic availability.'),
      HealthFeature(12, 'Emergency Detection & SOS', Icons.sos_outlined, status: FeatureStatus.available),
      HealthFeature(13, 'Voice Assistant (Urdu / English / Roman Urdu)', Icons.mic_none),
      HealthFeature(14, 'Recovery Monitoring & Follow-Up', Icons.healing_outlined),
      HealthFeature(15, 'Medical Second Opinion Support', Icons.fact_check_outlined),
    ],
  ),
  HealthModule(
    id: 'mental',
    title: 'Mental Health & Stress',
    subtitle: 'Screening, mood, breathing, support',
    icon: Icons.self_improvement,
    color: AppColors.mind,
    tint: AppColors.mindTint,
    features: [
      HealthFeature(16, 'Mental Health Screening', Icons.psychology_outlined, status: FeatureStatus.available),
      HealthFeature(17, 'Mental Health Chatbot', Icons.chat_bubble_outline),
      HealthFeature(18, 'Stress, Anxiety & Mood Assessment', Icons.mood_outlined, status: FeatureStatus.available),
      HealthFeature(19, 'Personalized Stress Relief', Icons.spa_outlined),
      HealthFeature(20, 'Camera Exercise Monitoring', Icons.fitness_center,
          status: FeatureStatus.prototype, note: 'On-device prototype; accuracy depends on phone and lighting.'),
      HealthFeature(21, 'Posture Detection & Correction', Icons.accessibility_new,
          status: FeatureStatus.prototype, note: 'On-device prototype.'),
      HealthFeature(22, 'Guided Breathing & Relaxation', Icons.air, status: FeatureStatus.available),
      HealthFeature(23, 'Meditation & Wellness Plan', Icons.self_improvement),
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
      HealthFeature(26, 'Prescription & Handwriting Reader', Icons.receipt_long_outlined),
      HealthFeature(27, 'Medicine Identification from Image', Icons.camera_alt_outlined),
      HealthFeature(28, 'Nearby Pharmacy & Availability', Icons.local_pharmacy_outlined,
          status: FeatureStatus.prototype, note: _noData),
      HealthFeature(29, 'Medicine Price Comparison', Icons.sell_outlined,
          status: FeatureStatus.prototype, note: _noData),
      HealthFeature(30, 'Same-Salt / Generic Alternatives', Icons.swap_horiz),
      HealthFeature(31, 'Drug Interaction & Safety Checker', Icons.warning_amber_outlined),
      HealthFeature(32, 'Allergy & Contraindication Warning', Icons.do_not_disturb_on_outlined, status: FeatureStatus.available),
      HealthFeature(33, 'Smart Medicine Reminders', Icons.alarm),
      HealthFeature(34, 'Schedule from Prescription Image', Icons.schedule),
      HealthFeature(35, 'Manual Medicine Entry & Schedule', Icons.edit_calendar_outlined, status: FeatureStatus.available),
      HealthFeature(36, 'Intake Tracking & Missed-Dose Alerts', Icons.task_alt, status: FeatureStatus.available),
      HealthFeature(37, 'Medicine Info & Side Effects', Icons.info_outline),
    ],
  ),
  HealthModule(
    id: 'records',
    title: 'Health Records & Patient Care',
    subtitle: 'EHR, history, family, QR passport',
    icon: Icons.folder_shared_outlined,
    color: AppColors.records,
    tint: AppColors.recordsTint,
    features: [
      HealthFeature(38, 'Electronic Health Records', Icons.folder_open_outlined),
      HealthFeature(39, 'Medical History', Icons.history_edu_outlined),
      HealthFeature(40, 'Future Health Risk Prediction', Icons.trending_up),
      HealthFeature(41, 'Health Trends & Analytics', Icons.show_chart, status: FeatureStatus.available),
      HealthFeature(42, 'Smartwatch / Wearable Monitoring', Icons.watch_outlined,
          status: FeatureStatus.prototype, note: 'Needs Health Connect and a supported wearable.'),
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


List<HealthFeature> get allFeatures => [for (final m in healthModules) ...m.features];
