import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/feature_forms.dart';
import '../../providers/auth_provider.dart';
import '../../screens/assistant/assistant_chat_screen.dart';
import '../../screens/doctors/doctors_screens.dart';
import '../../screens/labs/lab_finder_screen.dart';
import '../../screens/reports/report_compare_screen.dart';
import '../../screens/reports/reports_screen.dart';
import '../../services/report_repository.dart';
import '../../screens/emergency/sos_screen.dart';
import '../../screens/medicines/medicines_screen.dart';
import '../../screens/mental/breathing_screen.dart';
import '../../screens/mental/crisis_screen.dart';
import '../../screens/mental/companion/mood_checkin_screen.dart';
import '../../screens/mental/mood_screen.dart';
import '../../screens/mental/screening_screen.dart';
import '../../screens/modules/feature_form_screen.dart';
import '../../screens/pharmacy/medicine_search_screen.dart';
import '../../screens/pharmacy/pharmacy_finder_screen.dart';
import '../../screens/prescriptions/prescription_reader_screen.dart';
import '../../screens/modules/feature_screen.dart';
import '../../screens/records/activity_screen.dart';
import '../../screens/records/emergency_card_screen.dart';
import '../../screens/settings/consent_screen.dart';

/// Which screen opens for each of the 50 features.
Widget screenForFeature(int number) {
  switch (number) {
    // The AI Health Assistant chat covers symptoms, follow-up questions, prediction, triage,
    // test suggestions and the "Why this result?" explanation.
    case 1 || 2 || 3 || 4 || 5 || 46:
      return const AssistantChatScreen();
    case 7:
      // Ask city and test, then show every lab's price for that test.
      return const TestPickerScreen();
    case 10:
      return const DoctorsIntroScreen();
    case 6:
      // Ask first: find labs, or find a test and compare prices. (After a symptom check,
      // the suggested tests open LabOptionsScreen directly.)
      return const LabFinderScreen();
    case 8:
      return const ReportsScreen();
    case 9:
      return Builder(
        builder: (ctx) => ReportCompareScreen(repository: ReportRepository(ctx.read<AuthProvider>().repository.api)),
      );
    case 12:
      return const SosScreen();
    case 13:
      return const AssistantChatScreen();
    case 16:
      return const ScreeningScreen();
    case 18:
      return const ScreeningScreen(initialInstrument: 'gad7');
    case 17 || 19:
      // MindEase flow: mood check-in -> affirmation & tips -> companion chat.
      return const MoodCheckInScreen();
    case 22:
      return const BreathingScreen();
    case 24:
      return const MoodScreen();
    case 25:
      return const CrisisScreen();
    case 28:
      return const PharmacyFinderScreen();
    case 30 || 37:
      return const MedicineSearchScreen();
    case 26 || 34:
      // Photograph a prescription -> AI reads the handwriting -> user checks -> reminders.
      return const PrescriptionReaderScreen();
    case 32 || 33 || 35 || 36:
      return const MedicinesScreen();
    case 48:
      return const ConsentScreen();
    case 44:
      return const EmergencyCardScreen();
    case 49:
      return const ActivityScreen();
  }
  if (featureForms.containsKey(number)) return FeatureFormScreen(number: number);
  return FeatureScreen(number: number);
}
