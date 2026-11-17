import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'noctra_theme_tokens.dart';

export 'noctra_design_tokens.dart';
export 'noctra_theme_backdrop.dart';
export 'noctra_theme_tokens.dart';

enum NoirThemeMode {
  glassmorphicBlack,
  liquidGlass;

  static const noirBlack = glassmorphicBlack;
}

extension NoirThemeModeX on NoirThemeMode {
  bool get isDark => true;
  bool get isLiquidGlass => this == NoirThemeMode.liquidGlass;
  bool get isGlassmorphicBlack => this == NoirThemeMode.glassmorphicBlack;
  bool get isWhite => false;
  bool get isMaterialU => false;
}

class NoirColors {
  // Glassmorphic Black Palette (Deep noir translucent surfaces with frosted specular borders)
  static const Color blackCanvas = Color(0xFF070709);
  static const Color blackSurface = Color(0xD90E0E14);
  static const Color blackSurfaceVariant = Color(0xC4161620);
  static const Color blackElevatedSurface = Color(0xEB1E1E2A);
  static const Color blackGlassBg = Color(0xCC0D0D12);
  static const Color blackBorder = Color(0x2EFFFFFF);
  static const Color blackBorderSubtle = Color(0x18FFFFFF);
  static const Color blackTextPrimary = Color(0xFFFFFFFF);
  static const Color blackTextSecondary = Color(0xFFA8A8B6);
  static const Color blackTextTertiary = Color(0xFF7C7C8A);
  static const Color blackAccent = Color(0xFFFFFFFF);
  static const Color blackSecondaryAccent = Color(0xFF8E8E98);

  // Liquid Glass — deep sapphire canvas, fluid glass surfaces, aurora cyan actions, violet selection
  static const Color glassCanvas = Color(0xFF162E4A);
  static const Color glassSurface = Color(0xD0253E60);
  static const Color glassSurfaceVariant = Color(0xC0356080);
  static const Color glassElevatedSurface = Color(0xDF4A7AAA);
  static const Color glassTextPrimary = Color(0xFFF0F6FF);
  static const Color glassTextSecondary = Color(0xFFB0C8E8);
  static const Color glassTextTertiary = Color(0xFF8EB5DF);
  static const Color glassAccent = Color(0xFF7EC8FF);
  static const Color glassSecondaryAccent = Color(0xFFB8A8FF);
  static const Color glassTertiaryAccent = Color(0xFF68E8C0);

  // Fallbacks for legacy isDark checks in widgets (both active themes are dark/glass)
  static const Color whiteTextPrimary = blackTextPrimary;
  static const Color whiteTextSecondary = blackTextSecondary;
  static const Color whiteTextTertiary = blackTextTertiary;
  static const Color whiteBorder = blackBorder;
  static const Color whiteBorderSubtle = blackBorderSubtle;
  static const Color whiteSurface = blackSurface;
  static const Color whiteSurfaceVariant = blackSurfaceVariant;
  static const Color whiteElevatedSurface = blackElevatedSurface;
  static const Color whiteCanvas = blackCanvas;
  static const Color whiteAccent = blackAccent;
  static const Color whiteSecondaryAccent = blackSecondaryAccent;
}

class NoirTheme {
  static ThemeData getTheme(NoirThemeMode mode) {
    final isLiquidGlass = mode == NoirThemeMode.liquidGlass;

    final canvas = isLiquidGlass ? NoirColors.glassCanvas : NoirColors.blackCanvas;
    final surface = isLiquidGlass ? NoirColors.glassSurface : NoirColors.blackSurface;
    final surfaceVariant = isLiquidGlass
        ? NoirColors.glassSurfaceVariant
        : NoirColors.blackSurfaceVariant;
    final elevatedSurface = isLiquidGlass
        ? NoirColors.glassElevatedSurface
        : NoirColors.blackElevatedSurface;
    final textPrimary = isLiquidGlass
        ? NoirColors.glassTextPrimary
        : NoirColors.blackTextPrimary;
    final textSecondary = isLiquidGlass
        ? NoirColors.glassTextSecondary
        : NoirColors.blackTextSecondary;
    final textTertiary = isLiquidGlass
        ? NoirColors.glassTextTertiary
        : NoirColors.blackTextTertiary;
    final accent = isLiquidGlass ? NoirColors.glassAccent : NoirColors.blackAccent;
    final secondaryAccent = isLiquidGlass
        ? NoirColors.glassSecondaryAccent
        : NoirColors.blackSecondaryAccent;
    final tertiaryAccent =
        isLiquidGlass ? NoirColors.glassTertiaryAccent : accent;

    final tokens = NoctraThemeTokens(
      canvas: canvas,
      surface: surface,
      surfaceVariant: surfaceVariant,
      elevatedSurface: elevatedSurface,
      primaryText: textPrimary,
      secondaryText: textSecondary,
      tertiaryText: textTertiary,
      border: isLiquidGlass ? const Color(0x77D0E4FF) : NoirColors.blackBorder,
      subtleBorder: isLiquidGlass
          ? const Color(0x44C0D8F0)
          : NoirColors.blackBorderSubtle,
      accent: accent,
      secondaryAccent: secondaryAccent,
      tertiaryAccent: tertiaryAccent,
      scrim: Colors.black.withValues(alpha: isLiquidGlass ? 0.32 : 0.55),
      glassBlurSigma: isLiquidGlass ? 18 : 14,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: canvas,
      colorScheme: ColorScheme(
        brightness: Brightness.dark,
        primary: accent,
        onPrimary: Colors.black,
        secondary: secondaryAccent,
        onSecondary: Colors.black,
        tertiary: tertiaryAccent,
        onTertiary: Colors.black,
        error: const Color(0xFFB0B0B0),
        onError: Colors.black,
        surface: surface,
        onSurface: textPrimary,
      ),
      extensions: [tokens],
      fontFamily: 'Inter',
      textTheme: TextTheme(
        displayLarge: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.9,
            color: textPrimary),
        headlineMedium: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: textPrimary),
        titleLarge: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary),
        titleMedium: TextStyle(
            fontSize: 15, fontWeight: FontWeight.w600, color: textPrimary),
        bodyLarge: TextStyle(
            fontSize: 15, fontWeight: FontWeight.w400, color: textPrimary),
        bodyMedium: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w400, color: textSecondary),
        labelSmall: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: textSecondary),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        selectedItemColor: accent,
        unselectedItemColor: textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  static BoxDecoration liquidGlassDecoration({
    required bool isDark,
    double radius = 18,
    bool isHighlighted = false,
  }) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: isHighlighted ? 0.14 : 0.08),
          const Color(0xFF0E0E12).withValues(alpha: 0.88),
          const Color(0xFF060608).withValues(alpha: 0.94),
        ],
        stops: const [0.0, 0.45, 1.0],
      ),
      border: Border.all(
        color: isHighlighted
            ? NoirColors.blackBorder
            : NoirColors.blackBorderSubtle,
        width: 1.0,
      ),
    );
  }
}
