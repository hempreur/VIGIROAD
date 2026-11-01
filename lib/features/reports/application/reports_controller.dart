import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vigiroad_traffic/vigiroad_traffic.dart';

import '../../../app/providers.dart';
import '../../navigation/application/navigation_providers.dart';
import '../../navigation/application/navigation_session.dart';
import '../../navigation/domain/geo_fix.dart';
import '../../sentrix/application/sentrix_controller.dart';
import '../../settings/application/settings_controller.dart';
import '../data/reports_client.dart';

class ReportsState {
  const ReportsState({this.reports = const [], this.available = true, this.message});

  /// Signalements actifs autour de la position.
  final List<ChickenReport> reports;

  /// Serveur configuré et option activée.
  final bool available;
  final String? message;
}

final reportsClientProvider = Provider<ReportsClient?>((ref) {
  final c = ref.watch(appConfigProvider);
  if (!c.trafficEnabled) return null;
  return HttpReportsClient(baseUrl: c.trafficApiUrl, apiKey: c.trafficApiKey, userAgent: c.userAgent);
});

final reportsProvider = NotifierProvider<ReportsController, ReportsState>(ReportsController.new);

/// Résultat d'un signalement envoyé.
sealed class SubmitResult {
  const SubmitResult();
}

class Submitted extends SubmitResult {
  const Submitted(this.report);
  final ChickenReport report;
}

class SubmitFailed extends SubmitResult {
  const SubmitFailed(this.message);
  final String message;
}

/// Signalements « Chicken » : envoi, affichage sur la carte (zone de ±30 km
/// autour de la position, rafraîchie chaque minute) et annonce vocale quand
/// un signalement est devant le véhicule, à moins de [announceWithinM].
class ReportsController extends Notifier<ReportsState> {
  static const refreshEvery = Duration(seconds: 60);
  static const halfBoxDeg = 0.27;
  static const moveRefreshM = 5000.0;
  static const announceWithinM = 1500.0;

  Timer? _timer;
  GeoPoint? _lastCenter;
  bool _busy = false;
  final _announced = <String>{};

  @override
  ReportsState build() {
    final client = ref.watch(reportsClientProvider);
    final enabled = ref.watch(appSettingsProvider.select((s) => s.chickenReports));
    if (client == null) return const ReportsState(available: false, message: 'Serveur VIGIROAD non configuré');

    ref.listen(positionProvider, (_, next) {
      final p = next.value?.point;
      if (p == null) return;
      final last = _lastCenter;
      if (enabled && (last == null || _distance(last, p) > moveRefreshM)) unawaited(refresh());
      _checkAhead();
    });
    if (enabled) {
      _timer = Timer.periodic(refreshEvery, (_) => unawaited(refresh()));
      unawaited(Future.microtask(refresh));
    }
    ref.onDispose(() => _timer?.cancel());
    return ReportsState(available: enabled);
  }

  DateTime _now() => ref.read(clockProvider)();

  static double _distance(GeoPoint a, GeoPoint b) =>
      haversine(LatLng(a.latitude, a.longitude), LatLng(b.latitude, b.longitude));

  List<ChickenReport> _alive(Iterable<ChickenReport> rs) => [for (final r in rs) if (r.activeAt(_now())) r];

  Future<void> refresh() async {
    final client = ref.read(reportsClientProvider);
    final fix = ref.read(positionProvider).value;
    if (client == null || fix == null || _busy || !ref.read(appSettingsProvider).chickenReports) return;
    _busy = true;
    try {
      final p = fix.point;
      final box = BBox(
        p.longitude - halfBoxDeg * 1.5,
        p.latitude - halfBoxDeg,
        p.longitude + halfBoxDeg * 1.5,
        p.latitude + halfBoxDeg,
      );
      final reports = await client.inBox(box);
      if (!ref.mounted) return;
      _lastCenter = p;
      state = ReportsState(reports: _alive(reports));
      _checkAhead();
    } on ReportsException catch (e) {
      if (!ref.mounted) return;
      // On garde les marqueurs encore valides plutôt que de tout effacer.
      state = ReportsState(reports: _alive(state.reports), message: e.message);
    } finally {
      _busy = false;
    }
  }

  /// Signale un Chicken à la position actuelle.
  Future<SubmitResult> submit(ReportSide side) async {
    final client = ref.read(reportsClientProvider);
    if (client == null) return const SubmitFailed('Signalement impossible : serveur VIGIROAD non configuré.');
    final fix = ref.read(positionProvider).value;
    if (fix == null) return const SubmitFailed('Position GPS inconnue : signalement impossible.');
    try {
      final r = await client.submit(
        position: LatLng(fix.point.latitude, fix.point.longitude),
        heading: fix.headingReliable ? fix.headingDeg! % 360 : null,
        side: side,
      );
      if (!ref.mounted) return Submitted(r);
      // Son propre signalement n'est pas annoncé.
      _announced.add(r.id);
      state = ReportsState(
        reports: _alive([for (final x in state.reports) if (x.id != r.id) x, r]),
        available: state.available,
      );
      return Submitted(r);
    } on ReportsException catch (e) {
      return SubmitFailed(e.message);
    }
  }

  /// Annonce (une fois chacun) les signalements devant le véhicule.
  void _checkAhead() {
    if (!ref.read(appSettingsProvider).chickenReports || !ref.read(voiceGuidanceProvider)) return;
    final fix = ref.read(positionProvider).value;
    if (fix == null || !fix.headingReliable) return;
    final me = LatLng(fix.point.latitude, fix.point.longitude);
    final heading = fix.headingDeg!;
    ChickenReport? best;
    var bestD = double.infinity;
    for (final r in state.reports) {
      if (_announced.contains(r.id) || !r.activeAt(_now())) continue;
      final d = haversine(me, r.position);
      if (d > announceWithinM || d < 30) continue;
      // Devant : dans un cône de ±50° autour du cap.
      if (headingDelta(bearing(me, r.position), heading) > 50) continue;
      if (d < bestD) {
        best = r;
        bestD = d;
      }
    }
    final r = best;
    if (r == null) return;
    _announced.add(r.id);
    unawaited(ref.read(sentrixProvider.notifier).announce(announcement(r, bestD, heading)));
  }

  /// Phrase annoncée par SENTRIX.
  static String announcement(ChickenReport r, double distanceM, double myHeading) {
    final m = distanceM < 1000 ? '${(distanceM / 50).round() * 50} mètres' : '${(distanceM / 1000).toStringAsFixed(1).replaceAll('.', ',')} kilomètre';
    final where = r.concerns(myHeading) ? 'sur votre route' : 'sur la voie d\'en face';
    return 'Attention, Chicken signalé $where dans $m.';
  }
}
