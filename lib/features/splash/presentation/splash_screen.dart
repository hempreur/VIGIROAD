import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/theme/vr_colors.dart';
import '../../../core/theme/vr_typography.dart';
import '../../../core/widgets/brand_wordmark.dart';
import '../../../core/widgets/vr_backdrop.dart';
import '../../sentrix/domain/sentrix_state.dart';
import '../../sentrix/presentation/sentrix_head.dart';

/// Écran de démarrage : identité VIGIROAD pendant le chargement des états
/// d'autorisation, puis redirection vers l'accueil ou l'écran d'autorisations.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key, this.minimumDuration = const Duration(milliseconds: 1800)});

  /// Durée minimale d'affichage, pour que l'animation reste lisible.
  final Duration minimumDuration;

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..forward();

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  Future<void> _boot() async {
    final results = await Future.wait([
      ref.read(permissionsProvider.future),
      Future<void>.delayed(widget.minimumDuration),
    ]);
    if (!mounted) return;
    final statuses = results.first as Map<AppCapability, CapabilityStatus>;
    final ready = statuses.values.every((s) => s == CapabilityStatus.granted);
    context.go(ready ? Routes.home : Routes.permissions);
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic);
    return Scaffold(
      body: VrBackdrop(
        child: Center(
          child: FadeTransition(
            opacity: fade,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(fade),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SentrixHead(size: 150, state: SentrixState.idle),
                  const SizedBox(height: 28),
                  const BrandWordmark(size: 44),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'NAVIGATION  •  LECTURE DE PLAQUES  •  ASSISTANT VOCAL',
                        maxLines: 1,
                        style: VrText.caption.copyWith(letterSpacing: 1.2, fontSize: 11),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  const _GlowProgress(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Barre de chargement indéterminée, fine et lumineuse.
class _GlowProgress extends StatefulWidget {
  const _GlowProgress();

  @override
  State<_GlowProgress> createState() => _GlowProgressState();
}

class _GlowProgressState extends State<_GlowProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const width = 160.0;
    return Semantics(
      label: 'Chargement',
      child: SizedBox(
        width: width,
        height: 3,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Stack(
              children: [
                Container(color: VrColors.cyan.withValues(alpha: 0.12)),
                Positioned(
                  left: -60 + (width + 60) * _c.value,
                  width: 60,
                  top: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          VrColors.cyan.withValues(alpha: 0),
                          VrColors.cyanBright,
                          VrColors.cyan.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
