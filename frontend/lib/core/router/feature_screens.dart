import 'package:flutter/material.dart';

import '../../models/feature_forms.dart';
import '../../screens/emergency/sos_screen.dart';
import '../../screens/medicines/medicines_screen.dart';
import '../../screens/mental/breathing_screen.dart';
import '../../screens/mental/crisis_screen.dart';
import '../../screens/mental/mood_screen.dart';
import '../../screens/mental/screening_screen.dart';
import '../../screens/modules/feature_form_screen.dart';
import '../../screens/modules/feature_screen.dart';
import '../../screens/records/activity_screen.dart';
import '../../screens/settings/consent_screen.dart';
import '../../screens/symptoms/symptom_checker_screen.dart';

/// Which screen opens for each of the 50 features.
Widget screenForFeature(int number) {
  switch (number) {
    // Symptom checker covers symptoms, follow-up questions, prediction, triage,
    // test suggestions and the "Why this result?" explanation.
    case 1 || 2 || 3 || 4 || 5 || 46:
      return const SymptomCheckerScreen();
    case 12:
      return const SosScreen();
    case 16:
      return const ScreeningScreen();
    case 18:
      return const ScreeningScreen(initialInstrument: 'gad7');
    case 22:
      return const BreathingScreen();
    case 24:
      return const MoodScreen();
    case 25:
      return const CrisisScreen();
    case 32 || 33 || 35 || 36:
      return const MedicinesScreen();
    case 48:
      return const ConsentScreen();
    case 49:
      return const ActivityScreen();
  }
  if (featureForms.containsKey(number)) return FeatureFormScreen(number: number);
  return FeatureScreen(number: number);
}
