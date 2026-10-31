// Le résultat est lu dans logcat par la CI.
// ignore_for_file: avoid_print

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:vigiroad/features/sentrix/data/wake_word_engine.dart';

/// Test de fumée du mot d'activation dans un APK **release** (R8 actif) :
/// chargement des trois modèles ONNX embarqués, chaîne en flux identique à
/// l'application sur 3 s de bruit faible, score calculé et sous le seuil.
/// Ne mesure pas la détection (voir docs/WAKE_WORD.md).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ColoredBox(color: Color(0xFF000000)));
  try {
    final info = await WakeWordModelInfo.load();
    final models = await OnnxWakeWordModels.load();
    final features = WakeWordFeatures(models);
    final rnd = math.Random(1);
    final audio = Int16List.fromList([for (var i = 0; i < 48000; i++) rnd.nextInt(600) - 300]);
    final scores = await features.push(audio);
    await models.close();
    final ok = scores.isNotEmpty && scores.every((s) => s >= 0 && s <= 1) && scores.every((s) => s < info.threshold);
    print('VIGIROAD_WAKEWORD_SMOKE ${ok ? 'OK' : 'FAIL'} scores=${scores.length} max=${scores.isEmpty ? '-' : scores.reduce(math.max).toStringAsFixed(4)} seuil=${info.threshold}');
  } catch (e, st) {
    print('VIGIROAD_WAKEWORD_SMOKE ERROR $e\n$st');
  }
}
