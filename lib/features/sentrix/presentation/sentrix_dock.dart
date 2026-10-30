import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/vr_colors.dart';
import '../../../core/theme/vr_typography.dart';
import '../../plates/application/plates_providers.dart';
import '../application/sentrix_controller.dart';
import '../domain/sentrix_state.dart';
import 'sentrix_head.dart';

/// Tête SENTRIX interactive : appui = écoute d'une commande (activation
/// manuelle), appui long = menu. L'état visuel suit l'écoute, l'analyse,
/// la réponse, les alertes et les erreurs.
class SentrixButton extends ConsumerWidget {
  const SentrixButton({super.key, required this.onLongPress, this.size = 78});

  final VoidCallback onLongPress;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(sentrixProvider);
    final alert = ref.watch(activeAlertProvider);
    final visual = alert != null && ui.visual == SentrixState.idle ? SentrixState.notification : ui.visual;
    return Semantics(
      button: true,
      label: ui.busy ? 'Annuler l\'écoute de SENTRIX' : 'Parler à SENTRIX',
      hint: 'Appui long : menu',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: ref.read(sentrixProvider.notifier).toggleListening,
        onLongPress: onLongPress,
        child: SentrixHead(size: size, state: visual),
      ),
    );
  }
}

/// Bulle de dialogue de SENTRIX (« Je vous écoute… »), comme sur la référence.
class SentrixBubble extends ConsumerWidget {
  const SentrixBubble({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(sentrixProvider);
    final text = ui.visual == SentrixState.listening ? (ui.transcript ?? ui.reply) : ui.reply;
    final error = ui.visual == SentrixState.error;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: text == null
          ? const SizedBox.shrink()
          : Semantics(
              key: ValueKey(text),
              liveRegion: true,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 250),
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                decoration: BoxDecoration(
                  color: VrColors.panel.withValues(alpha: 0.95),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(4),
                  ),
                  border: Border.all(color: (error ? VrColors.alert : VrColors.cyan).withValues(alpha: 0.7)),
                  boxShadow: [BoxShadow(color: VrColors.glow(0.25), blurRadius: 14)],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (ui.visual == SentrixState.listening && ui.transcript == null)
                      Text('Dites une commande', style: VrText.caption.copyWith(fontSize: 11.5)),
                    Text(
                      text,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: VrText.label.copyWith(
                        fontWeight: FontWeight.w600,
                        color: error ? VrColors.alertText : VrColors.textPrimary,
                        fontStyle: ui.visual == SentrixState.listening && ui.transcript != null
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
