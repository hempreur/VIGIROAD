import 'dart:async';

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

class SpeechUnavailable implements Exception {
  const SpeechUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Reconnaissance vocale : écoute une phrase et la retourne en texte.
abstract interface class SpeechInput {
  /// Écoute jusqu'au silence ou au délai ; retourne le texte final, ou
  /// `null` si rien n'a été compris.
  Future<String?> listenOnce({
    required void Function(String partial) onPartial,
    Duration listenFor,
    Duration pauseFor,
  });

  Future<void> cancel();
}

/// Moteur de reconnaissance du système (Google sur Android, Apple sur iOS).
class SystemSpeechInput implements SpeechInput {
  SystemSpeechInput({this.localeId = 'fr_FR'});

  final String localeId;
  final _stt = SpeechToText();
  bool? _ready;
  Completer<String?>? _pending;
  String _last = '';

  Future<bool> _init() async {
    if (_ready == true) return true;
    _ready = await _stt.initialize(
      onError: (SpeechRecognitionError e) => _finish(),
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') _finish();
      },
    );
    return _ready!;
  }

  void _finish() {
    final p = _pending;
    if (p == null || p.isCompleted) return;
    _pending = null;
    p.complete(_last.trim().isEmpty ? null : _last.trim());
  }

  @override
  Future<String?> listenOnce({
    required void Function(String partial) onPartial,
    Duration listenFor = const Duration(seconds: 8),
    Duration pauseFor = const Duration(seconds: 2),
  }) async {
    if (!await _init()) {
      throw const SpeechUnavailable('Reconnaissance vocale indisponible sur ce téléphone.');
    }
    await cancel();
    _last = '';
    final completer = _pending = Completer<String?>();
    // ignore: deprecated_member_use
    await _stt.listen(
      onResult: (r) {
        _last = r.recognizedWords;
        onPartial(_last);
        if (r.finalResult) _finish();
      },
      // ignore: deprecated_member_use
      listenFor: listenFor,
      // ignore: deprecated_member_use
      pauseFor: pauseFor,
      // ignore: deprecated_member_use
      localeId: localeId,
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.confirmation,
      ),
    );
    // Garde-fou si le moteur ne signale jamais la fin.
    return completer.future.timeout(listenFor + const Duration(seconds: 3), onTimeout: () {
      unawaited(_stt.stop());
      return _last.trim().isEmpty ? null : _last.trim();
    });
  }

  @override
  Future<void> cancel() async {
    if (_stt.isListening) await _stt.cancel();
    _finish();
  }
}
