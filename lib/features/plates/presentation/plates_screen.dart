import 'package:flutter/material.dart';

import '../../../core/theme/vr_colors.dart';
import '../../../core/theme/vr_typography.dart';
import '../../../core/widgets/glow_panel.dart';
import '../../../core/widgets/vr_page.dart';

/// Gestion de la liste de plaques à surveiller.
///
/// La base chiffrée, l'import CSV/JSON et la saisie arrivent en phase 5 ;
/// l'écran documente dès maintenant le format attendu.
class PlatesScreen extends StatelessWidget {
  const PlatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const VrPage(
      title: 'Plaques à surveiller',
      children: [
        EmptyStatePanel(
          icon: Icons.storage_rounded,
          title: 'Aucune plaque enregistrée',
          message: 'L\'import de fichiers CSV/JSON et la saisie manuelle seront '
              'disponibles avec la base de plaques chiffrée (phase 5).',
        ),
        SizedBox(height: 20),
        Text('FORMAT DU FICHIER CSV', style: VrText.sectionTitle),
        SizedBox(height: 10),
        GlowPanel(
          child: Text(
            'plate,country,category,priority\n'
            'AA123BB,FR,Surveillance,high\n'
            'CC456DD,FR,Surveillance,medium',
            style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: VrColors.textPrimary, height: 1.5),
          ),
        ),
        SizedBox(height: 8),
        Text(
          'priority : low, medium ou high. Les tirets et espaces des plaques sont '
          'ignorés à l\'import. Exemple ci-dessus fictif.',
          style: VrText.caption,
        ),
      ],
    );
  }
}
