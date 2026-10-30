import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:vigiroad/features/plates/domain/plate_format.dart';
import 'package:vigiroad/features/plates/domain/plate_voter.dart';

/// Banc de mesure de la chaîne post-OCR (extraction → correction → vote).
///
/// Jeu SYNTHÉTIQUE et reproductible (graine fixe) : pour chaque véhicule,
/// une série d'images dont la lecture OCR simulée subit les erreurs typiques
/// (image ratée, confusions visuelles, caractère faux, bruit autour, textes
/// parasites). Mesure la précision (plaques confirmées justes) et le rappel.
///
/// Ce banc NE mesure PAS la qualité de l'OCR ML Kit sur de vraies photos :
/// voir docs/OCR.md pour le protocole de mesure sur appareil.
const _letters = 'ABCDEFGHJKLMNPQRSTVWXYZ';
const _digits = '0123456789';

/// Confusions donnant un AUTRE caractère valide (non corrigeables).
const _harmfulSwaps = {
  'H': 'M', 'M': 'H', 'E': 'F', 'F': 'E', 'C': 'G', 'P': 'R', 'R': 'P',
  'K': 'X', 'V': 'Y', 'N': 'M', '3': '8', '8': '3', '1': '7', '6': '5', '9': '0',
};

/// Confusions lettre↔chiffre (corrigeables par position).
const _benignSwaps = {'B': '8', 'D': '0', 'S': '5', 'Z': '2', 'G': '6', 'T': '7', 'A': '4', '0': 'D', '1': 'I', '8': 'B', '5': 'S'};

const _distractors = ['SORTIE 12', 'PARKING', 'A6 LYON', 'STOP', 'ZONE 30', 'RN7', 'TAXI', 'BUS', 'P+R 450'];

String randomPlate(Random r) {
  String l() => _letters[r.nextInt(_letters.length)];
  String d() => _digits[r.nextInt(10)];
  while (true) {
    final p = '${l()}${l()}${d()}${d()}${d()}${l()}${l()}';
    if (const FrenchSivFormat().isValid(p)) return p;
  }
}

class _Scenario {
  _Scenario(this.name, {required this.miss, required this.benign, required this.harmful, required this.frames});
  final String name;
  final double miss, benign, harmful;
  final int frames;
}

/// Lecture OCR simulée d'une plaque sur une image.
String? simulateRead(String plate, Random r, _Scenario s) {
  if (r.nextDouble() < s.miss) return null;
  final chars = plate.split('');
  for (var i = 0; i < chars.length; i++) {
    final x = r.nextDouble();
    if (x < s.harmful && _harmfulSwaps.containsKey(chars[i])) {
      chars[i] = _harmfulSwaps[chars[i]]!;
    } else if (x < s.harmful + s.benign && _benignSwaps.containsKey(chars[i])) {
      chars[i] = _benignSwaps[chars[i]]!;
    }
  }
  final p = chars.join();
  final text = '${p.substring(0, 2)}-${p.substring(2, 5)}-${p.substring(5)}';
  return switch (r.nextInt(4)) {
    0 => 'F $text',
    1 => text.replaceAll('-', ' '),
    2 => '$text 75',
    _ => text,
  };
}

void main() {
  final scenarios = [
    _Scenario('Conditions favorables', miss: 0.15, benign: 0.03, harmful: 0.01, frames: 8),
    _Scenario('Conditions moyennes', miss: 0.3, benign: 0.06, harmful: 0.03, frames: 8),
    _Scenario('Conditions difficiles', miss: 0.5, benign: 0.1, harmful: 0.06, frames: 10),
  ];
  const vehicles = 2000;
  final report = StringBuffer()
    ..writeln('# Banc de mesure post-OCR (synthétique)')
    ..writeln()
    ..writeln('$vehicles véhicules par scénario, images toutes les 250 ms, graine fixe 2026.')
    ..writeln('Taux par caractère : miss = image sans lecture, benign = confusion lettre/chiffre, harmful = autre caractère valide.')
    ..writeln()
    ..writeln('| Scénario | Images/véh. | miss | benign | harmful | Précision | Rappel | Fausses plaques | Temps moyen/image |')
    ..writeln('|---|---|---|---|---|---|---|---|---|');

  for (final s in scenarios) {
    test('banc : ${s.name}', () {
      final r = Random(2026);
      var tp = 0, fp = 0, miss = 0;
      final sw = Stopwatch();
      var analyzed = 0;
      for (var v = 0; v < vehicles; v++) {
        final plate = randomPlate(r);
        final voter = PlateVoter();
        final t0 = DateTime(2026, 1, 1, 0, 0, v);
        final confirmed = <String>{};
        for (var f = 0; f < s.frames; f++) {
          final now = t0.add(Duration(milliseconds: 250 * f));
          final lines = [
            ?simulateRead(plate, r, s),
            if (r.nextDouble() < 0.3) _distractors[r.nextInt(_distractors.length)],
          ];
          sw.start();
          final obs = [
            for (final line in lines)
              for (final c in PlateFormats.extract(line))
                PlateObservation(candidate: c, at: now, ocrConfidence: 0.75 + r.nextDouble() * 0.2),
          ];
          confirmed.addAll(voter.add(obs, now).map((e) => e.normalized));
          sw.stop();
          analyzed++;
        }
        if (confirmed.contains(plate)) tp++;
        fp += confirmed.where((p) => p != plate).length;
        if (!confirmed.contains(plate)) miss++;
      }
      final precision = tp + fp == 0 ? 1.0 : tp / (tp + fp);
      final recall = tp / vehicles;
      final avgUs = sw.elapsedMicroseconds / analyzed;
      report.writeln(
        '| ${s.name} | ${s.frames} | ${s.miss} | ${s.benign} | ${s.harmful} | '
        '${(precision * 100).toStringAsFixed(2)} % | ${(recall * 100).toStringAsFixed(1)} % | $fp | '
        '${avgUs.toStringAsFixed(0)} µs |',
      );
      // ignore: avoid_print
      print('${s.name}: précision ${(precision * 100).toStringAsFixed(2)} %, rappel ${(recall * 100).toStringAsFixed(1)} %, fausses plaques $fp, manquées $miss');

      // Exigence du cahier des charges : réduire les faux positifs.
      expect(precision, greaterThanOrEqualTo(0.99));
      if (s.name == 'Conditions favorables') expect(recall, greaterThanOrEqualTo(0.95));
    });
  }

  tearDownAll(() {
    Directory('test_reports').createSync(recursive: true);
    File('test_reports/alpr_pipeline_benchmark.md').writeAsStringSync(report.toString());
  });
}
