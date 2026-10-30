import 'package:flutter/widgets.dart';

import 'vr_colors.dart';

/// Styles de texte VIGIROAD.
///
/// Rajdhani (condensée, technique) pour les titres, chiffres et plaques —
/// comme les intitulés de l'image de référence ; Inter pour le texte courant.
abstract final class VrText {
  static const String display = 'Rajdhani';
  static const String body = 'Inter';

  static const TextStyle brand = TextStyle(
    fontFamily: display,
    fontWeight: FontWeight.w700,
    fontSize: 40,
    letterSpacing: 6,
    color: VrColors.textPrimary,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontFamily: display,
    fontWeight: FontWeight.w700,
    fontSize: 20,
    letterSpacing: 1.2,
    color: VrColors.cyan,
  );

  /// Grand chiffre de navigation (distance avant manœuvre, vitesse).
  static const TextStyle metric = TextStyle(
    fontFamily: display,
    fontWeight: FontWeight.w700,
    fontSize: 30,
    height: 1,
    color: VrColors.textPrimary,
  );

  static const TextStyle plate = TextStyle(
    fontFamily: display,
    fontWeight: FontWeight.w700,
    fontSize: 32,
    letterSpacing: 1.5,
    color: Color(0xFF111418),
  );

  static const TextStyle label = TextStyle(
    fontFamily: body,
    fontWeight: FontWeight.w500,
    fontSize: 14,
    color: VrColors.textPrimary,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: body,
    fontWeight: FontWeight.w400,
    fontSize: 12.5,
    color: VrColors.textSecondary,
  );
}
