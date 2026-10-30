import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/theme/vr_colors.dart';
import '../../../core/theme/vr_typography.dart';
import '../../../core/widgets/glow_panel.dart';
import '../../../core/widgets/vr_page.dart';

/// Réglages. Cette version affiche l'état réel des autorisations et des
/// services configurés ; les réglages de détection, d'alerte et de voix
/// arrivent avec leurs modules (phases 4 à 8).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static String _statusLabel(CapabilityStatus? s) => switch (s) {
    CapabilityStatus.granted => 'Autorisé',
    CapabilityStatus.permanentlyDenied => 'Refusé — à modifier dans les réglages',
    CapabilityStatus.restricted => 'Restreint par le système',
    CapabilityStatus.denied => 'Non autorisé',
    null => 'Vérification…',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final perms = ref.watch(permissionsProvider).value;
    final controller = ref.read(permissionsProvider.notifier);

    return VrPage(
      title: 'Réglages',
      children: [
        const Text('AUTORISATIONS', style: VrText.sectionTitle),
        const SizedBox(height: 10),
        GlowPanel(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Column(
            children: [
              for (final c in AppCapability.values)
                InfoRow(
                  label: c.title,
                  value: _statusLabel(perms?[c]),
                  trailing: perms?[c] == CapabilityStatus.granted
                      ? const Icon(Icons.check_circle_rounded, color: VrColors.trafficFluid)
                      : TextButton(
                          onPressed: perms?[c] == CapabilityStatus.denied
                              ? () => controller.request(c)
                              : controller.openSettings,
                          child: const Text('Modifier', style: TextStyle(color: VrColors.cyan)),
                        ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text('SERVICES', style: VrText.sectionTitle),
        const SizedBox(height: 10),
        GlowPanel(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Column(
            children: [
              InfoRow(label: 'Fond de carte', value: Uri.parse(config.mapStyleUrl).host),
              InfoRow(label: 'Itinéraires', value: Uri.parse(config.routingBaseUrl).host),
              InfoRow(label: 'Recherche d\'adresses', value: Uri.parse(config.geocodingBaseUrl).host),
              const InfoRow(label: 'Trafic en temps réel', value: 'Aucun fournisseur configuré'),
              InfoRow(
                label: 'Synchronisation des plaques',
                value: config.platesSyncEnabled ? Uri.parse(config.platesSyncUrl).host : 'Désactivée',
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text('À PROPOS', style: VrText.sectionTitle),
        const SizedBox(height: 10),
        GlowPanel(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Column(
            children: [
              InfoRow(label: 'Environnement', value: config.environment.name),
              const InfoRow(label: 'Version', value: '1.0.0 (développement)'),
              const InfoRow(
                label: 'Données cartographiques',
                value: '© contributeurs OpenStreetMap, style © CARTO',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
