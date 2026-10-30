import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'plate_format.dart';
import 'plate_models.dart';

/// Une plaque vue sur une image du flux caméra.
class PlateObservation {
  const PlateObservation({
    required this.candidate,
    required this.at,
    this.ocrConfidence,
    this.box,
  });

  final PlateCandidate candidate;
  final DateTime at;

  /// Confiance OCR de la ligne (Android uniquement ; `null` sur iOS).
  final double? ocrConfidence;

  /// Boîte englobante dans l'image analysée.
  final Rect? box;

  /// Qualité d'une observation : confiance OCR, pénalisée par les corrections.
  double get quality => ((ocrConfidence ?? 0.85) - 0.08 * candidate.corrections).clamp(0.05, 1.0);
}

/// Paramètres de confirmation.
class VoterSettings {
  const VoterSettings({
    this.window = const Duration(milliseconds: 2500),
    this.minVotes = 3,
    this.minAgreement = 0.6,
    this.minConfidence = 0.7,
    this.reemitAfter = const Duration(seconds: 10),
  });

  /// Fenêtre glissante d'observations prises en compte.
  final Duration window;

  /// Nombre minimal de lectures identiques pour confirmer.
  final int minVotes;

  /// Part minimale de la lecture majoritaire parmi les lectures voisines
  /// (qui ne diffèrent que d'un caractère).
  final double minAgreement;

  /// Confiance agrégée minimale pour confirmer.
  final double minConfidence;

  /// Une même plaque confirmée n'est réémise qu'après ce délai.
  final Duration reemitAfter;
}

/// Combine les lectures de plusieurs images pour confirmer une plaque.
///
/// Une lecture OCR isolée n'est jamais considérée comme fiable : il faut
/// [VoterSettings.minVotes] lectures identiques dans la fenêtre, majoritaires
/// face aux variantes proches (« AA123BB » contre « AA123B8 »), avec une
/// confiance agrégée suffisante.
class PlateVoter {
  PlateVoter([this.settings = const VoterSettings()]);

  final VoterSettings settings;
  final _obs = <PlateObservation>[];
  final _emitted = <String, DateTime>{};

  /// Ajoute les observations d'une image ; retourne les plaques confirmées
  /// à cet instant (nouvelles ou réémises après le délai).
  List<PlateReading> add(Iterable<PlateObservation> frame, DateTime now) {
    _obs.addAll(frame);
    _obs.removeWhere((o) => now.difference(o.at) > settings.window);
    _emitted.removeWhere((_, t) => now.difference(t) > settings.reemitAfter * 3);

    final byPlate = <String, List<PlateObservation>>{};
    for (final o in _obs) {
      byPlate.putIfAbsent(o.candidate.normalized, () => []).add(o);
    }

    final confirmed = <PlateReading>[];
    for (final MapEntry(key: plate, value: votes) in byPlate.entries) {
      if (votes.length < settings.minVotes) continue;
      final rivals = byPlate.entries
          .where((e) => e.key != plate && _nearlyEqual(e.key, plate))
          .fold<int>(0, (n, e) => n + e.value.length);
      final agreement = votes.length / (votes.length + rivals);
      if (agreement < settings.minAgreement) continue;

      final quality = votes.map((o) => o.quality).reduce((a, b) => a + b) / votes.length;
      // Bonus de concordance : plus de votes = plus de certitude, plafonné.
      final support = math.min(1.0, 0.75 + 0.05 * votes.length);
      final confidence = (quality * agreement * support).clamp(0.0, 0.99);
      if (confidence < settings.minConfidence) continue;

      final last = _emitted[plate];
      if (last != null && now.difference(last) < settings.reemitAfter) continue;
      _emitted[plate] = now;

      final c = votes.first.candidate;
      confirmed.add(PlateReading(
        normalized: plate,
        display: c.display,
        confidence: confidence,
        country: c.country,
      ));
    }
    return confirmed;
  }

  void reset() {
    _obs.clear();
    _emitted.clear();
  }

  /// Même longueur et au plus un caractère différent.
  static bool _nearlyEqual(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      if (a.codeUnitAt(i) != b.codeUnitAt(i) && ++diff > 1) return false;
    }
    return true;
  }
}
