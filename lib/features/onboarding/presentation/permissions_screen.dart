import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/theme/vr_colors.dart';
import '../../../core/theme/vr_typography.dart';
import '../../../core/widgets/glow_panel.dart';
import '../../../core/widgets/vr_backdrop.dart';
import '../../../core/widgets/vr_button.dart';
import '../../sentrix/domain/sentrix_state.dart';
import '../../sentrix/presentation/sentrix_head.dart';

/// Demande des autorisations caméra, GPS et micro, avec explication de
/// l'usage de chacune. L'application reste utilisable sans toutes les
/// autorisations : seules les fonctions concernées sont désactivées.
class PermissionsScreen extends ConsumerWidget {
  const PermissionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statuses = ref.watch(permissionsProvider);
    final controller = ref.read(permissionsProvider.notifier);

    return Scaffold(
      body: VrBackdrop(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            children: [
              const Row(
                children: [
                  SentrixHead(size: 76, state: SentrixState.speaking),
                  SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Avant de prendre la route, j\'ai besoin de quelques autorisations.',
                      style: VrText.label,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text('AUTORISATIONS', style: VrText.sectionTitle),
              const SizedBox(height: 12),
              ...switch (statuses) {
                AsyncData(:final value) => [
                  for (final c in AppCapability.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _CapabilityTile(
                        capability: c,
                        status: value[c] ?? CapabilityStatus.denied,
                        onRequest: () => controller.request(c),
                        onOpenSettings: controller.openSettings,
                      ),
                    ),
                ],
                AsyncError(:final error) => [
                  GlowPanel(
                    tone: PanelTone.alert,
                    child: Text(
                      'Impossible de lire l\'état des autorisations : $error',
                      style: VrText.label,
                    ),
                  ),
                ],
                _ => [
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(color: VrColors.cyan),
                    ),
                  ),
                ],
              },
              const SizedBox(height: 12),
              const Text(
                'Les images de la caméra sont analysées sur le téléphone et ne sont '
                'jamais envoyées. Vous pourrez modifier ces choix dans les réglages '
                'du système.',
                style: VrText.caption,
              ),
              const SizedBox(height: 24),
              VrButton(
                label: 'Continuer',
                icon: Icons.arrow_forward_rounded,
                style: VrButtonStyle.primary,
                expanded: true,
                onPressed: () => context.go(Routes.home),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CapabilityTile extends StatelessWidget {
  const _CapabilityTile({
    required this.capability,
    required this.status,
    required this.onRequest,
    required this.onOpenSettings,
  });

  final AppCapability capability;
  final CapabilityStatus status;
  final VoidCallback onRequest;
  final VoidCallback onOpenSettings;

  IconData get _icon => switch (capability) {
    AppCapability.location => Icons.near_me_rounded,
    AppCapability.camera => Icons.photo_camera_rounded,
    AppCapability.microphone => Icons.mic_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final granted = status == CapabilityStatus.granted;
    final blocked = status == CapabilityStatus.permanentlyDenied ||
        status == CapabilityStatus.restricted;

    return GlowPanel(
      child: Row(
        children: [
          Icon(_icon, color: VrColors.cyan, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  capability.title,
                  style: VrText.label.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(capability.purpose, style: VrText.caption),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (granted)
            const Icon(
              Icons.check_circle_rounded,
              color: VrColors.trafficFluid,
              semanticLabel: 'Autorisé',
            )
          else
            TextButton(
              onPressed: blocked ? onOpenSettings : onRequest,
              style: TextButton.styleFrom(
                foregroundColor: VrColors.cyan,
                minimumSize: const Size(48, 48),
              ),
              child: Text(blocked ? 'Réglages' : 'Autoriser'),
            ),
        ],
      ),
    );
  }
}
