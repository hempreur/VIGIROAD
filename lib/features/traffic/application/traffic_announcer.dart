import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../navigation/application/navigation_session.dart';
import '../../sentrix/application/sentrix_controller.dart';
import '../domain/traffic_labels.dart';
import 'traffic_controller.dart';

/// Distance devant le véhicule à partir de laquelle une perturbation est annoncée.
const trafficAnnounceAheadM = 5000.0;

final trafficAnnouncerProvider = Provider<TrafficAnnouncer>((ref) {
  final a = TrafficAnnouncer(ref);
  ref.listen(navigationSessionProvider, (_, _) => a.check());
  ref.listen(trafficProvider, (_, _) => a.check());
  return a;
});

/// SENTRIX annonce les perturbations situées sur l'itinéraire, une fois
/// chacune, quand elles sont à moins de [trafficAnnounceAheadM] devant.
/// Le bouton de coupure du guidage vocal coupe aussi ces annonces.
class TrafficAnnouncer {
  TrafficAnnouncer(this._ref);

  final Ref _ref;
  final _announced = <String>{};
  final _attempts = <String, int>{};
  Object? _route;
  bool _speaking = false;

  void check() {
    final nav = _ref.read(navigationSessionProvider);
    final progress = nav.progress;
    if (!identical(nav.route, _route)) {
      _route = nav.route;
      _announced.clear();
      _attempts.clear();
    }
    if (!nav.hasRoute || progress == null || _speaking) return;
    if (!_ref.read(voiceGuidanceProvider)) return;
    final traffic = _ref.read(trafficProvider);
    if (traffic.status != TrafficStatus.known && traffic.status != TrafficStatus.unknown) return;

    final along = progress.alongM;
    for (final r in traffic.onRoute) {
      final ahead = r.alongM - along;
      if (ahead < 0 || ahead > trafficAnnounceAheadM || _announced.contains(r.event.id)) continue;
      _announced.add(r.event.id);
      final attempt = _attempts[r.event.id] = (_attempts[r.event.id] ?? 0) + 1;
      _speaking = true;
      unawaited(_ref.read(sentrixProvider.notifier).announce(TrafficLabels.announcement(r.event, ahead)).then((spoken) {
        _speaking = false;
        // Annonce non prononcée (coupée par une consigne) : un seul nouvel essai.
        if (!spoken && attempt < 2) _announced.remove(r.event.id);
      }));
      return; // une annonce à la fois, la plus proche d'abord
    }
  }
}
