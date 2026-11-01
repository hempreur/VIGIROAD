import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/audio/voice_providers.dart';
import '../data/speech_input.dart';
import '../domain/command_engine.dart';
import '../domain/sentrix_state.dart';
import 'sentrix_commands.dart';

/// État affiché de SENTRIX.
class SentrixUi {
  const SentrixUi({this.visual = SentrixState.idle, this.transcript, this.reply});

  final SentrixState visual;

  /// Ce que SENTRIX a entendu (affiché pendant l'écoute).
  final String? transcript;

  /// Réponse affichée dans la bulle.
  final String? reply;

  bool get busy => visual == SentrixState.listening || visual == SentrixState.thinking;
}

final speechInputProvider = Provider<SpeechInput>((ref) => SystemSpeechInput());

final sentrixCommandsProvider = Provider<List<SentrixCommand>>((ref) => sentrixCommands);

final sentrixEngineProvider = Provider<CommandEngine<SentrixContext>>(
  (ref) => CommandEngine(ref.watch(sentrixCommandsProvider)),
);

/// Durée d'affichage de la bulle après une réponse.
final sentrixBubbleDurationProvider = Provider<Duration>((ref) => const Duration(seconds: 4));

final sentrixProvider = NotifierProvider<SentrixController, SentrixUi>(SentrixController.new);

/// Cycle d'une commande : écoute (activation manuelle) → transcription →
/// analyse → exécution → réponse vocale et visuelle.
class SentrixController extends Notifier<SentrixUi> {
  Timer? _bubbleTimer;
  int _session = 0;

  @override
  SentrixUi build() {
    ref.onDispose(() => _bubbleTimer?.cancel());
    return const SentrixUi();
  }

  /// Bouton SENTRIX : démarre l'écoute, ou l'annule si elle est en cours.
  Future<void> toggleListening() async {
    if (state.busy) {
      await cancel();
    } else {
      await listen();
    }
  }

  Future<void> cancel() async {
    _session++;
    await ref.read(speechInputProvider).cancel();
    state = const SentrixUi();
  }

  /// Écoute une commande (appui sur la tête de SENTRIX, seul moyen de
  /// l'activer). Renvoie `true` si une phrase a été entendue.
  Future<bool> listen() async {
    final session = ++_session;
    _bubbleTimer?.cancel();

    final mic = await ref.read(permissionsProvider.notifier).request(AppCapability.microphone);
    if (session != _session) return false;
    if (mic != CapabilityStatus.granted) {
      await _reply(session, const CommandResult.failure('Autorisez le microphone pour me parler.'), speak: false);
      return false;
    }

    // Pas d'écoute pendant ses propres réponses : SENTRIX s'entendrait.
    // Les consignes de navigation et les alertes, elles, ne sont pas coupées.
    await ref.read(voiceQueueProvider).clear(only: VoicePriority.assistant);
    state = const SentrixUi(visual: SentrixState.listening, reply: 'Je vous écoute…');

    final String? heard;
    try {
      heard = await ref.read(speechInputProvider).listenOnce(
        onPartial: (t) {
          if (session == _session && t.isNotEmpty) {
            state = SentrixUi(visual: SentrixState.listening, transcript: t);
          }
        },
      );
    } on SpeechUnavailable catch (e) {
      await _reply(session, CommandResult.failure(e.message));
      return false;
    }
    if (session != _session) return false;
    if (heard == null) {
      await _reply(session, const CommandResult.failure('Je n\'ai rien entendu.'), speak: false);
      return false;
    }
    await execute(heard, session: session);
    return true;
  }

  /// Annonce spontanée de SENTRIX (perturbation sur l'itinéraire…) :
  /// affichée dans la bulle et prononcée. N'interrompt pas une écoute en
  /// cours. Renvoie `true` si l'annonce a été prononcée jusqu'au bout.
  Future<bool> announce(String text) async {
    if (state.busy) return false;
    final session = ++_session;
    _bubbleTimer?.cancel();
    state = SentrixUi(visual: SentrixState.speaking, reply: text);
    var spoken = false;
    try {
      spoken = await ref.read(voiceQueueProvider).say(text, VoicePriority.assistant);
    } catch (_) {
      // Pas de synthèse vocale : l'annonce reste affichée.
    }
    if (session == _session) {
      _bubbleTimer = Timer(ref.read(sentrixBubbleDurationProvider), () {
        if (session == _session) state = const SentrixUi();
      });
      state = SentrixUi(reply: text);
    }
    return spoken;
  }

  /// Interprète et exécute une phrase (aussi utilisé par les tests).
  Future<CommandResult> execute(String utterance, {int? session, bool speakFailure = true}) async {
    final s = session ?? ++_session;
    state = SentrixUi(visual: SentrixState.thinking, transcript: utterance);
    final match = ref.read(sentrixEngineProvider).match(utterance);
    final CommandResult result;
    if (match == null) {
      result = const CommandResult.failure(
        'Je n\'ai pas compris. Dites « aide » pour connaître les commandes.',
      );
    } else {
      try {
        result = await match.command.action(SentrixContext(ref));
      } catch (_) {
        await _reply(s, const CommandResult.failure('Une erreur est survenue.'), transcript: utterance);
        return const CommandResult.failure('Une erreur est survenue.');
      }
    }
    await _reply(s, result, transcript: utterance, speak: result.success || speakFailure);
    return result;
  }

  Future<void> _reply(int session, CommandResult r, {String? transcript, bool speak = true}) async {
    if (session != _session) return;
    state = SentrixUi(
      visual: r.success ? SentrixState.speaking : SentrixState.error,
      transcript: transcript,
      reply: r.reply,
    );
    if (speak) {
      try {
        await ref.read(voiceQueueProvider).say(r.reply, VoicePriority.assistant);
      } catch (_) {
        // Pas de synthèse vocale : la réponse reste affichée.
      }
    }
    if (session != _session) return;
    _bubbleTimer?.cancel();
    _bubbleTimer = Timer(ref.read(sentrixBubbleDurationProvider), () {
      if (session == _session) state = const SentrixUi();
    });
    if (r.success) state = SentrixUi(visual: SentrixState.idle, transcript: transcript, reply: r.reply);
  }
}
