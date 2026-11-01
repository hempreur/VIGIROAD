import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:vigiroad/features/plates/domain/camera_tuning.dart';

void main() {
  final t0 = DateTime(2026, 11, 1, 20);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  group('anti-vibrations (gyroscope)', () {
    test('sans gyroscope : toutes les images sont analysées', () {
      final g = MotionGate();
      expect(g.shouldAnalyze(t0), isTrue);
      expect(g.hasSensor, isFalse);
    });

    test('secousse : image ignorée, puis analysée au calme', () {
      final g = MotionGate(smoothing: 0);
      g.addGyro(0.9, 0.2, 0.1);
      expect(g.calm, isFalse);
      expect(g.shouldAnalyze(at(0)), isFalse);
      expect(g.shouldAnalyze(at(200)), isFalse);
      g.addGyro(0.05, 0.02, 0.01);
      expect(g.shouldAnalyze(at(250)), isTrue);
    });

    test('vibrations continues : une image quand même au bout du délai', () {
      final g = MotionGate(smoothing: 0, maxWait: const Duration(milliseconds: 700));
      g.addGyro(1, 1, 1);
      expect(g.shouldAnalyze(at(0)), isFalse);
      expect(g.shouldAnalyze(at(500)), isFalse);
      expect(g.shouldAnalyze(at(700)), isTrue);
      expect(g.shouldAnalyze(at(750)), isFalse, reason: 'nouvelle attente');
    });

    test('lissage : un pic isolé ne bloque pas', () {
      final g = MotionGate();
      for (var i = 0; i < 10; i++) {
        g.addGyro(0.02, 0.01, 0);
      }
      g.addGyro(0.3, 0, 0);
      expect(g.calm, isTrue);
    });
  });

  group('netteté adaptative', () {
    test('image floue de bougé écartée par rapport aux images récentes', () {
      final g = SharpnessGate();
      for (var i = 0; i < 8; i++) {
        expect(g.accept(120), isTrue);
      }
      expect(g.accept(40), isFalse, reason: '3 fois plus floue que d\'habitude');
      expect(g.accept(100), isTrue);
    });

    test('plancher absolu', () {
      expect(SharpnessGate(floor: 12).accept(8), isFalse);
    });

    test('scène peu contrastée (nuit) : seuil relatif, pas absolu', () {
      final g = SharpnessGate();
      for (var i = 0; i < 8; i++) {
        expect(g.accept(20), isTrue);
      }
      expect(g.accept(18), isTrue);
    });
  });

  group('zoom et mise au point', () {
    test('plaque lointaine au centre : zoom progressif jusqu\'à la taille cible', () {
      final t = CameraTuner(maxZoom: 3);
      final a = t.update([const Rect.fromLTWH(0.46, 0.5, 0.06, 0.02)], at(0));
      expect(a.zoom, closeTo(1.3, 1e-9), reason: 'pas maximal de ×1,3');
      expect(a.focus, isNotNull);
      expect(a.focus!.dx, closeTo(0.49, 1e-9));
      // Trop tôt pour un nouveau pas.
      expect(t.update([const Rect.fromLTWH(0.45, 0.5, 0.08, 0.03)], at(200)).zoom, isNull);
      final b = t.update([const Rect.fromLTWH(0.45, 0.5, 0.08, 0.03)], at(500));
      expect(b.zoom, closeTo(1.3 * 1.3, 1e-9));
    });

    test('jamais au-delà du zoom maximal', () {
      final t = CameraTuner(maxZoom: 2);
      var ms = 0;
      for (var i = 0; i < 10; i++) {
        t.update([const Rect.fromLTWH(0.48, 0.5, 0.03, 0.01)], at(ms));
        ms += 500;
      }
      expect(t.zoom, 2);
    });

    test('plaque excentrée : zoom limité pour la garder dans le champ', () {
      final t = CameraTuner(maxZoom: 3);
      final a = t.update([const Rect.fromLTWH(0.70, 0.5, 0.06, 0.02)], at(0));
      // Bord droit à 0,76 → 0,26 du centre ; (0,5 − 0,06) / 0,26 ≈ 1,69 > 1,3 : pas plein.
      expect(a.zoom, closeTo(1.3, 1e-9));
      final t2 = CameraTuner(maxZoom: 3);
      final b = t2.update([const Rect.fromLTWH(0.86, 0.5, 0.06, 0.02)], at(0));
      expect(b.zoom, isNull, reason: 'déjà près du bord : zoomer la ferait sortir');
    });

    test('plusieurs plaques : toutes restent dans le champ', () {
      final t = CameraTuner(maxZoom: 3);
      final a = t.update([
        const Rect.fromLTWH(0.20, 0.5, 0.05, 0.02),
        const Rect.fromLTWH(0.70, 0.45, 0.07, 0.02),
      ], at(0));
      // Plaque gauche à 0,30 du centre → facteur ≤ 0,44 / 0,30 ≈ 1,47 ; pas de 1,3.
      expect(a.zoom, closeTo(1.3, 1e-9));
      final b = t.update([
        const Rect.fromLTWH(0.01, 0.5, 0.05, 0.02),
        const Rect.fromLTWH(0.70, 0.45, 0.07, 0.02),
      ], at(600));
      expect(b.zoom, closeTo(1.3 / 1.3, 1e-9), reason: 'plaque collée au bord : dézoom');
    });

    test('plaque trop proche : dézoom', () {
      final t = CameraTuner(maxZoom: 3);
      t.update([const Rect.fromLTWH(0.47, 0.5, 0.05, 0.02)], at(0));
      expect(t.zoom, greaterThan(1));
      final a = t.update([const Rect.fromLTWH(0.3, 0.4, 0.42, 0.1)], at(600));
      expect(a.zoom, lessThan(1.3));
    });

    test('plus de plaque : retour au grand angle et mise au point automatique', () {
      final t = CameraTuner(maxZoom: 3);
      t.update([const Rect.fromLTWH(0.47, 0.5, 0.05, 0.02)], at(0));
      expect(t.update(const [], at(1000)).isEmpty, isTrue, reason: 'pas tout de suite');
      final a = t.update(const [], at(1700));
      expect(a.zoom, closeTo(1, 1e-9));
      expect(a.resetFocus, isTrue);
      expect(t.update(const [], at(3000)).isEmpty, isTrue);
    });

    test('mise au point renouvelée si la plaque se déplace', () {
      final t = CameraTuner(maxZoom: 1);
      expect(t.update([const Rect.fromLTWH(0.4, 0.5, 0.2, 0.05)], at(0)).focus, isNotNull);
      expect(t.update([const Rect.fromLTWH(0.41, 0.5, 0.2, 0.05)], at(300)).focus, isNull);
      expect(t.update([const Rect.fromLTWH(0.1, 0.3, 0.2, 0.05)], at(600)).focus, isNotNull);
      expect(t.update([const Rect.fromLTWH(0.1, 0.3, 0.2, 0.05)], at(3000)).focus, isNotNull, reason: 'rafraîchie');
    });

    test('mise au point sur la plaque la plus proche (la plus grande)', () {
      final t = CameraTuner(maxZoom: 1);
      final a = t.update([
        const Rect.fromLTWH(0.1, 0.5, 0.06, 0.02),
        const Rect.fromLTWH(0.6, 0.6, 0.2, 0.06),
      ], at(0));
      expect(a.focus!.dx, closeTo(0.7, 1e-9));
    });
  });
}
