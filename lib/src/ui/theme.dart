import 'dart:ui';
import 'package:flutter/material.dart';

/// Design tokens, typography, and motion primitives for BMS Rider's
/// "Electro-Core" precision telemetry interface.
abstract final class VoltTokens {
  // 60% Neutral Dark Base
  static const Color bgCanvas = Color(0xFF070A0F);
  static const Color bgSurface = Color(0xFF0E141D);
  static const Color bgElevated = Color(0xFF151D29);
  static const Color bgInteractive = Color(0xFF1C2636);
  static const Color bgGlass = Color(0xCC111823);

  // 30% Text & Structural Contrast (WCAG >= 4.5:1 on surfaces)
  static const Color textPrimary = Color(0xFFF3F7FB);
  static const Color textSecondary = Color(0xFFA3B1C2);
  static const Color textMuted = Color(0xFF6E7E91);
  static const Color borderSubtle = Color(0x14FFFFFF);
  static const Color borderStrong = Color(0x26FFFFFF);

  // 10% Brand & Semantic Energy Accents
  static const Color voltMint = Color(0xFF00E5A0);
  static const Color voltMintBright = Color(0xFF38F8BD);
  static const Color voltCyan = Color(0xFF00C8FF);
  static const Color voltAmber = Color(0xFFFFB300);
  static const Color voltCoral = Color(0xFFFF4D5E);
  static const Color voltPurple = Color(0xFFA78BFA);

  // Spacing (4/8-pt grid)
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s48 = 48;

  // Radii
  static const double r8 = 8;
  static const double r12 = 12;
  static const double r16 = 16;
  static const double r20 = 20;
  static const double r24 = 24;
  static const double rPill = 999;

  // Motion curves & durations
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration medium = Duration(milliseconds: 320);
  static const Duration slow = Duration(milliseconds: 520);
  static const Curve curveOut = Curves.easeOutCubic;
  static const Curve curveSpring = Curves.easeOutBack;

  static Color socColor(num soc) {
    if (soc >= 50) return voltMint;
    if (soc >= 22) return voltAmber;
    return voltCoral;
  }

  static Color modeColor(String mode) {
    final m = mode.toLowerCase();
    if (m.contains('hyper')) return voltCoral;
    if (m.contains('sport')) return voltAmber;
    return voltMint;
  }

  static List<BoxShadow> softShadow([Color tint = voltMint]) => [
        BoxShadow(
          color: const Color(0xFF020408).withValues(alpha: 0.65),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: tint.withValues(alpha: 0.04),
          blurRadius: 24,
          spreadRadius: -4,
          offset: const Offset(0, 4),
        ),
      ];
}

/// Deliberate 4-tier typographic scale with tabular numeric discipline.
abstract final class VoltType {
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  // 1. Hero Telemetry Display (Speed, Primary SOC)
  static const TextStyle displayHero = TextStyle(
    fontSize: 64,
    fontWeight: FontWeight.w800,
    height: 1.0,
    letterSpacing: -2.0,
    color: VoltTokens.textPrimary,
    fontFeatures: tabular,
  );

  static const TextStyle displayLarge = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w800,
    height: 1.1,
    letterSpacing: -1.0,
    color: VoltTokens.textPrimary,
    fontFeatures: tabular,
  );

  // 2. Metric Value / Section Header
  static const TextStyle metricValue = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w800,
    height: 1.15,
    letterSpacing: -0.6,
    color: VoltTokens.textPrimary,
    fontFeatures: tabular,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: -0.2,
    color: VoltTokens.textPrimary,
  );

  // 3. Body / Interactive Copy
  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.45,
    color: VoltTokens.textSecondary,
  );

  static const TextStyle bodyStrong = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    height: 1.4,
    color: VoltTokens.textPrimary,
    fontFeatures: tabular,
  );

  // 4. Micro / Technical Eyebrow / Units
  static const TextStyle labelMicro = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 0.9,
    color: VoltTokens.textMuted,
    fontFeatures: tabular,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.35,
    color: VoltTokens.textSecondary,
    fontFeatures: tabular,
  );

  static const TextStyle mono = TextStyle(
    fontFamily: 'monospace',
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.45,
    color: VoltTokens.textPrimary,
    fontFeatures: tabular,
  );
}

/// Builds the global Material 3 ThemeData using VoltTokens.
ThemeData buildVoltTheme() {
  const scheme = ColorScheme.dark(
    primary: VoltTokens.voltMint,
    onPrimary: Color(0xFF002114),
    primaryContainer: Color(0xFF083828),
    onPrimaryContainer: VoltTokens.voltMintBright,
    secondary: VoltTokens.voltCyan,
    onSecondary: Color(0xFF001F29),
    secondaryContainer: Color(0xFF0A2E3D),
    onSecondaryContainer: Color(0xFF9EEBFF),
    tertiary: VoltTokens.voltAmber,
    error: VoltTokens.voltCoral,
    onError: Color(0xFF2D0006),
    surface: VoltTokens.bgSurface,
    onSurface: VoltTokens.textPrimary,
    onSurfaceVariant: VoltTokens.textSecondary,
    outline: VoltTokens.borderStrong,
    outlineVariant: VoltTokens.borderSubtle,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: VoltTokens.bgCanvas,
    canvasColor: VoltTokens.bgCanvas,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: VoltTokens.textPrimary,
      ),
      iconTheme: IconThemeData(color: VoltTokens.textPrimary, size: 22),
    ),
    cardTheme: CardThemeData(
      color: VoltTokens.bgSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VoltTokens.r20),
        side: const BorderSide(color: VoltTokens.borderSubtle, width: 1),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: VoltTokens.voltMint,
        foregroundColor: const Color(0xFF031B11),
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.1,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VoltTokens.r16),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: VoltTokens.bgElevated,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      labelStyle: const TextStyle(color: VoltTokens.textSecondary, fontSize: 13),
      hintStyle: const TextStyle(color: VoltTokens.textMuted, fontSize: 13),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(VoltTokens.r12),
        borderSide: const BorderSide(color: VoltTokens.borderSubtle),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(VoltTokens.r12),
        borderSide: const BorderSide(color: VoltTokens.voltMint, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(VoltTokens.r12),
        borderSide: const BorderSide(color: VoltTokens.voltCoral),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(VoltTokens.r12),
        borderSide: const BorderSide(color: VoltTokens.borderSubtle),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: VoltTokens.borderSubtle,
      thickness: 1,
      space: 24,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: VoltTokens.bgElevated,
      contentTextStyle: VoltType.bodyStrong,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VoltTokens.r12),
        side: const BorderSide(color: VoltTokens.borderStrong),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: VoltTokens.bgSurface,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: VoltTokens.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
  );
}

/// Custom route with subtle slide + fade transition that respects reduced motion.
PageRoute<T> voltPageRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: VoltTokens.medium,
    reverseTransitionDuration: VoltTokens.fast,
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.disableAnimationsOf(context)) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: VoltTokens.curveOut,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.0, 0.035),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}
