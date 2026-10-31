import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vigiroad/app/providers.dart';
import 'package:vigiroad/core/audio/voice_providers.dart';
import 'package:vigiroad/features/navigation/application/navigation_session.dart';
import 'package:vigiroad/features/sentrix/application/sentrix_controller.dart';
import 'package:vigiroad/features/sentrix/application/wake_word_controller.dart';
import 'package:vigiroad/features/sentrix/data/wake_word_engine.dart';
import 'package:vigiroad/features/settings/application/settings_controller.dart';
import 'package:vigiroad/features/settings/domain/app_settings.dart';

import '../helpers/fakes.dart';

/// Modèles factices : enregistrent les entrées, score piloté par le test.
class FakeModels implements WakeWordModels {
  final melInputs = <Float32List>[];
  final embedInputs = <Float32List>[];
  final classifyInputs = <Float32List>[];
  double score = 0.0;
  bool closed = false;

  @override
  Future<List<Float32List>> mel(Float32List samples) async {
    melInputs.add(samples);
    // 8 trames par bloc, valeur = numéro d'appel (pour suivre l'ordre).
    return [for (var i = 0; i < 8; i++) Float32List(32)..fillRange(0, 32, melInputs.length * 10.0)];
  }

  @override
  Future<Float32List> embed(Float32List window) async {
    embedInputs.add(window);
    return Float32List(96)..fillRange(0, 96, embedInputs.length.toDouble());
  }

  @override
  Future<double> classify(Float32List features) async {
    classifyInputs.add(features);
    return score;
  }

  @override
  Future<void> close() async => closed = true;
}

/// Synthèse vocale qu'on peut laisser « en train de parler ».
class HoldSpeaker extends FakeSpeaker {
  Completer<void>? holding;
  @override
  Future<void> speak(String text) async {
    await super.speak(text);
    await holding?.future;
  }
}

class FakeMic implements MicStream {
  StreamController<Int16List>? ctrl;
  int starts = 0, stops = 0;

  @override
  Future<Stream<Int16List>> start() async {
    starts++;
    ctrl = StreamController<Int16List>();
    return ctrl!.stream;
  }

  @override
  Future<void> stop() async {
    stops++;
    await ctrl?.close();
    ctrl = null;
  }

  void push(int blocks) => ctrl?.add(Int16List(1280 * blocks));
}

