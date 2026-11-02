import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/vr_colors.dart';
import '../../../core/theme/vr_typography.dart';
import '../../../core/widgets/glow_panel.dart';
import '../../../core/widgets/vr_button.dart';
import '../../../app/version.dart';
import '../../navigation/application/navigation_session.dart';
import '../application/app_policy_controller.dart';
import '../application/update_controller.dart';

/// Enveloppe toute l'application : quand une nouvelle version est publiée,
/// une fenêtre centrée et bloquante (mise à jour obligatoire) recouvre
/// l'écran. Une seule fenêtre à la fois, quel que soit le nombre de
/// vérifications.
class UpdateGate extends ConsumerWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(updatePromptVisibleProvider);
    final locked = ref.watch(policyLockVisibleProvider);
    // Version refusée par le serveur VIGIROAD : on cherche aussitôt le
    // fichier de mise à jour (Android) pour proposer l'installation directe.
    ref.listen(appPolicyProvider.select((p) => p.status), (_, next) {
      if (next == PolicyStatus.outdated) unawaited(ref.read(updateProvider.notifier).check());
    });
    final blocked = ref.watch(appPolicyProvider.select((p) => p.status == PolicyStatus.blocked));
    return Stack(
      children: [
        child,
        // Blocage à distance : rien d'autre n'est accessible.
        if (locked && (blocked || !visible))
          const Positioned.fill(child: _Overlay(child: _PolicyCard()))
        else if (visible)
          const Positioned.fill(child: _UpdateOverlay()),
      ],
    );
  }
}

/// Version refusée ou application bloquée : écran bloquant, sauf pendant un
/// guidage en cours (affiché à l'arrivée ou à l'arrêt, par sécurité).
final policyLockVisibleProvider = Provider<bool>((ref) {
  final locked = ref.watch(appPolicyProvider.select((p) => p.locked));
  final guiding = ref.exists(navigationSessionProvider) &&
      ref.watch(navigationSessionProvider.select((s) => s.hasRoute));
  return locked && !guiding;
});

/// Fond assombri, aucun toucher ne passe.
class _Overlay extends StatelessWidget {
  const _Overlay({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: ColoredBox(color: Colors.black.withValues(alpha: 0.72)),
        ),
      ),
      const Positioned.fill(child: ModalBarrier(dismissible: false)),
      Center(
        child: SafeArea(
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24), child: child),
        ),
      ),
    ],
  );
}

class _PolicyCard extends ConsumerWidget {
  const _PolicyCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(appPolicyProvider);
    final c = ref.read(appPolicyProvider.notifier);
    final u = ref.watch(updateProvider);
    final blocked = p.status == PolicyStatus.blocked;
    return Material(
      type: MaterialType.transparency,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: GlowPanel(
          tone: blocked ? PanelTone.alert : PanelTone.normal,
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          radius: 22,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  blocked ? Icons.block_rounded : Icons.system_update_rounded,
                  color: blocked ? VrColors.alert : VrColors.cyan,
                  size: 48,
                ),
                const SizedBox(height: 8),
                Text(
                  blocked ? 'Application suspendue' : 'Version obsolète',
                  textAlign: TextAlign.center,
                  style: VrText.sectionTitle.copyWith(fontSize: 20),
                ),
                const SizedBox(height: 8),
                Text(
                  p.message ??
                      (blocked
                          ? 'VIGIROAD est temporairement suspendu.'
                          : 'Cette version de VIGIROAD n\'est plus utilisable : installez la dernière version.'),
                  textAlign: TextAlign.center,
                  style: VrText.caption.copyWith(color: VrColors.textPrimary, fontSize: 13),
                ),
                if (!blocked) ...[
                  const SizedBox(height: 16),
                  _VersionRow('Version installée', appVersionLabel, VrColors.textSecondary),
                  if (p.latestVersion != null) ...[
                    const SizedBox(height: 6),
                    _VersionRow('Dernière version', p.latestVersion!, VrColors.cyan),
                  ],
                  const SizedBox(height: 16),
                  VrButton(
                    label: u.status == UpdateStatus.downloading ? 'Téléchargement…' : 'Mettre à jour',
                    icon: Icons.system_update_rounded,
                    style: VrButtonStyle.primary,
                    expanded: true,
                    onPressed: () async {
                      // Android : installation directe si le fichier est publié,
                      // sinon (iPhone) page de téléchargement.
                      await ref.read(updateProvider.notifier).check();
                      if (!ref.read(updateProvider).pending) await c.openDownloadPage();
                    },
                  ),
                ],
                const SizedBox(height: 8),
                VrButton(
                  label: 'Réessayer',
                  icon: Icons.refresh_rounded,
                  expanded: true,
                  onPressed: c.check,
                ),
                const SizedBox(height: 8),
                VrButton(
                  label: 'Quitter l\'application',
                  icon: Icons.power_settings_new_rounded,
                  expanded: true,
                  onPressed: () => SystemNavigator.pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UpdateOverlay extends ConsumerWidget {
  const _UpdateOverlay();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // La fenêtre recouvre toutes les pages : le bouton retour peut quitter
    // l'application mais jamais contourner la mise à jour.
    return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) => Stack(
          children: [
            // Arrière-plan assombri et légèrement flouté ; aucun toucher ne passe.
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 4 * t, sigmaY: 4 * t),
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.62 * t)),
              ),
            ),
            const Positioned.fill(child: ModalBarrier(dismissible: false)),
            Center(
              child: Opacity(
                opacity: t,
                child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
              ),
            ),
          ],
        ),
        child: const SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: _UpdateCard(),
          ),
        ),
    );
  }
}

