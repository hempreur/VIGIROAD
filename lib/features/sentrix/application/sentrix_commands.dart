import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../navigation/application/navigation_providers.dart';
import '../../navigation/application/navigation_session.dart';
import '../../navigation/domain/geo_math.dart';
import '../../navigation/domain/instructions.dart';
import '../../plates/application/alert_service.dart';
import '../../plates/application/plate_scanning_controller.dart';
import '../../plates/application/plates_providers.dart';
import '../../traffic/application/traffic_controller.dart';
import '../../traffic/application/traffic_summary.dart';
import '../domain/command_engine.dart';

/// Contexte donné aux actions : accès aux modules de l'application.
class SentrixContext {
  const SentrixContext(this.ref);
  final Ref ref;

  void open(String route) => ref.read(routerProvider).push(route).ignore();
}

typedef SentrixCommand = VoiceCommand<SentrixContext>;

/// Commandes vocales de SENTRIX.
///
/// Liste PROVISOIRE reprenant les exemples de l'image de référence ; les
/// commandes définitives seront fixées avec le propriétaire du projet.
/// Pour en ajouter une : déclarer un [SentrixCommand] ci-dessous (voir
/// docs/SENTRIX.md).
final List<SentrixCommand> sentrixCommands = [
  SentrixCommand(
    id: 'navigation.start',
    label: 'Lancer la navigation',
    phrases: ['Lancer la navigation', 'Chercher une adresse', 'Aller quelque part', 'Nouvelle destination'],
    action: (c) async {
      c.open(Routes.search);
      return const CommandResult('Où voulez-vous aller ?');
    },
  ),
  SentrixCommand(
    id: 'navigation.stop',
    label: 'Arrêter la navigation',
    phrases: ['Arrêter la navigation', 'Annuler le guidage'],
    keywords: ['navigation'],
    action: (c) async {
      if (c.ref.read(destinationProvider) == null) {
        return const CommandResult('Aucun guidage en cours.');
      }
      c.ref.read(destinationProvider.notifier).clear();
      return const CommandResult('Guidage arrêté.');
    },
  ),
  SentrixCommand(
    id: 'navigation.eta',
    label: 'Heure d\'arrivée',
    phrases: ['Heure d\'arrivée', 'Dans combien de temps j\'arrive', 'Quand est-ce que j\'arrive', 'Combien de temps reste-t-il', 'Distance restante'],
    action: (c) async {
      final nav = c.ref.read(navigationSessionProvider);
      final p = nav.progress, eta = nav.arrival;
      if (!nav.hasRoute || p == null || eta == null) {
        return const CommandResult('Aucun itinéraire en cours.');
      }
      final min = (p.remainingS / 60).round();
      final step = nav.nextStep;
      final next = step == null ? '' : ' Prochaine indication : ${Instructions.spoken(step, inMeters: p.toNextManeuverM)}';
      return CommandResult(
        'Arrivée prévue à ${eta.hour} heures ${eta.minute.toString().padLeft(2, '0')}, '
        'dans $min minute${min > 1 ? 's' : ''}, ${formatDistance(p.remainingM).replaceAll(',', ' virgule ')}.$next',
      );
    },
  ),
  SentrixCommand(
    id: 'detection.on',
    label: 'Activer la détection',
    phrases: ['Activer la détection', 'Lancer la détection', 'Activer la caméra'],
    keywords: ['detection'],
    action: (c) async {
      final scan = c.ref.read(plateScanningProvider.notifier);
      await scan.start();
      final s = c.ref.read(plateScanningProvider);
      return s.status == ScanStatus.error
          ? CommandResult.failure(s.message ?? 'La caméra ne peut pas démarrer.')
          : const CommandResult('Lecture des plaques activée.');
    },
  ),
  SentrixCommand(
    id: 'detection.off',
    label: 'Désactiver la détection',
    phrases: ['Désactiver la détection', 'Arrêter la détection', 'Couper la caméra'],
    keywords: ['detection'],
    action: (c) async {
      await c.ref.read(plateScanningProvider.notifier).stop();
      return const CommandResult('Lecture des plaques arrêtée.');
    },
  ),
  SentrixCommand(
    id: 'traffic.show',
    label: 'Afficher le trafic',
    phrases: ['Afficher le trafic', 'État du trafic', 'Y a-t-il des bouchons'],
    action: (c) async {
      final r = trafficSummary(c.ref.read(trafficProvider), c.ref.read(navigationSessionProvider));
      return r.ok ? CommandResult(r.text) : CommandResult.failure(r.text);
    },
  ),
  SentrixCommand(
    id: 'alert.last',
    label: 'Lire la dernière alerte',
    phrases: ['Lire la dernière alerte', 'Dernière alerte', 'Quelle était la dernière alerte'],
    keywords: ['alerte'],
    action: (c) async {
      final active = c.ref.read(activeAlertProvider);
      final log = await c.ref.read(detectionsProvider.future);
      final plate = active?.reading.display ?? (log.isEmpty ? null : log.first.display);
      if (plate == null) return const CommandResult('Aucune alerte enregistrée.');
      final category = active?.category ?? log.first.category;
      final at = active?.at ?? log.first.at;
      return CommandResult(
        'Dernière alerte à ${at.hour} heures ${at.minute.toString().padLeft(2, '0')} : '
        'plaque ${plate.split('').join(' ').replaceAll('-', ',')}, $category.',
      );
    },
  ),
  SentrixCommand(
    id: 'history.open',
    label: 'Ouvrir l\'historique',
    phrases: ['Ouvrir l\'historique', 'Afficher l\'historique', 'Historique des détections'],
    keywords: ['historique'],
    action: (c) async {
      c.open(Routes.history);
      return const CommandResult('Voici l\'historique des détections.');
    },
  ),
  SentrixCommand(
    id: 'plates.open',
    label: 'Ouvrir la liste des plaques',
    phrases: ['Ouvrir la liste des plaques', 'Plaques à surveiller', 'Gérer les plaques'],
    keywords: ['plaque'],
    action: (c) async {
      c.open(Routes.plates);
      return const CommandResult('Voici la liste des plaques à surveiller.');
    },
  ),
  SentrixCommand(
    id: 'settings.open',
    label: 'Ouvrir les réglages',
    phrases: ['Ouvrir les réglages', 'Paramètres'],
    keywords: ['reglages'],
    action: (c) async {
      c.open(Routes.settings);
      return const CommandResult('Voici les réglages.');
    },
  ),
  SentrixCommand(
    id: 'voice.off',
    label: 'Couper le guidage vocal',
    phrases: ['Couper le guidage vocal', 'Désactiver la voix', 'Silence'],
    action: (c) async {
      if (c.ref.read(voiceGuidanceProvider)) c.ref.read(voiceGuidanceProvider.notifier).toggle();
      return const CommandResult('Guidage vocal coupé.');
    },
  ),
  SentrixCommand(
    id: 'voice.on',
    label: 'Activer le guidage vocal',
    phrases: ['Activer le guidage vocal', 'Activer la voix', 'Réactiver le son'],
    action: (c) async {
      if (!c.ref.read(voiceGuidanceProvider)) c.ref.read(voiceGuidanceProvider.notifier).toggle();
      return const CommandResult('Guidage vocal activé.');
    },
  ),
  SentrixCommand(
    id: 'speed.read',
    label: 'Quelle est ma vitesse',
    phrases: ['Quelle est ma vitesse', 'À quelle vitesse je roule'],
    keywords: ['vitesse'],
    action: (c) async {
      final kmh = c.ref.read(positionProvider).value?.speedKmh;
      return kmh == null
          ? const CommandResult.failure('Vitesse indisponible pour le moment.')
          : CommandResult('Vous roulez à $kmh kilomètres heure.');
    },
  ),
  SentrixCommand(
    id: 'help',
    label: 'Aide',
    phrases: ['Aide', 'Que peux-tu faire', 'Quelles sont les commandes'],
    action: (c) async => CommandResult(
      'Vous pouvez dire par exemple : ${[for (final cmd in sentrixCommands.take(5)) cmd.label.toLowerCase()].join(', ')}.',
    ),
  ),
];
