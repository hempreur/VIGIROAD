import 'package:flutter/material.dart';

/// Icône du bouton de signalement (pilon blanc, cercle néon bleu), fournie
/// par le propriétaire de VIGIROAD.
const chickenButtonAsset = 'assets/icons/chicken_button.png';

/// Icône seule (fenêtre de signalement, aide…).
class ChickenIcon extends StatelessWidget {
  const ChickenIcon({super.key, this.size = 46});

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    chickenButtonAsset,
    width: size,
    height: size,
    filterQuality: FilterQuality.medium,
    excludeFromSemantics: true,
  );
}

/// Bouton rond « Chicken » : ouvre le choix du sens du signalement.
class ChickenButton extends StatefulWidget {
  const ChickenButton({super.key, required this.onPressed, this.size = 64});

  final VoidCallback? onPressed;
  final double size;

  @override
  State<ChickenButton> createState() => _ChickenButtonState();
}

class _ChickenButtonState extends State<ChickenButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Signaler un Chicken',
    excludeSemantics: true,
    child: GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _down ? 0.92 : 1,
        duration: const Duration(milliseconds: 90),
        child: ChickenIcon(size: widget.size),
      ),
    ),
  );
}
