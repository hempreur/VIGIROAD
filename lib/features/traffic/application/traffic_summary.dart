import '../../navigation/application/navigation_session.dart';
import '../domain/traffic_labels.dart';
import 'traffic_controller.dart';

/// Réponse de SENTRIX à « état du trafic » : uniquement ce que disent les
/// sources, et « inconnu » quand elles ne couvrent pas la zone.
({bool ok, String text}) trafficSummary(TrafficState t, NavState nav) {
  switch (t.status) {
    case TrafficStatus.disabled:
      return (ok: false, text: 'Le trafic en temps réel n\'est pas disponible : aucun serveur de trafic n\'est configuré.');
    case TrafficStatus.waiting:
      return (ok: false, text: 'Je récupère l\'état du trafic, réessayez dans un instant.');
    case TrafficStatus.error:
      return (ok: false, text: 'Le trafic est indisponible pour le moment : ${t.message ?? 'serveur injoignable'}.');
    case TrafficStatus.unknown:
      return (ok: true, text: 'État du trafic inconnu ici : aucune source à jour ne couvre cette zone.');
    case TrafficStatus.known:
      break;
  }
  final along = nav.progress?.alongM;
  if (nav.hasRoute && along != null) {
    final ahead = [for (final r in t.onRoute) if (r.alongM >= along) r];
    if (ahead.isEmpty) return (ok: true, text: 'Aucune perturbation signalée sur votre itinéraire.');
    final first = ahead.first;
    final n = ahead.length;
    return (
      ok: true,
      text: '${n == 1 ? 'Une perturbation signalée' : '$n perturbations signalées'} sur votre itinéraire. '
          '${n == 1 ? '' : 'La prochaine : '}${TrafficLabels.announcement(first.event, first.alongM - along)}',
    );
  }
  final n = t.nearby.length;
  if (n == 0) return (ok: true, text: 'Aucune perturbation signalée dans les environs.');
  return (ok: true, text: '${n == 1 ? 'Une perturbation signalée' : '$n perturbations signalées'} dans les environs.');
}
