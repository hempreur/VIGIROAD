import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vigiroad/core/audio/voice_queue.dart';
import 'package:vigiroad/features/navigation/data/speaker.dart';

/// Moteur vocal dont la fin de chaque phrase est pilotée par le test.
class _ManualSpeaker implements Speaker {
  final log = <String>[];
  final _done = <Completer<void>>[];
  int stops = 0;

  @override
  Future<void> speak(String text) {
    log.add(text);
    final c = Completer<void>();
    _done.add(c);
    return c.future;
  }

  /// Termine la phrase en cours.
  void finish() {
    final open = _done.where((c) => !c.isCompleted);
    if (open.isNotEmpty) open.first.complete();
  }

  @override
  Future<void> stop() async {
    stops++;
    finish();
  }
}

void main() {
  late _ManualSpeaker speaker;
  late VoiceQueue q;
  var now = DateTime(2026);

  setUp(() {
    speaker = _ManualSpeaker();
    now = DateTime(2026);
    q = VoiceQueue(speaker, clock: () => now);
  });

  test('une seule voix à la fois, dans l\'ordre', () async {
    unawaited(q.say('A1', VoicePriority.assistant));
    unawaited(q.say('A2', VoicePriority.assistant));
    await pumpEventQueue();
    expect(speaker.log, ['A1']);
    speaker.finish();
    await pumpEventQueue();
    expect(speaker.log, ['A1', 'A2']);
  });

  test('une consigne de navigation interrompt SENTRIX', () async {
    final sentrix = q.say('Réponse longue de SENTRIX', VoicePriority.assistant);
    await pumpEventQueue();
    final guidance = q.say('Dans 300 mètres, tournez à droite.', VoicePriority.guidance);
    await pumpEventQueue();
    expect(speaker.stops, 1);
    expect(speaker.log.last, 'Dans 300 mètres, tournez à droite.');
    expect(await sentrix, isFalse, reason: 'interrompue');
    speaker.finish();
    expect(await guidance, isTrue);
  });

  test('une alerte n\'interrompt pas une consigne : elle attend son tour', () async {
    unawaited(q.say('Tournez à gauche.', VoicePriority.guidance));
    await pumpEventQueue();
    unawaited(q.say('Alerte. Plaque A A …', VoicePriority.alert));
    unawaited(q.say('Réponse SENTRIX', VoicePriority.assistant));
    await pumpEventQueue();
    expect(speaker.stops, 0);
    expect(speaker.log, ['Tournez à gauche.']);
    speaker.finish();
    await pumpEventQueue();
    expect(speaker.log.last, 'Alerte. Plaque A A …');
    speaker.finish();
    await pumpEventQueue();
    expect(speaker.log.last, 'Réponse SENTRIX');
  });

  test('seule la consigne la plus récente est gardée en attente', () async {
    unawaited(q.say('Consigne 1', VoicePriority.guidance));
    await pumpEventQueue();
    final stale = q.say('Consigne 2', VoicePriority.guidance);
    final fresh = q.say('Consigne 3', VoicePriority.guidance);
    expect(await stale, isFalse);
    speaker.finish();
    await pumpEventQueue();
    speaker.finish();
    expect(await fresh, isTrue);
    expect(speaker.log, ['Consigne 1', 'Consigne 3']);
  });

  test('une alerte coupée par une consigne est répétée ensuite', () async {
    final alert = q.say('Alerte plaque', VoicePriority.alert);
    await pumpEventQueue();
    unawaited(q.say('Tournez maintenant.', VoicePriority.guidance));
    await pumpEventQueue();
    speaker.finish();
    await pumpEventQueue();
    expect(speaker.log, ['Alerte plaque', 'Tournez maintenant.', 'Alerte plaque']);
    speaker.finish();
    expect(await alert, isTrue);
  });

  test('annonce périmée abandonnée', () async {
    unawaited(q.say('Longue phrase', VoicePriority.guidance));
    await pumpEventQueue();
    final late = q.say('Réponse tardive', VoicePriority.assistant);
    now = now.add(const Duration(seconds: 20));
    speaker.finish();
    expect(await late, isFalse);
    expect(speaker.log, ['Longue phrase']);
  });

  test('effacement ciblé', () async {
    unawaited(q.say('SENTRIX', VoicePriority.assistant));
    await pumpEventQueue();
    await q.clear(only: VoicePriority.assistant);
    await pumpEventQueue();
    expect(q.speaking, isFalse);
  });
}
