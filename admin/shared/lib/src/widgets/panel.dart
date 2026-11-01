import 'package:flutter/material.dart';

import '../theme.dart';

/// Panneau sombre à bordure lumineuse (identité VIGIROAD).
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.title, this.trailing, this.glow = false});

  final Widget child;
  final EdgeInsets padding;
  final String? title;
  final Widget? trailing;
  final bool glow;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [VrColors.panelLight, VrColors.panel],
      ),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: VrColors.border(glow ? 0.55 : 0.18)),
      boxShadow: [if (glow) BoxShadow(color: VrColors.cyan.withValues(alpha: 0.18), blurRadius: 22)],
    ),
    padding: padding,
    child: title == null
        ? child
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(width: 3, height: 16, color: VrColors.cyan, margin: const EdgeInsets.only(right: 10)),
                  Expanded(child: Text(title!.toUpperCase(), style: VrText.section)),
                  ?trailing,
                ],
              ),
              const SizedBox(height: 14),
              child,
            ],
          ),
  );
}

enum Health { ok, warning, critical, unknown }

Color healthColor(Health h) => switch (h) {
  Health.ok => VrColors.ok,
  Health.warning => VrColors.warning,
  Health.critical => VrColors.critical,
  Health.unknown => VrColors.textMuted,
};

/// Pastille lumineuse d'état.
class StatusDot extends StatelessWidget {
  const StatusDot(this.health, {super.key, this.size = 9});
  final Health health;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = healthColor(health);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: c.withValues(alpha: 0.7), blurRadius: 8)],
      ),
    );
  }
}

/// Étiquette d'état (« En ligne », « Désactivé »…).
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, this.health, {super.key});
  final String label;
  final Health health;

  @override
  Widget build(BuildContext context) {
    final c = healthColor(health);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusDot(health, size: 6),
          const SizedBox(width: 6),
          Text(label, style: VrText.caption.copyWith(color: c, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Indicateur chiffré du tableau de bord.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.sub,
    this.color = VrColors.cyan,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? sub;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
    child: GestureDetector(
      onTap: onTap,
      child: Panel(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label.toUpperCase(), style: VrText.caption.copyWith(letterSpacing: 0.8), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value, style: VrText.metric.copyWith(fontSize: 28)),
                  ),
                  if (sub != null) Text(sub!, style: VrText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Ligne « libellé : valeur » des fiches détaillées.
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.mono = false, this.trailing});
  final String label;
  final String value;
  final bool mono;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 190, child: Text(label, style: VrText.label)),
        Expanded(child: SelectableText(value, style: mono ? VrText.mono : VrText.body)),
        ?trailing,
      ],
    ),
  );
}

/// Grille responsive de cartes de largeur minimale [minWidth].
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({super.key, required this.children, this.minWidth = 230, this.spacing = 14});
  final List<Widget> children;
  final double minWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final cols = ((c.maxWidth + spacing) / (minWidth + spacing)).floor().clamp(1, children.isEmpty ? 1 : children.length);
      final w = (c.maxWidth - spacing * (cols - 1)) / cols;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [for (final ch in children) SizedBox(width: w, child: ch)],
      );
    },
  );
}

/// Message centré (liste vide, fonction indisponible).
class EmptyState extends StatelessWidget {
  const EmptyState(this.message, {super.key, this.icon = Icons.inbox_outlined});
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(28),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: VrColors.textMuted, size: 34),
        const SizedBox(height: 10),
        Text(message, style: VrText.caption, textAlign: TextAlign.center),
      ],
    ),
  );
}

/// Bouton principal VIGIROAD.
class VrButton extends StatelessWidget {
  const VrButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.danger = false,
    this.primary = true,
    this.busy = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool danger;
  final bool primary;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final color = danger ? VrColors.critical : VrColors.cyan;
    final enabled = onPressed != null && !busy;
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (busy)
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
        else if (icon != null)
          Icon(icon, size: 18),
        if (busy || icon != null) const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
    const pad = EdgeInsets.symmetric(horizontal: 16, vertical: 14);
    if (primary) {
      return FilledButton(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: danger ? VrColors.critical : VrColors.cyan,
          foregroundColor: danger ? Colors.white : VrColors.background,
          disabledBackgroundColor: VrColors.line,
          shape: shape,
          padding: pad,
        ),
        child: child,
      );
    }
    return OutlinedButton(
      onPressed: enabled ? onPressed : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: enabled ? color.withValues(alpha: 0.6) : VrColors.line),
        shape: shape,
        padding: pad,
      ),
      child: child,
    );
  }
}
