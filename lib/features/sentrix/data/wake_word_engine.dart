import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:record/record.dart';

/// Modèles du mot d'activation (openWakeWord), injectables pour les tests.
abstract interface class WakeWordModels {
  /// Melspectrogramme : échantillons int16 bruts (en float) → trames de 32.
  Future<List<Float32List>> mel(Float32List samples);

  /// Plongement (96) d'une fenêtre de 76 × 32 trames.
  Future<Float32List> embed(Float32List window);

  /// Probabilité du mot sur 16 × 96 plongements (1,28 s).
  Future<double> classify(Float32List features);

  Future<void> close();
}

/// Chaîne de caractéristiques openWakeWord en flux, identique à
/// l'entraînement (tools/wakeword/features.py) : blocs de 1 280 échantillons
/// (80 ms), melspectrogramme sur le bloc et 480 échantillons de contexte,
/// sortie /10 + 2, plongement des 76 dernières trames, classifieur sur les
/// 16 derniers plongements.
class WakeWordFeatures {
  WakeWordFeatures(this.models);

  final WakeWordModels models;

  static const chunk = 1280;
  static const context = 480;
  static const melWindow = 76;
  static const embeddings = 16;

  final _pending = <int>[];
  Int16List _raw = Int16List(context);
  final _mel = <Float32List>[for (var i = 0; i < melWindow; i++) Float32List(32)..fillRange(0, 32, 1)];
  final _features = <Float32List>[];
  int _real = 0;

  void reset() {
    _pending.clear();
    _raw = Int16List(context);
    _features.clear();
    _real = 0;
    for (final r in _mel) {
      r.fillRange(0, 32, 1);
    }
  }

  /// Ajoute des échantillons ; renvoie un score par bloc de 80 ms complet
  /// (rien tant que 16 plongements réels n'ont pas été calculés).
  Future<List<double>> push(Int16List samples) async {
    _pending.addAll(samples);
    final out = <double>[];
    while (_pending.length >= chunk) {
      final block = Int16List.fromList(_pending.sublist(0, chunk));
      _pending.removeRange(0, chunk);
      final s = await _process(block);
      if (s != null) out.add(s);
    }
    return out;
  }

  Future<double?> _process(Int16List block) async {
    final input = Float32List(context + chunk);
    for (var i = 0; i < context; i++) {
      input[i] = _raw[_raw.length - context + i].toDouble();
    }
    for (var i = 0; i < chunk; i++) {
      input[context + i] = block[i].toDouble();
    }
    _raw = Int16List.fromList(block.sublist(chunk - context));

    for (final frame in await models.mel(input)) {
      final t = Float32List(32);
      for (var i = 0; i < 32; i++) {
        t[i] = frame[i] / 10 + 2;
      }
      _mel.add(t);
    }
    _mel.removeRange(0, _mel.length - melWindow);

    final window = Float32List(melWindow * 32);
    for (var r = 0; r < melWindow; r++) {
      window.setRange(r * 32, r * 32 + 32, _mel[r]);
    }
    _features.add(await models.embed(window));
    if (_features.length > embeddings) _features.removeAt(0);
    _real++;
    if (_real < embeddings) return null;

    final f = Float32List(embeddings * 96);
    for (var i = 0; i < embeddings; i++) {
      f.setRange(i * 96, i * 96 + 96, _features[i]);
    }
    return models.classify(f);
  }
}

/// Décision : score au-dessus du seuil, puis 2 s sans nouvelle détection.
class WakeWordDetector {
  WakeWordDetector({required this.threshold, this.refractoryBlocks = 25});

  final double threshold;
  final int refractoryBlocks;
  int _cooldown = 0;

  bool add(double score) {
    if (_cooldown > 0) {
      _cooldown--;
      return false;
    }
    if (score >= threshold) {
      _cooldown = refractoryBlocks;
      return true;
    }
    return false;
  }

  void reset() => _cooldown = 0;
}

/// Flux du micro en PCM 16 bits, 16 kHz, mono.
abstract interface class MicStream {
  Future<Stream<Int16List>> start();
  Future<void> stop();
}

class RecordMicStream implements MicStream {
  final _rec = AudioRecorder();

  @override
  Future<Stream<Int16List>> start() async {
    final bytes = await _rec.startStream(
      const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1),
    );
    var carry = <int>[];
    return bytes.map((chunk) {
      final all = carry.isEmpty ? chunk : Uint8List.fromList([...carry, ...chunk]);
      final even = all.length - all.length % 2;
      carry = all.sublist(even);
      final data = ByteData.sublistView(all, 0, even);
      final out = Int16List(even ~/ 2);
      for (var i = 0; i < out.length; i++) {
        out[i] = data.getInt16(i * 2, Endian.little);
      }
      return out;
    });
  }

  @override
  Future<void> stop() async {
    if (await _rec.isRecording()) await _rec.stop();
  }
}

