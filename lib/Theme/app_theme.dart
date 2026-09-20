import 'package:flutter/material.dart';

// Brand seed color (purple)
const kBrandSeed = Color(0xFF9C1BFF); // The exact brand color

// --- THEME DATA DEFINITIONS ---

ThemeData getLightTheme() {
  // FIX: Manually create a ColorScheme.light to force the primary color.
  final myCustomLightColorScheme = ColorScheme.light(
    // Force the primary color to your exact brand color
    primary: kBrandSeed,

    // Define the color that will be used for text/icons *on* the primary color.
    // Since kBrandSeed is dark, white is the best contrasting color for text.
    onPrimary: Colors.white,
    surface: const Color(0xFFFAFAFA),
    onSurface: Colors.black87,

    // Default secondary, which M3 would normally generate a good complement for.
    // We'll use a slightly lighter purple or you can define your own secondary brand color here.
    secondary: const Color(0xFFB570FF),
  );

  return ThemeData(
      colorScheme: myCustomLightColorScheme, // Use the custom scheme
      useMaterial3: true,
      extensions: [
        const AppTokens(success: Color(0xFF388E3C), warning: Color(0xFFFBC02D))
      ]
  );
}

ThemeData getDarkTheme() {
  // FIX: Instead of using fromSeed, we manually create a ColorScheme
  // to force the primary color to be the *exact* kBrandSeed value.
  final myCustomDarkColorScheme = ColorScheme.dark(
    // Force the primary color to your exact brand color
    primary: kBrandSeed,

    // Use a very dark grey for surfaces (like Cards, Dialogs)
    surface: const Color(0xFF1A1A1A),

    // Define the color that will be used for text/icons *on* the primary color
    onPrimary: Colors.white,
    onSurface: Colors.white70,

    // --- NEW COLORS ADDED TO FIX TEAL BACKGROUNDS ---
    // Text fields often use container colors for their fill in dark mode.
    // Setting these to a subtle shade of purple or dark grey.
    primaryContainer: const Color(0xFF2A0050), // Dark subtle purple tint
    onPrimaryContainer: Colors.white,

    secondary: kBrandSeed, // Sometimes secondary is used, set it to the brand color
    secondaryContainer: const Color(0xFF1A1A1A), // Dark grey, blending with surface/background
    onSecondaryContainer: Colors.white70,
    // -------------------------------------------------

    // You can define other required colors here if they need to be specific:
    // tertiary: ...,
    error: Colors.red, // Added a standard error color
  );

  return ThemeData(
    colorScheme: myCustomDarkColorScheme,
    useMaterial3: true,
    // Define extensions for the dark theme as well
    extensions: [
      const AppTokens(success: Color(0xFF66BB6A), warning: Color(0xFFFFB300))
    ],
    // Optional: You can explicitly set the Scaffold background to be the
    // scheme's background color (which is now pure black)
    scaffoldBackgroundColor: myCustomDarkColorScheme.surface,

    // --- TEXT FIELD SPECIFIC TWEAKS ---
    // If the above color scheme change is not enough, you can specifically style the input decoration theme.
    inputDecorationTheme: InputDecorationTheme(
      fillColor: myCustomDarkColorScheme.surface, // Force the fill to use the dark surface color
      filled: true,
      border: const OutlineInputBorder(
        borderSide: BorderSide.none, // Hide the border for a cleaner look
        borderRadius: BorderRadius.all(Radius.circular(8.0)),
      ),
      hoverColor: const Color(0xFF2A0050), // Subtle hover color
    ),
    // ------------------------------------
  );
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
