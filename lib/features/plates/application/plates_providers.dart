import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/plate_models.dart';

/// Dernière lecture OCR confirmée. Alimentée par le module caméra (phase 4) ;
/// reste vide tant que la lecture n'est pas active.
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
