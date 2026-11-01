import 'package:flutter/material.dart';

import 'domain.dart';

/// Flutter counterpart to the native Mikansei theme.
class MikanseiTheme {
  static const Color _lightAccent = Color(0xFF1F634C);
  static const Color _darkAccent = Color(0xFF7AD9B3);
  static const Color _lightPage = Color(0xFFF1F3F1);
  static const Color _darkPage = Color(0xFF1E2220);
  static const Color _lightCard = Color(0xFFFFFFFF);
  static const Color _darkCard = Color(0xFF2A302D);

  static ThemeData build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final palette = MikanseiPalette.forBrightness(brightness);
    final scheme = ColorScheme.fromSeed(
      seedColor: palette.accent,
      brightness: brightness,
      primary: palette.accent,
      onPrimary: dark ? const Color(0xFF17372B) : Colors.white,
      primaryContainer: dark
          ? const Color(0xFF254B3D)
          : const Color(0xFFDCECE4),
      onPrimaryContainer: dark
          ? const Color(0xFFD5F3E5)
          : const Color(0xFF17392C),
      secondary: dark ? const Color(0xFFC4CCC7) : const Color(0xFF606963),
      onSecondary: dark ? const Color(0xFF252B28) : Colors.white,
      secondaryContainer: dark
          ? const Color(0xFF39413D)
          : const Color(0xFFE5E9E6),
      onSecondaryContainer: dark
          ? const Color(0xFFE0E6E2)
          : const Color(0xFF29312C),
      tertiary: palette.homework,
      surface: palette.page,
      onSurface: dark ? const Color(0xFFE8ECE9) : const Color(0xFF202521),
      onSurfaceVariant: dark
          ? const Color(0xFFBAC3BD)
          : const Color(0xFF606963),
      surfaceContainer: dark
          ? const Color(0xFF343B37)
          : const Color(0xFFE7EBE8),
      surfaceContainerLow: palette.card,
      surfaceContainerHigh: dark
          ? const Color(0xFF3B433E)
          : const Color(0xFFE1E6E2),
      outline: dark ? const Color(0xFF87928B) : const Color(0xFF89938D),
      error: palette.error,
      onError: dark ? const Color(0xFF5F1412) : Colors.white,
      errorContainer: dark ? const Color(0xFF5F2421) : const Color(0xFFFFDAD6),
      onErrorContainer: dark
          ? const Color(0xFFFFDAD6)
          : const Color(0xFF410002),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      extensions: <ThemeExtension<dynamic>>[palette],
      scaffoldBackgroundColor: palette.page,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: palette.page,
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
        backgroundColor: palette.page,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 64,
        indicatorColor: scheme.primary.withValues(alpha: .18),
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
        color: palette.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outline.withValues(alpha: .12)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        side: BorderSide(color: scheme.outline.withValues(alpha: .6)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.card,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
        prefixIconColor: scheme.onSurfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outline.withValues(alpha: .28)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outline.withValues(alpha: .28)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
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

/// Semantic colors shared by cards, calendars, planning, and editors.
class MikanseiPalette extends ThemeExtension<MikanseiPalette> {
  const MikanseiPalette({
    required this.accent,
    required this.warm,
    required this.homework,
    required this.card,
    required this.page,
    required this.secondary,
    required this.error,
    required this.track,
    required this.onAccent,
    required this.completed,
  });

  final Color accent;
  final Color warm;
  final Color homework;
  final Color card;
  final Color page;
  final Color secondary;
  final Color error;
  final Color track;
  final Color onAccent;
  final Color completed;

  static MikanseiPalette of(BuildContext context) =>
      Theme.of(context).extension<MikanseiPalette>() ??
      forBrightness(Theme.of(context).brightness);

  static MikanseiPalette forBrightness(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final accent = dark
        ? MikanseiTheme._darkAccent
        : MikanseiTheme._lightAccent;
    final page = dark ? MikanseiTheme._darkPage : MikanseiTheme._lightPage;
    final card = dark ? MikanseiTheme._darkCard : MikanseiTheme._lightCard;
    final secondary = dark ? const Color(0xFFBEC8C1) : const Color(0xFF626A65);
    return MikanseiPalette(
      accent: accent,
      warm: dark ? const Color(0xFFE7A36A) : const Color(0xFFC26E2E),
      homework: dark ? const Color(0xFFB6BEFF) : const Color(0xFF4F5CB8),
      card: card,
      page: page,
      secondary: secondary,
      error: dark ? const Color(0xFFFFB4AB) : const Color(0xFFB3261E),
      track: dark ? const Color(0xFF363D39) : const Color(0xFFE5E9E6),
      onAccent: dark ? const Color(0xFF17372B) : Colors.white,
      completed: secondary,
    );
  }

  Color entryKind(EntryKind kind) => switch (kind) {
    EntryKind.task || EntryKind.schedule => accent,
    EntryKind.homework => homework,
    EntryKind.note => warm,
  };

  bool _isDoing(Entry entry) => entry.startedAt != null && !entry.completed;

  Color entryBackground(Entry entry) =>
      _isDoing(entry) ? accent.withValues(alpha: .14) : card;

  Color entryBorder(Entry entry) =>
      _isDoing(entry) ? accent : Colors.transparent;

  @override
  MikanseiPalette copyWith({
    Color? accent,
    Color? warm,
    Color? homework,
    Color? card,
    Color? page,
    Color? secondary,
    Color? error,
    Color? track,
    Color? onAccent,
    Color? completed,
  }) => MikanseiPalette(
    accent: accent ?? this.accent,
    warm: warm ?? this.warm,
    homework: homework ?? this.homework,
    card: card ?? this.card,
    page: page ?? this.page,
    secondary: secondary ?? this.secondary,
    error: error ?? this.error,
    track: track ?? this.track,
    onAccent: onAccent ?? this.onAccent,
    completed: completed ?? this.completed,
  );

  @override
  MikanseiPalette lerp(covariant MikanseiPalette? other, double t) {
    if (other == null) return this;
    return MikanseiPalette(
      accent: Color.lerp(accent, other.accent, t)!,
      warm: Color.lerp(warm, other.warm, t)!,
      homework: Color.lerp(homework, other.homework, t)!,
      card: Color.lerp(card, other.card, t)!,
      page: Color.lerp(page, other.page, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      error: Color.lerp(error, other.error, t)!,
      track: Color.lerp(track, other.track, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      completed: Color.lerp(completed, other.completed, t)!,
    );
  }
}

/// Compatibility alias for existing app wiring and callers.
class KraftTheme {
  static const paper = Color(0xFFF1F3F1);
  static const brown = Color(0xFF1F634C);
  static const ink = Color(0xFF202521);
  static ThemeData build(Brightness brightness) =>
      MikanseiTheme.build(brightness);
}
