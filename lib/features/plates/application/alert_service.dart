import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../navigation/application/navigation_providers.dart';
import '../../navigation/application/navigation_session.dart';
import '../data/repositories.dart';
import '../domain/alert_decider.dart';
import '../domain/plate_models.dart';
import 'plate_scanning_controller.dart';
import 'plates_providers.dart';
import 'watchlist_controller.dart';

/// Son d'alerte.
abstract interface class AlertSound {
  Future<void> play({double volume});
}

class AssetAlertSound implements AlertSound {
  final _player = AudioPlayer();

  @override
  Future<void> play({double volume = 1}) async {
    await _player.stop();
    await _player.setVolume(volume);
    await _player.play(AssetSource('sounds/alert.wav'));
  }
}

/// Réglages d'alerte (écran de réglages en phase 8).
class AlertSettings {
  const AlertSettings({
    this.sound = true,
    this.volume = 1,
    this.announce = true,
    this.logHistory = true,
    this.policy = const AlertPolicy(),
  });

  final bool sound;
  final double volume;

  /// Annonce vocale par SENTRIX.
  final bool announce;

  /// Enregistrement des correspondances dans l'historique.
  final bool logHistory;
  final AlertPolicy policy;
}

final alertSettingsProvider = Provider<AlertSettings>((ref) => const AlertSettings());
final alertSoundProvider = Provider<AlertSound>((ref) => AssetAlertSound());

/// Événements récents (diagnostic, tests).
final alertServiceProvider = NotifierProvider<AlertService, List<MatchOutcome>>(AlertService.new);

/// Relie la lecture des plaques à la liste : chaque plaque confirmée est
/// comparée ; une correspondance fiable déclenche encadré rouge, son,
/// annonce SENTRIX et journalisation. Les plaques non listées ne laissent
/// aucune trace.
class AlertService extends Notifier<List<MatchOutcome>> {
  late AlertDecider _decider;

  @override
  List<MatchOutcome> build() {
    final settings = ref.watch(alertSettingsProvider);
    _decider = AlertDecider(settings.policy);
    final sub = ref.read(plateScanningProvider.notifier).confirmed.listen(handle);
    ref.onDispose(sub.cancel);
    return const [];
  }

  Future<void> handle(PlateReading reading) async {
    final index = ref.read(watchlistIndexProvider);
    final outcome = _decider.examine(reading, (p) => index[p], ref.read(clockProvider)());
    state = [outcome, ...state.take(19)];
    if (outcome is! Raise) return;

    final alert = outcome.alert;
    final settings = ref.read(alertSettingsProvider);
    ref.read(activeAlertProvider.notifier).raise(alert);

    if (settings.sound) unawaited(ref.read(alertSoundProvider).play(volume: settings.volume));
    if (settings.announce) {
      // Annonce courte, épelée pour être comprise en conduisant.
      final spelled = alert.reading.display.split('').join(' ').replaceAll('-', ',');
      unawaited(ref.read(speakerProvider).speak('Alerte. Plaque $spelled. ${alert.category}.'));
    }
    if (settings.logHistory) {
      final pos = ref.read(positionProvider).value?.point;
      final log = await ref.read(detectionLogProvider.future);
      await log.add(DetectionRecord(
        plate: alert.reading.normalized,
        display: alert.reading.display,
        country: alert.reading.country,
        category: alert.category,
        priority: alert.priority,
        confidence: alert.reading.confidence,
        at: alert.at,
        latitude: pos?.latitude,
        longitude: pos?.longitude,
      ));
      ref.invalidate(detectionsProvider);
    }
  }
}

/// Historique des correspondances.
final detectionsProvider = FutureProvider<List<DetectionRecord>>(
  (ref) async => (await ref.watch(detectionLogProvider.future)).recent(),
);
