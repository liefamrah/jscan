import 'package:material_ui/material_ui.dart';

/// Semantic tokens for JScan's Warm Charcoal, Butter-Yellow (#F7D568) & Warm Paper (#F5F1E9) palette.
abstract final class AppColors {
  static const String fontFamily = 'PlusJakartaSans';

  // Signature brand tokens (matching assets/jscan_app_icon.svg & UI reference)
  static const Color yellow = Color(0xFFF7D568);
  static const Color yellowSoftLight = Color(0xFFFDF2CC);
  static const Color yellowDeep = Color(0xFFD4A72C);
  static const Color yellowContainerDark = Color(0xFF332D1B);

  static const Color charcoal = Color(0xFF1D1D1C);
  static const Color charcoalElevated = Color(0xFF282725);
  static const Color charcoalTileTop = Color(0xFF302F2D);

  // Light mode surfaces
  static const Color bgLight = Color(0xFFF5F1E9);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceVarLight = Color(0xFFEDE7DC);
  static const Color borderLight = Color(0xFFE3DDD1);
  static const Color textPrimaryLight = Color(0xFF1D1D1C);
  static const Color textSecondaryLight = Color(0xFF78736A);

  // Dark mode surfaces
  static const Color bgDark = Color(0xFF141413);
  static const Color surfaceDark = Color(0xFF1F1E1C);
  static const Color surfaceVarDark = Color(0xFF2B2A27);
  static const Color borderDark = Color(0xFF34322E);
  static const Color textPrimaryDark = Color(0xFFF5F1E9);
  static const Color textSecondaryDark = Color(0xFFA39E93);

  // Camera & scanner overlays
  static const Color cameraQuad = Color(0xFFF7D568);
  static const Color stableGreen = Color(0xFF22C55E);

  // Destructive
  static const Color dangerLight = Color(0xFFD9433B);
  static const Color dangerDark = Color(0xFFF87171);

  // Harmonious warm/ink accents for tool categories & donation highlight
  static const Color saweriaAccentLight = Color(0xFFF7D568);
  static const Color saweriaAccentDark = Color(0xFFF7D568);
  static const Color toolTealLight = Color(0xFF1F7A6E);
  static const Color toolTealDark = Color(0xFF4FD1C5);
  static const Color toolSkyLight = Color(0xFF2B6CB0);
  static const Color toolSkyDark = Color(0xFF63B3ED);
  static const Color toolRoseLight = Color(0xFFC53030);
  static const Color toolRoseDark = Color(0xFFFC8181);
}

ThemeData buildLightTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.yellow,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppColors.charcoal,
    onPrimary: AppColors.bgLight,
    primaryContainer: AppColors.yellow,
    onPrimaryContainer: AppColors.charcoal,
    secondary: AppColors.yellow,
    onSecondary: AppColors.charcoal,
    secondaryContainer: AppColors.yellowSoftLight,
    onSecondaryContainer: AppColors.charcoal,
    surface: AppColors.surfaceLight,
    onSurface: AppColors.textPrimaryLight,
    onSurfaceVariant: AppColors.textSecondaryLight,
    surfaceContainerHighest: AppColors.surfaceVarLight,
    outline: AppColors.borderLight,
    outlineVariant: AppColors.borderLight,
    error: AppColors.dangerLight,
    onError: Colors.white,
  );

  return _baseTheme(scheme, AppColors.bgLight, AppColors.borderLight);
}

ThemeData buildDarkTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.yellow,
    brightness: Brightness.dark,
  ).copyWith(
    primary: AppColors.yellow,
    onPrimary: AppColors.charcoal,
    primaryContainer: AppColors.yellowContainerDark,
    onPrimaryContainer: AppColors.yellow,
    secondary: AppColors.yellow,
    onSecondary: AppColors.charcoal,
    secondaryContainer: AppColors.charcoalElevated,
    onSecondaryContainer: AppColors.textPrimaryDark,
    surface: AppColors.surfaceDark,
    onSurface: AppColors.textPrimaryDark,
    onSurfaceVariant: AppColors.textSecondaryDark,
    surfaceContainerHighest: AppColors.surfaceVarDark,
    outline: AppColors.borderDark,
    outlineVariant: AppColors.borderDark,
    error: AppColors.dangerDark,
    onError: AppColors.charcoal,
  );

  return _baseTheme(scheme, AppColors.bgDark, AppColors.borderDark);
}

