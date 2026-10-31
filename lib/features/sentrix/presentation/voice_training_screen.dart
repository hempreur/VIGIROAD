import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/vr_colors.dart';
import '../../../core/theme/vr_typography.dart';
import '../../../core/widgets/glow_panel.dart';
import '../../../core/widgets/vr_button.dart';
import '../../../core/widgets/vr_page.dart';
import '../application/voice_training_controller.dart';
import '../data/voice_samples.dart';

/// Version affichée dans l'archive exportée.
const _appVersion = '1.1.2';

const _archive = VoiceTrainingController.archiveName;

/// Conseils pour varier les « Sentrix » (un modèle robuste a besoin de
/// prononciations, de volumes et de distances différents).
const _sentrixTips = [
  'Voix normale, téléphone à la main.',
  'Plus fort, comme pour couvrir la musique.',
  'Plus doucement, presque à voix basse.',
  'Plus vite, sans articuler.',
  'Téléphone sur son support, véhicule à l\'arrêt moteur allumé (ou passager).',
];

const _readingText =
    'Ce matin, nous avons pris l\'autoroute vers le centre-ville. Il y avait un peu de circulation '
    'à l\'entrée du tunnel, puis la route s\'est dégagée. Nous nous sommes arrêtés à la station-service '
    'pour prendre un café, avant de repartir vers la sortie numéro douze. Pense à appeler le garage '
    'demain pour la révision, et à vérifier la pression des pneus avant les vacances.';

/// Entraîner « Sentrix » avec sa voix : enregistrements stockés sur le
/// téléphone, exportés seulement à la demande de l'utilisateur.
class VoiceTrainingScreen extends ConsumerWidget {
  const VoiceTrainingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(voiceTrainingProvider);
    final c = ref.read(voiceTrainingProvider.notifier);
    final n = s.count(SampleKind.sentrix);
    final tip = _sentrixTips[(n ~/ 10).clamp(0, _sentrixTips.length - 1)];

