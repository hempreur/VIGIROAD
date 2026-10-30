import 'package:flutter/material.dart';

import '../../../core/widgets/vr_page.dart';

/// Historique des correspondances (journal alimenté en phase 5, filtres et
/// purge en phase 8).
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const VrPage(
      title: 'Historique',
      children: [
        EmptyStatePanel(
          icon: Icons.history_rounded,
          title: 'Aucune détection enregistrée',
          message: 'Seules les plaques présentes dans votre liste de surveillance '
              'sont journalisées ; les autres lectures sont oubliées immédiatement.',
        ),
      ],
    );
  }
}
