import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:record/record.dart';

import 'stored_zip.dart';

/// Enregistrements servant à entraîner le mot « Sentrix » avec la voix de
/// l'utilisateur. Ils restent dans le stockage privé de l'application tant
/// que l'utilisateur ne les exporte pas lui-même, et s'effacent à la demande.
enum SampleKind {
  /// « Sentrix » prononcé une fois, extrait de 2 s.
  sentrix(Duration(seconds: 2), 50, 30),

  /// Parole normale sans le mot (lecture d'un texte), 20 s.
  speech(Duration(seconds: 20), 3, 1),

  /// Silence ou bruit de la voiture, 20 s.
  ambient(Duration(seconds: 20), 2, 0);

  const SampleKind(this.duration, this.target, this.minimum);
  final Duration duration;

  /// Nombre conseillé, et minimum pour pouvoir exporter.
  final int target;
  final int minimum;
}

class VoiceSampleStore {
  VoiceSampleStore(this.root);

  final Directory root;

  Directory dir(SampleKind k) => Directory('${root.path}/${k.name}');

  Future<List<File>> files(SampleKind k) async {
    final d = dir(k);
    if (!await d.exists()) return const [];
    final list = [
      await for (final e in d.list())
        if (e is File && e.path.endsWith('.wav')) e,
    ]..sort((a, b) => a.path.compareTo(b.path));
    return list;
  }

  Future<Map<SampleKind, int>> counts() async => {for (final k in SampleKind.values) k: (await files(k)).length};

  /// Chemin du prochain enregistrement (numéroté).
  Future<String> nextPath(SampleKind k) async {
    await dir(k).create(recursive: true);
    final existing = await files(k);
    final last = existing.isEmpty
        ? 0
        : int.tryParse(existing.last.uri.pathSegments.last.split('_').last.split('.').first) ?? existing.length;
    return '${dir(k).path}/${k.name}_${(last + 1).toString().padLeft(3, '0')}.wav';
  }

  Future<void> deleteLast(SampleKind k) async {
    final f = await files(k);
    if (f.isNotEmpty) await f.last.delete();
  }

  Future<void> clear() async {
    if (await root.exists()) await root.delete(recursive: true);
  }

  /// Archive à transmettre pour l'entraînement : fichiers WAV 16 kHz mono
  /// et `manifest.json` (nombres, durée, version) — aucune autre donnée.
  Future<Uint8List> exportZip({required String appVersion, DateTime? now}) async {
    final t = now ?? DateTime.now();
    final entries = <String, Uint8List>{};
    final counts = <String, int>{};
    for (final k in SampleKind.values) {
      final f = await files(k);
      counts[k.name] = f.length;
      for (final file in f) {
        entries['${k.name}/${file.uri.pathSegments.last}'] = await file.readAsBytes();
      }
    }
    entries['manifest.json'] = Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert({
      'format': 1,
      'purpose': 'Entraînement du mot d\'activation « Sentrix » (VIGIROAD)',
      'app': appVersion,
      'created': t.toUtc().toIso8601String(),
      'sampleRate': 16000,
      'channels': 1,
      'counts': counts,
    })));
    return storedZip(entries, at: t);
  }
}

/// Enregistrement d'un extrait de durée fixe (WAV 16 kHz mono).
abstract interface class SampleRecorder {
  /// [onLevel] reçoit le niveau (0–1) pendant l'enregistrement.
  Future<void> record(String path, Duration duration, {void Function(double level)? onLevel});
  Future<void> cancel();
}

class RecordSampleRecorder implements SampleRecorder {
  final _rec = AudioRecorder();
  Completer<void>? _stop;

  @override
  Future<void> record(String path, Duration duration, {void Function(double level)? onLevel}) async {
    await _rec.start(const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1), path: path);
    final sub = _rec.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((a) {
      // dBFS (-60…0) → 0…1
      onLevel?.call(((a.current + 60) / 60).clamp(0.0, 1.0));
    });
    _stop = Completer<void>();
    await Future.any([Future<void>.delayed(duration), _stop!.future]);
    await sub.cancel();
    await _rec.stop();
  }

  @override
  Future<void> cancel() async {
    if (_stop?.isCompleted == false) _stop!.complete();
  }
}
