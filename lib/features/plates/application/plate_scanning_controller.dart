import 'dart:async';
import 'dart:ui' show Rect;

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/permissions/permission_service.dart';
import '../../settings/application/settings_controller.dart';
import '../data/plate_scanner.dart';
import '../domain/plate_models.dart';
import '../domain/plate_voter.dart';
import 'plates_providers.dart';
import 'watchlist_controller.dart';

enum ScanStatus { off, starting, running, paused, error }

/// État affiché du module de lecture.
class ScanState {
  const ScanState({
    this.status = ScanStatus.off,
    this.message,
    this.boxes = const [],
    this.sharpness,
    this.analysisMs,
    this.lowLight = false,
    this.ocrError,
    this.tracked = 0,
    this.zoom = 1,
  });

  final ScanStatus status;
  final String? message;

  /// Plaques **dangereuses** (présentes dans la liste de surveillance) de la
  /// dernière image, en coordonnées normalisées (0–1) dans l'image remise à
  /// l'endroit. Les autres plaques sont lues mais jamais affichées.
  final List<Rect> boxes;

  /// Nombre de plaques lues sur la dernière image (toutes, listées ou non).
  final int tracked;

  /// Zoom automatique de la caméra.
  final double zoom;
  final double? sharpness;
  final int? analysisMs;

  /// Luminosité faible : lecture moins fiable.
  final bool lowLight;

  /// Analyse en échec répété : cause affichée au conducteur.
  final String? ocrError;

  bool get active => status == ScanStatus.running || status == ScanStatus.starting;
}

final plateScannerProvider = Provider<PlateScanner>((ref) {
  final mode = ref.watch(appSettingsProvider.select((s) => s.performance));
  final autoZoom = ref.watch(appSettingsProvider.select((s) => s.autoZoom));
  final scanner = MlKitPlateScanner(minInterval: mode.minInterval, autoZoom: autoZoom);
  ref.onDispose(() => unawaited(scanner.dispose()));
  return scanner;
});

final voterSettingsProvider = Provider<VoterSettings>(
  (ref) => VoterSettings(minVotes: ref.watch(appSettingsProvider.select((s) => s.minVotes))),
);

/// Horloge du module plaques (tests).
final scanClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final plateScanningProvider = NotifierProvider<PlateScanningController, ScanState>(PlateScanningController.new);

/// Lecture des plaques : démarre/arrête la caméra, vote sur plusieurs images
/// et publie les plaques confirmées.
class PlateScanningController extends Notifier<ScanState> {
  StreamSubscription<ScanFrame>? _sub;
  StreamSubscription<String>? _errSub;
  int _errorStreak = 0;
  late PlateVoter _voter;
  bool _wanted = false;
  AppLifecycleListener? _lifecycle;

  final _confirmed = StreamController<PlateReading>.broadcast();

  /// Plaques confirmées (consommées par le moteur de correspondance, phase 5).
  Stream<PlateReading> get confirmed => _confirmed.stream;

  @override
  ScanState build() {
    _voter = PlateVoter(ref.watch(voterSettingsProvider));
    final scanner = ref.watch(plateScannerProvider);
    _lifecycle = AppLifecycleListener(
      // La caméra ne peut pas tourner en arrière-plan (iOS, Android) :
      // on la libère et on reprend au retour si la lecture était demandée.
      onHide: () => unawaited(_pause()),
      onShow: () {
        if (_wanted) unawaited(_start());
      },
    );
    ref.onDispose(() {
      _lifecycle?.dispose();
      unawaited(_sub?.cancel());
      unawaited(_errSub?.cancel());
      unawaited(scanner.stop());
      unawaited(_confirmed.close());
    });
    return const ScanState();
  }

  Future<void> toggle() => state.active ? stop() : start();

  Future<void> start() async {
    _wanted = true;
    final perms = ref.read(permissionsProvider.notifier);
    final status = await perms.request(AppCapability.camera);
    if (status != CapabilityStatus.granted) {
      _wanted = false;
      state = const ScanState(
        status: ScanStatus.error,
        message: 'Autorisez la caméra pour lire les plaques.',
      );
      return;
    }
    await _start();
  }

  Future<void> stop() async {
    _wanted = false;
    await _halt();
    state = const ScanState();
  }

  Future<void> _pause() async {
    if (!state.active) return;
    await _halt();
    state = const ScanState(status: ScanStatus.paused, message: 'Lecture suspendue (application en arrière-plan)');
  }

  Future<void> _halt() async {
    await _sub?.cancel();
    _sub = null;
    await _errSub?.cancel();
    _errSub = null;
    _errorStreak = 0;
    await ref.read(plateScannerProvider).stop();
    _voter.reset();
  }

  Future<void> _start() async {
    final scanner = ref.read(plateScannerProvider);
    state = const ScanState(status: ScanStatus.starting);
    _sub ??= scanner.frames.listen(_onFrame);
    _errSub ??= scanner.errors.listen(_onError);
    try {
      await scanner.start();
      if (!_wanted) {
        await _halt();
        return;
      }
      state = const ScanState(status: ScanStatus.running);
    } on ScannerException catch (e) {
      _wanted = false;
      await _halt();
      state = ScanState(status: ScanStatus.error, message: e.toString());
    }
  }

  /// Trois échecs d'analyse d'affilée : la lecture ne fonctionne pas, on le
  /// dit plutôt que de laisser croire qu'aucune plaque n'est visible.
  void _onError(String message) {
    if (state.status != ScanStatus.running) return;
    if (++_errorStreak < 3) return;
    state = ScanState(status: ScanStatus.running, ocrError: 'Lecture des plaques en échec : $message');
  }

  void _onFrame(ScanFrame f) {
    if (state.status != ScanStatus.running) return;
    if (f.analyzed) _errorStreak = 0;
    final now = ref.read(scanClockProvider)();
    final w = f.uprightSize.width, h = f.uprightSize.height;
    final listed = ref.read(watchlistIndexProvider);
    state = ScanState(
      status: ScanStatus.running,
      boxes: [
        for (final o in f.observations)
          if (o.box != null && w > 0 && h > 0 && listed.containsKey(o.candidate.normalized))
            Rect.fromLTRB(o.box!.left / w, o.box!.top / h, o.box!.right / w, o.box!.bottom / h),
      ],
      tracked: {for (final o in f.observations) o.candidate.normalized}.length,
      sharpness: f.sharpness,
      analysisMs: f.took.inMilliseconds,
      lowLight: f.brightness < 35,
      zoom: f.zoom,
    );
    // Toutes les plaques de l'image sont votées et comparées à la liste
    // (lecture multi-plaques) ; seules les dangereuses seront affichées.
    for (final reading in _voter.add(f.observations, now)) {
      _confirmed.add(reading);
    }
  }
}
