import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Shared color/type tokens for the admin console — same palette language
/// as the KamaiPlus POS app (slate ink, emerald accent) so the two feel
/// like one product, but tuned for a data-dense desktop screen rather than
/// a phone: tighter type scale, table-friendly monospace for figures.
class AdminColors {
  static const ink = Color(0xFF0F172A);
  static const inkMuted = Color(0xFF64748B);
  static const inkFaint = Color(0xFF94A3B8);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceSunken = Color(0xFFF8FAFC);
  static const border = Color(0xFFE2E8F0);
  static const accent = Color(0xFF059669);
  static const accentSoft = Color(0xFFECFDF5);
  static const accentBorder = Color(0xFFA7F3D0);
  static const amber = Color(0xFFD97706);
  static const amberSoft = Color(0xFFFEF3C7);
  static const red = Color(0xFFDC2626);
  static const redSoft = Color(0xFFFEE2E2);
  static const violet = Color(0xFF7C3AED);
  static const violetSoft = Color(0xFFF5F3FF);
}

class AdminTheme {
  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: AdminColors.accent, brightness: Brightness.light),
      scaffoldBackgroundColor: AdminColors.surfaceSunken,
      fontFamily: GoogleFonts.inter().fontFamily,
    );
    return base.copyWith(
      textTheme: GoogleFonts.interTextTheme(base.textTheme),
      appBarTheme: const AppBarTheme(
        backgroundColor: AdminColors.surface,
        foregroundColor: AdminColors.ink,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: AdminColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AdminColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AdminColors.surfaceSunken,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AdminColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AdminColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AdminColors.accent, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AdminColors.ink,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
      ),
    );
  }

  static TextStyle heading(double size) => GoogleFonts.outfit(fontSize: size, fontWeight: FontWeight.w800, color: AdminColors.ink);
  static TextStyle mono(double size) => GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: FontWeight.w600, color: AdminColors.ink);
}
