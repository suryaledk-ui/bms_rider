import 'package:flutter/material.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// BMS Rider design tokens.
///
/// Identity: "engineered electro" — a dark instrument console for the battery
/// pack. One signature motif (`CellStackGauge`) carries the brand; everything
/// else stays disciplined: hairline strokes, soft depth, monospace metrics.
/// ─────────────────────────────────────────────────────────────────────────────
abstract final class AppColors {
  // Neutral surfaces (dark-first, deep blue-black).
  static const background = Color(0xFF0A0E14);
  static const surface = Color(0xFF111720);
  static const surfaceHi = Color(0xFF161E2A);
  static const surfaceLo = Color(0xFF0C121A);

  // Hairlines / strokes.
  static const stroke = Color(0xFF252F40);
  static const strokeSoft = Color(0xFF1B2331);

  // Electro palette.
  static const primary = Color(0xFF2FE6B0); // charge mint
  static const onPrimary = Color(0xFF04120C);
  static const primarySoft = Color(0x2E2FE6B0); // 18% wash
  static const accent = Color(0xFF4CC9F0); // cool cyan, secondary
  static const valid = Color(0xFF37D67A);
  static const warn = Color(0xFFFFB454);
  static const danger = Color(0xFFFF5C7A);

  // Text ramp (all ≥ 4.5:1 on surfaces).
  static const onSurface = Color(0xFFEDF2F7);
  static const onSurfaceMuted = Color(0xFF9AA8BC);
  static const onSurfaceDim = Color(0xFF6E7F96);

  /// SOC → semantic color.
  static Color socColor(int soc) {
    if (soc > 50) return primary;
    if (soc > 20) return warn;
    return danger;
  }
}

abstract final class AppRadius {
  static const card = 20.0;
  static const control = 14.0;
  static const field = 14.0;
  static const pill = 999.0;
  static const sheet = 28.0;
}

abstract final class AppSpace {
  static const s2 = 2.0;
  static const s4 = 4.0;
  static const s8 = 8.0;
  static const s12 = 12.0;
  static const s16 = 16.0;
  static const s20 = 20.0;
  static const s24 = 24.0;
  static const s32 = 32.0;
  static const s40 = 40.0;
  static const s48 = 48.0;
}

/// Monospace metric numerals — the "instrument" voice of the app.
abstract final class MonoFont {
  static const family = 'monospace';
}

abstract final class AppType {
  // ── Metrics ────────────────────────────────────────────────────────────────
  static TextStyle metric(double size, {Color? color}) => TextStyle(
        fontFamily: MonoFont.family,
        fontSize: size,
        fontWeight: FontWeight.w700,
        height: 1.05,
        letterSpacing: -0.5,
        color: color ?? AppColors.onSurface,
      );

  static const metricDisplay = TextStyle(
    fontFamily: MonoFont.family,
    fontSize: 56,
    fontWeight: FontWeight.w700,
    height: 1.0,
    letterSpacing: -1.5,
    color: AppColors.onSurface,
  );

  // ── Hierarchy ──────────────────────────────────────────────────────────────
  static const h1 = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w800,
    height: 1.15,
    letterSpacing: -0.4,
    color: AppColors.onSurface,
  );
  static const h2 = TextStyle(
    fontSize: 19,
    fontWeight: FontWeight.w800,
    height: 1.2,
    letterSpacing: -0.2,
    color: AppColors.onSurface,
  );
  static const h3 = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.3,
    color: AppColors.onSurface,
  );
  static const body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.45,
    color: AppColors.onSurface,
  );
  static const caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: AppColors.onSurfaceMuted,
  );
  static const micro = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: 1.2,
    color: AppColors.onSurfaceMuted,
  );

  // ── Mono auxiliary ─────────────────────────────────────────────────────────
  static const monoLabel = TextStyle(
    fontFamily: MonoFont.family,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: 0.6,
    color: AppColors.onSurfaceDim,
  );
  static const monoSmall = TextStyle(
    fontFamily: MonoFont.family,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: AppColors.onSurfaceMuted,
  );
  static const monoCode = TextStyle(
    fontFamily: MonoFont.family,
    fontSize: 11,
    height: 1.5,
    color: AppColors.onSurfaceMuted,
  );
}

