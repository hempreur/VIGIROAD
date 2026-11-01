import 'package:flutter/material.dart';

import '../../../../core/theme/vr_colors.dart';
import '../../../../core/theme/vr_typography.dart';
import '../../../../core/widgets/glow_panel.dart';
import '../../domain/plate_models.dart';

/// Encadré d'alerte rouge : plaque de la liste de surveillance confirmée.
///
/// Placé en bas d'écran pour ne jamais masquer le cartouche de guidage
/// (règle 7).
class AlertBanner extends StatelessWidget {
  const AlertBanner({super.key, required this.alert, this.thumbnail, this.onDismiss, this.others = 0});

  final PlateAlert alert;

  /// Autres plaques dangereuses vues en même temps (lecture multi-plaques).
  final int others;

  /// Vignette du véhicule (si l'enregistrement d'image est activé).
  final Widget? thumbnail;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'Alerte : plaque ${alert.reading.display} détectée dans la liste de surveillance, '
          'catégorie ${alert.category}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onDismiss,
        child: GlowPanel(
          tone: PanelTone.alert,
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Row(
            children: [
              const Icon(Icons.warning_rounded, color: VrColors.alert, size: 46),
              const SizedBox(width: 10),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) => FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: box.maxWidth,
                      child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Plaque détectée dans la liste de surveillance',
                      maxLines: 2,
                      style: VrText.label.copyWith(
                        color: VrColors.alertText,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${alert.reading.display}  •  ${alert.category}${others > 0 ? '  •  +$others autre${others > 1 ? 's' : ''}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: VrText.label.copyWith(color: VrColors.alertText.withValues(alpha: 0.85)),
                    ),
                  ],
                ),
                    ),
                  ),
                ),
              ),
              if (thumbnail != null) ...[
                const SizedBox(width: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(width: 72, height: 54, child: thumbnail),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
