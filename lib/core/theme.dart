import 'package:flutter/material.dart';

/// Grub brand palette – taken from the Grub logo.
class GrubColors {
  static const green = Color(0xFF3DA832); // fresh green (primary)
  static const greenBright = Color(0xFF7CC814); // leaf highlight
  static const greenDark = Color(0xFF145A1E); // headings
  static const greenLight = Color(0xFFEFF8EA); // light secondary background
  static const greenTint = Color(0xFFDDF0D3);
  static const orange = Color(0xFFFF8A1C); // the "G" in the logo – used sparingly
  static const ink = Color(0xFF1D2A1F);
  static const muted = Color(0xFF6B7A6D);
  static const line = Color(0xFFE6ECE4);
  static const danger = Color(0xFFD64545);
  static const warning = Color(0xFFB7791F);
  static const white = Colors.white;
}

class GrubTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: GrubColors.green,
      primary: GrubColors.green,
      secondary: GrubColors.orange,
      surface: Colors.white,
      brightness: Brightness.light,
    );
    const radius = 18.0;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.white,
      fontFamily: null, // system font: SF on iOS, Roboto on Android
      textTheme: const TextTheme(
        displaySmall: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: GrubColors.ink, letterSpacing: -1),
        headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: GrubColors.greenDark, letterSpacing: -0.4),
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: GrubColors.greenDark),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: GrubColors.ink),
        bodyLarge: TextStyle(fontSize: 16, color: GrubColors.ink),
        bodyMedium: TextStyle(fontSize: 14, color: GrubColors.ink),
        bodySmall: TextStyle(fontSize: 12, color: GrubColors.muted),
        labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        foregroundColor: GrubColors.greenDark,
        titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: GrubColors.greenDark),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: GrubColors.green,
          foregroundColor: Colors.white,
          disabledBackgroundColor: GrubColors.green.withValues(alpha: 0.35),
          disabledForegroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: GrubColors.greenDark,
          minimumSize: const Size.fromHeight(50),
          side: const BorderSide(color: GrubColors.line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: GrubColors.greenLight,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: GrubColors.green, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: GrubColors.greenLight,
        selectedColor: GrubColors.greenDark,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: GrubColors.greenTint,
        surfaceTintColor: Colors.white,
        labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
