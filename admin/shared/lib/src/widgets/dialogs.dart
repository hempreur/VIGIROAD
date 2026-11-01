import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/client.dart';
import '../theme.dart';
import 'panel.dart';

/// Notification en bas de fenêtre (succès, erreur, information).
void notify(BuildContext context, String message, {Health health = Health.ok}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: Duration(seconds: health == Health.critical ? 8 : 4),
        content: Row(
          children: [
            StatusDot(health),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: VrText.body)),
          ],
        ),
      ),
    );
}

/// Fenêtre de confirmation. Avec [typed], l'utilisateur doit saisir ce texte
/// (actions irréversibles).
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String action = 'Confirmer',
  bool danger = false,
  String? typed,
}) async {
  final ctrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, setState) {
        final allowed = typed == null || ctrl.text.trim().toLowerCase() == typed.toLowerCase();
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                danger ? Icons.warning_amber_rounded : Icons.help_outline_rounded,
                color: danger ? VrColors.critical : VrColors.cyan,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(title)),
            ],
          ),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message, style: VrText.body),
                if (typed != null) ...[
                  const SizedBox(height: 16),
                  Text('Saisissez « $typed » pour confirmer :', style: VrText.label),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('confirm-typed'),
                    controller: ctrl,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
            VrButton(label: action, danger: danger, onPressed: allowed ? () => Navigator.pop(d, true) : null),
          ],
        );
      },
    ),
  );
  ctrl.dispose();
  return ok ?? false;
}

/// Exécute une action de l'API avec notification du résultat.
Future<T?> runAction<T>(BuildContext context, Future<T> Function() action, {String? success}) async {
  try {
    final r = await action();
    if (context.mounted && success != null) notify(context, success);
    return r;
  } on ApiException catch (e) {
    if (context.mounted) notify(context, e.message, health: Health.critical);
    return null;
  }
}

/// Fenêtre de saisie de champs texte (modification d'informations).
Future<Map<String, String>?> editFields(
  BuildContext context, {
  required String title,
  required Map<String, String> fields,
  Map<String, String> initial = const {},
  Set<String> obscure = const {},
  String action = 'Enregistrer',
}) async {
  final ctrls = {for (final k in fields.keys) k: TextEditingController(text: initial[k] ?? '')};
  final r = await showDialog<Map<String, String>>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in fields.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  key: Key('field-${e.key}'),
                  controller: ctrls[e.key],
                  obscureText: obscure.contains(e.key),
                  decoration: InputDecoration(labelText: e.value),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
        VrButton(
          label: action,
          onPressed: () => Navigator.pop(d, {for (final e in ctrls.entries) e.key: e.value.text.trim()}),
        ),
      ],
    ),
  );
  for (final c in ctrls.values) {
    c.dispose();
  }
  return r;
}

/// Affiche une valeur sensible à transmettre (code à usage unique…).
Future<void> showSecret(BuildContext context, {required String title, required String value, required String help}) =>
    showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(help, style: VrText.body),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: VrColors.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: VrColors.border(0.6)),
                ),
                child: Center(
                  child: SelectableText(value, key: const Key('secret-value'), style: VrText.display.copyWith(fontSize: 28, letterSpacing: 4)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              unawaited(Clipboard.setData(ClipboardData(text: value)));
              notify(context, 'Copié dans le presse-papiers');
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copier'),
          ),
          VrButton(label: 'Fermer', onPressed: () => Navigator.pop(d)),
        ],
      ),
    );

/// Enregistre un fichier choisi par l'utilisateur (export CSV / JSON).
Future<void> saveExport(BuildContext context, {required String name, required String content, required String extension}) async {
  try {
    final location = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: [XTypeGroup(label: extension.toUpperCase(), extensions: [extension])],
    );
    if (location == null) return;
    await File(location.path).writeAsString(content);
    if (context.mounted) notify(context, 'Fichier enregistré : ${location.path}');
  } catch (e) {
    if (context.mounted) notify(context, 'Enregistrement impossible : $e', health: Health.critical);
  }
}
