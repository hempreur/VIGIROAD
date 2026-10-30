import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/vr_colors.dart';
import '../../application/plate_scanning_controller.dart';

/// Aperçu caméra (recadré pour remplir le panneau) + cadres lumineux
/// autour des plaques repérées, comme dans la vue caméra de la référence.
class ScannerPreview extends ConsumerWidget {
  const ScannerPreview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(plateScannerProvider).controller;
    final (_, boxes) = ref.watch(plateScanningProvider.select((s) => (s.status, s.boxes)));
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: VrColors.background);
    }
    final preview = controller.value.previewSize;
    // previewSize est en paysage ; l'application est en portrait.
    final upright = preview == null ? const Size(720, 1280) : Size(preview.height, preview.width);
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox.fromSize(
          size: upright,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CameraPreview(controller),
              CustomPaint(painter: PlateBoxesPainter(boxes)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cadres cyan lumineux, coordonnées normalisées 0–1.
class PlateBoxesPainter extends CustomPainter {
  const PlateBoxesPainter(this.boxes);

  final List<Rect> boxes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in boxes) {
      final r = Rect.fromLTRB(b.left * size.width, b.top * size.height, b.right * size.width, b.bottom * size.height)
          .inflate(size.width * 0.012);
      final rr = RRect.fromRectAndRadius(r, Radius.circular(size.width * 0.012));
      canvas.drawRRect(
        rr,
        Paint()
          ..color = VrColors.cyan.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.012
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.01),
      );
      canvas.drawRRect(
        rr,
        Paint()
          ..color = VrColors.cyanBright
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.005,
      );
    }
  }

  @override
  bool shouldRepaint(PlateBoxesPainter old) => old.boxes != boxes;
}
