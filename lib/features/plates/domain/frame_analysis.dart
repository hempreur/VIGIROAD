import 'dart:math' as math;
import 'dart:typed_data';

/// Mesure de netteté par variance du laplacien sur le plan de luminance.
///
/// Calculée sur une grille sous-échantillonnée (≈ 160 × 120 points) pour
/// rester négligeable devant l'OCR. Valeur élevée = image nette.
double laplacianVariance(
  Uint8List luma, {
  required int width,
  required int height,
  required int rowStride,
  int pixelStride = 1,
  int targetWidth = 160,
}) {
  final step = math.max(1, width ~/ targetWidth);
  var sum = 0.0, sumSq = 0.0;
  var n = 0;
  int at(int x, int y) => luma[y * rowStride + x * pixelStride];
  for (var y = step; y < height - step; y += step) {
    for (var x = step; x < width - step; x += step) {
      final l = at(x - step, y) + at(x + step, y) + at(x, y - step) + at(x, y + step) - 4 * at(x, y);
      sum += l;
      sumSq += l * l;
      n++;
    }
  }
  if (n == 0) return 0;
  final mean = sum / n;
  return sumSq / n - mean * mean;
}

/// Luminosité moyenne (0–255) sur une grille sous-échantillonnée.
double meanLuma(Uint8List luma, {required int width, required int height, required int rowStride, int pixelStride = 1}) {
  final step = math.max(1, width ~/ 80);
  var sum = 0, n = 0;
  for (var y = 0; y < height; y += step) {
    for (var x = 0; x < width; x += step) {
      sum += luma[y * rowStride + x * pixelStride];
      n++;
    }
  }
  return n == 0 ? 0 : sum / n;
}

/// Cadence d'analyse adaptative.
///
/// Une seule analyse à la fois ; l'intervalle entre deux analyses s'allonge
/// quand l'OCR est lent (téléphone chargé ou chaud) et se raccourcit sinon,
/// entre [minInterval] et [maxInterval].
class FrameThrottle {
  FrameThrottle({
    this.minInterval = const Duration(milliseconds: 150),
    this.maxInterval = const Duration(milliseconds: 1000),
  }) : _interval = minInterval > const Duration(milliseconds: 250) ? minInterval : const Duration(milliseconds: 250);

  final Duration minInterval;
  final Duration maxInterval;
  Duration _interval;
  DateTime? _lastStart;
  bool _busy = false;

  Duration get interval => _interval;
  bool get busy => _busy;

  /// Faut-il analyser l'image arrivant à [now] ?
  bool shouldProcess(DateTime now) {
    if (_busy) return false;
    final last = _lastStart;
    return last == null || now.difference(last) >= _interval;
  }

  void begin(DateTime now) {
    _busy = true;
    _lastStart = now;
  }

  /// Fin d'analyse : ajuste l'intervalle à 1,5 × la durée mesurée (lissée).
  void end(Duration took) {
    _busy = false;
    final target = took * 1.5;
    final smoothed = Duration(microseconds: (_interval.inMicroseconds * 0.7 + target.inMicroseconds * 0.3).round());
    _interval = smoothed < minInterval ? minInterval : (smoothed > maxInterval ? maxInterval : smoothed);
  }

  /// Ralentissement forcé (ex. surchauffe signalée), réversible par [end].
  void backOff() => _interval = maxInterval;
}
