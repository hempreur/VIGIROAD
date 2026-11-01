import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/audio/voice_providers.dart';
import '../../../core/permissions/permission_service.dart';
import '../../settings/application/settings_controller.dart';
import '../data/wake_word_engine.dart';
import '../domain/sentrix_state.dart';
import 'sentrix_controller.dart';

enum WakeWordStatus { off, starting, listening, paused, unavailable }

class WakeWordState {
  const WakeWordState(this.status, {this.message});
  final WakeWordStatus status;
  final String? message;
}

/// Création du moteur (remplacée dans les tests).
final wakeWordEngineFactoryProvider = Provider<Future<WakeWordEngine> Function()>((ref) {
  return () async {
    final info = await WakeWordModelInfo.load();
    return WakeWordEngine(
      models: await OnnxWakeWordModels.load(),
      mic: RecordMicStream(),
      threshold: info.threshold,
      patience: info.patience,
      gate: SpeechGate(),
    );
  };
});

/// Libéré (micro coupé) quand l'écran de navigation n'est plus affiché.
/// Seuil et mesures du modèle embarqué.
final wakeWordInfoProvider = FutureProvider<WakeWordModelInfo>((ref) => WakeWordModelInfo.load());

final wakeWordProvider = NotifierProvider.autoDispose<WakeWordController, WakeWordState>(WakeWordController.new);

/// Silence à respecter après une annonce de l'application avant de
/// réécouter (écho, réverbération, fin de phrase encore dans le tampon).
final wakeWordVoiceTailProvider = Provider<Duration>((ref) => const Duration(milliseconds: 1500));

/// Pause après une activation sans commande (fausse détection probable).
final wakeWordFalseTriggerPauseProvider = Provider<Duration>((ref) => const Duration(seconds: 10));

/// Mot d'activation « Sentrix » : écoute sur le téléphone, rien n'est envoyé.
///
/// Actif seulement si l'option est activée, l'écran de navigation affiché,
/// l'application au premier plan et le micro autorisé. Coupé pendant que
/// SENTRIX écoute ou parle, et pendant toute annonce de l'application
/// (guidage, alertes de plaques, perturbations) puis 1,5 s après : le modèle
/// ne doit jamais analyser la voix de l'application elle-même, ni un reste
/// de cette voix dans son tampon de 1,3 s (cause des activations « toutes
/// seules » de la version 1.4).
class WakeWordController extends Notifier<WakeWordState> {
  WakeWordEngine? _engine;
  StreamSubscription<double>? _det;
  StreamSubscription<Object>? _err;
  bool _visible = true;
  int _gen = 0;
  Timer? _resume;
  DateTime? _quietUntil;

  @override
  WakeWordState build() {
    final enabled = ref.watch(appSettingsProvider.select((s) => s.wakeWord));
    final lifecycle = AppLifecycleListener(
      onHide: () {
        _visible = false;
        unawaited(_sync());
      },
      onShow: () {
        _visible = true;
        unawaited(_sync());
      },
    );
    ref.listen(sentrixProvider.select((s) => s.busy || s.visual == SentrixState.speaking), (_, _) => unawaited(_sync()));
    final voice = ref.read(voiceQueueProvider).speakingChanges.listen((speaking) {
      if (!speaking) _holdFor(ref.read(wakeWordVoiceTailProvider));
      unawaited(_sync());
    });
    ref.onDispose(() {
      lifecycle.dispose();
      unawaited(voice.cancel());
      _resume?.cancel();
      _gen++;
      final e = _engine;
      _engine = null;
      unawaited(_det?.cancel());
      unawaited(_err?.cancel());
      unawaited(e?.dispose());
    });
    if (!enabled) return const WakeWordState(WakeWordStatus.off);
    unawaited(Future.microtask(_sync));
    return const WakeWordState(WakeWordStatus.starting);
  }

  bool get _sentrixBusy {
    final s = ref.read(sentrixProvider);
    return s.busy || s.visual == SentrixState.speaking;
  }

  // Horloge réelle : la reprise est pilotée par un minuteur.
  DateTime get _now => DateTime.now();

  /// Écoute suspendue jusqu'à [d] à partir de maintenant.
  void _holdFor(Duration d) {
    final until = _now.add(d);
    if (_quietUntil == null || until.isAfter(_quietUntil!)) _quietUntil = until;
    _resume?.cancel();
    _resume = Timer(d, () => unawaited(_sync()));
  }

  bool get _quiet {
    final q = _quietUntil;
    return q != null && _now.isBefore(q);
  }

  Future<void> _sync() async {
    if (!ref.mounted) return;
    if (!ref.read(appSettingsProvider).wakeWord) return;
    final gen = ++_gen;
    final shouldListen = _visible && !_sentrixBusy && !ref.read(voiceQueueProvider).speaking && !_quiet;
    if (!shouldListen) {
      await _engine?.stop();
      if (gen == _gen && ref.mounted && state.status != WakeWordStatus.unavailable) {
        state = const WakeWordState(WakeWordStatus.paused);
      }
      return;
    }
    final mic = await ref.read(permissionsProvider.notifier).request(AppCapability.microphone);
    if (gen != _gen || !ref.mounted) return;
    if (mic != CapabilityStatus.granted) {
      state = const WakeWordState(WakeWordStatus.unavailable, message: 'Autorisez le micro pour le mot « Sentrix ».');
      return;
    }
    try {
      final engine = _engine ??= await _create();
      if (gen != _gen || !ref.mounted) return;
      await engine.start();
      if (gen == _gen && ref.mounted) state = const WakeWordState(WakeWordStatus.listening);
    } on Object catch (e) {
      if (ref.mounted) {
        state = WakeWordState(WakeWordStatus.unavailable, message: 'Mot « Sentrix » indisponible : $e');
      }
    }
  }

  Future<WakeWordEngine> _create() async {
    final engine = await ref.read(wakeWordEngineFactoryProvider)();
    _det = engine.detections.listen((_) => unawaited(_onDetected()));
    _err = engine.errors.listen((e) {
      if (ref.mounted) state = WakeWordState(WakeWordStatus.unavailable, message: 'Mot « Sentrix » : $e');
    });
    return engine;
  }

  Future<void> _onDetected() async {
    // La voix de l'application (guidage, alertes) ne doit pas déclencher SENTRIX.
    if (ref.read(voiceQueueProvider).speaking || _sentrixBusy || _quiet || state.status != WakeWordStatus.listening) return;
    await _engine?.stop();
    if (!ref.mounted) return;
    // SENTRIX prend le micro ; l'écoute du mot reprend quand il a fini.
    final heard = await ref.read(sentrixProvider.notifier).listen(fromWakeWord: true);
    if (!ref.mounted) return;
    // Rien entendu après « Sentrix » : sans doute une fausse détection
    // (radio, passager) ; on n'insiste pas pendant quelques secondes.
    if (!heard) _holdFor(ref.read(wakeWordFalseTriggerPauseProvider));
    unawaited(_sync());
  }
}
