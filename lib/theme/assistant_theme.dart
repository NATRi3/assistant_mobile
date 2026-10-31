import 'package:flutter/material.dart';

import 'token_loader.dart';

ThemeData assistantTheme(DesignTokens tokens, Brightness brightness) {
  Color c(String name) => tokens.color(brightness, name);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: c('primary'),
        brightness: brightness,
      ).copyWith(
        primary: c('primary'),
        onPrimary: c('onPrimary'),
        surface: c('surface'),
        onSurface: c('text'),
        onSurfaceVariant: c('muted'),
        outline: c('border'),
        error: c('danger'),
      );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c('background'),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(fontSize: 16, height: 1.5),
      bodyMedium: TextStyle(fontSize: 16, height: 1.5),
      titleLarge: TextStyle(fontSize: 24, height: 1.3),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 56),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.all(16),
      ),
    ),
  );
}
