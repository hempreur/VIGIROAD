import 'package:flutter/material.dart';

const _pkg = 'vigiroad_admin_core';

/// Palette VIGIROAD (identique à l'application mobile, docs/DESIGN.md) et
/// couleurs d'état des applications d'administration.
abstract final class VrColors {
  static const background = Color(0xFF02050A);
  static const backgroundRaised = Color(0xFF010C15);
  static const panel = Color(0xFF07131E);
  static const panelLight = Color(0xFF0E1B27);
  static const anthracite = Color(0xFF121C26);
  static const line = Color(0xFF1A2A38);

  static const cyan = Color(0xFF19CFF4);
  static const cyanBright = Color(0xFF48E6FF);
  static const electric = Color(0xFF066DD3);
  static const electricBright = Color(0xFF2F8CFF);

  /// Service fonctionnel.
  static const ok = Color(0xFF3FBF5A);

  /// Avertissement.
  static const warning = Color(0xFFF09E1B);

  /// Erreur critique.
  static const critical = Color(0xFFF6282F);
  static const criticalText = Color(0xFFF8484D);

  static const textPrimary = Color(0xFFF2F7FA);
  static const textSecondary = Color(0xFFA9B8C4);
  static const textMuted = Color(0xFF7B8A93);

  /// Séries des graphiques.
  static const series = [cyan, electricBright, ok, warning, Color(0xFFB37CFF), Color(0xFFFF6FB1)];

  static Color border([double opacity = 0.28]) => cyan.withValues(alpha: opacity);
}

abstract final class VrText {
  static const display = TextStyle(
    fontFamily: 'Rajdhani',
    package: _pkg,
    fontWeight: FontWeight.w700,
    fontSize: 30,
    letterSpacing: 1.2,
    color: VrColors.textPrimary,
  );
  static const title = TextStyle(
    fontFamily: 'Rajdhani',
    package: _pkg,
    fontWeight: FontWeight.w700,
    fontSize: 22,
    letterSpacing: 1.0,
    color: VrColors.textPrimary,
  );
  static const section = TextStyle(
    fontFamily: 'Rajdhani',
    package: _pkg,
    fontWeight: FontWeight.w600,
    fontSize: 17,
    letterSpacing: 1.1,
    color: VrColors.textPrimary,
  );
  static const metric = TextStyle(
    fontFamily: 'Rajdhani',
    package: _pkg,
    fontWeight: FontWeight.w700,
    fontSize: 30,
    height: 1.05,
    color: VrColors.textPrimary,
  );
  static const body = TextStyle(fontFamily: 'Inter', package: _pkg, fontSize: 13.5, color: VrColors.textPrimary);
  static const label = TextStyle(
    fontFamily: 'Inter',
    package: _pkg,
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
    color: VrColors.textSecondary,
  );
  static const caption = TextStyle(fontFamily: 'Inter', package: _pkg, fontSize: 12, color: VrColors.textMuted);
  static const mono = TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.35, color: VrColors.textPrimary);
}

ThemeData vrTheme() {
  const scheme = ColorScheme.dark(
    primary: VrColors.cyan,
    onPrimary: VrColors.background,
    secondary: VrColors.electricBright,
    surface: VrColors.panel,
    onSurface: VrColors.textPrimary,
    error: VrColors.critical,
    outline: VrColors.line,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: Brightness.dark);
  return base.copyWith(
    scaffoldBackgroundColor: VrColors.background,
    canvasColor: VrColors.background,
    textTheme: base.textTheme.apply(fontFamily: 'Inter', package: _pkg, bodyColor: VrColors.textPrimary),
    dividerTheme: const DividerThemeData(color: VrColors.line, thickness: 1, space: 1),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: VrColors.panelLight,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: VrColors.border()),
      ),
      textStyle: VrText.caption.copyWith(color: VrColors.textPrimary),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: VrColors.backgroundRaised,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: VrText.label,
      hintStyle: VrText.caption,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: VrColors.line)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: VrColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: VrColors.cyan, width: 1.4),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: VrColors.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: VrColors.border())),
      titleTextStyle: VrText.title,
      contentTextStyle: VrText.body,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: VrColors.panelLight,
      contentTextStyle: VrText.body,
      behavior: SnackBarBehavior.floating,
      width: 520,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: VrColors.border())),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(VrColors.cyan.withValues(alpha: 0.35)),
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(3),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: VrColors.cyan),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? VrColors.cyan : null),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? VrColors.cyan : VrColors.textMuted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? VrColors.cyan.withValues(alpha: 0.35) : VrColors.line,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: VrColors.panelLight,
      textStyle: VrText.body,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: VrColors.border())),
    ),
  );
}