/// Page transition: a gentle rise + settle. Fast, cheap, not a default slide.
class SweepPageTransitionsBuilder extends PageTransitionsBuilder {
  const SweepPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      return child;
    }
    final t = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: t,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.025),
          end: Offset.zero,
        ).animate(t),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1.0).animate(t),
          child: child,
        ),
      ),
    );
  }
}

ThemeData buildAppTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.primary,
    onPrimary: AppColors.onPrimary,
    primaryContainer: AppColors.primarySoft,
    onPrimaryContainer: AppColors.primary,
    secondary: AppColors.accent,
    onSecondary: Color(0xFF04131C),
    secondaryContainer: Color(0x234CC9F0),
    onSecondaryContainer: AppColors.accent,
    tertiary: AppColors.valid,
    onTertiary: Color(0xFF04110A),
    error: AppColors.danger,
    onError: Color(0xFF2A0A12),
    surface: AppColors.surface,
    onSurface: AppColors.onSurface,
    onSurfaceVariant: AppColors.onSurfaceMuted,
    outline: AppColors.stroke,
    outlineVariant: AppColors.strokeSoft,
    surfaceContainerLowest: AppColors.background,
    surfaceContainerLow: AppColors.surfaceLo,
    surfaceContainer: AppColors.surface,
    surfaceContainerHigh: AppColors.surfaceHi,
    surfaceContainerHighest: Color(0xFF1B2433),
    inverseSurface: AppColors.onSurface,
    onInverseSurface: AppColors.background,
    shadow: Color(0x66000000),
    scrim: Color(0xCC04060A),
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    splashFactory: InkSparkle.splashFactory,
  );

  final textTheme = base.textTheme.copyWith(
    displayLarge: AppType.metric(52),
    displayMedium: AppType.metric(40),
    displaySmall: AppType.metric(32),
    headlineLarge: AppType.metric(26),
    headlineMedium: AppType.h1,
    headlineSmall: AppType.h2,
    titleLarge: AppType.h2,
    titleMedium: AppType.h3,
    titleSmall: AppType.h3.copyWith(fontSize: 14),
    bodyLarge: AppType.body,
    bodyMedium: AppType.caption,
    bodySmall: AppType.caption.copyWith(fontSize: 11, letterSpacing: 0.4),
    labelLarge: const TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
      height: 1.2,
    ),
    labelMedium: AppType.micro,
    labelSmall: AppType.monoLabel,
  );

  return base.copyWith(
    textTheme: textTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 4,
      titleTextStyle: AppType.h2,
      iconTheme: IconThemeData(color: AppColors.onSurfaceMuted, size: 22),
      actionsIconTheme: IconThemeData(color: AppColors.onSurfaceMuted, size: 22),
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surfaceHi,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.card)),
        side: BorderSide(color: AppColors.stroke, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: const WidgetStatePropertyAll(AppColors.primary),
        foregroundColor: const WidgetStatePropertyAll(AppColors.onPrimary),
        minimumSize: const WidgetStatePropertyAll(Size(0, 52)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: AppSpace.s20),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
        ),
        textStyle: const WidgetStatePropertyAll(TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        )),
        elevation: const WidgetStatePropertyAll(0),
        overlayColor: WidgetStatePropertyAll(AppColors.onPrimary.withValues(alpha: 0.08)),
        side: const WidgetStatePropertyAll(BorderSide(color: Colors.transparent)),
        iconSize: const WidgetStatePropertyAll(20),
        iconColor: const WidgetStatePropertyAll(AppColors.onPrimary),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: const WidgetStatePropertyAll(AppColors.surfaceHi),
        foregroundColor: const WidgetStatePropertyAll(AppColors.onSurface),
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
        ),
        minimumSize: const WidgetStatePropertyAll(Size(0, 52)),
        side: const WidgetStatePropertyAll(BorderSide(color: AppColors.stroke)),
        textStyle: const WidgetStatePropertyAll(TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
        )),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: const WidgetStatePropertyAll(AppColors.primary),
        textStyle: const WidgetStatePropertyAll(TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        )),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: AppSpace.s16, vertical: AppSpace.s12),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
        ),
        overlayColor: WidgetStatePropertyAll(AppColors.primary.withValues(alpha: 0.08)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      elevation: 0,
      backgroundColor: AppColors.surface.withValues(alpha: 0.94),
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      indicatorColor: AppColors.primarySoft,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        return TextStyle(
          fontSize: 11.5,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
          letterSpacing: 0.4,
          color: states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.onSurfaceDim,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        return IconThemeData(
          size: 24,
          color: states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.onSurfaceDim,
        );
      }),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceLo,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.s16, vertical: 14),
      labelStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.onSurfaceMuted,
      ),
      floatingLabelStyle: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppColors.primary,
      ),
      hintStyle: const TextStyle(color: AppColors.onSurfaceDim),
      prefixIconColor: AppColors.onSurfaceDim,
      suffixIconColor: AppColors.onSurfaceMuted,
      helperStyle: AppType.caption,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: const BorderSide(color: AppColors.stroke),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: const BorderSide(color: AppColors.stroke),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: const BorderSide(color: AppColors.danger, width: 1.4),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.strokeSoft,
      thickness: 1,
      space: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surfaceHi,
      contentTextStyle: const TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
        color: AppColors.onSurface,
      ),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        side: const BorderSide(color: AppColors.stroke),
      ),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      showDragHandle: false,
      dragHandleColor: AppColors.stroke,
      elevation: 0,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surfaceHi,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: const BorderSide(color: AppColors.stroke),
      ),
      titleTextStyle: AppType.h2,
      contentTextStyle: AppType.body.copyWith(color: AppColors.onSurfaceMuted),
      elevation: 0,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surfaceLo,
      selectedColor: AppColors.primarySoft,
      side: const BorderSide(color: AppColors.stroke),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
      labelStyle: AppType.caption.copyWith(fontWeight: FontWeight.w600),
      secondaryLabelStyle: AppType.caption,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      labelPadding: EdgeInsets.zero,
      iconTheme: const IconThemeData(size: 16, color: AppColors.onSurfaceMuted),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.surfaceHi,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.stroke),
      ),
      textStyle: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.onSurface,
      ),
      waitDuration: const Duration(milliseconds: 350),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primary,
      linearTrackColor: AppColors.surfaceLo,
      circularTrackColor: AppColors.strokeSoft,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: AppColors.onSurfaceMuted,
      textColor: AppColors.onSurface,
      titleTextStyle: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.onSurface,
      ),
      subtitleTextStyle: TextStyle(fontSize: 12.5, color: AppColors.onSurfaceMuted),
      contentPadding: EdgeInsets.symmetric(horizontal: AppSpace.s16, vertical: 2),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: SweepPageTransitionsBuilder(),
        TargetPlatform.iOS: SweepPageTransitionsBuilder(),
        TargetPlatform.macOS: SweepPageTransitionsBuilder(),
        TargetPlatform.windows: SweepPageTransitionsBuilder(),
        TargetPlatform.linux: SweepPageTransitionsBuilder(),
        TargetPlatform.fuchsia: SweepPageTransitionsBuilder(),
      },
    ),
    fontFamilyFallback: const ['Roboto', 'Noto Sans', 'sans-serif'],
    visualDensity: VisualDensity.standard,
  );
}
