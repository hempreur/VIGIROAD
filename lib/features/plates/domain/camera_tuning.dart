import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

/// Filtre anti-vibrations par gyroscope.
///
/// Le téléphone fixé au pare-brise vibre (route, moteur) : une image prise
/// pendant une secousse est floue de bougé et l'OCR s'y trompe. On mesure la
/// vitesse angulaire (rad/s) en continu et on n'analyse que les images prises
/// pendant un instant calme. Si la route ne laisse jamais de répit, on
/// analyse quand même au bout de [maxWait] (la meilleure image possible
/// plutôt que rien).
class MotionGate {
  MotionGate({this.calmRadPerS = 0.25, this.maxWait = const Duration(milliseconds: 700), this.smoothing = 0.35});

  /// Vitesse angulaire sous laquelle l'image est considérée comme stable.
  final double calmRadPerS;
  final Duration maxWait;

  /// Lissage exponentiel des mesures (0 = aucun, 1 = figé).
  final double smoothing;

  double _level = 0;
  bool _hasSensor = false;
  DateTime? _waitingSince;

  /// Vitesse angulaire lissée (rad/s), 0 sans gyroscope.
  double get level => _level;
  bool get hasSensor => _hasSensor;

  void addGyro(double x, double y, double z) {
    final m = math.sqrt(x * x + y * y + z * z);
    _level = _hasSensor ? _level * smoothing + m * (1 - smoothing) : m;
    _hasSensor = true;
  }

  bool get calm => !_hasSensor || _level <= calmRadPerS;

  /// Faut-il analyser l'image qui arrive maintenant ?
  bool shouldAnalyze(DateTime now) {
    if (calm) {
      _waitingSince = null;
      return true;
    }
    final since = _waitingSince ??= now;
    if (now.difference(since) >= maxWait) {
      _waitingSince = null;
      return true;
    }
    return false;
  }
}

/// Seuil de netteté adaptatif.
///
/// La netteté absolue dépend de la scène (nuit, brouillard, ville) : une
/// image est écartée si elle est nettement plus floue que les images
/// récentes (flou de bougé), ou sous un plancher absolu.
class SharpnessGate {
  SharpnessGate({this.floor = 12, this.relative = 0.55, this.history = 20});

  final double floor;

  /// Part minimale de la netteté médiane récente.
  final double relative;
  final int history;
  final _recent = <double>[];

  double get median {
    if (_recent.isEmpty) return 0;
    final s = [..._recent]..sort();
    return s[s.length ~/ 2];
  }

  /// Enregistre la netteté et dit si l'image mérite l'OCR.
  bool accept(double sharpness) {
    final ok = sharpness >= floor && (_recent.length < 5 || sharpness >= median * relative);
    _recent.add(sharpness);
    if (_recent.length > history) _recent.removeAt(0);
    return ok;
  }

  void reset() => _recent.clear();
}

/// Réglage à appliquer à la caméra.
class TuningAction {
  const TuningAction({this.zoom, this.focus, this.resetFocus = false});

  /// Nouveau facteur de zoom (null = inchangé).
  final double? zoom;

  /// Point de mise au point et d'exposition, normalisé (0–1) dans l'image
  /// remise à l'endroit (null = inchangé).
  final Offset? focus;

  /// Retour à la mise au point automatique continue.
  final bool resetFocus;

  bool get isEmpty => zoom == null && focus == null && !resetFocus;
  static const none = TuningAction();
}

/// Zoom et mise au point automatiques sur les plaques repérées.
///
/// - Plaque trop petite pour être lue (moins de [smallWidth] de la largeur de
///   l'image) : zoom progressif, seulement si toutes les plaques visibles
///   restent dans le champ (le zoom est centré) ;
/// - plaque trop grande ou collée au bord : dézoom ;
/// - plus aucune plaque pendant [lostAfter] : retour progressif au grand
///   angle pour repérer les suivantes ;
/// - mise au point et exposition sur la plaque la plus proche (la plus
///   grande), renouvelées si elle se déplace ;
/// - changements espacés d'au moins [minStep] (pas d'oscillation).
class CameraTuner {
  CameraTuner({
    this.minZoom = 1,
    double maxZoom = 3,
    this.smallWidth = 0.11,
    this.targetWidth = 0.17,
    this.largeWidth = 0.38,
    this.edgeMargin = 0.06,
    this.maxStepFactor = 1.3,
    this.minStep = const Duration(milliseconds: 450),
    this.lostAfter = const Duration(milliseconds: 1600),
    this.refocusAfter = const Duration(seconds: 2),
  }) : maxZoom = math.max(minZoom, maxZoom),
       _zoom = minZoom;

