import 'package:flutter/material.dart';

import '../../../../core/theme/vr_colors.dart';
import '../../../../core/theme/vr_typography.dart';
import '../../../../core/widgets/glow_panel.dart';
import '../../domain/geo_math.dart';
import '../../domain/route.dart';

/// Icône de manœuvre (flèche) pour le cartouche de guidage.
IconData maneuverIcon(RouteStep s) {
  final d = s.direction;
  final right = d == ManeuverDirection.right || d == ManeuverDirection.sharpRight;
  final left = d == ManeuverDirection.left || d == ManeuverDirection.sharpLeft;
  final slightRight = d == ManeuverDirection.slightRight;
  final slightLeft = d == ManeuverDirection.slightLeft;
  return switch (s.kind) {
    ManeuverKind.arrive => Icons.flag_rounded,
    ManeuverKind.roundabout || ManeuverKind.exitRoundabout => Icons.roundabout_right_rounded,
    ManeuverKind.offRamp || ManeuverKind.onRamp =>
      (left || slightLeft) ? Icons.ramp_left_rounded : Icons.ramp_right_rounded,
    ManeuverKind.fork => (left || slightLeft) ? Icons.fork_left_rounded : Icons.fork_right_rounded,
    ManeuverKind.merge => Icons.merge_rounded,
    _ when d == ManeuverDirection.uturn => Icons.u_turn_left_rounded,
    _ when right => Icons.turn_right_rounded,
    _ when left => Icons.turn_left_rounded,
    _ when slightRight => Icons.turn_slight_right_rounded,
    _ when slightLeft => Icons.turn_slight_left_rounded,
    _ => Icons.straight_rounded,
  };
}

/// Bandeau « Arrivée 15:42 · 23 min · 18,4 km » + bouton de guidage vocal.
class EtaChip extends StatelessWidget {
  const EtaChip({
    super.key,
    required this.arrival,
    required this.remainingS,
    required this.remainingM,
    required this.voiceOn,
    required this.onToggleVoice,
    this.rerouting = false,
  });

  final DateTime arrival;
  final double remainingS;
  final double remainingM;
  final bool voiceOn;
  final VoidCallback onToggleVoice;
  final bool rerouting;

  static String formatDuration(double seconds) {
    final min = (seconds / 60).round();
    if (min < 60) return '$min min';
    final h = min ~/ 60, m = min % 60;
    return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final time = '${arrival.hour.toString().padLeft(2, '0')}:${arrival.minute.toString().padLeft(2, '0')}';
    final text = rerouting
        ? 'Recalcul de l\'itinéraire…'
        : 'Arrivée $time  •  ${formatDuration(remainingS)}  •  ${formatDistance(remainingM)}';
    return GlowPanel(
      padding: const EdgeInsets.only(left: 12, right: 2),
      radius: 14,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            rerouting ? Icons.sync_rounded : Icons.schedule_rounded,
            size: 18,
            color: VrColors.cyan,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: VrText.label.copyWith(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            onPressed: onToggleVoice,
            tooltip: voiceOn ? 'Couper le guidage vocal' : 'Activer le guidage vocal',
            icon: Icon(
              voiceOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              color: voiceOn ? VrColors.textPrimary : VrColors.textMuted,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }
}