TextTheme _buildTextTheme(ColorScheme scheme) {
  final primary = scheme.onSurface;
  final secondary = scheme.onSurfaceVariant;
  return TextTheme(
    headlineLarge: TextStyle(
      fontFamily: AppColors.fontFamily,
      fontSize: 30,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.8,
      height: 1.15,
      color: primary,
    ),
    headlineMedium: TextStyle(
      fontFamily: AppColors.fontFamily,
      fontSize: 25,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.6,
      height: 1.18,
      color: primary,
    ),
    headlineSmall: TextStyle(
      fontFamily: AppColors.fontFamily,
      fontSize: 21,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.45,
      height: 1.22,
      color: primary,
    ),
    titleLarge: TextStyle(
      fontFamily: AppColors.fontFamily,
      fontSize: 18,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
      height: 1.25,
      color: primary,
    ),
    titleMedium: TextStyle(
      fontFamily: AppColors.fontFamily,
      fontSize: 15.5,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
      height: 1.3,
      color: primary,
    ),
    titleSmall: TextStyle(
      fontFamily: AppColors.fontFamily,
      fontSize: 13.5,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.1,
      height: 1.3,
      color: primary,
    ),
    bodyLarge: TextStyle(
      fontFamily: AppColors.fontFamily,
      fontSize: 15,
      fontWeight: FontWeight.w500,
      height: 1.45,
      color: primary,
    ),
    bodyMedium: TextStyle(
      fontFamily: AppColors.fontFamily,
      fontSize: 13.5,
      fontWeight: FontWeight.w500,
      height: 1.42,
      color: primary,
    ),
    bodySmall: TextStyle(
      fontFamily: AppColors.fontFamily,
      fontSize: 12,
      fontWeight: FontWeight.w500,
      height: 1.38,
      color: secondary,
    ),
    labelLarge: TextStyle(
      fontFamily: AppColors.fontFamily,
      fontSize: 13.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.1,
      color: primary,
    ),
    labelMedium: TextStyle(
      fontFamily: AppColors.fontFamily,
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
      color: secondary,
    ),
    labelSmall: TextStyle(
      fontFamily: AppColors.fontFamily,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
      color: secondary,
    ),
  );
}

ThemeData _baseTheme(ColorScheme scheme, Color scaffoldBg, Color borderColor) {
  final textTheme = _buildTextTheme(scheme);
  final isDark = scheme.brightness == Brightness.dark;

  return ThemeData(
    useMaterial3: true,
    fontFamily: AppColors.fontFamily,
    colorScheme: scheme,
    textTheme: textTheme,
    scaffoldBackgroundColor: scaffoldBg,
    dividerColor: borderColor,
    appBarTheme: AppBarTheme(
      backgroundColor: scaffoldBg,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: borderColor),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surface,
      selectedColor: AppColors.yellow,
      checkmarkColor: AppColors.charcoal,
      side: BorderSide(color: borderColor),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      labelStyle: TextStyle(
        fontFamily: AppColors.fontFamily,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        textStyle: const TextStyle(
          fontFamily: AppColors.fontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        minimumSize: const Size(48, 48),
        side: BorderSide(color: borderColor, width: 1.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        textStyle: const TextStyle(
          fontFamily: AppColors.fontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: AppColors.yellow,
        selectedForegroundColor: AppColors.charcoal,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurfaceVariant,
        side: BorderSide(color: borderColor),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        textStyle: const TextStyle(
          fontFamily: AppColors.fontFamily,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return isDark ? AppColors.charcoal : AppColors.charcoal;
        }
        return scheme.onSurfaceVariant;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.yellow;
        }
        return scheme.surfaceContainerHighest;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return Colors.transparent;
        }
        return borderColor;
      }),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: AppColors.yellow,
      thumbColor: isDark ? AppColors.yellow : AppColors.charcoal,
      inactiveTrackColor: scheme.surfaceContainerHighest,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: isDark ? AppColors.yellow : AppColors.charcoal,
          width: 1.6,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark ? AppColors.textPrimaryDark : AppColors.charcoal,
      contentTextStyle: TextStyle(
        fontFamily: AppColors.fontFamily,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: isDark ? AppColors.charcoal : AppColors.bgLight,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
