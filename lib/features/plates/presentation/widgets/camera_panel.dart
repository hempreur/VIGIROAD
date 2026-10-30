import 'package:flutter/material.dart';

import '../../../../core/theme/vr_colors.dart';
import '../../../../core/theme/vr_typography.dart';
import '../../../../core/widgets/glow_panel.dart';

/// Panneau « Caméra arrière » intégré à la navigation.
///
/// [preview] reçoit le flux de la caméra quand la lecture est active
/// (branché en phase 4) ; sinon le panneau affiche l'état arrêté.
class CameraPanel extends StatelessWidget {
  const CameraPanel({
    super.key,
    required this.active,
    this.preview,
    this.inactiveMessage = 'Lecture des plaques arrêtée',
    this.inactiveDetail,
  });

  final bool active;
  final Widget? preview;
  final String inactiveMessage;
  final String? inactiveDetail;

  @override
  Widget build(BuildContext context) {
    return GlowPanel(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (active && preview != null)
              preview!
            else
              DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF0A1622), Color(0xFF03080E)],
                  ),
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 36, 16, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.videocam_off_rounded, color: VrColors.textMuted, size: 34),
                        const SizedBox(height: 8),
                        Text(inactiveMessage, style: VrText.label, textAlign: TextAlign.center),
                        if (inactiveDetail != null) ...[
                          const SizedBox(height: 2),
                          Text(inactiveDetail!, style: VrText.caption, textAlign: TextAlign.center),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            Positioned(left: 10, top: 10, child: _CameraBadge(live: active)),
          ],
        ),
      ),
    );
  }
}

class _CameraBadge extends StatelessWidget {
  const _CameraBadge({required this.live});

  final bool live;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: VrColors.background.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: VrColors.border(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: live ? VrColors.alert : VrColors.textMuted,
              boxShadow: live
                  ? [BoxShadow(color: VrColors.alert.withValues(alpha: 0.7), blurRadius: 6)]
                  : null,
            ),
          ),
          const SizedBox(width: 7),
          Text('Caméra arrière', style: VrText.label.copyWith(fontSize: 13)),
        ],
      ),
    );
  }
}
