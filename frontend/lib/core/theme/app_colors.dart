import 'package:flutter/material.dart';

/// All colors used in the app, in one place.
/// Palette "Royal Purple": violet #7C3AED for actions, deep purple #2A1B4D for text and headers,
/// soft lavender #F1EBFE tints on a light #F7F6FB background — font Poppins.
class AppColors {
  AppColors._();

  // The four brand colours.
  static const Color mint = Color(0xFFF1EBFE); // lavender tint
  static const Color softGreen = Color(0xFFDDD0FB);
  static const Color green = Color(0xFF7C3AED); // violet (main action colour)
  static const Color deep = Color(0xFF2A1B4D); // deep purple

  static const Color primary = deep; // titles, dark buttons
  static const Color primaryDeep = Color(0xFF1A1033); // header gradient end
  static const Color accent = green; // actions, highlights
  static const Color background = Color(0xFFF7F6FB);
  static const Color card = Color(0xFFFFFFFF);
  static const Color text = Color(0xFF1F1A2E);
  static const Color textMuted = Color(0xFF64748B);
  static const Color border = Color(0xFFE6E2EF);
  static const Color warning = Color(0xFFF59E0B);
  static const Color critical = Color(0xFFDC2626);
  static const Color success = Color(0xFF059669); // stays green: "good / normal"

  // Light tints used behind icons and banners.
  static const Color accentTint = mint;
  static const Color primaryTint = Color(0xFFEEEAF5);
  static const Color warningTint = Color(0xFFFEF3C7);
  static const Color criticalTint = Color(0xFFFEE2E2);

  // One gentle colour per health module (strong, tint).
  static const Color diagnosis = green;
  static const Color diagnosisTint = mint;
  static const Color mind = Color(0xFFDB5C9A);
  static const Color mindTint = Color(0xFFFCE9F3);
  static const Color medicine = Color(0xFFE29A2D);
  static const Color medicineTint = Color(0xFFFCF1DF);
  static const Color records = Color(0xFF2563EB);
  static const Color recordsTint = Color(0xFFE8F0FE);

  /// Soft shadow tinted with the deep brand colour, so cards feel lifted, not dirty.
  static const List<BoxShadow> softShadow = [
    BoxShadow(color: Color(0x142A1B4D), blurRadius: 24, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x0A2A1B4D), blurRadius: 4, offset: Offset(0, 1)),
  ];
}
