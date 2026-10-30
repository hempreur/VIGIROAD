import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/vr_colors.dart';
import '../theme/vr_typography.dart';
import 'glow_panel.dart';
import 'vr_backdrop.dart';

/// Gabarit des écrans secondaires : fond nocturne, en-tête avec retour.
class VrPage extends StatelessWidget {
  const VrPage({super.key, required this.title, required this.children, this.actions = const []});

  final String title;
  final List<Widget> children;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: VrBackdrop(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Retour',
                      onPressed: () => context.canPop() ? context.pop() : null,
                      icon: const Icon(Icons.arrow_back_rounded, color: VrColors.textPrimary),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(title.toUpperCase(), style: VrText.sectionTitle.copyWith(fontSize: 22)),
                    ),
                    ...actions,
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: children,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bloc « état vide » honnête : explique pourquoi l'écran n'a pas de contenu.
class EmptyStatePanel extends StatelessWidget {
  const EmptyStatePanel({super.key, required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return GlowPanel(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Icon(icon, size: 40, color: VrColors.cyan),
          const SizedBox(height: 10),
          Text(title, style: VrText.label.copyWith(fontWeight: FontWeight.w600, fontSize: 16), textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(message, style: VrText.caption, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// Ligne libellé / valeur dans un panneau.
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.label, required this.value, this.trailing});

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: VrText.label),
                const SizedBox(height: 2),
                Text(value, style: VrText.caption),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
