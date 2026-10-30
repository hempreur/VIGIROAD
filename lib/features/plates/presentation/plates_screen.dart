import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/vr_colors.dart';
import '../../../core/theme/vr_typography.dart';
import '../../../core/widgets/glow_panel.dart';
import '../../../core/widgets/plate_badge.dart';
import '../../../core/widgets/vr_button.dart';
import '../../../core/widgets/vr_page.dart';
import '../application/watchlist_controller.dart';
import '../data/repositories.dart';
import '../domain/plate_models.dart';
import '../domain/watch_entry.dart';
import '../domain/watchlist_import.dart';

/// Lecture d'un fichier choisi par l'utilisateur (remplaçable en test).
typedef PickedFile = ({String name, String content});
final watchlistFilePickerProvider = Provider<Future<PickedFile?> Function()>((ref) => () async {
  final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['csv', 'json', 'txt']);
  if (file == null) return null;
  final bytes = await file.xFile.readAsBytes();
  return (name: file.name, content: utf8.decode(bytes, allowMalformed: true));
});

/// Gestion de la liste de plaques à surveiller.
class PlatesScreen extends ConsumerStatefulWidget {
  const PlatesScreen({super.key});

  @override
  ConsumerState<PlatesScreen> createState() => _PlatesScreenState();
}

class _PlatesScreenState extends ConsumerState<PlatesScreen> {
  String _query = '';

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _edit([WatchEntry? existing]) async {
    final result = await showDialog<WatchEntry>(
      context: context,
      builder: (_) => _EntryDialog(existing: existing),
    );
    if (result == null) return;
    await ref.read(watchlistProvider.notifier).save(result, replacing: existing?.plate);
    _snack('Plaque ${result.display} enregistrée');
  }

