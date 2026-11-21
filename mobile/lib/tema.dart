import 'package:flutter/material.dart';

/// Tema visual pensado para adultos mayores (RNF01):
/// letra grande (mínimo 18 pt en acciones), alto contraste y botones amplios.
class TemaMediCheck {
  static const Color azul = Color(0xFF0B5394);
  static const Color verde = Color(0xFF1B7F3B);
  static const Color rojo = Color(0xFFB3261E);
  static const Color ambar = Color(0xFFB26A00);
  static const Color fondo = Color(0xFFF5F8FC);

  static ThemeData get claro {
    final esquema = ColorScheme.fromSeed(seedColor: azul, primary: azul, surface: Colors.white);
    final base = ThemeData(useMaterial3: true, colorScheme: esquema, scaffoldBackgroundColor: fondo);
    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineSmall: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Color(0xFF102A43)),
        titleLarge: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF102A43)),
        titleMedium: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: Color(0xFF102A43)),
        bodyLarge: const TextStyle(fontSize: 18, color: Color(0xFF243B53)),
        bodyMedium: const TextStyle(fontSize: 16, color: Color(0xFF334E68)),
        labelLarge: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: azul,
        foregroundColor: Colors.white,
        centerTitle: false,
        titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          textStyle: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        labelStyle: const TextStyle(fontSize: 18),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 1,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        contentTextStyle: TextStyle(fontSize: 17),
      ),
    );
  }
}
