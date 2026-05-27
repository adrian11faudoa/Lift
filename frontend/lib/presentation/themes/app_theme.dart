import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // ─── Brand Colors ────────────────────────────────────────────
  static const Color primaryBlue    = Color(0xFF2563EB);
  static const Color primaryOrange  = Color(0xFFEA580C);
  static const Color accentGreen    = Color(0xFF16A34A);
  static const Color accentRed      = Color(0xFFDC2626);
  static const Color accentPurple   = Color(0xFF7C3AED);

  // Dark palette
  static const Color darkBg         = Color(0xFF0A0A0F);
  static const Color darkSurface    = Color(0xFF111118);
  static const Color darkCard       = Color(0xFF1A1A25);
  static const Color darkBorder     = Color(0xFF2A2A35);
  static const Color darkText       = Color(0xFFF1F1F3);
  static const Color darkSubtext    = Color(0xFF8B8B9A);

  // Light palette
  static const Color lightBg        = Color(0xFFF8F8FC);
  static const Color lightSurface   = Color(0xFFFFFFFF);
  static const Color lightCard      = Color(0xFFF1F1F8);
  static const Color lightBorder    = Color(0xFFE2E2EE);
  static const Color lightText      = Color(0xFF0A0A0F);
  static const Color lightSubtext   = Color(0xFF6B6B7A);

  // ─── Dark Theme ──────────────────────────────────────────────
  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.dark(
      primary:        primaryBlue,
      primaryContainer: primaryBlue.withOpacity(0.2),
      secondary:      primaryOrange,
      secondaryContainer: primaryOrange.withOpacity(0.2),
      tertiary:       accentGreen,
      surface:        darkSurface,
      background:     darkBg,
      error:          accentRed,
      onPrimary:      Colors.white,
      onSecondary:    Colors.white,
      onSurface:      darkText,
      onBackground:   darkText,
      outline:        darkBorder,
    ),
    scaffoldBackgroundColor: darkBg,
    fontFamily: 'Inter',

    // AppBar
    appBarTheme: const AppBarTheme(
      backgroundColor: darkBg,
      elevation: 0,
      scrolledUnderElevation: 0,
      iconTheme: IconThemeData(color: darkText),
      titleTextStyle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: darkText,
      ),
    ),

    // Cards
    cardTheme: CardTheme(
      color: darkCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: darkBorder, width: 1),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    ),

    // Buttons
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: darkText,
        side: const BorderSide(color: darkBorder),
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryBlue,
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    // Input fields
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkCard,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: darkBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: darkBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primaryBlue, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: accentRed),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      labelStyle: const TextStyle(color: darkSubtext),
      hintStyle: const TextStyle(color: darkSubtext),
    ),

    // Bottom nav
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: darkSurface,
      indicatorColor: primaryBlue.withOpacity(0.15),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: primaryBlue,
          );
        }
        return TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          color: darkSubtext,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: primaryBlue);
        }
        return const IconThemeData(color: darkSubtext);
      }),
    ),

    // BottomSheet
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: darkSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),

    // Divider
    dividerTheme: const DividerThemeData(
      color: darkBorder,
      thickness: 1,
      space: 1,
    ),

    // Chip
    chipTheme: ChipThemeData(
      backgroundColor: darkCard,
      selectedColor: primaryBlue.withOpacity(0.2),
      labelStyle: const TextStyle(fontFamily: 'Inter', fontSize: 13),
      side: const BorderSide(color: darkBorder),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),

    // Text
    textTheme: const TextTheme(
      displayLarge:  TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: darkText),
      displayMedium: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: darkText),
      headlineLarge: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: darkText),
      headlineMedium:TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: darkText),
      titleLarge:    TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: darkText),
      titleMedium:   TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: darkText),
      bodyLarge:     TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w400, color: darkText),
      bodyMedium:    TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w400, color: darkText),
      bodySmall:     TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w400, color: darkSubtext),
      labelLarge:    TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: darkText),
    ),
  );

  // ─── Light Theme ─────────────────────────────────────────────
  static ThemeData get lightTheme => darkTheme.copyWith(
    brightness: Brightness.light,
    colorScheme: ColorScheme.light(
      primary:        primaryBlue,
      primaryContainer: primaryBlue.withOpacity(0.1),
      secondary:      primaryOrange,
      surface:        lightSurface,
      background:     lightBg,
      error:          accentRed,
      onSurface:      lightText,
      onBackground:   lightText,
      outline:        lightBorder,
    ),
    scaffoldBackgroundColor: lightBg,
    appBarTheme: const AppBarTheme(
      backgroundColor: lightBg,
      elevation: 0,
      scrolledUnderElevation: 0,
      iconTheme: IconThemeData(color: lightText),
      titleTextStyle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: lightText,
      ),
    ),
    cardTheme: CardTheme(
      color: lightSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: lightBorder, width: 1),
      ),
    ),
  );
}

// Theme mode provider
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.dark) {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('dark_mode') ?? true;
    state = isDark ? ThemeMode.dark : ThemeMode.light;
  }

  Future<void> toggle() async {
    state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', state == ThemeMode.dark);
  }
}
