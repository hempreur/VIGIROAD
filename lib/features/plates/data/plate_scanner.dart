import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show Rect, Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../domain/frame_analysis.dart';
import '../domain/plate_format.dart';
import '../domain/plate_voter.dart';

/// Résultat de l'analyse d'une image du flux.
class ScanFrame {
  const ScanFrame({
    required this.observations,
    required this.uprightSize,
    required this.sharpness,
    required this.brightness,
    required this.took,
    required this.analyzed,
  });

  final List<PlateObservation> observations;

  /// Taille de l'image analysée, remise à l'endroit (portrait).
  final Size uprightSize;
  final double sharpness;
  final double brightness;
  final Duration took;

  /// `false` si l'image a été écartée (floue) sans OCR.
  final bool analyzed;
}

enum ScannerIssue { noCamera, permissionDenied, cameraError }

class ScannerException implements Exception {
  const ScannerException(this.issue, [this.detail]);
  final ScannerIssue issue;
  final String? detail;

  @override
  String toString() => switch (issue) {
    ScannerIssue.noCamera => 'Aucune caméra arrière disponible.',
    ScannerIssue.permissionDenied => 'L\'accès à la caméra n\'est pas autorisé.',
    ScannerIssue.cameraError => 'Erreur caméra${detail == null ? '' : ' : $detail'}.',
  };
}

/// Lecteur de plaques : caméra arrière + OCR sur l'appareil.
abstract interface class PlateScanner {
  /// Contrôleur pour l'aperçu (null tant que la caméra n'est pas prête).
  CameraController? get controller;
  Stream<ScanFrame> get frames;
  Future<void> start();
  Future<void> stop();
  Future<void> dispose();
}

class MlKitPlateScanner implements PlateScanner {
  MlKitPlateScanner({this.minSharpness = 12, this.formats = PlateFormats.all});

  /// Seuil de netteté (variance du laplacien) sous lequel l'image est ignorée.
  final double minSharpness;
  final List<PlateFormat> formats;

  final _frames = StreamController<ScanFrame>.broadcast();
  final _throttle = FrameThrottle();
  TextRecognizer? _recognizer;
  CameraController? _controller;
  CameraDescription? _camera;

  static const _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  @override
  CameraController? get controller => _controller;

  @override
  Stream<ScanFrame> get frames => _frames.stream;

  @override
  Future<void> start() async {
    if (_controller?.value.isStreamingImages ?? false) return;
    final cameras = await availableCameras();
    _camera = cameras.where((c) => c.lensDirection == CameraLensDirection.back).firstOrNull;
    if (_camera == null) throw const ScannerException(ScannerIssue.noCamera);

    final controller = CameraController(
      _camera!,
      // 720p : bon compromis lisibilité des plaques / coût de l'OCR.
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );
    try {
      await controller.initialize();
      await controller.setFocusMode(FocusMode.auto);
    } on CameraException catch (e) {
      await controller.dispose();
      if (e.code.contains('Denied') || e.code.contains('denied')) {
        throw const ScannerException(ScannerIssue.permissionDenied);
      }
      throw ScannerException(ScannerIssue.cameraError, e.description ?? e.code);
    }
    _controller = controller;
    _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    await controller.startImageStream(_onImage);
  }

  @override
  Future<void> stop() async {
    final c = _controller;
    _controller = null;
    if (c == null) return;
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
    } on CameraException {
      // Caméra déjà libérée par le système (appel entrant, autre application…).
    }
    await c.dispose();
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _recognizer?.close();
    _recognizer = null;
    await _frames.close();
  }

  int? _rotationDegrees(CameraController c) {
    final sensor = _camera!.sensorOrientation;
    if (Platform.isIOS) return sensor;
    final comp = _orientations[c.value.deviceOrientation];
    if (comp == null) return null;
    return (sensor - comp + 360) % 360;
  }

  Future<void> _onImage(CameraImage image) async {
    final now = DateTime.now();
    final c = _controller;
    final recognizer = _recognizer;
    if (c == null || recognizer == null || !_throttle.shouldProcess(now)) return;
    _throttle.begin(now);
    final watch = Stopwatch()..start();
    try {
      final rotation = _rotationDegrees(c);
      if (rotation == null || image.planes.isEmpty) return;
      final upright = rotation % 180 == 0
          ? Size(image.width.toDouble(), image.height.toDouble())
          : Size(image.height.toDouble(), image.width.toDouble());

      // Netteté et luminosité sur la luminance (NV21 : plan Y en tête ;
      // BGRA : canal vert comme approximation).
      final plane = image.planes.first;
      final isBgra = image.format.group == ImageFormatGroup.bgra8888;
      final luma = isBgra ? Uint8List.sublistView(plane.bytes, 1) : plane.bytes;
      final stride = plane.bytesPerRow;
      final px = isBgra ? 4 : 1;
      final sharp = laplacianVariance(luma, width: image.width, height: image.height, rowStride: stride, pixelStride: px);
      final bright = meanLuma(luma, width: image.width, height: image.height, rowStride: stride, pixelStride: px);

      if (sharp < minSharpness) {
        _emit(ScanFrame(observations: const [], uprightSize: upright, sharpness: sharp, brightness: bright, took: watch.elapsed, analyzed: false));
        return;
      }

      final format = InputImageFormatValue.fromRawValue(image.format.raw);
      final rot = InputImageRotationValue.fromRawValue(rotation);
      if (format == null || rot == null) return;
      final input = InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rot,
          format: format,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
      final text = await recognizer.processImage(input);
      final observations = <PlateObservation>[];
      for (final block in text.blocks) {
        for (final line in block.lines) {
          for (final cand in PlateFormats.extract(line.text, formats: formats)) {
            observations.add(PlateObservation(
              candidate: cand,
              at: now,
              ocrConfidence: line.confidence,
              box: line.boundingBox,
            ));
          }
        }
        // Plaque coupée en deux lignes par l'OCR (« AA-123 » / « -BB ») :
        // on tente aussi le bloc entier.
        if (block.lines.length > 1 && observations.every((o) => !block.boundingBox.overlaps(o.box ?? Rect.zero))) {
          for (final cand in PlateFormats.extract(block.text.replaceAll('\n', ' '), formats: formats)) {
            observations.add(PlateObservation(candidate: cand, at: now, box: block.boundingBox));
          }
        }
      }
      _emit(ScanFrame(
        observations: observations,
        uprightSize: upright,
        sharpness: sharp,
        brightness: bright,
        took: watch.elapsed,
        analyzed: true,
      ));
    } catch (e, st) {
      debugPrint('VIGIROAD OCR: $e\n$st');
    } finally {
      _throttle.end(watch.elapsed);
    }
  }

  void _emit(ScanFrame f) {
    if (!_frames.isClosed) _frames.add(f);
  }
}
