import 'package:flutter/material.dart';

import '../modules/feature_form_screen.dart';

/// Records tab: your health records (feature 38) — add and see them in one place.
class RecordsScreen extends StatelessWidget {
  const RecordsScreen({super.key});

  @override
  Widget build(BuildContext context) => const FeatureFormScreen(number: 38);
}
