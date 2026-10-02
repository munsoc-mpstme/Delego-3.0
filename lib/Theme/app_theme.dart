import 'package:flutter/material.dart';

import '../widgets/neon.dart';

// Brand colour: MumbaiMUN '26 electric blue.
const kBrandSeed = Neon.blue;

ThemeData _build(ColorScheme scheme, {required AppTokens tokens}) {
  final onSurface = scheme.onSurface;
  return ThemeData(
    useMaterial3: true,
    fontFamily: Neon.font,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    extensions: [tokens],
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: Neon.font,
        fontWeight: FontWeight.w900,
        fontSize: 18,
        letterSpacing: 0.8,
        color: onSurface,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        textStyle: const TextStyle(
            fontFamily: Neon.font, fontWeight: FontWeight.w900, letterSpacing: 0.6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        textStyle: const TextStyle(
            fontFamily: Neon.font, fontWeight: FontWeight.w900, letterSpacing: 0.6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.tertiary, width: 2),
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerHighest,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
  );
}

// --- THEME DATA DEFINITIONS ---

ThemeData getLightTheme() {
  const scheme = ColorScheme.light(
    primary: Neon.blue,
    onPrimary: Neon.lime,
    secondary: Neon.pink,
    onSecondary: Neon.yellow,
    tertiary: Neon.violet,
    surface: Color(0xFFF2F4FF),
    onSurface: Neon.navy,
    surfaceContainerHighest: Color(0xFFE2E6FF),
    surfaceContainerHigh: Color(0xFFFFFFFF),
    outlineVariant: Color(0xFFC3C9F5),
    error: Color(0xFFD7263D),
  );
  return _build(scheme,
      tokens: const AppTokens(success: Color(0xFF1B9E5A), warning: Color(0xFFE0A100)));
}

ThemeData getDarkTheme() {
  const scheme = ColorScheme.dark(
    primary: Neon.blue,
    onPrimary: Neon.lime,
    secondary: Neon.pink,
    onSecondary: Neon.yellow,
    tertiary: Neon.lime,
    surface: Neon.black,
    onSurface: Colors.white,
    surfaceContainerHighest: Color(0xFF1C1C1E),
    surfaceContainerHigh: Color(0xFF141414),
    outlineVariant: Color(0xFF2E2E30),
    primaryContainer: Color(0xFF1B2A9E),
    onPrimaryContainer: Colors.white,
    error: Color(0xFFFF5470),
  );
  return _build(scheme,
      tokens: const AppTokens(success: Neon.green, warning: Neon.yellow));
}

// --- THEME EXTENSION (Optional: custom tokens) ---

class AppTokens extends ThemeExtension<AppTokens> {
  final Color success;
  final Color warning;

  const AppTokens({required this.success, required this.warning});

  @override
  AppTokens copyWith({Color? success, Color? warning}) =>
      AppTokens(success: success ?? this.success, warning: warning ?? this.warning);

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    return AppTokens(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }
}
