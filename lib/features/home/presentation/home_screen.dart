import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/config/app_config.dart';
import '../../../core/theme/vr_colors.dart';
import '../../../core/theme/vr_typography.dart';
import '../../../core/widgets/brand_wordmark.dart';
import '../../../core/widgets/glow_panel.dart';
import '../../../core/widgets/vr_backdrop.dart';
import '../../sentrix/presentation/sentrix_head.dart';

/// Accueil provisoire de la phase 1.
///
/// Affiche honnêtement l'état d'avancement de chaque module (règle 2 :
/// aucune simulation présentée comme opérationnelle). Il sera remplacé par
/// l'écran GPS principal en phase 2/3.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const _modules = <(IconData, String, String)>[
    (Icons.navigation_rounded, 'Navigation GPS', 'Phase 3'),
    (Icons.traffic_rounded, 'Trafic', 'Fournisseur à brancher'),
    (Icons.photo_camera_rounded, 'Caméra & OCR', 'Phase 4'),
    (Icons.storage_rounded, 'Base de plaques & alertes', 'Phase 5'),
    (Icons.mic_rounded, 'Assistant SENTRIX', 'Phase 6'),
    (Icons.history_rounded, 'Historique & réglages', 'Phase 8'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    return Scaffold(
      body: VrBackdrop(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Center(child: SentrixHead(size: 110)),
              const SizedBox(height: 16),
              const Center(child: BrandWordmark(size: 32)),
              const SizedBox(height: 4),
              const Center(
                child: Text(
                  'Version de développement — socle technique (phase 1)',
                  style: VrText.caption,
                ),
              ),
              const SizedBox(height: 28),
              const Text('MODULES', style: VrText.sectionTitle),
              const SizedBox(height: 12),
              GlowPanel(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Column(
                  children: [
                    for (final (icon, title, status) in _modules)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            Icon(icon, color: VrColors.cyan),
                            const SizedBox(width: 14),
                            Expanded(child: Text(title, style: VrText.label)),
                            Text(status, style: VrText.caption),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Environnement : ${config.environment.name}'
                '${config.environment == AppEnvironment.prod ? '' : ' (non production)'}',
                style: VrText.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
