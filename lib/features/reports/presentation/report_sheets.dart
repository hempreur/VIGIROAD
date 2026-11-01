import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vigiroad_traffic/vigiroad_traffic.dart';

import '../../../core/theme/vr_colors.dart';
import '../../../core/theme/vr_typography.dart';
import '../../../core/widgets/glow_panel.dart';
import '../../navigation/application/navigation_providers.dart';
import '../application/reports_controller.dart';
import 'chicken_button.dart';

/// Émoji du marqueur de signalement (pas d'émoji « tenders » : le pilon de
/// volaille en est le plus proche).
const chickenMarkerEmoji = '🍗';

/// Fenêtre ouverte par le bouton Chicken : ma route (flèche vers le haut)
/// ou route d'en face (flèche vers le bas).
Future<void> showChickenReportSheet(BuildContext context, WidgetRef ref) async {
  final side = await showModalBottomSheet<ReportSide>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => const ChickenReportSheet(),
  );
  if (side == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final result = await ref.read(reportsProvider.notifier).submit(side);
  messenger.showSnackBar(SnackBar(
    content: Text(switch (result) {
      Submitted(report: final r) when r.confirmations > 1 =>
        '$chickenMarkerEmoji Signalement confirmé (${r.confirmations} conducteurs) — visible 2 h',
      Submitted() => '$chickenMarkerEmoji Chicken signalé ${side == ReportSide.mine ? 'sur votre route' : 'en face'} — visible 2 h par les conducteurs proches',
      SubmitFailed(:final message) => message,
    }),
  ));
}

class ChickenReportSheet extends StatelessWidget {
  const ChickenReportSheet({super.key});

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: GlowPanel(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                ChickenIcon(),
                SizedBox(width: 12),
                Expanded(child: Text('Signaler un Chicken', style: VrText.label)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Où est-il ? Le marqueur $chickenMarkerEmoji reste 2 h sur la carte de tous les conducteurs proches.',
              style: VrText.caption,
            ),
            const SizedBox(height: 14),
            const Row(
              children: [
                Expanded(
                  child: _SideButton(side: ReportSide.mine, icon: Icons.arrow_upward_rounded, label: 'Ma route'),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: _SideButton(side: ReportSide.opposite, icon: Icons.arrow_downward_rounded, label: 'Route en face'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _SideButton extends StatelessWidget {
  const _SideButton({required this.side, required this.icon, required this.label});

  final ReportSide side;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: Material(
      color: VrColors.panelLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFFFB020), width: 1.6),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).pop(side),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(
            children: [
              Icon(icon, size: 52, color: const Color(0xFFFFB020)),
              const SizedBox(height: 6),
              Text(label, style: VrText.label.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Détail d'un marqueur touché sur la carte.
void showChickenReportDetails(BuildContext context, ChickenReport r, {double? myHeading, required DateTime now}) {
  final ago = now.difference(r.createdAt);
  final left = r.expiresAt.difference(now);
  String dur(Duration d) => d.inMinutes < 1 ? 'moins d\'une minute' : d.inMinutes < 60 ? '${d.inMinutes} min' : '${d.inHours} h ${(d.inMinutes % 60).toString().padLeft(2, '0')}';
  final where = myHeading == null || r.heading == null
      ? (r.side == ReportSide.mine ? 'Sur la route du conducteur qui l\'a signalé' : 'Sur la voie d\'en face du conducteur qui l\'a signalé')
      : (r.concerns(myHeading) ? 'Dans votre sens de circulation' : 'Dans le sens opposé au vôtre');
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: GlowPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('$chickenMarkerEmoji  Chicken signalé', style: VrText.label),
              const SizedBox(height: 8),
              Text(where, style: VrText.caption.copyWith(color: VrColors.textPrimary)),
              Text('Signalé il y a ${dur(ago)}${r.confirmations > 1 ? ' · confirmé par ${r.confirmations} conducteurs' : ''}', style: VrText.caption),
              Text('Disparaît dans ${dur(left.isNegative ? Duration.zero : left)}', style: VrText.caption),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Ouvre le détail d'un signalement depuis l'écran de navigation.
void openChickenReport(BuildContext context, WidgetRef ref, ChickenReport r, DateTime now) {
  final fix = ref.read(positionProvider).value;
  showChickenReportDetails(context, r, myHeading: fix != null && fix.headingReliable ? fix.headingDeg : null, now: now);
}

/// Image du marqueur (pastille sombre cerclée d'ambre + 🍗), en PNG pour la
/// carte MapLibre (dont les polices ne contiennent pas d'émoji).
Future<Uint8List> renderChickenMarker({double size = 96}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final c = Offset(size / 2, size / 2);
  final r = size * 0.42;
  canvas.drawCircle(c, r + size * 0.04, Paint()..color = const Color(0xFFFFB020).withValues(alpha: 0.45)..maskFilter = MaskFilter.blur(BlurStyle.normal, size * 0.04));
  canvas.drawCircle(c, r, Paint()..color = const Color(0xFF07131E));
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..color = const Color(0xFFFFB020)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size * 0.05,
  );
  final tp = TextPainter(
    text: TextSpan(text: chickenMarkerEmoji, style: TextStyle(fontSize: size * 0.46)),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  final image = await recorder.endRecording().toImage(size.round(), size.round());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}
