import 'package:flutter/painting.dart';

/// Palette officielle VIGIROAD.
///
/// Valeurs mesurées sur l'image de référence (médiane des pixels par teinte),
/// voir `docs/DESIGN.md`. Ne pas introduire de couleur hors de cette palette
/// sans mettre à jour la documentation de design.
abstract final class VrColors {
  // Fonds
  static const Color background = Color(0xFF02050A);
  static const Color backgroundRaised = Color(0xFF010C15);
  static const Color panel = Color(0xFF07131E);
  static const Color panelLight = Color(0xFF0E1B27);
  static const Color mapBase = Color(0xFF1F303D);

  // Accents
  static const Color cyan = Color(0xFF19CFF4);
  static const Color cyanBright = Color(0xFF48E6FF);
  static const Color electric = Color(0xFF066DD3);
  static const Color routeCore = Color(0xFFC9FFFF);

  // États
  static const Color alert = Color(0xFFF6282F);
  static const Color alertText = Color(0xFFF8484D);
  static const Color alertBackground = Color(0xFF190E12);

  // Circulation
  static const Color trafficFluid = Color(0xFF4EAA33);
  static const Color trafficSlow = Color(0xFFF09E1B);
  static const Color trafficJam = Color(0xFFF72119);

  // Plaque d'immatriculation française
  static const Color plateWhite = Color(0xFFF4F5F7);
  static const Color plateEuBlue = Color(0xFF1F4FB4);

  // Texte
  static const Color textPrimary = Color(0xFFF2F7FA);
  static const Color textSecondary = Color(0xFFA9B8C4);
  static const Color textMuted = Color(0xFF5E6C73);

  // Bordures lumineuses
  static Color border([double opacity = 0.35]) => cyan.withValues(alpha: opacity);
  static Color glow([double opacity = 0.45]) => cyan.withValues(alpha: opacity);
}