  final double minZoom;
  final double maxZoom;
  final double smallWidth;
  final double targetWidth;
  final double largeWidth;
  final double edgeMargin;
  final double maxStepFactor;
  final Duration minStep;
  final Duration lostAfter;
  final Duration refocusAfter;

  double _zoom;
  DateTime? _lastZoomChange;
  DateTime? _lastSeen;
  Offset? _focus;
  DateTime? _focusAt;

  double get zoom => _zoom;
  Offset? get focus => _focus;

  /// Plaques repérées sur la dernière image analysée (cadres normalisés).
  TuningAction update(List<Rect> plates, DateTime now) {
    if (plates.isEmpty) return _noPlate(now);
    _lastSeen = now;
    final zoom = _zoomFor(plates, now);
    final focus = _focusFor(plates, now);
    return TuningAction(zoom: zoom, focus: focus);
  }

  TuningAction _noPlate(DateTime now) {
    final seen = _lastSeen;
    if (seen == null || now.difference(seen) < lostAfter) return TuningAction.none;
    double? zoom;
    if (_zoom > minZoom + 0.01 && _canChange(now)) {
      zoom = _set(math.max(minZoom, _zoom / maxStepFactor), now);
    }
    final reset = _focus != null;
    _focus = null;
    _focusAt = null;
    if (_zoom <= minZoom + 0.01) _lastSeen = null;
    return TuningAction(zoom: zoom, resetFocus: reset);
  }

  bool _canChange(DateTime now) => _lastZoomChange == null || now.difference(_lastZoomChange!) >= minStep;

  double _set(double z, DateTime now) {
    _zoom = z;
    _lastZoomChange = now;
    return z;
  }

  double? _zoomFor(List<Rect> plates, DateTime now) {
    if (!_canChange(now)) return null;
    final union = plates.reduce((a, b) => a.expandToInclude(b));
    final smallest = plates.map((p) => p.width).reduce(math.min);
    final largest = plates.map((p) => p.width).reduce(math.max);
    final nearEdge = union.left < edgeMargin / 2 ||
        union.top < edgeMargin / 2 ||
        union.right > 1 - edgeMargin / 2 ||
        union.bottom > 1 - edgeMargin / 2;

    if ((largest > largeWidth || nearEdge) && _zoom > minZoom + 0.01) {
      return _set(math.max(minZoom, _zoom / (nearEdge ? maxStepFactor : 1.15)), now);
    }
    if (smallest >= smallWidth || _zoom >= maxZoom - 0.01) return null;

    // Facteur voulu pour amener la plus petite plaque à la largeur cible…
    var f = math.min(maxStepFactor, targetWidth / smallest);
    // … limité pour que toutes les plaques restent dans le champ recadré.
    final room = [
      0.5 - union.left,
      union.right - 0.5,
      0.5 - union.top,
      union.bottom - 0.5,
    ].reduce(math.max);
    final fit = (0.5 - edgeMargin) / math.max(room, 1e-6);
    f = math.min(f, fit);
    final next = math.min(maxZoom, _zoom * f);
    if (next < _zoom * 1.05) return null;
    return _set(next, now);
  }

  Offset? _focusFor(List<Rect> plates, DateTime now) {
    final nearest = plates.reduce((a, b) => a.width * a.height >= b.width * b.height ? a : b);
    final c = nearest.center;
    final prev = _focus;
    final moved = prev == null || (prev - c).distance > 0.12;
    final stale = _focusAt == null || now.difference(_focusAt!) >= refocusAfter;
    if (!moved && !stale) return null;
    // Le zoom est centré : les coordonnées restent valables dans l'image.
    _focus = Offset(c.dx.clamp(0.0, 1.0), c.dy.clamp(0.0, 1.0));
    _focusAt = now;
    return _focus;
  }

  void reset() {
    _zoom = minZoom;
    _lastZoomChange = null;
    _lastSeen = null;
    _focus = null;
    _focusAt = null;
  }
}
