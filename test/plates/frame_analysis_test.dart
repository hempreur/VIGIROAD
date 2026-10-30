import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vigiroad/features/plates/domain/frame_analysis.dart';

void main() {
  const w = 320, h = 240;

  Uint8List image(int Function(int x, int y) f) {
    final b = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        b[y * w + x] = f(x, y).clamp(0, 255);
      }
    }
    return b;
  }

  test('image nette (damier) bien plus nette qu\'une image floue (dégradé)', () {
    final sharp = image((x, y) => ((x ~/ 4 + y ~/ 4).isEven) ? 230 : 20);
    final blurry = image((x, y) => 100 + x ~/ 8);
    final vs = laplacianVariance(sharp, width: w, height: h, rowStride: w);
    final vb = laplacianVariance(blurry, width: w, height: h, rowStride: w);
    expect(vs, greaterThan(1000));
    expect(vb, lessThan(5));
  });

  test('luminosité moyenne', () {
    expect(meanLuma(image((_, _) => 40), width: w, height: h, rowStride: w), 40);
  });

  test('pixels entrelacés (BGRA) et pas de ligne', () {
    final b = Uint8List(w * h * 4)..fillRange(0, w * h * 4, 200);
    expect(meanLuma(b, width: w, height: h, rowStride: w * 4, pixelStride: 4), 200);
  });

  group('FrameThrottle', () {
    final t0 = DateTime(2026);
    test('une seule analyse à la fois', () {
      final th = FrameThrottle();
      expect(th.shouldProcess(t0), isTrue);
      th.begin(t0);
      expect(th.shouldProcess(t0.add(const Duration(seconds: 1))), isFalse);
    });

    test('ralentit quand l\'OCR est lent, plafonné', () {
      final th = FrameThrottle();
      for (var i = 0; i < 20; i++) {
        th.begin(t0);
        th.end(const Duration(milliseconds: 900));
      }
      expect(th.interval, th.maxInterval);
      for (var i = 0; i < 40; i++) {
        th.begin(t0);
        th.end(const Duration(milliseconds: 40));
      }
      expect(th.interval, th.minInterval);
    });

    test('respecte l\'intervalle', () {
      final th = FrameThrottle();
      th.begin(t0);
      th.end(const Duration(milliseconds: 100));
      expect(th.shouldProcess(t0.add(const Duration(milliseconds: 50))), isFalse);
      expect(th.shouldProcess(t0.add(const Duration(milliseconds: 400))), isTrue);
    });
  });
}
