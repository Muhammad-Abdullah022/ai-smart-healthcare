import 'package:flutter/material.dart';

/// All colors used in the app, in one place.
/// Palette: #EAF9E7 (mint), #C0E6BA (soft green), #4CA771 (green), #013237 (deep teal) — font Poppins.
class AppColors {
  AppColors._();

  // The four brand colours.
  static const Color mint = Color(0xFFEAF9E7);
  static const Color softGreen = Color(0xFFC0E6BA);
  static const Color green = Color(0xFF4CA771);
  static const Color deep = Color(0xFF013237);

  static const Color primary = deep; // titles, dark buttons
  static const Color primaryDeep = Color(0xFF00242A); // header gradient end
  static const Color accent = green; // actions, highlights
  static const Color background = Color(0xFFF3FBF1);
  static const Color card = Color(0xFFFFFFFF);
  static const Color text = Color(0xFF0E2A2E);
  static const Color textMuted = Color(0xFF5E7470);
  static const Color border = Color(0xFFD7EBD3);
  static const Color warning = Color(0xFFF59E0B);
  static const Color critical = Color(0xFFDC2626);
  static const Color success = Color(0xFF2E8B57);

  // Light tints used behind icons and banners.
  static const Color accentTint = mint;
  static const Color primaryTint = Color(0xFFE1F0EC);
  static const Color warningTint = Color(0xFFFEF3C7);
  static const Color criticalTint = Color(0xFFFEE2E2);

  // One gentle colour per health module (strong, tint).
  static const Color diagnosis = green;
  static const Color diagnosisTint = mint;
  static const Color mind = Color(0xFF7C6BD9);
  static const Color mindTint = Color(0xFFEFECFB);
  static const Color medicine = Color(0xFFE29A2D);
  static const Color medicineTint = Color(0xFFFCF1DF);
  static const Color records = Color(0xFF2F7F8A);
  static const Color recordsTint = Color(0xFFE0F1F2);

  /// Soft shadow tinted with the deep brand colour, so cards feel lifted, not dirty.
  static const List<BoxShadow> softShadow = [
    BoxShadow(color: Color(0x14013237), blurRadius: 24, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x0A013237), blurRadius: 4, offset: Offset(0, 1)),
  ];
}
