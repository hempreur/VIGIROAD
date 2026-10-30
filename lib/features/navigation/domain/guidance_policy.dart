import 'instructions.dart';
import 'route.dart';
import 'route_tracker.dart';

/// Moments d'annonce d'une manœuvre.
enum AnnounceStage { early, prepare, now }

/// Décide quand annoncer vocalement la prochaine manœuvre.
///
/// Trois annonces par manœuvre au plus (« Dans 1 kilomètre… », « Dans 300
/// mètres… », « Tournez à droite. »), avec des distances adaptées à la
/// vitesse ; chaque annonce n'est prononcée qu'une fois.
class GuidancePolicy {
  final _done = <(int, AnnounceStage)>{};
  int? _lastStep;

  /// Distances de déclenchement (mètres) selon la vitesse.
  static ({double early, double prepare, double now}) thresholds(double speedKmh) {
    if (speedKmh >= 90) return (early: 2000, prepare: 700, now: 120);
    if (speedKmh >= 55) return (early: 1000, prepare: 350, now: 70);
    return (early: 500, prepare: 180, now: 35);
  }

  /// Annonce de départ, prononcée au début du guidage.
  String start(NavRoute route) {
    final first = route.steps.length > 1 ? route.steps[1] : route.steps.first;
    final firstRoad = Instructions.road(route.steps.first);
    final lead = firstRoad.isEmpty ? 'Guidage démarré.' : 'Guidage démarré, suivez $firstRoad.';
    return '$lead ${Instructions.spoken(first, inMeters: route.steps.first.distanceM)}';
  }

  /// Phrase à prononcer maintenant, ou `null`.
  String? next(RouteProgress p, NavRoute route, {required double speedKmh}) {
    final i = p.nextStepIndex;
    if (i != _lastStep) _lastStep = i;
    final step = route.steps[i];
    final d = p.toNextManeuverM;
    final t = thresholds(speedKmh);

    AnnounceStage? stage;
    if (d <= t.now) {
      stage = AnnounceStage.now;
    } else if (d <= t.prepare) {
      stage = AnnounceStage.prepare;
    } else if (d <= t.early && d > t.prepare * 1.6) {
      stage = AnnounceStage.early;
    }
    if (stage == null) return null;
    // Une étape déjà franchie (prepare/now) rend caduques les précédentes.
    if (!_done.add((i, stage))) return null;
    if (stage == AnnounceStage.prepare) _done.add((i, AnnounceStage.early));
    if (stage == AnnounceStage.now) {
      _done
        ..add((i, AnnounceStage.early))
        ..add((i, AnnounceStage.prepare));
    }
    return Instructions.spoken(step, inMeters: stage == AnnounceStage.now ? 0 : d);
  }

  void reset() {
    _done.clear();
    _lastStep = null;
  }
}
