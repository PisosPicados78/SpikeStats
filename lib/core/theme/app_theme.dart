import 'package:flutter/material.dart';

class AppTheme {
  // Paleta institucional UCC.
  static const Color blueDiversity = Color(0xFF00ACC9);
  static const Color greenSolidarity = Color(0xFF80BA27);
  static const Color greenFreedom = Color(0xFFCAD400);
  static const Color blueFounders = Color(0xFF132740);
  static const Color grayEquity = Color(0xFF5F5E5E);

  static const Color courtWood = Color(0xFFEAF5F7);
  static const Color courtGreen = greenSolidarity;
  static const Color courtLine = Colors.white;

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: blueFounders,
        onPrimary: Colors.white,
        secondary: blueDiversity,
        onSecondary: blueFounders,
        tertiary: greenSolidarity,
        onTertiary: blueFounders,
        surface: Color(0xFFF8FBFC),
        onSurface: blueFounders,
        error: Color(0xFFB3261E),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: blueFounders,
        foregroundColor: Colors.white,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: blueDiversity,
        foregroundColor: blueFounders,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: blueFounders,
        unselectedItemColor: grayEquity,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.dark(
        primary: blueDiversity,
        onPrimary: blueFounders,
        secondary: greenSolidarity,
        onSecondary: blueFounders,
        tertiary: greenFreedom,
        onTertiary: blueFounders,
        surface: Color(0xFF0D1D2D),
        onSurface: Color(0xFFF1F7F8),
        error: Color(0xFFFFB4AB),
      ),
      scaffoldBackgroundColor: const Color(0xFF0D1D2D),
      appBarTheme: const AppBarTheme(
        backgroundColor: blueFounders,
        foregroundColor: Colors.white,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: blueDiversity,
        foregroundColor: blueFounders,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: blueFounders,
        selectedItemColor: blueDiversity,
        unselectedItemColor: Color(0xFFC4CED4),
      ),
    );
  }
}
