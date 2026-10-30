import 'dart:convert';

import 'watch_entry.dart';

/// Problème rencontré sur une ligne/entrée du fichier importé.
class ImportIssue {
  const ImportIssue(this.line, this.reason);

  /// Numéro de ligne (CSV, à partir de 1) ou index d'entrée (JSON, à partir de 1).
  final int line;
  final String reason;

  @override
  String toString() => 'Ligne $line : $reason';
}

/// Résultat de l'analyse d'un fichier de plaques.
class ImportReport {
  const ImportReport({required this.entries, required this.duplicates, required this.issues});

  final List<WatchEntry> entries;

  /// Plaques présentes plusieurs fois dans le fichier (seule la 1re est gardée).
  final int duplicates;
  final List<ImportIssue> issues;

  bool get isEmpty => entries.isEmpty;
}

class ImportFormatException implements Exception {
  const ImportFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

const _plateKeys = {'plate', 'plaque', 'immatriculation', 'registration', 'numero', 'numéro'};
const _countryKeys = {'country', 'pays'};
const _categoryKeys = {'category', 'categorie', 'catégorie', 'type'};
const _priorityKeys = {'priority', 'priorite', 'priorité'};
const _noteKeys = {'note', 'notes', 'commentaire', 'comment'};

/// Analyse un fichier CSV ou JSON (détection par extension, puis contenu).
ImportReport parseWatchlist(String content, {String? fileName}) {
  final text = content.startsWith('﻿') ? content.substring(1) : content;
  final ext = fileName?.split('.').last.toLowerCase();
  final trimmed = text.trimLeft();
  if (ext == 'json' || (ext != 'csv' && (trimmed.startsWith('[') || trimmed.startsWith('{')))) {
    return parseWatchlistJson(text);
  }
  return parseWatchlistCsv(text);
}

class _Builder {
  final entries = <WatchEntry>[];
  final seen = <String>{};
  final issues = <ImportIssue>[];
  var duplicates = 0;

  void add(int line, {required String plate, String country = '', String category = '', String priority = '', String note = ''}) {
    final c = country.trim().isEmpty ? 'FR' : country.trim().toUpperCase();
    final v = validatePlate(plate, country: c);
    if (v.error != null) {
      issues.add(ImportIssue(line, '${v.error} (« ${plate.trim()} »)'));
      return;
    }
    final p = parsePriority(priority);
    if (p == null) {
      issues.add(ImportIssue(line, 'Priorité inconnue « $priority » (attendu low, medium ou high)'));
      return;
    }
    if (!seen.add(v.plate!)) {
      duplicates++;
      return;
    }
    entries.add(WatchEntry(
      plate: v.plate!,
      country: c,
      category: category.trim().isEmpty ? 'Surveillance' : category.trim(),
      priority: p,
      note: note.trim(),
      source: EntrySource.import,
    ));
  }

  ImportReport build() => ImportReport(entries: entries, duplicates: duplicates, issues: issues);
}

/// Découpe CSV conforme RFC 4180 (guillemets, guillemets doublés, retours
/// à la ligne dans un champ).
List<List<String>> splitCsv(String text, String delimiter) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == delimiter) {
      row.add(field.toString());
      field.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(field.toString());
      field.clear();
      rows.add(row);
      row = <String>[];
    } else {
      field.write(ch);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows;
}

ImportReport parseWatchlistCsv(String text) {
  final firstLine = text.split(RegExp(r'\r?\n')).firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
  if (firstLine.isEmpty) throw const ImportFormatException('Le fichier est vide.');
  final delimiter = [';', '\t', ','].reduce(
    (best, d) => d.allMatches(firstLine).length > best.allMatches(firstLine).length ? d : best,
  );
  final rows = splitCsv(text, delimiter);

  final header = rows.first.map((h) => h.trim().toLowerCase()).toList();
  int col(Set<String> keys) => header.indexWhere(keys.contains);
  var plateCol = col(_plateKeys);
  final hasHeader = plateCol >= 0;
  // Sans en-tête : ordre du modèle (plate, country, category, priority, note).
  if (!hasHeader) plateCol = 0;
  final countryCol = hasHeader ? col(_countryKeys) : 1;
  final categoryCol = hasHeader ? col(_categoryKeys) : 2;
  final priorityCol = hasHeader ? col(_priorityKeys) : 3;
  final noteCol = hasHeader ? col(_noteKeys) : 4;

  final b = _Builder();
  for (var i = hasHeader ? 1 : 0; i < rows.length; i++) {
    final r = rows[i];
    if (r.every((c) => c.trim().isEmpty)) continue;
    String at(int c) => c >= 0 && c < r.length ? r[c] : '';
    b.add(
      i + 1,
      plate: at(plateCol),
      country: at(countryCol),
      category: at(categoryCol),
      priority: at(priorityCol),
      note: at(noteCol),
    );
  }
  return b.build();
}

ImportReport parseWatchlistJson(String text) {
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException catch (e) {
    throw ImportFormatException('JSON invalide : ${e.message}');
  }
  final list = switch (json) {
    final List<dynamic> l => l,
    {'plates': final List<dynamic> l} => l,
    {'entries': final List<dynamic> l} => l,
    _ => throw const ImportFormatException('JSON attendu : une liste de plaques, ou un objet { "plates": [...] }.'),
  };
  final b = _Builder();
  for (var i = 0; i < list.length; i++) {
    final item = list[i];
    if (item is String) {
      b.add(i + 1, plate: item);
      continue;
    }
    if (item is! Map<String, dynamic>) {
      b.issues.add(ImportIssue(i + 1, 'Entrée ni texte ni objet'));
      continue;
    }
    String pick(Set<String> keys) {
      for (final e in item.entries) {
        if (keys.contains(e.key.toLowerCase())) return '${e.value ?? ''}';
      }
      return '';
    }

    b.add(
      i + 1,
      plate: pick(_plateKeys),
      country: pick(_countryKeys),
      category: pick(_categoryKeys),
      priority: pick(_priorityKeys),
      note: pick(_noteKeys),
    );
  }
  return b.build();
}

/// Export CSV (même format que l'import).
String exportWatchlistCsv(Iterable<WatchEntry> entries) {
  String q(String s) => s.contains(RegExp('[,"\n\r]')) ? '"${s.replaceAll('"', '""')}"' : s;
  final b = StringBuffer('plate,country,category,priority,note\n');
  for (final e in entries) {
    b.writeln([e.plate, e.country, q(e.category), e.priority.name, q(e.note)].join(','));
  }
  return b.toString();
}
