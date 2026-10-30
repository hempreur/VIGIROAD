import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/theme/vr_colors.dart';
import '../../../core/theme/vr_typography.dart';
import '../../../core/widgets/glow_panel.dart';
import '../../../core/widgets/square_icon_button.dart';
import '../../../core/widgets/vr_button.dart';
import '../../plates/application/plates_providers.dart';
import '../../plates/presentation/widgets/alert_banner.dart';
import '../../plates/presentation/widgets/camera_panel.dart';
import '../../plates/presentation/widgets/ocr_panel.dart';
import '../../sentrix/domain/sentrix_state.dart';
import '../../sentrix/presentation/sentrix_head.dart';
import '../application/navigation_providers.dart';
import '../data/location_source.dart';
import '../application/navigation_session.dart';
import '../domain/geo_math.dart';
import '../domain/instructions.dart';
import 'widgets/guidance_widgets.dart';
import 'widgets/maneuver_card.dart';
import 'widgets/map_view.dart';
import 'widgets/position_puck.dart';
import 'widgets/speed_gauge.dart';
import 'widgets/traffic_legend.dart';

/// Écran GPS principal — composition de l'image de référence :
/// cartouche de guidage et boutons en haut, carte au centre, compteur,
/// caméra arrière, lecture OCR et alerte en bas.
class NavigationScreen extends ConsumerStatefulWidget {
  const NavigationScreen({super.key});

