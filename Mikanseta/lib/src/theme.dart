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
          : const Color(0xFFFFFDF8),
      outline: dark ? const Color(0xFF9A826A) : const Color(0xFF9B7D5C),
      // 浅色用更醒目的暖红；深色配浅暖红与深红棕文字，保持可读对比。
      error: dark ? const Color(0xFFFFB4A5) : const Color(0xFFB3402F),
      onError: dark ? const Color(0xFF5C1A0F) : const Color(0xFFFFF8EE),
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
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 64,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 26,
          fontWeight: FontWeight.w700,
          letterSpacing: .2,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 64,
        indicatorColor: scheme.primary.withValues(alpha: .22),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11.5,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? scheme.onSurface
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          // 极浅描边让亮卡片与纸面分离。
          side: BorderSide(color: scheme.outline.withValues(alpha: .12)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        side: BorderSide(color: scheme.outline.withValues(alpha: .6)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
        prefixIconColor: scheme.onSurfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(
            color: scheme.primary.withValues(alpha: .45),
            width: 1.2,
          ),
        ),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: scheme.outline.withValues(alpha: .3)),
        labelStyle: TextStyle(color: scheme.onSurface, fontSize: 13),
        shape: const StadiumBorder(),
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
