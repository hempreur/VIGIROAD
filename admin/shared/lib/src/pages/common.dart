import 'package:flutter/material.dart';

import '../theme.dart';

/// Contenu de page défilant, marges homogènes.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scrollbar(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    ),
  );
}

/// Sélecteur de période (24 h / 7 j / 30 j…).
class PeriodPicker extends StatelessWidget {
  const PeriodPicker({super.key, required this.value, required this.options, required this.onChanged});
  final String value;
  final Map<String, String> options;
  final void Function(String) onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<String>(
    segments: [for (final e in options.entries) ButtonSegment(value: e.key, label: Text(e.value))],
    selected: {value},
    showSelectedIcon: false,
    onSelectionChanged: (s) => onChanged(s.first),
    style: ButtonStyle(
      visualDensity: VisualDensity.compact,
      textStyle: WidgetStatePropertyAll(VrText.caption.copyWith(fontWeight: FontWeight.w600)),
      backgroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? VrColors.cyan.withValues(alpha: 0.18) : VrColors.backgroundRaised,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? VrColors.cyan : VrColors.textSecondary,
      ),
      side: const WidgetStatePropertyAll(BorderSide(color: VrColors.line)),
    ),
  );
}

/// Champ de recherche instantanée (déclenchée après une courte pause).
class SearchField extends StatefulWidget {
  const SearchField({super.key, required this.onChanged, this.hint = 'Rechercher…', this.width = 320});
  final void Function(String) onChanged;
  final String hint;
  final double width;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  final _c = TextEditingController();
  int _gen = 0;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.width,
    child: TextField(
      key: const Key('search'),
      controller: _c,
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: _c.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  _c.clear();
                  setState(() {});
                  widget.onChanged('');
                },
              ),
      ),
      onChanged: (v) {
        final g = ++_gen;
        setState(() {});
        Future<void>.delayed(const Duration(milliseconds: 280), () {
          if (g == _gen && mounted) widget.onChanged(v.trim());
        });
      },
    ),
  );
}

List<Map<String, dynamic>> listOf(Object? v) => ((v as List<dynamic>?) ?? const []).cast<Map<String, dynamic>>();

double? dbl(Object? v) => (v as num?)?.toDouble();
