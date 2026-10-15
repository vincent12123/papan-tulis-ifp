import 'package:flutter/material.dart';

/// Design tokens from docs/design-system.md. The only place colors and
/// sizes may be defined; widgets must reference these, never raw values.
abstract final class AppColors {
  static const primary = Color(0xFF1D4ED8);
  static const onPrimary = Color(0xFFFFFFFF);
  static const primaryContainer = Color(0xFFDBEAFE);

  static const canvas = Color(0xFFFFFFFF);
  static const text = Color(0xFF111827);
  static const textMuted = Color(0xFF4B5563);
  static const border = Color(0xFFD1D5DB);
  static const surface = Color(0xFFFFFFFF);
  static const background = Color(0xFFF3F4F6);

  static const success = Color(0xFF15803D);
  static const warning = Color(0xFFB45309);
  static const danger = Color(0xFFB91C1C);
}

/// Pen palette (board content, not UI chrome).
/// Bangun ruang (REQ-23): faces, edges, and the cut plane.
abstract final class SolidColors {
  static const face = Color(0xFF93C5FD);
  static const edge = Color(0xFF111827);
  static const cut = Color(0xFFEA580C);
  static const label = Color(0xFF111827);
}

/// Alat peraga scenes (REQ-26, REQ-28) and the quiz (REQ-27).
abstract final class PeragaColors {
  static const ink = Color(0xFF111827);
  static const muted = Color(0xFF6B7280);
  static const glass = Color(0xFF94A3B8);
  static const water = Color(0xFFBFDBFE);
  static const milky = Color(0xFFE5E7EB);
  static const bob = Color(0xFF2563EB);
  static const block = Color(0xFF60A5FA);
  static const velocity = Color(0xFF16A34A);
  static const force = Color(0xFFDC2626);
  static const weight = Color(0xFF6B7280);
  static const flameBlue = Color(0xFF3B82F6);
  static const flameCore = Color(0xFFBFDBFE);
  static const flameYellow = Color(0xFFF59E0B);
  static const flameOrange = Color(0xFFEA580C);
  static const smoke = Color(0xFF6B7280);
  static const bubble = Color(0xFFFFFFFF);
  static const acidRed = Color(0xFFE11D48);
  static const baseBlue = Color(0xFF2563EB);
  static const litmusPurple = Color(0xFF7C3AED);
  static const phenolPink = Color(0xFFDB2777);
  static const clear = Color(0xFFF1F5F9);
  static const metals = [
    Color(0xFFD1D5DB), // Mg
    Color(0xFF9CA3AF), // Zn
    Color(0xFF4B5563), // Fe
    Color(0xFFB45309), // Cu
  ];
  static const matched = Color(0xFFDCFCE7);
  static const wrong = Color(0xFFFEE2E2);
}

/// Tema papan (REQ-29): white, chalkboard green, black.
enum BoardTheme {
  putih('Putih', Color(0xFFFFFFFF)),
  hijau('Hijau kapur', Color(0xFF1F3B2D)),
  hitam('Hitam', Color(0xFF18181B));

  const BoardTheme(this.label, this.color);
  final String label;
  final Color color;
  bool get dark => this != BoardTheme.putih;
}

abstract final class PenColors {
  static const black = Color(0xFF111827);
  static const white = Color(0xFFF8FAFC);
  static const yellow = Color(0xFFFDE047);
  static const blue = Color(0xFF1D4ED8);
  static const red = Color(0xFFDC2626);
  static const green = Color(0xFF15803D);
  static const orange = Color(0xFFEA580C);
  static const purple = Color(0xFF7C3AED);

  static const all = <({Color color, String label})>[
    (color: black, label: 'Hitam'),
    (color: blue, label: 'Biru'),
    (color: red, label: 'Merah'),
    (color: green, label: 'Hijau'),
    (color: orange, label: 'Oranye'),
    (color: purple, label: 'Ungu'),
    (color: white, label: 'Putih'),
    (color: yellow, label: 'Kuning'),
  ];
}

/// Series of a chart made from a table (REQ-21), in column order.
abstract final class ChartColors {
  static const series = [
    PenColors.blue,
    PenColors.red,
    PenColors.green,
    PenColors.purple,
    PenColors.orange,
  ];
  static const grid = Color(0xFFE5E7EB);
}

abstract final class PenWidths {
  static const thin = 3.0;
  static const medium = 6.0;
  static const thick = 12.0;

  static const all = <({double width, String label})>[
    (width: thin, label: 'Tipis'),
    (width: medium, label: 'Sedang'),
    (width: thick, label: 'Tebal'),
  ];
}

abstract final class AppSizes {
  /// Primary touch targets on the panel (NFR-06).
  static const primaryTarget = 64.0;

  /// Secondary touch targets (NFR-06).
  static const target = 48.0;

  static const toolIcon = 32.0;
  static const listIcon = 24.0;

  static const textBody = 20.0;
  static const textSection = 24.0;
  static const textTitle = 28.0;

  static const space4 = 4.0;
  static const space8 = 8.0;
  static const space12 = 12.0;
  static const space16 = 16.0;
  static const space24 = 24.0;
  static const space32 = 32.0;
  static const space48 = 48.0;

  static const radiusSmall = 8.0;
  static const radiusMedium = 12.0;
  static const radiusLarge = 20.0;

  static const elevation = 2.0;
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    onPrimary: AppColors.onPrimary,
    primaryContainer: AppColors.primaryContainer,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    onSurfaceVariant: AppColors.textMuted,
    outline: AppColors.border,
    error: AppColors.danger,
  );
  const body = TextStyle(fontSize: AppSizes.textBody, color: AppColors.text);
  final minTarget = WidgetStateProperty.all(
    const Size(AppSizes.target, AppSizes.target),
  );
  final buttonText = WidgetStateProperty.all(
    const TextStyle(
      fontFamily: 'Roboto',
      fontSize: AppSizes.textBody,
      fontWeight: FontWeight.w500,
    ),
  );
  return ThemeData(
    useMaterial3: true,
    // design-system §3: Roboto everywhere (the Android default, named so
    // every style, including button labels, resolves to it).
    fontFamily: 'Roboto',
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    textTheme: const TextTheme(
      titleLarge: TextStyle(
        fontSize: AppSizes.textTitle,
        fontWeight: FontWeight.w600,
        color: AppColors.text,
      ),
      titleMedium: TextStyle(
        fontSize: AppSizes.textSection,
        fontWeight: FontWeight.w600,
        color: AppColors.text,
      ),
      bodyLarge: body,
      bodyMedium: body,
      bodySmall: TextStyle(
        fontSize: AppSizes.textBody,
        color: AppColors.textMuted,
      ),
      labelLarge: TextStyle(
        fontSize: AppSizes.textBody,
        fontWeight: FontWeight.w500,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(minimumSize: minTarget, textStyle: buttonText),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(minimumSize: minTarget, textStyle: buttonText),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(minimumSize: minTarget, textStyle: buttonText),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        minimumSize: minTarget,
        iconSize: WidgetStateProperty.all(AppSizes.toolIcon),
      ),
    ),
    tooltipTheme: const TooltipThemeData(
      textStyle: TextStyle(
        fontSize: AppSizes.textBody,
        color: AppColors.onPrimary,
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.surface,
      titleTextStyle: TextStyle(
        fontSize: AppSizes.textSection,
        fontWeight: FontWeight.w600,
        color: AppColors.text,
      ),
      contentTextStyle: body,
    ),
  );
}
