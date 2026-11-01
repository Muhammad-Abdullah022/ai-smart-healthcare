import 'package:flutter/material.dart';

/// All colors used in the app, in one place.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF16324F); // navy
  static const Color primaryDeep = Color(0xFF0F2438); // header gradient end
  static const Color accent = Color(0xFF14B8A6); // healthcare teal
  static const Color background = Color(0xFFF5F8FC);
  static const Color card = Color(0xFFFFFFFF);
  static const Color text = Color(0xFF1F2937);
  static const Color textMuted = Color(0xFF6B7280);
  static const Color border = Color(0xFFE2E8F0);
  static const Color warning = Color(0xFFF59E0B);
  static const Color critical = Color(0xFFDC2626);
  static const Color success = Color(0xFF16A34A);

  // Light tints used behind icons and banners.
  static const Color accentTint = Color(0xFFE6F7F5);
  static const Color primaryTint = Color(0xFFE8EEF5);
  static const Color warningTint = Color(0xFFFEF3C7);
  static const Color criticalTint = Color(0xFFFEE2E2);

  // One gentle colour per health module (strong, tint).
  static const Color diagnosis = Color(0xFF14B8A6);
  static const Color diagnosisTint = Color(0xFFE3F6F3);
  static const Color mind = Color(0xFF7C6BD9);
  static const Color mindTint = Color(0xFFEFECFB);
  static const Color medicine = Color(0xFFE29A2D);
  static const Color medicineTint = Color(0xFFFCF1DF);
  static const Color records = Color(0xFF3B82C4);
  static const Color recordsTint = Color(0xFFE5EFF9);

  /// Soft shadow tinted with navy instead of grey, so cards feel lifted, not dirty.
  static const List<BoxShadow> softShadow = [
    BoxShadow(color: Color(0x1416324F), blurRadius: 24, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x0A16324F), blurRadius: 4, offset: Offset(0, 1)),
  ];
}