  Future<void> _delete(WatchEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la plaque ?'),
        content: Text('${e.display} sera retirée de la liste de surveillance.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer', style: TextStyle(color: VrColors.alert)),
          ),
        ],
      ),
    );
    if (ok ?? false) await ref.read(watchlistProvider.notifier).remove(e.plate);
  }

  Future<void> _import() async {
    final PickedFile? file;
    try {
      file = await ref.read(watchlistFilePickerProvider)();
    } on Exception catch (e) {
      _snack('Lecture du fichier impossible : $e');
      return;
    }
    if (file == null || !mounted) return;
    final ImportReport report;
    try {
      report = parseWatchlist(file.content, fileName: file.name);
    } on ImportFormatException catch (e) {
      _snack(e.message);
      return;
    }
    if (!mounted) return;
    final mode = await showDialog<ImportMode>(
      context: context,
      builder: (_) => _ImportPreview(fileName: file!.name, report: report),
    );
    if (mode == null) return;
    final s = await ref.read(watchlistProvider.notifier).importReport(report, mode: mode);
    _snack('${s.added} ajoutée(s), ${s.updated} mise(s) à jour');
  }

  Future<void> _sync() async {
    try {
      final s = await ref.read(watchlistProvider.notifier).sync();
      _snack('Synchronisation : ${s.added} ajoutée(s), ${s.updated} mise(s) à jour'
          '${s.report.issues.isEmpty ? '' : ', ${s.report.issues.length} ligne(s) ignorée(s)'}');
    } on ImportFormatException catch (e) {
      _snack(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(watchlistProvider);
    final config = ref.watch(appConfigProvider);
    final q = normalize(_query);

    return VrPage(
      title: 'Plaques à surveiller',
      children: [
        Row(
          children: [
            Expanded(child: VrButton(label: 'Ajouter', icon: Icons.add_rounded, style: VrButtonStyle.primary, expanded: true, onPressed: _edit)),
            const SizedBox(width: 10),
            Expanded(child: VrButton(label: 'Importer', icon: Icons.upload_file_rounded, expanded: true, onPressed: _import)),
          ],
        ),
        if (config.platesSyncEnabled) ...[
          const SizedBox(height: 10),
          VrButton(label: 'Synchroniser la liste distante', icon: Icons.sync_rounded, expanded: true, onPressed: _sync),
        ],
        const SizedBox(height: 14),
        GlowPanel(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          radius: 14,
          glow: false,
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            style: VrText.label,
            decoration: const InputDecoration(
              border: InputBorder.none,
              icon: Icon(Icons.search_rounded, color: VrColors.cyan),
              hintText: 'Rechercher une plaque ou une catégorie',
              hintStyle: TextStyle(color: VrColors.textMuted),
            ),
          ),
        ),
        const SizedBox(height: 14),
        ...switch (list) {
          AsyncData(:final value) when value.isEmpty => [
            const EmptyStatePanel(
              icon: Icons.storage_rounded,
              title: 'Aucune plaque enregistrée',
              message: 'Ajoutez une plaque ou importez un fichier CSV/JSON. '
                  'La liste est stockée chiffrée sur le téléphone.',
            ),
            const SizedBox(height: 16),
            const _FormatHelp(),
          ],
          AsyncData(:final value) => [
            Text(
              '${value.length} plaque(s)',
              style: VrText.caption,
            ),
            const SizedBox(height: 8),
            for (final e in value.where((e) => q.isEmpty || e.plate.contains(q) || normalize(e.category).contains(q)))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _EntryTile(entry: e, onTap: () => _edit(e), onDelete: () => _delete(e)),
              ),
          ],
          AsyncError(:final error) => [
            GlowPanel(tone: PanelTone.alert, child: Text('Base de plaques indisponible : $error', style: VrText.label)),
          ],
          _ => [const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: VrColors.cyan)))],
        },
      ],
    );
  }

  static String normalize(String s) => s.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.onTap, required this.onDelete});

  final WatchEntry entry;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final color = switch (entry.priority) {
      WatchPriority.high => VrColors.alert,
      WatchPriority.medium => VrColors.trafficSlow,
      WatchPriority.low => VrColors.textSecondary,
    };
    return GestureDetector(
      onTap: onTap,
      child: GlowPanel(
        glow: false,
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          children: [
            PlateBadge(text: entry.display, countryLetter: euBandLetter(entry.country), height: 34),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.category, style: VrText.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    'Priorité ${priorityLabel(entry.priority).toLowerCase()}'
                    '${entry.note.isEmpty ? '' : ' · ${entry.note}'}',
                    style: VrText.caption.copyWith(color: color),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Supprimer ${entry.display}',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded, color: VrColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryDialog extends StatefulWidget {
  const _EntryDialog({this.existing});
  final WatchEntry? existing;

  @override
  State<_EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends State<_EntryDialog> {
  late final _plate = TextEditingController(text: widget.existing?.display ?? '');
  late final _category = TextEditingController(text: widget.existing?.category ?? 'Surveillance');
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  late final _country = TextEditingController(text: widget.existing?.country ?? 'FR');
  late WatchPriority _priority = widget.existing?.priority ?? WatchPriority.medium;
  String? _error;

  @override
  void dispose() {
    for (final c in [_plate, _category, _note, _country]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final country = _country.text.trim().isEmpty ? 'FR' : _country.text.trim().toUpperCase();
    final v = validatePlate(_plate.text, country: country);
    if (v.error != null) {
      setState(() => _error = v.error);
      return;
    }
    Navigator.pop(
      context,
      WatchEntry(
        plate: v.plate!,
        country: country,
        category: _category.text.trim().isEmpty ? 'Surveillance' : _category.text.trim(),
        priority: _priority,
        note: _note.text.trim(),
        source: widget.existing?.source ?? EntrySource.manual,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String label, {String? error}) => InputDecoration(labelText: label, errorText: error);
    return AlertDialog(
      title: Text(widget.existing == null ? 'Nouvelle plaque' : 'Modifier la plaque'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _plate,
              autofocus: widget.existing == null,
              textCapitalization: TextCapitalization.characters,
              decoration: deco('Plaque (ex. AA-123-BB)', error: _error),
            ),
            TextField(controller: _country, textCapitalization: TextCapitalization.characters, decoration: deco('Pays (code ISO, ex. FR)')),
            TextField(controller: _category, decoration: deco('Catégorie')),
            TextField(controller: _note, decoration: deco('Note (facultative)')),
            const SizedBox(height: 12),
            SegmentedButton<WatchPriority>(
              segments: [
                for (final p in WatchPriority.values) ButtonSegment(value: p, label: Text(priorityLabel(p))),
              ],
              selected: {_priority},
              onSelectionChanged: (s) => setState(() => _priority = s.first),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        TextButton(onPressed: _submit, child: const Text('Enregistrer')),
      ],
    );
  }
}

class _ImportPreview extends StatelessWidget {
  const _ImportPreview({required this.fileName, required this.report});
  final String fileName;
  final ImportReport report;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Importer la liste'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(fileName, style: VrText.caption),
            const SizedBox(height: 8),
            Text('${report.entries.length} plaque(s) valide(s)', style: VrText.label),
            if (report.duplicates > 0) Text('${report.duplicates} doublon(s) ignoré(s)', style: VrText.caption),
            if (report.issues.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('${report.issues.length} ligne(s) invalide(s) :', style: VrText.label.copyWith(color: VrColors.trafficSlow)),
              for (final i in report.issues.take(8)) Text('• $i', style: VrText.caption),
              if (report.issues.length > 8) Text('… et ${report.issues.length - 8} autre(s)', style: VrText.caption),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        if (report.entries.isNotEmpty) ...[
          TextButton(
            onPressed: () => Navigator.pop(context, ImportMode.replaceSource),
            child: const Text('Remplacer les imports'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ImportMode.merge),
            child: const Text('Ajouter'),
          ),
        ],
      ],
    );
  }
}

class _FormatHelp extends StatelessWidget {
  const _FormatHelp();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('FORMAT DU FICHIER CSV', style: VrText.sectionTitle),
        SizedBox(height: 10),
        GlowPanel(
          child: Text(
            'plate,country,category,priority\n'
            'AA123BB,FR,Surveillance,high\n'
            'CC456DD,FR,Surveillance,medium',
            style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: VrColors.textPrimary, height: 1.5),
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Séparateur virgule ou point-virgule. priority : low, medium ou high. Tirets et espaces '
          'des plaques ignorés. JSON accepté : [{"plate": "AA123BB", "category": "…"}]. Exemple fictif.',
          style: VrText.caption,
        ),
      ],
    );
  }
}
