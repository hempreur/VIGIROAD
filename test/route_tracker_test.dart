import 'package:flutter_test/flutter_test.dart';
import 'package:vigiroad/features/navigation/domain/guidance_policy.dart';
import 'package:vigiroad/features/navigation/domain/route_tracker.dart';

import 'helpers/fakes.dart';

void main() {
  group('RouteTracker', () {
    final route = testRoute();

    test('longueur du tracé ≈ 1500 m', () {
      expect(RouteTracker(route).length, closeTo(1500, 5));
    });

    test('progression sur le premier tronçon', () {
      final t = RouteTracker(route);
      final p = t.update(north(300, 4));
      expect(p.offRouteM, closeTo(4, 1));
      expect(p.alongM, closeTo(300, 3));
      expect(p.remainingM, closeTo(1200, 5));
      expect(p.nextStepIndex, 1);
      expect(p.toNextManeuverM, closeTo(700, 5));
      expect(p.remainingS, closeTo(180 * 1200 / 1500, 2));
      expect(p.speedLimitKmh, 50);
      expect(p.arrived, isFalse);
    });

    test('après le virage : prochaine étape = arrivée, limitation 30', () {
      final t = RouteTracker(route);
      t.update(north(900));
      final p = t.update(north(1000, 200));
      expect(p.nextStepIndex, 2);
      expect(p.toNextManeuverM, closeTo(300, 5));
      expect(p.speedLimitKmh, 30);
    });

    test('arrivée', () {
      final t = RouteTracker(route);
      t.update(north(1000, 400));
      expect(t.update(north(1000, 495)).arrived, isTrue);
    });

    test('écart au tracé mesuré', () {
      final p = RouteTracker(route).update(north(500, 150));
      expect(p.offRouteM, closeTo(150, 3));
    });
  });

  group('OffRouteDetector', () {
    test('exige plusieurs positions hors trajet consécutives', () {
      final t = RouteTracker(testRoute());
      final d = OffRouteDetector();
      final off = t.update(north(500, 120));
      final on = t.update(north(500, 5));
      expect(d.feed(off), isFalse);
      expect(d.feed(off), isFalse);
      expect(d.feed(on), isFalse, reason: 'retour sur le trajet : compteur remis à zéro');
      expect(d.feed(off), isFalse);
      expect(d.feed(off), isFalse);
      expect(d.feed(off), isTrue);
    });

    test('tolère une précision GPS médiocre', () {
      final p = RouteTracker(testRoute()).update(north(500, 60));
      final d = OffRouteDetector();
      for (var i = 0; i < 5; i++) {
        expect(d.feed(p, accuracyM: 50), isFalse);
      }
    });
  });

  group('GuidancePolicy', () {
    test('annonce une fois par palier, adaptée à la vitesse', () {
      final route = testRoute();
      final t = RouteTracker(route);
      final g = GuidancePolicy();
      String? at(double m) => g.next(t.update(north(m)), route, speedKmh: 50);

      expect(at(100), isNull, reason: 'à 900 m de la manœuvre, au-delà du palier ville');
      expect(at(520), startsWith('Dans 500 mètres, tournez à droite'));
      expect(at(530), isNull);
      expect(at(830), startsWith('Dans 170 mètres'));
      expect(at(840), isNull);
      expect(at(975), 'Tournez à droite sur Avenue Victoria.');
      expect(at(980), isNull);
    });

    test('paliers plus lointains sur voie rapide', () {
      expect(GuidancePolicy.thresholds(110).early, 2000);
      expect(GuidancePolicy.thresholds(70).prepare, 350);
      expect(GuidancePolicy.thresholds(30).now, 35);
    });

    test('annonce de départ', () {
      expect(GuidancePolicy().start(testRoute()), startsWith('Guidage démarré, suivez Rue de Rivoli. Dans 1 kilomètre, tournez à droite'));
    });
  });
}