    ref.listen(voiceTrainingProvider.select((x) => x.message), (_, m) {
      if (m != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    });

    return VrPage(
      title: 'Entraîner « Sentrix »',
      children: [
        const Text(
          'Pour que SENTRIX réagisse à votre voix quand vous dites « Sentrix », enregistrez le mot plusieurs '
          'fois, un peu de parole normale et le bruit de votre voiture. Les enregistrements restent sur ce '
          'téléphone ; vous les exportez vous-même pour l\'entraînement, et pouvez tout effacer à tout moment.',
          style: VrText.caption,
        ),
        const SizedBox(height: 6),
        Text(
          'En voiture : uniquement à l\'arrêt ou en tant que passager.',
          style: VrText.caption.copyWith(color: VrColors.trafficSlow),
        ),
        const SizedBox(height: 14),
        _Step(
          title: '1. Dites « Sentrix »',
          kind: SampleKind.sentrix,
          state: s,
          detail: 'Appuyez, attendez « Parlez maintenant », puis dites « Sentrix » une seule fois.\n$tip',
          onRecord: () => c.record(SampleKind.sentrix),
          onUndo: () => c.deleteLast(SampleKind.sentrix),
        ),
        const SizedBox(height: 10),
        _Step(
          title: '2. Parlez normalement (20 s)',
          kind: SampleKind.speech,
          state: s,
          detail: 'Lisez ce texte à voix haute, sans dire « Sentrix » :\n« $_readingText »',
          onRecord: () => c.record(SampleKind.speech),
          onUndo: () => c.deleteLast(SampleKind.speech),
        ),
        const SizedBox(height: 10),
        _Step(
          title: '3. Bruit de la voiture (20 s, facultatif)',
          kind: SampleKind.ambient,
          state: s,
          detail: 'Restez silencieux, moteur allumé à l\'arrêt, ventilation ou musique faible.',
          onRecord: () => c.record(SampleKind.ambient),
          onUndo: () => c.deleteLast(SampleKind.ambient),
        ),
        const SizedBox(height: 16),
        Text('4. Envoyez les enregistrements', style: VrText.label),
        const SizedBox(height: 6),
        Text(
          s.canExport
              ? 'Touchez « Envoyer » puis choisissez l\'application Claude (ou e-mail, Drive…) : le fichier '
                  '$_archive sera joint à votre message.'
              : 'Disponible après au moins ${SampleKind.sentrix.minimum} « Sentrix » et 1 enregistrement de parole normale.',
          style: VrText.caption.copyWith(color: VrColors.textSecondary),
        ),
        const SizedBox(height: 8),
        VrButton(
          label: 'Envoyer les enregistrements',
          icon: Icons.send_rounded,
          style: VrButtonStyle.primary,
          expanded: true,
          onPressed: s.canExport && s.recording == null ? () => c.export(appVersion: _appVersion) : null,
        ),
        const SizedBox(height: 8),
        VrButton(
          label: 'Enregistrer dans un fichier',
          icon: Icons.save_alt_rounded,
          expanded: true,
          onPressed: s.canExport && s.recording == null ? () => c.export(appVersion: _appVersion, toFile: true) : null,
        ),
        if (s.exported) ...[
          const SizedBox(height: 10),
          GlowPanel(
            padding: const EdgeInsets.all(14),
            child: Text(
              'Fichier prêt. Dans la conversation avec Claude, joignez $_archive (bouton « + » ou trombone) '
              'et envoyez-le. Vous pourrez ensuite effacer les enregistrements de ce téléphone.',
              style: VrText.caption.copyWith(color: VrColors.textPrimary),
            ),
          ),
        ],
        const SizedBox(height: 16),
        VrButton(
          label: 'Tout effacer',
          icon: Icons.delete_forever_rounded,
          expanded: true,
          onPressed: s.recording != null
              ? null
              : () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (d) => AlertDialog(
                      title: const Text('Effacer les enregistrements ?'),
                      content: const Text('Tous les enregistrements de votre voix seront supprimés de ce téléphone.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
                        TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Effacer')),
                      ],
                    ),
                  );
                  if (ok ?? false) await c.clear();
                },
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.title,
    required this.kind,
    required this.state,
    required this.detail,
    required this.onRecord,
    required this.onUndo,
  });

  final String title;
  final SampleKind kind;
  final VoiceTrainingState state;
  final String detail;
  final VoidCallback onRecord;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final n = state.count(kind);
    final busy = state.recording != null;
    final mine = state.recording == kind;
    final done = n >= kind.target;
    return GlowPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: VrText.label)),
              Text(
                '$n / ${kind.target}',
                key: ValueKey('count-${kind.name}'),
                style: VrText.label.copyWith(color: done ? VrColors.trafficFluid : VrColors.cyan),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(detail, style: VrText.caption.copyWith(color: VrColors.textSecondary)),
          const SizedBox(height: 10),
          if (mine) ...[
            Text(
              !state.live
                  ? 'Préparation du micro… attendez'
                  : kind == SampleKind.sentrix
                  ? 'Parlez maintenant…'
                  : 'Enregistrement…',
              style: VrText.caption.copyWith(color: state.live ? VrColors.cyan : VrColors.textMuted),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: state.level,
                minHeight: 6,
                backgroundColor: VrColors.cyan.withValues(alpha: 0.12),
                valueColor: const AlwaysStoppedAnimation(VrColors.cyan),
              ),
            ),
          ] else
            Row(
              children: [
                Expanded(
                  child: VrButton(
                    label: n == 0 ? 'Enregistrer' : 'Enregistrer encore',
                    icon: Icons.mic_rounded,
                    style: VrButtonStyle.primary,
                    onPressed: busy ? null : onRecord,
                  ),
                ),
                const SizedBox(width: 8),
                VrButton(label: 'Annuler', icon: Icons.undo_rounded, onPressed: busy || n == 0 ? null : onUndo),
              ],
            ),
        ],
      ),
    );
  }
}
