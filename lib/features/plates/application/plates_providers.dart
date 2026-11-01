import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/plate_models.dart';

/// Dernière plaque **dangereuse** confirmée (présente dans la liste de
/// surveillance). Les plaques ordinaires ne sont jamais affichées.
final lastReadingProvider = NotifierProvider<LastReadingController, PlateReading?>(
  LastReadingController.new,
);

class LastReadingController extends Notifier<PlateReading?> {
  @override
  PlateReading? build() => null;

  void update(PlateReading reading) => state = reading;
  void clear() => state = null;
}

/// Alerte de correspondance affichée à l'écran. Alimentée par le moteur de
/// correspondance (phase 5).
final activeAlertProvider = NotifierProvider<ActiveAlertController, PlateAlert?>(
  ActiveAlertController.new,
);

class ActiveAlertController extends Notifier<PlateAlert?> {
  @override
  PlateAlert? build() => null;

  void raise(PlateAlert alert) => state = alert;
  void dismiss() => state = null;
}

/// Plaques dangereuses vues récemment (lecture multi-plaques) : la plus
/// prioritaire est dans [activeAlertProvider], les autres sont signalées
/// sur l'encadré (« +1 »).
final recentAlertsProvider = NotifierProvider<RecentAlertsController, List<PlateAlert>>(RecentAlertsController.new);

class RecentAlertsController extends Notifier<List<PlateAlert>> {
  /// Durée pendant laquelle une alerte compte parmi les plaques simultanées.
  static const window = Duration(seconds: 45);

  @override
  List<PlateAlert> build() => const [];

  /// Ajoute (ou rafraîchit) une alerte ; renvoie la plus prioritaire.
  PlateAlert add(PlateAlert alert) {
    final kept = [
      for (final a in state)
        if (a.reading.normalized != alert.reading.normalized && alert.at.difference(a.at) < window) a,
      alert,
    ]..sort((a, b) {
      final p = b.priority.index.compareTo(a.priority.index);
      return p != 0 ? p : b.at.compareTo(a.at);
    });
    state = kept;
    return kept.first;
  }

  void clear() => state = const [];
}
