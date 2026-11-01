import 'package:flutter/material.dart';

import '../theme.dart';
import 'panel.dart';

class VrColumn {
  const VrColumn(this.label, {this.flex = 1, this.numeric = false, this.sortKey});
  final String label;
  final int flex;
  final bool numeric;

  /// Clé de tri transmise à [VrTable.onSort] (null = non triable).
  final String? sortKey;
}

/// Tableau de données sombre : en-têtes triables, lignes cliquables, survol.
class VrTable extends StatefulWidget {
  const VrTable({
    super.key,
    required this.columns,
    required this.rows,
    this.onTap,
    this.empty = 'Aucun élément',
    this.sortKey,
    this.onSort,
    this.maxHeight,
  });

  final List<VrColumn> columns;
  final List<List<Widget>> rows;
  final void Function(int index)? onTap;
  final String empty;
  final String? sortKey;
  final void Function(String key)? onSort;

  /// Hauteur maximale avant défilement (null = toutes les lignes).
  final double? maxHeight;

  @override
  State<VrTable> createState() => _VrTableState();
}

class _VrTableState extends State<VrTable> {
  int? _hover;

  @override
  Widget build(BuildContext context) {
    Widget cell(VrColumn c, Widget child) => Expanded(
      flex: c.flex,
      child: Align(alignment: c.numeric ? Alignment.centerRight : Alignment.centerLeft, child: child),
    );
    final header = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: VrColors.line))),
      child: Row(
        children: [
          for (final c in widget.columns)
            cell(
              c,
              InkWell(
                onTap: c.sortKey == null || widget.onSort == null ? null : () => widget.onSort!(c.sortKey!),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        c.label.toUpperCase(),
                        style: VrText.caption.copyWith(
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w600,
                          color: c.sortKey != null && c.sortKey == widget.sortKey ? VrColors.cyan : VrColors.textMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (c.sortKey != null && c.sortKey == widget.sortKey)
                      const Icon(Icons.arrow_downward_rounded, size: 13, color: VrColors.cyan),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (widget.rows.isEmpty) {
      return Column(mainAxisSize: MainAxisSize.min, children: [header, EmptyState(widget.empty)]);
    }
    final rows = [
      for (var i = 0; i < widget.rows.length; i++)
        MouseRegion(
          onEnter: (_) => setState(() => _hover = i),
          onExit: (_) => setState(() => _hover = null),
          cursor: widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap == null ? null : () => widget.onTap!(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _hover == i ? VrColors.cyan.withValues(alpha: 0.06) : (i.isOdd ? VrColors.backgroundRaised.withValues(alpha: 0.4) : null),
                border: const Border(bottom: BorderSide(color: VrColors.line, width: 0.6)),
              ),
              child: DefaultTextStyle(
                style: VrText.body,
                overflow: TextOverflow.ellipsis,
                child: Row(
                  children: [
                    for (var c = 0; c < widget.columns.length; c++)
                      cell(widget.columns[c], c < widget.rows[i].length ? widget.rows[i][c] : const SizedBox()),
                  ],
                ),
              ),
            ),
          ),
        ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        if (widget.maxHeight == null)
          ...rows
        else
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: widget.maxHeight!),
            child: ListView(shrinkWrap: true, children: rows),
          ),
      ],
    );
  }
}

/// Texte de cellule (une ligne, coupé si trop long, info-bulle complète).
class CellText extends StatelessWidget {
  const CellText(this.text, {super.key, this.muted = false, this.color, this.mono = false});
  final String text;
  final bool muted;
  final Color? color;
  final bool mono;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: text.length > 28 ? text : '',
    waitDuration: const Duration(milliseconds: 600),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: (mono ? VrText.mono : VrText.body).copyWith(color: color ?? (muted ? VrColors.textMuted : null)),
    ),
  );
}

/// Pagination simple (précédent / suivant).
class Pager extends StatelessWidget {
  const Pager({super.key, required this.offset, required this.limit, required this.total, required this.onChanged});
  final int offset;
  final int limit;
  final int total;
  final void Function(int offset) onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          total == 0 ? '0 résultat' : '${offset + 1}–${(offset + limit).clamp(0, total)} sur $total',
          style: VrText.caption,
        ),
        const SizedBox(width: 10),
        IconButton(
          tooltip: 'Page précédente',
          onPressed: offset > 0 ? () => onChanged((offset - limit).clamp(0, total)) : null,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        IconButton(
          tooltip: 'Page suivante',
          onPressed: offset + limit < total ? () => onChanged(offset + limit) : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    ),
  );
}
