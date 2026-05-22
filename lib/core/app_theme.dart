import 'package:flutter/material.dart';

/// Единая тема приложения.
///
/// Все базовые цвета, стили карточек и Material 3 настройки лежат здесь,
/// чтобы UI был консистентным и чтобы экраны не дублировали оформление.
class AppTheme {
  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2563EB),
      brightness: Brightness.light,
    );

    return ThemeData(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFFF7F8FA),
      useMaterial3: true,
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    );
  }
}