/// Modèles ONNX embarqués (assets/wakeword/).
class OnnxWakeWordModels implements WakeWordModels {
  OnnxWakeWordModels._(this._mel, this._emb, this._cls);

  static const dir = 'assets/wakeword';

  static Future<OnnxWakeWordModels> load() async {
    final ort = OnnxRuntime();
    return OnnxWakeWordModels._(
      await ort.createSessionFromAsset('$dir/melspectrogram.onnx'),
      await ort.createSessionFromAsset('$dir/embedding_model.onnx'),
      await ort.createSessionFromAsset('$dir/sentrix.onnx'),
    );
  }

  final OrtSession _mel, _emb, _cls;

  Future<List<double>> _run(OrtSession s, Float32List data, List<int> shape) async {
    final input = await OrtValue.fromList(data, shape);
    final outputs = await s.run({s.inputNames.first: input});
    try {
      final out = outputs[s.outputNames.first]!;
      return [for (final v in await out.asFlattenedList()) (v as num).toDouble()];
    } finally {
      await input.dispose();
      for (final o in outputs.values) {
        await o.dispose();
      }
    }
  }

  @override
  Future<List<Float32List>> mel(Float32List samples) async {
    final flat = await _run(_mel, samples, [1, samples.length]);
    return [
      for (var i = 0; i + 32 <= flat.length; i += 32) Float32List.fromList(flat.sublist(i, i + 32)),
    ];
  }

  @override
  Future<Float32List> embed(Float32List window) async =>
      Float32List.fromList(await _run(_emb, window, [1, 76, 32, 1]));

  @override
  Future<double> classify(Float32List features) async => (await _run(_cls, features, [1, 16, 96])).first;

  @override
  Future<void> close() async {
    await _mel.close();
    await _emb.close();
    await _cls.close();
  }
}

/// Seuil et mesures publiés avec le modèle (assets/wakeword/sentrix.json).
class WakeWordModelInfo {
  const WakeWordModelInfo({required this.threshold, this.recall, this.faPerHour});

  static Future<WakeWordModelInfo> load() async {
    final j = jsonDecode(await rootBundle.loadString('${OnnxWakeWordModels.dir}/sentrix.json')) as Map<String, dynamic>;
    final test = j['test'] as Map<String, dynamic>? ?? const {};
    return WakeWordModelInfo(
      threshold: (j['threshold'] as num).toDouble(),
      recall: (test['recall'] as num?)?.toDouble(),
      faPerHour: (test['fa_per_hour_fr_speech'] as num?)?.toDouble(),
    );
  }

  final double threshold;

  /// Taux de détection mesuré (voix de synthèse jamais vues à l'entraînement).
  final double? recall;

  /// Fausses activations par heure mesurées sur de la parole française réelle.
  final double? faPerHour;
}

/// Écoute continue : micro → caractéristiques → décision.
class WakeWordEngine {
  WakeWordEngine({required this.models, required this.mic, required this.threshold});

  final WakeWordModels models;
  final MicStream mic;
  final double threshold;

  late final _features = WakeWordFeatures(models);
  late final _detector = WakeWordDetector(threshold: threshold);
  final _detections = StreamController<double>.broadcast();
  final _errors = StreamController<Object>.broadcast();
  StreamSubscription<Int16List>? _sub;
  Future<void> _queue = Future.value();
  int _backlog = 0;

  /// Score de chaque détection.
  Stream<double> get detections => _detections.stream;

  /// Erreurs d'analyse (modèle, micro).
  Stream<Object> get errors => _errors.stream;
  bool get running => _sub != null;

  Future<void> start() async {
    if (_sub != null) return;
    _features.reset();
    _detector.reset();
    final stream = await mic.start();
    _sub = stream.listen((samples) {
      // Traitement en série ; en cas de retard on saute des blocs plutôt
      // que d'accumuler de la latence.
      if (_backlog > 6) return;
      _backlog++;
      _queue = _queue.then((_) async {
        try {
          for (final s in await _features.push(samples)) {
            if (_detector.add(s) && !_detections.isClosed) _detections.add(s);
          }
        } finally {
          _backlog--;
        }
      }).catchError((Object e) {
        if (!_errors.isClosed) _errors.add(e);
      });
    }, onError: (Object e) {
      if (!_errors.isClosed) _errors.add(e);
    });
  }

  Future<void> stop() async {
    final s = _sub;
    _sub = null;
    await s?.cancel();
    await mic.stop();
    await _queue;
  }

  Future<void> dispose() async {
    await stop();
    await models.close();
    await _detections.close();
    await _errors.close();
  }
}
