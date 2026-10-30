import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'vr_colors.dart';
import 'vr_typography.dart';

/// Thème global.
///
/// L'interface VIGIROAD est construite avec ses propres composants
/// (`lib/core/widgets`) ; ce thème ne sert qu'à aligner les éléments système
/// résiduels (sélection de texte, dialogues, barres de défilement) sur la
/// palette pour qu'aucun élément Material par défaut ne dépareille.
abstract final class VrTheme {
  static const SystemUiOverlayStyle overlay = SystemUiOverlayStyle(
    statusBarColor: Color(0x00000000),
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: VrColors.background,
    systemNavigationBarIconBrightness: Brightness.light,
  );

  static ThemeData build() {
    const scheme = ColorScheme.dark(
      primary: VrColors.cyan,
      onPrimary: VrColors.background,
      secondary: VrColors.electric,
      onSecondary: VrColors.textPrimary,
      error: VrColors.alert,
      onError: VrColors.textPrimary,
      surface: VrColors.panel,
      onSurface: VrColors.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: VrColors.background,
      fontFamily: VrText.body,
      splashFactory: NoSplash.splashFactory,
      highlightColor: VrColors.cyan.withValues(alpha: 0.08),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: VrColors.cyan,
        selectionColor: VrColors.cyan.withValues(alpha: 0.3),
        selectionHandleColor: VrColors.cyan,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: VrColors.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: VrColors.border()),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: VrColors.panelLight,
        contentTextStyle: VrText.label,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: VrColors.border()),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
