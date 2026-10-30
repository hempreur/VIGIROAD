// Le résultat est lu dans logcat par la CI.
// ignore_for_file: avoid_print

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:vigiroad/features/plates/domain/plate_format.dart';

/// Test de fumée de l'OCR dans un APK **release** (R8 actif, mêmes règles
/// ProGuard que l'application) : dessine une plaque, la convertit en NV21
/// comme le flux caméra Android, la passe à ML Kit par le même chemin
/// (`InputImage.fromBytes`) et écrit le résultat dans logcat.
/// Ce n'est pas une mesure de taux de reconnaissance.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ColoredBox(color: Color(0xFF000000)));
  const plate = 'AA-123-BB';
  try {
    const w = 1280, h = 720;
    final rgba = await _render(plate, w, h);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final text = await recognizer.processImage(InputImage.fromBytes(
      bytes: _toNv21(rgba, w, h),
      metadata: InputImageMetadata(
        size: const Size(w + 0.0, h + 0.0),
        rotation: InputImageRotation.rotation0deg,
        format: InputImageFormat.nv21,
        bytesPerRow: w,
      ),
    ));
    await recognizer.close();
    final read = text.text.replaceAll('\n', ' | ');
    final found = [
      for (final line in text.text.split('\n')) ...PlateFormats.extract(line),
    ].any((c) => c.normalized == 'AA123BB');
    print('VIGIROAD_OCR_SMOKE ${found ? 'OK' : 'FAIL'} lu="$read"');
  } catch (e, st) {
    print('VIGIROAD_OCR_SMOKE ERROR $e\n$st');
  }
}

Future<Uint8List> _render(String plate, int w, int h) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec)..drawRect(Rect.fromLTWH(0, 0, w + 0.0, h + 0.0), Paint()..color = const Color(0xFFFFFFFF));
  final tp = TextPainter(
    text: TextSpan(
      text: plate,
      style: const TextStyle(color: Color(0xFF000000), fontSize: 150, fontWeight: FontWeight.w700),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, Offset((w - tp.width) / 2, (h - tp.height) / 2));
  final image = await rec.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return data!.buffer.asUint8List();
}

/// RGBA → NV21 (plan Y puis V/U entrelacés, sous-échantillonnés 2×2).
Uint8List _toNv21(Uint8List rgba, int w, int h) {
  final out = Uint8List(w * h * 3 ~/ 2);
  for (var i = 0; i < w * h; i++) {
    final r = rgba[i * 4], g = rgba[i * 4 + 1], b = rgba[i * 4 + 2];
    out[i] = ((66 * r + 129 * g + 25 * b + 128) >> 8) + 16;
  }
  out.fillRange(w * h, out.length, 128); // image en niveaux de gris
  return out;
}
