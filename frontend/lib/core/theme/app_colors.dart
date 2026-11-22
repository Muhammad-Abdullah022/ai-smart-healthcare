import 'package:flutter/material.dart';

/// All colors used in the app, in one place.
/// Palette "Forest & Lime": fresh green #40916C for actions, deep forest #1B4332 for text and headers,
/// soft green #E3F4EA tints on a light #F4F8F5 background — font Poppins.
class AppColors {
  AppColors._();

  // The four brand colours.
  static const Color mint = Color(0xFFE3F4EA); // soft green tint
  static const Color softGreen = Color(0xFFB7E4C7);
  static const Color green = Color(0xFF40916C); // fresh green (main action colour)
  static const Color deep = Color(0xFF1B4332); // deep forest green

  static const Color primary = deep; // titles, dark buttons
  static const Color primaryDeep = Color(0xFF0F2A1F); // header gradient end
  static const Color accent = green; // actions, highlights
  static const Color background = Color(0xFFF4F8F5);
  static const Color card = Color(0xFFFFFFFF);
  static const Color text = Color(0xFF1C2B24);
  static const Color textMuted = Color(0xFF64748B);
  static const Color border = Color(0xFFDDE8E1);
  static const Color warning = Color(0xFFF59E0B);
  static const Color critical = Color(0xFFDC2626);
  static const Color success = Color(0xFF059669); // stays green: "good / normal"

  // Light tints used behind icons and banners.
  static const Color accentTint = mint;
  static const Color primaryTint = Color(0xFFE8F0EB);
  static const Color warningTint = Color(0xFFFEF3C7);
  static const Color criticalTint = Color(0xFFFEE2E2);

  // One gentle colour per health module (strong, tint).
  static const Color diagnosis = green;
  static const Color diagnosisTint = mint;
  static const Color mind = Color(0xFF7C6BD9);
  static const Color mindTint = Color(0xFFEFECFB);
  static const Color medicine = Color(0xFFE29A2D);
  static const Color medicineTint = Color(0xFFFCF1DF);
  static const Color records = Color(0xFF2563EB);
  static const Color recordsTint = Color(0xFFE8F0FE);

  /// Soft shadow tinted with the deep brand colour, so cards feel lifted, not dirty.
  static const List<BoxShadow> softShadow = [
    BoxShadow(color: Color(0x141B4332), blurRadius: 24, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x0A1B4332), blurRadius: 4, offset: Offset(0, 1)),
  ];
}
