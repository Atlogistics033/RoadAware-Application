import 'package:flutter/material.dart';

class AppTheme {
  // Theme Color Palette
  static const Color primaryBlue = Color(0xFF0096C7);
  static const Color secondaryBlue = Color(0xFF48CAE4);
  static const Color blackText = Color(0xFF000000);
  static const Color whiteBg = Color(0xFFFFFFFF);
  static const Color lightGray = Color(0xFFF8F9FA);
  static const Color darkGray = Color(0xFF343A40);

  // Gradient definitions
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [secondaryBlue, primaryBlue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient whiteGradient = LinearGradient(
    colors: [whiteBg, lightGray],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Box Shadows for Glassmorphism/Premium Cards
  static List<BoxShadow> softShadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.06),
      blurRadius: 15,
      offset: const Offset(0, 5),
    ),
  ];

  static List<BoxShadow> intenseShadow = [
    BoxShadow(
      color: primaryBlue.withValues(alpha: 0.2),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ];

  // ThemeData configuration
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: whiteBg,
      primaryColor: primaryBlue,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        primary: primaryBlue,
        secondary: secondaryBlue,
        surface: whiteBg,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: blackText,
          fontSize: 28.0,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
        headlineMedium: TextStyle(
          color: blackText,
          fontSize: 22.0,
          fontWeight: FontWeight.bold,
        ),
        titleLarge: TextStyle(
          color: blackText,
          fontSize: 18.0,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(
          color: blackText,
          fontSize: 16.0,
        ),
        bodyMedium: TextStyle(
          color: darkGray,
          fontSize: 14.0,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightGray,
        hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
        labelStyle: const TextStyle(color: blackText, fontSize: 14, fontWeight: FontWeight.w500),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: Color(0xFFE9ECEF), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: primaryBlue, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: whiteBg,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          elevation: 0,
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
