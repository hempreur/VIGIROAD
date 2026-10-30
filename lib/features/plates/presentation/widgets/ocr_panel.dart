import 'package:flutter/material.dart';

import '../../../../core/theme/vr_colors.dart';
import '../../../../core/theme/vr_typography.dart';
import '../../../../core/widgets/glow_panel.dart';
import '../../../../core/widgets/plate_badge.dart';
import '../../domain/plate_models.dart';

/// Fenêtre « Lecture OCR » : dernière plaque lue + détails (confiance,
/// pays, type), comme le bloc sous la caméra dans la référence.
class OcrPanel extends StatelessWidget {
  const OcrPanel({super.key, required this.reading});

  /// `null` tant qu'aucune plaque n'a été lue avec une confiance suffisante.
  final PlateReading? reading;

  @override
  Widget build(BuildContext context) {
    final r = reading;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 6,
          child: GlowPanel(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.document_scanner_outlined, color: VrColors.cyan, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Lecture OCR',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: VrText.sectionTitle.copyWith(fontSize: 17, color: VrColors.textPrimary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: PlateBadge(
                      text: r?.display,
                      countryLetter: euBandLetter(r?.country ?? 'FR'),
                      height: 46,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 4,
          child: GlowPanel(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _meta('Confiance', r == null ? '—' : '${r.confidencePercent} %'),
                _meta('Pays', r == null ? '—' : countryName(r.country)),
                _meta('Type', r?.vehicleType ?? '—'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _meta(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$label : ', style: VrText.caption),
            TextSpan(
              text: value,
              style: VrText.caption.copyWith(color: VrColors.textPrimary, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
