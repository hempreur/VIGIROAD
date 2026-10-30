import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Synthèse vocale. Une seule voix à la fois : une nouvelle annonce
/// interrompt la précédente (la file à priorités arrive en phase 7).
abstract interface class Speaker {
  Future<void> speak(String text);
  Future<void> stop();
}

class TtsSpeaker implements Speaker {
  TtsSpeaker({String language = 'fr-FR'}) : _language = language;

  final FlutterTts _tts = FlutterTts();
  final String _language;
  Future<void>? _init;

  Future<void> _ensureInit() => _init ??= () async {
    await _tts.setLanguage(_language);
    await _tts.setSpeechRate(defaultTargetPlatform == TargetPlatform.iOS ? 0.52 : 0.5);
    await _tts.setVolume(1);
    await _tts.awaitSpeakCompletion(true);
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // Baisse la musique pendant les annonces, et parle même en mode silencieux.
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.duckOthers,
          IosTextToSpeechAudioCategoryOptions.interruptSpokenAudioAndMixWithOthers,
        ],
        IosTextToSpeechAudioMode.voicePrompt,
      );
    }
  }();

  @override
  Future<void> speak(String text) async {
    await _ensureInit();
    await _tts.stop();
    // focus : demande le focus audio Android (atténue la musique).
    await _tts.speak(text, focus: true);
  }

  @override
  Future<void> stop() async => _tts.stop();
}
