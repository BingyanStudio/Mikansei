import 'package:flutter/material.dart';

class KraftTheme {
  static const paper = Color(0xFFF5EDDE);
  static const brown = Color(0xFF805734);
  static const ink = Color(0xFF38291E);
  static ThemeData build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: brown,
      brightness: brightness,
      primary: dark ? const Color(0xFFDFBB91) : brown,
      onPrimary: dark ? ink : const Color(0xFFFFF8EE),
      primaryContainer: dark
          ? const Color(0xFF57402C)
          : const Color(0xFFE5CFB2),
      onPrimaryContainer: dark ? const Color(0xFFF1E3D1) : ink,
      secondaryContainer: dark
          ? const Color(0xFF49392D)
          : const Color(0xFFEBDBC3),
      onSecondaryContainer: dark ? const Color(0xFFF1E3D1) : ink,
      surface: dark ? const Color(0xFF241E19) : paper,
      onSurface: dark ? const Color(0xFFF1E3D1) : ink,
      onSurfaceVariant: dark
          ? const Color(0xFFCBB89E)
          : const Color(0xFF68503A),
      surfaceContainer: dark
          ? const Color(0xFF362B22)
          : const Color(0xFFEDE0CD),
      surfaceContainerLow: dark
          ? const Color(0xFF2E251E)
          : const Color(0xFFFFF8ED),
      outline: dark ? const Color(0xFF9A826A) : const Color(0xFF9B7D5C),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        centerTitle: false,
        elevation: 0,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.primary.withValues(alpha: .16),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outline.withValues(alpha: .35)),
        ),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: scheme.outline.withValues(alpha: .35)),
        labelStyle: TextStyle(color: scheme.onSurface),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outline.withValues(alpha: .2),
      ),
      textTheme: Typography.material2021().black.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
    );
  }
}
