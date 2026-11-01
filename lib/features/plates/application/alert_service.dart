import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/voice_providers.dart';
import '../../navigation/application/navigation_providers.dart';
import '../../settings/application/settings_controller.dart';
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
    this.saveLocation = true,
    this.retention,
    this.policy = const AlertPolicy(),
  });

  final bool sound;
  final double volume;

  /// Annonce vocale par SENTRIX.
  final bool announce;

  /// Enregistrement des correspondances dans l'historique.
  final bool logHistory;

  /// Enregistrer la position GPS avec la correspondance.
  final bool saveLocation;

  /// Durée de conservation de l'historique (`null` = illimitée).
  final Duration? retention;
  final AlertPolicy policy;
}

/// Réglages d'alerte issus des réglages de l'application.
final alertSettingsProvider = Provider<AlertSettings>((ref) {
  final s = ref.watch(appSettingsProvider);
  return AlertSettings(
    sound: s.alertSound,
    volume: s.alertVolume,
    announce: s.sentrixAnnounce,
    logHistory: s.logHistory,
    saveLocation: s.saveLocation,
    retention: s.retention.duration,
    policy: AlertPolicy(minConfidence: s.minConfidence),
  );
});
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
    // Seule une plaque dangereuse (présente dans la liste) est affichée.
    if (outcome is Suppressed) ref.read(lastReadingProvider.notifier).update(reading);
    if (outcome is! Raise) return;

    final alert = outcome.alert;
    final settings = ref.read(alertSettingsProvider);
    ref.read(lastReadingProvider.notifier).update(reading);
    // Plusieurs plaques dangereuses en même temps : la plus prioritaire en tête.
    ref.read(activeAlertProvider.notifier).raise(ref.read(recentAlertsProvider.notifier).add(alert));

    if (settings.sound) unawaited(ref.read(alertSoundProvider).play(volume: settings.volume));
    if (settings.announce) {
      // Annonce courte, épelée pour être comprise en conduisant.
      final spelled = alert.reading.display.split('').join(' ').replaceAll('-', ',');
      unawaited(ref.read(voiceQueueProvider).say('Alerte. Plaque $spelled. ${alert.category}.', VoicePriority.alert));
    }
    if (settings.logHistory) {
      final pos = settings.saveLocation ? ref.read(positionProvider).value?.point : null;
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
      if (settings.retention != null) {
        await log.purgeOlderThan(alert.at.subtract(settings.retention!));
      }
      ref.invalidate(detectionsProvider);
    }
  }
}

/// Historique des correspondances.
/// La durée de conservation est appliquée à chaque lecture de l'historique.
final detectionsProvider = FutureProvider<List<DetectionRecord>>((ref) async {
  final log = await ref.watch(detectionLogProvider.future);
  final retention = ref.watch(alertSettingsProvider.select((s) => s.retention));
  if (retention != null) {
    await log.purgeOlderThan(ref.read(clockProvider)().subtract(retention));
  }
  return log.recent();
});