  @override
  ConsumerState<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends ConsumerState<NavigationScreen> {
  bool _following = true;
  bool _tilted = true;

  static const double _gap = 8;
  static const double _side = 12;
  static const double _button = 52;

  void _openMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SentrixMenu(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    final position = ref.watch(positionProvider);
    final destination = ref.watch(destinationProvider);
    final nav = ref.watch(navigationSessionProvider);
    final voiceOn = ref.watch(voiceGuidanceProvider);
    final showEta = nav.hasRoute && nav.progress != null && nav.arrival != null;
    final speedLimit = nav.hasRoute ? nav.progress?.speedLimitKmh : null;
    final alert = ref.watch(activeAlertProvider);
    final reading = ref.watch(lastReadingProvider);
    final scanning = ref.watch(plateScanningProvider);
    final locationGranted =
        ref.watch(permissionsProvider).value?[AppCapability.location] == CapabilityStatus.granted;
    final mapBuilder = ref.watch(mapViewBuilderProvider);

    final fix = position.value;
    final media = MediaQuery.of(context);
    final pad = media.padding;
    final size = media.size;

    // Hauteurs des zones, proportionnelles à l'écran comme sur la référence.
    final cameraH = (size.height * 0.2).clamp(130.0, 190.0);
    const ocrH = 104.0;
    const speedRowH = 72.0;
    const alertH = 88.0;
    final bottomH = pad.bottom + _side + ocrH + _gap + cameraH + _gap + speedRowH +
        (alert != null ? alertH + _gap : 0);
    final topH = pad.top + _side + 112 + (showEta ? 54 : 0);
    final insets = EdgeInsets.only(top: topH, bottom: bottomH);
    final puckY = topH + (size.height - topH - bottomH) / 2;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: mapBuilder(
              MapViewArgs(
                styleUrl: config.mapStyleUrl,
                following: _following,
                tilted: _tilted,
                fix: fix,
                destination: destination?.point,
                route: nav.route?.geometry,
                insets: insets,
                locationGranted: locationGranted,
                onUserGesture: () {
                  if (_following) setState(() => _following = false);
                },
              ),
            ),
          ),
          // Voile sombre sous la barre d'état et derrière les panneaux du bas.
          const _Scrims(),
          if (_following && fix != null)
            Positioned(
              left: size.width / 2 - 27,
              top: puckY - 27,
              child: const IgnorePointer(child: PositionPuck()),
            ),

          // --- Haut : cartouche + colonne de boutons ---------------------------
          Positioned(
            top: pad.top + _side,
            left: _side,
            right: _side,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildManeuverCard(destination, nav),
                      if (showEta) ...[
                        const SizedBox(height: 6),
                        EtaChip(
                          arrival: nav.arrival!,
                          remainingS: nav.progress!.remainingS,
                          remainingM: nav.progress!.remainingM,
                          rerouting: nav.status == NavStatus.rerouting,
                          voiceOn: voiceOn,
                          onToggleVoice: ref.read(voiceGuidanceProvider.notifier).toggle,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: _gap),
                Column(
                  children: [
                    SquareIconButton(
                      icon: _tilted ? Icons.layers_rounded : Icons.layers_outlined,
                      tooltip: _tilted ? 'Vue à plat' : 'Vue conduite 3D',
                      active: _tilted,
                      size: _button,
                      onPressed: () => setState(() => _tilted = !_tilted),
                    ),
                    const SizedBox(height: _gap),
                    SquareIconButton(
                      icon: Icons.navigation_rounded,
                      tooltip: 'Recentrer sur ma position',
                      active: _following,
                      size: _button,
                      onPressed: fix == null ? null : () => setState(() => _following = true),
                    ),
                    const SizedBox(height: _gap),
                    SquareIconButton(
                      icon: Icons.warning_rounded,
                      tooltip: 'Historique des alertes',
                      alert: true,
                      size: _button,
                      onPressed: () => context.push(Routes.history),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Positioned(
            top: pad.top + _side + 3 * _button + 3 * _gap + 6,
            right: _side,
            child: const TrafficLegend(available: false),
          ),

          if (position.hasError)
            Positioned(
              top: topH + 4,
              left: _side,
              right: _side + _button + _gap,
              child: _LocationProblem(error: position.error!),
            ),

          // --- Bas : compteur, caméra, OCR, alerte -------------------------------
          Positioned(
            left: _side,
            right: _side,
            bottom: pad.bottom + _side,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: speedRowH,
                  child: Row(
                    children: [
                      SpeedGauge(
                        speedKmh: fix?.speedKmh,
                        overLimit: speedLimit != null && (fix?.speedKmh ?? 0) > speedLimit + 3,
                      ),
                      if (speedLimit != null) ...[
                        const SizedBox(width: 10),
                        SpeedLimitSign(limitKmh: speedLimit),
                      ],
                      const Spacer(),
                      Semantics(
                        button: true,
                        label: 'Ouvrir le menu SENTRIX',
                        child: GestureDetector(
                          onTap: _openMenu,
                          child: const SentrixHead(size: 78, state: SentrixState.idle),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: _gap),
                SizedBox(
                  height: cameraH,
                  child: CameraPanel(
                    active: scanning,
                    inactiveDetail: 'Module caméra en cours de développement (phase 4)',
                  ),
                ),
                const SizedBox(height: _gap),
                SizedBox(height: ocrH, child: OcrPanel(reading: reading)),
                if (alert != null) ...[
                  const SizedBox(height: _gap),
                  SizedBox(
                    height: alertH,
                    child: AlertBanner(
                      alert: alert,
                      onDismiss: ref.read(activeAlertProvider.notifier).dismiss,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManeuverCard(Destination? destination, NavState nav) {
    void openSearch() => context.push(Routes.search);
    final stop = ref.read(destinationProvider.notifier).clear;
    if (destination == null) return ManeuverCard.prompt(onTap: openSearch);

    final step = nav.nextStep;
    switch (nav.status) {
      case NavStatus.guiding || NavStatus.rerouting when step != null:
        return ManeuverCard(
          icon: maneuverIcon(step),
          headline: formatDistance(nav.progress!.toNextManeuverM),
          title: Instructions.headline(step),
          subtitle: Instructions.towards(step) ?? destination.label,
          onClose: stop,
        );
      case NavStatus.arrived:
        return ManeuverCard(
          icon: Icons.flag_rounded,
          headline: 'Arrivé',
          title: destination.label,
          subtitle: destination.detail,
          onClose: stop,
        );
      case NavStatus.failed:
        return ManeuverCard(
          icon: Icons.wifi_off_rounded,
          headline: 'Itinéraire indisponible',
          title: nav.message ?? 'Erreur inconnue',
          subtitle: 'Touchez pour réessayer',
          onTap: ref.read(navigationSessionProvider.notifier).retry,
          onClose: stop,
        );
      case NavStatus.waitingForGps:
        return ManeuverCard(
          icon: Icons.gps_not_fixed_rounded,
          headline: 'En attente du GPS',
          title: destination.label,
          subtitle: 'Le guidage démarrera dès la première position',
          onClose: stop,
        );
      default:
        return ManeuverCard(
          icon: Icons.route_rounded,
          headline: 'Calcul…',
          title: destination.label,
          subtitle: destination.detail,
          onClose: stop,
        );
    }
  }
}

class _Scrims extends StatelessWidget {
  const _Scrims();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Column(
        children: [
          Container(
            height: MediaQuery.paddingOf(context).top + 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [VrColors.background.withValues(alpha: 0.85), VrColors.background.withValues(alpha: 0)],
              ),
            ),
          ),
          const Spacer(),
          Container(
            height: MediaQuery.sizeOf(context).height * 0.5,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [VrColors.background.withValues(alpha: 0), VrColors.background.withValues(alpha: 0.9)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationProblem extends ConsumerWidget {
  const _LocationProblem({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = error is LocationUnavailable ? error.toString() : 'Position GPS indisponible.';
    return GestureDetector(
      onTap: () => ref.read(permissionsProvider.notifier).openSettings(),
      child: GlowPanel(
        tone: PanelTone.alert,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.location_off_rounded, color: VrColors.alert),
            const SizedBox(width: 10),
            Expanded(child: Text('$message Touchez pour ouvrir les réglages.', style: VrText.caption.copyWith(color: VrColors.textPrimary))),
          ],
        ),
      ),
    );
  }
}

/// Menu ouvert depuis SENTRIX : accès aux écrans de gestion.
class _SentrixMenu extends StatelessWidget {
  const _SentrixMenu();

  @override
  Widget build(BuildContext context) {
    void go(String route) {
      Navigator.of(context).pop();
      context.push(route);
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: GlowPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  SentrixHead(size: 64, state: SentrixState.speaking),
                  SizedBox(width: 12),
                  Expanded(child: Text('Que voulez-vous faire ?', style: VrText.label)),
                ],
              ),
              const SizedBox(height: 14),
              VrButton(label: 'Chercher une destination', icon: Icons.search_rounded, expanded: true, onPressed: () => go(Routes.search)),
              const SizedBox(height: 8),
              VrButton(label: 'Plaques à surveiller', icon: Icons.storage_rounded, expanded: true, onPressed: () => go(Routes.plates)),
              const SizedBox(height: 8),
              VrButton(label: 'Historique des détections', icon: Icons.history_rounded, expanded: true, onPressed: () => go(Routes.history)),
              const SizedBox(height: 8),
              VrButton(label: 'Réglages', icon: Icons.settings_rounded, expanded: true, onPressed: () => go(Routes.settings)),
            ],
          ),
        ),
      ),
    );
  }
}
