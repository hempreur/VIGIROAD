import 'dart:async';
import 'dart:collection';

import '../../features/navigation/data/speaker.dart';

/// Priorité d'une annonce vocale (la plus haute d'abord).
enum VoicePriority {
  /// Consigne de navigation : toujours prioritaire (sécurité).
  guidance,

  /// Alerte de plaque.
  alert,

  /// Réponse de SENTRIX.
  assistant,
}

class _Utterance {
  _Utterance(this.text, this.priority, this.queuedAt);
  final String text;
  final VoicePriority priority;
  DateTime queuedAt;
  final done = Completer<bool>();
}

/// File d'annonces vocales : une seule voix à la fois.
///
/// - Une annonce plus prioritaire interrompt celle en cours (une consigne
///   de navigation coupe une réponse de SENTRIX) ; une alerte interrompue
///   est répétée ensuite.
/// - Les autres attendent leur tour, par priorité puis ordre d'arrivée.
/// - Une annonce restée trop longtemps en attente est abandonnée (une
///   consigne « dans 300 mètres » vieille de 15 s serait fausse).
/// - Une nouvelle consigne de navigation remplace celles encore en attente.
class VoiceQueue {
  VoiceQueue(this._speaker, {DateTime Function()? clock, this.maxWait = const Duration(seconds: 12)})
    : _clock = clock ?? DateTime.now;

  final Speaker _speaker;
  final DateTime Function() _clock;
  final Duration maxWait;

  final _pending = ListQueue<_Utterance>();
  _Utterance? _current;
  final _speakingChanges = StreamController<bool>.broadcast(sync: true);
  DateTime? _lastEnd;

  bool get speaking => _current != null;

  /// `true` quand l'application commence à parler, `false` quand elle se tait
  /// (file vide). Sert à couper le mot d'activation pendant ses propres annonces.
  Stream<bool> get speakingChanges => _speakingChanges.stream;

  /// Fin de la dernière annonce (null si aucune).
  DateTime? get lastEnd => _lastEnd;
  VoicePriority? get currentPriority => _current?.priority;
  int get pendingCount => _pending.length;

  /// Programme une annonce ; le futur indique si elle a été prononcée
  /// jusqu'au bout (`false` si interrompue ou abandonnée).
  Future<bool> say(String text, VoicePriority priority) {
    final u = _Utterance(text, priority, _clock());
    if (priority == VoicePriority.guidance) {
      // Seule la consigne la plus récente compte.
      _pending.removeWhere((p) {
        final drop = p.priority == VoicePriority.guidance;
        if (drop) p.done.complete(false);
        return drop;
      });
    }
    final cur = _current;
    if (cur != null && priority.index < cur.priority.index) {
      _pending.addFirst(u);
      unawaited(_speaker.stop());
      // La fin de l'annonce interrompue relancera la file.
    } else {
      _insert(u);
      if (cur == null) unawaited(_pump());
    }
    return u.done.future;
  }

  void _insert(_Utterance u) {
    final list = _pending.toList()..add(u);
    list.sort((a, b) {
      final p = a.priority.index.compareTo(b.priority.index);
      return p != 0 ? p : a.queuedAt.compareTo(b.queuedAt);
    });
    _pending
      ..clear()
      ..addAll(list);
  }

  Future<void> _pump() async {
    var announced = false;
    while (_pending.isNotEmpty && _current == null) {
      final u = _pending.removeFirst();
      if (_clock().difference(u.queuedAt) > maxWait) {
        u.done.complete(false);
        continue;
      }
      _current = u;
      if (!announced) {
        // Après _current : les auditeurs voient déjà `speaking == true`.
        announced = true;
        _speakingChanges.add(true);
      }
      var completed = true;
      try {
        // Garde-fou : un moteur vocal qui ne signale pas la fin ne doit pas
        // bloquer la file (≈ 90 ms par caractère, au moins 4 s).
        await _speaker
            .speak(u.text)
            .timeout(Duration(milliseconds: 4000 + 90 * u.text.length), onTimeout: () {});
      } catch (_) {
        completed = false;
      }
      // Interrompue si une annonce prioritaire a été placée en tête.
      final interrupted = _pending.isNotEmpty && _pending.first.priority.index < u.priority.index;
      _current = null;
      if (interrupted && u.priority == VoicePriority.alert && !u.done.isCompleted) {
        // Une alerte coupée par une consigne est répétée juste après.
        u.queuedAt = _clock();
        _insert(u);
        continue;
      }
      if (!u.done.isCompleted) u.done.complete(completed && !interrupted);
    }
    if (announced && _current == null) {
      _lastEnd = _clock();
      _speakingChanges.add(false);
    }
  }

  /// Coupe tout (ex. passage en arrière-plan, guidage arrêté).
  Future<void> clear({VoicePriority? only}) async {
    _pending.removeWhere((p) {
      final drop = only == null || p.priority == only;
      if (drop && !p.done.isCompleted) p.done.complete(false);
      return drop;
    });
    if (_current != null && (only == null || _current!.priority == only)) {
      await _speaker.stop();
    }
  }
}
