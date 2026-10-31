import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/providers.dart';
import '../../../core/permissions/permission_service.dart';
import '../data/voice_samples.dart';

/// Dossier privé des enregistrements (remplacé dans les tests).
final voiceSampleStoreProvider = FutureProvider<VoiceSampleStore>((ref) async {
  final docs = await getApplicationDocumentsDirectory();
  return VoiceSampleStore(Directory('${docs.path}/sentrix_samples'));
});

final sampleRecorderProvider = Provider<SampleRecorder>((ref) => RecordSampleRecorder());

/// Enregistrement d'un fichier choisi par l'utilisateur (remplacé dans les tests).
final zipSaverProvider = Provider<Future<bool> Function(String name, Uint8List bytes)>(
  (ref) => (name, bytes) async =>
      await FilePicker.saveFile(fileName: name, bytes: bytes, mimeType: 'application/zip') != null,
);

class VoiceTrainingState {
  const VoiceTrainingState({
    this.counts = const {},
    this.recording,
    this.level = 0,
    this.message,
  });

  final Map<SampleKind, int> counts;

  /// Type en cours d'enregistrement (null : au repos).
  final SampleKind? recording;
  final double level;
  final String? message;

  int count(SampleKind k) => counts[k] ?? 0;
  bool get canExport => SampleKind.values.every((k) => count(k) >= k.minimum);

  VoiceTrainingState copyWith({Map<SampleKind, int>? counts, SampleKind? recording, bool clearRecording = false, double? level, String? message}) =>
      VoiceTrainingState(
        counts: counts ?? this.counts,
        recording: clearRecording ? null : recording ?? this.recording,
        level: level ?? this.level,
        message: message,
      );
}

final voiceTrainingProvider = NotifierProvider.autoDispose<VoiceTrainingController, VoiceTrainingState>(VoiceTrainingController.new);

/// Collecte des « Sentrix » prononcés par l'utilisateur, de parole normale et
/// de bruit ambiant, pour entraîner un modèle adapté à sa voix.
class VoiceTrainingController extends Notifier<VoiceTrainingState> {
  @override
  VoiceTrainingState build() {
    final recorder = ref.read(sampleRecorderProvider);
    ref.onDispose(() => unawaited(recorder.cancel()));
    unawaited(Future.microtask(refresh));
    return const VoiceTrainingState();
  }

  Future<VoiceSampleStore> get _store => ref.read(voiceSampleStoreProvider.future);

  Future<void> refresh() async {
    final counts = await (await _store).counts();
    if (ref.mounted) state = state.copyWith(counts: counts);
  }

  Future<void> record(SampleKind kind) async {
    if (state.recording != null) return;
    final mic = await ref.read(permissionsProvider.notifier).request(AppCapability.microphone);
    if (!ref.mounted) return;
    if (mic != CapabilityStatus.granted) {
      state = state.copyWith(message: 'Autorisez le micro pour enregistrer.');
      return;
    }
    final store = await _store;
    final path = await store.nextPath(kind);
    state = state.copyWith(recording: kind, level: 0);
    try {
      await ref.read(sampleRecorderProvider).record(path, kind.duration, onLevel: (l) {
        if (ref.mounted) state = state.copyWith(level: l);
      });
    } on Object catch (e) {
      if (ref.mounted) state = state.copyWith(clearRecording: true, message: 'Enregistrement impossible : $e');
      return;
    }
    if (!ref.mounted) return;
    state = state.copyWith(clearRecording: true, level: 0, counts: await store.counts());
  }

  Future<void> deleteLast(SampleKind kind) async {
    await (await _store).deleteLast(kind);
    await refresh();
  }

  Future<void> clear() async {
    await (await _store).clear();
    await refresh();
  }

  /// Exporte l'archive ; renvoie vrai si l'utilisateur l'a enregistrée.
  Future<bool> export({required String appVersion}) async {
    final bytes = await (await _store).exportZip(appVersion: appVersion);
    final ok = await ref.read(zipSaverProvider)('vigiroad_sentrix_voix.zip', bytes);
    if (ref.mounted && ok) state = state.copyWith(message: 'Archive exportée (${(bytes.length / 1e6).toStringAsFixed(1)} Mo).');
    return ok;
  }
}