Int16List ramp(int n, int from) => Int16List.fromList([for (var i = 0; i < n; i++) (from + i) % 30000]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('caractéristiques en flux (parité avec l\'entraînement)', () {
    test('blocs de 80 ms avec 480 échantillons de contexte', () async {
      final m = FakeModels();
      final f = WakeWordFeatures(m);
      await f.push(ramp(1000, 0));
      expect(m.melInputs, isEmpty, reason: 'bloc incomplet');
      await f.push(ramp(1560, 1000));
      expect(m.melInputs, hasLength(2));
      expect(m.melInputs[0].length, 1760);
      expect(m.melInputs[0].sublist(0, 480), everyElement(0.0), reason: 'contexte initial nul');
      expect(m.melInputs[0][480], 0.0);
      expect(m.melInputs[0][1759], 1279.0, reason: 'valeurs int16 brutes, sans normalisation');
      // Le contexte du 2e bloc = les 480 derniers échantillons du 1er.
      expect(m.melInputs[1].sublist(0, 480), [for (var i = 800; i < 1280; i++) i.toDouble()]);
      expect(m.melInputs[1][480], 1280.0);
    });

    test('mel /10 + 2, fenêtre des 76 dernières trames', () async {
      final m = FakeModels();
      final f = WakeWordFeatures(m);
      await f.push(Int16List(1280));
      final w = m.embedInputs.single;
      expect(w.length, 76 * 32);
      expect(w.sublist(0, 32), everyElement(1.0), reason: 'tampon initial à 1');
      expect(w.sublist(75 * 32), everyElement(10 / 10 + 2));
    });

    test('score seulement après 16 plongements réels, sur les 16 derniers', () async {
      final m = FakeModels();
      final f = WakeWordFeatures(m);
      final scores = await f.push(Int16List(1280 * 20));
      expect(scores, hasLength(5));
      final last = m.classifyInputs.last;
      expect(last.length, 16 * 96);
      expect(last.first, 5.0);
      expect(last.last, 20.0);
    });
  });

  test('confirmation sur plusieurs blocs consécutifs', () {
    final d = WakeWordDetector(threshold: 0.9, patience: 3);
    expect([for (final s in [0.95, 0.95, 0.2, 0.95, 0.95]) d.add(s)], everyElement(isFalse), reason: 'pic interrompu');
    expect(d.add(0.95), isTrue, reason: '3e bloc consécutif');
  });

  test('décision : seuil puis 2 s de garde', () {
    final d = WakeWordDetector(threshold: 0.6);
    final hits = [for (final s in [0.2, 0.7, ...List.filled(25, 0.9), 0.9]) d.add(s)];
    expect(hits.where((h) => h), hasLength(2));
    expect(hits[1], isTrue);
    expect(hits.last, isTrue);
  });

  group('écoute', () {
    late FakeModels models;
    late FakeMic mic;
    late ProviderContainer c;
    late FakeSpeechInput speech;
    late HoldSpeaker speaker;

    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await pumpEventQueue();
      }
    }

    setUp(() async {
      models = FakeModels();
      mic = FakeMic();
      speech = FakeSpeechInput();
      speaker = HoldSpeaker();
      c = ProviderContainer(
        overrides: [
          wakeWordEngineFactoryProvider.overrideWithValue(
            () async => WakeWordEngine(models: models, mic: mic, threshold: 0.6),
          ),
          settingsStoreProvider.overrideWithValue(MemorySettingsStore(const AppSettings(wakeWord: true))),
          permissionServiceProvider.overrideWithValue(FakePermissionService.allGranted()),
          speechInputProvider.overrideWithValue(speech),
          speakerProvider.overrideWithValue(speaker),
          sentrixBubbleDurationProvider.overrideWithValue(Duration.zero),
        ],
      );
      c.listen(wakeWordProvider, (_, _) {});
      await c.read(settingsControllerProvider.future);
      await settle();
    });
    tearDown(() => c.dispose());

    test('« Sentrix » détecté : micro rendu, SENTRIX écoute, puis reprise', () async {
      expect(c.read(wakeWordProvider).status, WakeWordStatus.listening);
      expect(mic.starts, 1);

      mic.push(15);
      await settle();
      expect(speech.cancels, 0);
      models.score = 0.95;
      mic.push(2);
      await settle();
      // SENTRIX a écouté (rien entendu) puis l'écoute du mot a repris.
      expect(mic.stops, greaterThanOrEqualTo(1));
      expect(mic.starts, greaterThanOrEqualTo(2));
      expect(c.read(wakeWordProvider).status, WakeWordStatus.listening);
    });

    test('la voix de l\'application ne déclenche pas SENTRIX', () async {
      speaker.holding = Completer<void>();
      unawaited(c.read(voiceQueueProvider).say('Dans 300 mètres, tournez à droite.', VoicePriority.guidance));
      await settle();
      expect(c.read(voiceQueueProvider).speaking, isTrue);
      models.score = 0.95;
      mic.push(17);
      await settle();
      expect(mic.stops, 0, reason: 'détection ignorée pendant une annonce');
      expect(c.read(wakeWordProvider).status, WakeWordStatus.listening);
      speaker.holding!.complete();
    });

    test('option désactivée : micro coupé', () async {
      await c.read(settingsControllerProvider.notifier).change((s) => s.copyWith(wakeWord: false));
      await settle();
      expect(c.read(wakeWordProvider).status, WakeWordStatus.off);
      expect(mic.stops, greaterThanOrEqualTo(1));
      expect(models.closed, isTrue);
    });
  });
}
