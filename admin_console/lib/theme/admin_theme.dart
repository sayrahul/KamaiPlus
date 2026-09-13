import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Modern Enterprise / Fintech SaaS design tokens for KamaiPlus Admin.
/// Blends obsidian backgrounds, emerald accents, and crisp typography.
class AdminColors {
  // Dark Enterprise Palette
  static const bgDark = Color(0xFF090D16);
  static const bgSidebar = Color(0xFF0D1322);
  static const bgCard = Color(0xFF141D30);
  static const bgElevated = Color(0xFF1B263E);
  static const borderDark = Color(0xFF222F4C);
  static const borderLight = Color(0x1FFFFFFF);
  
  // High-contrast Text
  static const textWhite = Color(0xFFF8FAFC);
  static const textMuted = Color(0xFF94A3B8);
  static const textFaint = Color(0xFF64748B);
  
  // Mapped for complete dark theme compatibility across all screens
  static const ink = Color(0xFFF8FAFC);
  static const inkMuted = Color(0xFF94A3B8);
  static const inkFaint = Color(0xFF64748B);
  static const surface = Color(0xFF141D30);
  static const surfaceSunken = Color(0xFF090D16);
  static const border = Color(0xFF222F4C);
  
  // Brand Emerald
  static const accent = Color(0xFF10B981);
  static const accentGlow = Color(0xFF059669);
  static const accentSoft = Color(0xFF064E3B);
  static const accentBorder = Color(0xFF34D399);

  // Status Alerts
  static const amber = Color(0xFFF59E0B);
  static const amberSoft = Color(0xFF451A03);
  static const red = Color(0xFFEF4444);
  static const redSoft = Color(0xFF450A0A);
  static const redBorder = Color(0xFFF87171);
  static const violet = Color(0xFF8B5CF6);
  static const violetSoft = Color(0xFF2E1065);
  static const blue = Color(0xFF3B82F6);
  static const blueSoft = Color(0xFF1E3A8A);
}

class AdminTheme {
  static ThemeData get dark {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AdminColors.accent,
        brightness: Brightness.dark,
        surface: AdminColors.bgCard,
      ),
      scaffoldBackgroundColor: AdminColors.bgDark,
      fontFamily: GoogleFonts.inter().fontFamily,
    );
    return base.copyWith(
      textTheme: GoogleFonts.interTextTheme(base.textTheme),
      appBarTheme: const AppBarTheme(
        backgroundColor: AdminColors.bgSidebar,
        foregroundColor: AdminColors.textWhite,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: AdminColors.bgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AdminColors.borderDark),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AdminColors.bgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AdminColors.borderDark),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AdminColors.bgElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AdminColors.borderDark),
        ),
        textStyle: const TextStyle(color: AdminColors.textWhite, fontSize: 13),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStateProperty.all(AdminColors.bgElevated),
        dataRowColor: WidgetStateProperty.all(AdminColors.bgCard),
        dividerThickness: 1,
        headingTextStyle: const TextStyle(
          color: AdminColors.textWhite,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
        dataTextStyle: const TextStyle(
          color: AdminColors.textWhite,
          fontSize: 13,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AdminColors.bgSidebar,
        indicatorColor: AdminColors.accentSoft,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(color: AdminColors.accent, fontSize: 11, fontWeight: FontWeight.w700);
          }
          return const TextStyle(color: AdminColors.textMuted, fontSize: 11);
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AdminColors.bgElevated,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: const TextStyle(color: AdminColors.textFaint, fontSize: 13),
        labelStyle: const TextStyle(color: AdminColors.textMuted, fontSize: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AdminColors.borderDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AdminColors.borderDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AdminColors.accent, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AdminColors.accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
    );
  }

  // Light fallback
  static ThemeData get light => dark;

  static TextStyle heading(double size, {Color color = AdminColors.textWhite}) =>
      GoogleFonts.plusJakartaSans(fontSize: size, fontWeight: FontWeight.w800, color: color, letterSpacing: -0.5);

  static TextStyle sub(double size, {Color color = AdminColors.textMuted}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: FontWeight.w500, color: color);

  static TextStyle mono(double size, {Color color = AdminColors.textWhite}) =>
      GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: FontWeight.w600, color: color);
}

