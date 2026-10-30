import 'package:flutter_test/flutter_test.dart';
import 'package:vigiroad/features/plates/domain/plate_models.dart';
import 'package:vigiroad/features/plates/domain/watch_entry.dart';
import 'package:vigiroad/features/plates/domain/watchlist_import.dart';

void main() {
  group('CSV', () {
    test('exemple du cahier des charges', () {
      final r = parseWatchlist(
        'plate,country,category,priority\n'
        'AA123BB,FR,Surveillance,high\n'
        'CC456DD,FR,Surveillance,medium\n'
        'EE789FF,FR,Surveillance,high\n',
        fileName: 'liste.csv',
      );
      expect(r.issues, isEmpty);
      expect(r.entries.map((e) => e.plate), ['AA123BB', 'CC456DD', 'EE789FF']);
      expect(r.entries.first.priority, WatchPriority.high);
      expect(r.entries.first.display, 'AA-123-BB');
    });

    test('point-virgule, guillemets, BOM, en-têtes français, CRLF', () {
      final r = parseWatchlist(
        '﻿Plaque;Pays;Catégorie;Priorité;Note\r\n'
        '"AA-123-BB";FR;"Véhicule ; volé";haute;"dit ""rouge"""\r\n'
        'cc 456 dd;;;;\r\n',
      );
      expect(r.issues, isEmpty);
      expect(r.entries[0].category, 'Véhicule ; volé');
      expect(r.entries[0].note, 'dit "rouge"');
      expect(r.entries[0].priority, WatchPriority.high);
      expect(r.entries[1].plate, 'CC456DD');
      expect(r.entries[1].category, 'Surveillance');
      expect(r.entries[1].priority, WatchPriority.medium);
    });

    test('sans en-tête : ordre plate,country,category,priority', () {
      final r = parseWatchlistCsv('AA123BB,FR,Test,low\nEE789FF\n');
      expect(r.entries, hasLength(2));
      expect(r.entries[0].priority, WatchPriority.low);
    });

    test('lignes invalides et doublons signalés, valides conservées', () {
      final r = parseWatchlistCsv(
        'plate,priority\n'
        'AA123BB,high\n'
        'AA-123-BB,low\n'
        'XX12,high\n'
        'AI123BB,high\n'
        'CC456DD,urgent\n'
        '\n'
        'EE789FF,\n',
      );
      expect(r.entries.map((e) => e.plate), ['AA123BB', 'EE789FF']);
      expect(r.duplicates, 1);
      expect(r.issues.map((i) => i.line), [4, 5, 6]);
      expect(r.issues[2].reason, contains('Priorité inconnue'));
    });

    test('plaque étrangère acceptée hors format français', () {
      final r = parseWatchlistCsv('plate,country\nB-AB-1234,DE\n');
      expect(r.entries.single.plate, 'BAB1234');
      expect(r.entries.single.country, 'DE');
    });

    test('fichier vide', () {
      expect(() => parseWatchlistCsv('  \n'), throwsA(isA<ImportFormatException>()));
    });
  });

  group('JSON', () {
    test('liste d\'objets', () {
      final r = parseWatchlist('[{"plate":"AA-123-BB","category":"Surveillance","priority":"high"},{"Plaque":"CC456DD"}]');
      expect(r.entries.map((e) => e.plate), ['AA123BB', 'CC456DD']);
    });

    test('objet { plates: [...] } et chaînes simples', () {
      final r = parseWatchlist('{"plates":["AA123BB","EE789FF", 12]}', fileName: 'x.json');
      expect(r.entries, hasLength(2));
      expect(r.issues.single.line, 3);
    });

    test('JSON invalide', () {
      expect(() => parseWatchlist('{oops', fileName: 'x.json'), throwsA(isA<ImportFormatException>()));
      expect(() => parseWatchlist('{"a":1}'), throwsA(isA<ImportFormatException>()));
    });
  });

  test('export CSV relisible', () {
    const entries = [
      WatchEntry(plate: 'AA123BB', category: 'Vol, signalé', priority: WatchPriority.high, note: 'a "b"'),
      WatchEntry(plate: 'CC456DD'),
    ];
    final r = parseWatchlistCsv(exportWatchlistCsv(entries));
    expect(r.issues, isEmpty);
    expect(r.entries[0].category, 'Vol, signalé');
    expect(r.entries[0].note, 'a "b"');
    expect(r.entries[0].priority, WatchPriority.high);
  });

  test('validation de saisie', () {
    expect(validatePlate('aa-123-bb').plate, 'AA123BB');
    expect(validatePlate('').error, isNotNull);
    expect(validatePlate('AA-000-BB').error, isNotNull);
    expect(validatePlate('1234 AB 75').plate, '1234AB75');
  });
}
