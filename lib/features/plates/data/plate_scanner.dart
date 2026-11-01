import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' show Rect, Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../domain/camera_tuning.dart';

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
    this.zoom = 1,
    this.motion,
  });

  final List<PlateObservation> observations;

  /// Taille de l'image analysée, remise à l'endroit (portrait).
  final Size uprightSize;
  final double sharpness;
  final double brightness;
  final Duration took;

  /// `false` si l'image a été écartée (floue) sans OCR.
  final bool analyzed;

  /// Zoom de la caméra au moment de l'image.
  final double zoom;

  /// Vitesse angulaire (rad/s) mesurée par le gyroscope, null sans capteur.
  final double? motion;
}

/// Mesures du gyroscope (x, y, z en rad/s).
typedef GyroSource = Stream<({double x, double y, double z})> Function();

Stream<({double x, double y, double z})> _systemGyro() =>
    gyroscopeEventStream(samplingPeriod: SensorInterval.gameInterval).map((e) => (x: e.x, y: e.y, z: e.z));

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

  /// Erreurs d'analyse (OCR, conversion d'image), pour les rendre visibles.
  Stream<String> get errors;
  Future<void> start();
  Future<void> stop();
  Future<void> dispose();
}

class MlKitPlateScanner implements PlateScanner {
  MlKitPlateScanner({
    this.minSharpness = 12,
    this.formats = PlateFormats.all,
    Duration minInterval = const Duration(milliseconds: 150),
    GyroSource? gyro,
    this.autoZoom = true,
  }) : _throttle = FrameThrottle(minInterval: minInterval),
       _gyroSource = gyro ?? _systemGyro,
       _sharpGate = SharpnessGate(floor: minSharpness);

  /// Seuil de netteté (variance du laplacien) sous lequel l'image est ignorée.
  final double minSharpness;
  final List<PlateFormat> formats;

  /// Zoom et mise au point automatiques sur les plaques repérées.
  final bool autoZoom;

  final GyroSource _gyroSource;
  final SharpnessGate _sharpGate;
  final _motion = MotionGate();
  StreamSubscription<({double x, double y, double z})>? _gyroSub;
  CameraTuner _tuner = CameraTuner();
  bool _tuning = false;

  final _frames = StreamController<ScanFrame>.broadcast();
  final _errors = StreamController<String>.broadcast();
  final FrameThrottle _throttle;
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
  Stream<String> get errors => _errors.stream;

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
      await controller.setExposureMode(ExposureMode.auto);
    } on CameraException catch (e) {
      await controller.dispose();
      if (e.code.contains('Denied') || e.code.contains('denied')) {
        throw const ScannerException(ScannerIssue.permissionDenied);
      }
      throw ScannerException(ScannerIssue.cameraError, e.description ?? e.code);
    }
    _controller = controller;
    await _stabilize(controller);
    _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    _sharpGate.reset();
    _gyroSub ??= _safeGyro();
    await controller.startImageStream(_onImage);
  }

  /// Stabilisation de l'image par le téléphone (optique ou électronique,
  /// selon l'appareil) et bornes du zoom automatique. Rien n'est bloquant :
  /// un appareil qui ne gère pas une fonction lit quand même les plaques.
  Future<void> _stabilize(CameraController c) async {
    try {
      await c.setVideoStabilizationMode(VideoStabilizationMode.level2);
    } on Object catch (e) {
      debugPrint('VIGIROAD caméra : stabilisation indisponible ($e)');
    }
    var minZ = 1.0, maxZ = 1.0;
    try {
      minZ = await c.getMinZoomLevel();
      maxZ = await c.getMaxZoomLevel();
    } on Object {
      // Zoom non pris en charge.
    }
    // Au-delà de ×3 le zoom numérique dégrade la plaque plus qu'il n'aide.
    final lo = math.max(1.0, minZ);
    _tuner = CameraTuner(minZoom: lo, maxZoom: math.min(maxZ, 3.0));
    try {
      await c.setZoomLevel(lo);
    } on Object {
      // Ignoré.
    }
  }

  StreamSubscription<({double x, double y, double z})>? _safeGyro() {
    try {
      return _gyroSource().listen((g) => _motion.addGyro(g.x, g.y, g.z), onError: (Object _) {});
    } on Object {
      return null; // Pas de gyroscope : seule la netteté filtre les images.
    }
  }

  /// Applique zoom et mise au point (une seule commande à la fois).
  Future<void> _tune(CameraController c, TuningAction a) async {
    if (a.isEmpty || _tuning) return;
    _tuning = true;
    try {
      if (a.zoom case final z?) await c.setZoomLevel(z);
      if (a.focus case final p?) {
        await c.setFocusPoint(p);
        await c.setExposurePoint(p);
      } else if (a.resetFocus) {
        await c.setFocusPoint(null);
        await c.setExposurePoint(null);
        await c.setFocusMode(FocusMode.auto);
      }
    } on Object catch (e) {
      debugPrint('VIGIROAD caméra : réglage impossible ($e)');
    } finally {
      _tuning = false;
    }
  }

  @override
  Future<void> stop() async {
    final c = _controller;
    _controller = null;
    await _gyroSub?.cancel();
    _gyroSub = null;
    _tuner.reset();
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
    await _errors.close();
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
    // Secousse en cours : on attend l'image suivante, prise au calme.
    if (!_motion.shouldAnalyze(now)) return;
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

      final motion = _motion.hasSensor ? _motion.level : null;
      if (!_sharpGate.accept(sharp)) {
        _emit(ScanFrame(
          observations: const [],
          uprightSize: upright,
          sharpness: sharp,
          brightness: bright,
          took: watch.elapsed,
          analyzed: false,
          zoom: _tuner.zoom,
          motion: motion,
        ));
        return;
      }

      final format = InputImageFormatValue.fromRawValue(image.format.raw as int);
      final rot = InputImageRotationValue.fromRawValue(rotation);
      if (format == null || rot == null) {
        _error('format d\'image non pris en charge (${image.format.raw}, rotation $rotation)');
        return;
      }
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
      final zoomAtCapture = _tuner.zoom;
      if (autoZoom && upright.width > 0 && upright.height > 0) {
        final boxes = [
          for (final o in observations)
            if (o.box case final b?) Rect.fromLTRB(b.left / upright.width, b.top / upright.height, b.right / upright.width, b.bottom / upright.height),
        ];
        unawaited(_tune(c, _tuner.update(boxes, now)));
      }
      _emit(ScanFrame(
        observations: observations,
        uprightSize: upright,
        sharpness: sharp,
        brightness: bright,
        took: watch.elapsed,
        analyzed: true,
        zoom: zoomAtCapture,
        motion: motion,
      ));
    } catch (e, st) {
      debugPrint('VIGIROAD OCR: $e\n$st');
      _error('$e');
    } finally {
      _throttle.end(watch.elapsed);
    }
  }

  void _error(String message) {
    if (!_errors.isClosed) _errors.add(message.length > 160 ? '${message.substring(0, 160)}…' : message);
  }

  void _emit(ScanFrame f) {
    if (!_frames.isClosed) _frames.add(f);
  }
}
