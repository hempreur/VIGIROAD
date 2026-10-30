import 'plate_models.dart';
import 'watch_entry.dart';

/// Réglages des alertes.
class AlertPolicy {
  const AlertPolicy({
    this.minConfidence = 0.8,
    this.cooldown = const Duration(minutes: 5),
  });

  /// Confiance minimale d'une lecture confirmée pour déclencher l'alerte.
  final double minConfidence;

  /// Une même plaque ne redéclenche pas d'alerte avant ce délai.
  final Duration cooldown;
}

/// Résultat de l'examen d'une plaque confirmée.
sealed class MatchOutcome {
  const MatchOutcome();
}

/// Plaque absente de la liste : aucune trace conservée.
class NotListed extends MatchOutcome {
  const NotListed();
}

/// Plaque listée mais lecture pas assez sûre.
class LowConfidence extends MatchOutcome {
  const LowConfidence(this.entry, this.confidence);
  final WatchEntry entry;
  final double confidence;
}

/// Plaque listée, déjà signalée récemment.
class Suppressed extends MatchOutcome {
  const Suppressed(this.entry);
  final WatchEntry entry;
}

/// Alerte à déclencher.
class Raise extends MatchOutcome {
  const Raise(this.alert);
  final PlateAlert alert;
}

/// Compare les plaques confirmées à la liste (correspondance exacte sur la
/// forme normalisée) et décide des alertes, sans répétition.
class AlertDecider {
  AlertDecider(this.policy);

  final AlertPolicy policy;
  final _lastAlert = <String, DateTime>{};

  MatchOutcome examine(PlateReading reading, WatchEntry? Function(String plate) lookup, DateTime now) {
    final entry = lookup(reading.normalized);
    if (entry == null) return const NotListed();
    if (reading.confidence < policy.minConfidence) return LowConfidence(entry, reading.confidence);
    final last = _lastAlert[reading.normalized];
    if (last != null && now.difference(last) < policy.cooldown) return Suppressed(entry);
    _lastAlert[reading.normalized] = now;
    return Raise(PlateAlert(reading: reading, category: entry.category, priority: entry.priority, at: now));
  }

  void reset() => _lastAlert.clear();
}