class _UpdateCard extends ConsumerWidget {
  const _UpdateCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(updateProvider);
    final c = ref.read(updateProvider.notifier);
    final m = s.manifest!;
    final busy = s.status == UpdateStatus.downloading || s.status == UpdateStatus.installing;

    return Material(
      type: MaterialType.transparency,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: GlowPanel(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          radius: 22,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Fusée (icône de l'application, identique sur tous les téléphones).
                const Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Color(0x6619CFF4), blurRadius: 24)],
                    ),
                    child: Icon(Icons.rocket_launch_rounded, color: VrColors.cyan, size: 46),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Nouvelle mise à jour disponible !',
                  textAlign: TextAlign.center,
                  style: VrText.sectionTitle.copyWith(fontSize: 20),
                ),
                const SizedBox(height: 8),
                Text(
                  'Une nouvelle version de VIGIROAD est disponible.',
                  textAlign: TextAlign.center,
                  style: VrText.caption.copyWith(color: VrColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 16),
                _VersionRow('Version actuelle', s.installed?.versionName ?? '?', VrColors.textSecondary),
                const SizedBox(height: 6),
                _VersionRow('Nouvelle version', m.version, VrColors.cyan),
                if (m.notes.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Améliorations :', style: VrText.label),
                  const SizedBox(height: 6),
                  for (final n in m.notes.take(8))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('•  ', style: VrText.caption.copyWith(color: VrColors.cyan)),
                          Expanded(child: Text(n, style: VrText.caption.copyWith(color: VrColors.textPrimary))),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 14),
                Text(
                  'Cette mise à jour est obligatoire : la version installée n\'est plus prise en charge.',
                  textAlign: TextAlign.center,
                  style: VrText.caption.copyWith(color: VrColors.trafficSlow, fontSize: 12),
                ),
                const SizedBox(height: 16),
                ..._status(s, c),
                if (s.status == UpdateStatus.needsPermission)
                  VrButton(
                    label: 'Autoriser l\'installation',
                    icon: Icons.verified_user_rounded,
                    style: VrButtonStyle.primary,
                    expanded: true,
                    onPressed: c.openInstallSettings,
                  )
                else
                  VrButton(
                    label: switch (s.status) {
                      UpdateStatus.downloading => 'Téléchargement… ${(s.progress * 100).round()} %',
                      UpdateStatus.installing => 'Installation…',
                      UpdateStatus.failed => 'Réessayer',
                      _ => 'Mettre à jour maintenant',
                    },
                    icon: Icons.system_update_rounded,
                    style: VrButtonStyle.primary,
                    expanded: true,
                    onPressed: busy ? null : c.updateNow,
                  ),
                const SizedBox(height: 8),
                VrButton(
                  label: 'Quitter l\'application',
                  icon: Icons.power_settings_new_rounded,
                  expanded: true,
                  onPressed: busy ? null : () => SystemNavigator.pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _status(UpdateState s, UpdateController c) {
    switch (s.status) {
      case UpdateStatus.downloading:
        return [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: s.progress > 0 ? s.progress : null,
              minHeight: 6,
              backgroundColor: VrColors.cyan.withValues(alpha: 0.12),
              valueColor: const AlwaysStoppedAnimation(VrColors.cyan),
            ),
          ),
          const SizedBox(height: 12),
        ];
      case UpdateStatus.installing:
        return [
          Text(
            'Confirmez l\'installation dans la fenêtre d\'Android. VIGIROAD redémarrera sur la nouvelle version.',
            textAlign: TextAlign.center,
            style: VrText.caption.copyWith(color: VrColors.textSecondary),
          ),
          const SizedBox(height: 12),
        ];
      case UpdateStatus.needsPermission:
        return [
          Text(
            'Android doit autoriser VIGIROAD à installer ses mises à jour (une seule fois) : activez '
            '« Autoriser cette source », puis revenez dans l\'application.',
            textAlign: TextAlign.center,
            style: VrText.caption.copyWith(color: VrColors.textSecondary),
          ),
          const SizedBox(height: 12),
        ];
      case UpdateStatus.failed:
        return [
          Text(
            s.message ?? 'La mise à jour a échoué.',
            textAlign: TextAlign.center,
            style: VrText.caption.copyWith(color: VrColors.alertText),
          ),
          const SizedBox(height: 12),
        ];
      case UpdateStatus.none:
      case UpdateStatus.available:
        return const [];
    }
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow(this.label, this.value, this.color);
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: VrColors.background.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Row(
      children: [
        Expanded(child: Text(label, style: VrText.caption.copyWith(color: VrColors.textSecondary))),
        Text(value, style: VrText.label.copyWith(color: color)),
      ],
    ),
  );
}

/// Version affichée sur l'écran de version obsolète.
const appVersionLabel = '$appVersion ($appBuild)';
