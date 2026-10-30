import 'package:flutter_test/flutter_test.dart';
import 'package:vigiroad/features/plates/domain/plate_format.dart';
import 'package:vigiroad/features/plates/domain/plate_models.dart';
import 'package:vigiroad/features/plates/domain/plate_voter.dart';

PlateObservation obs(String plate, DateTime at, {double conf = 0.9, int corr = 0}) => PlateObservation(
  candidate: PlateCandidate(
    normalized: plate,
    display: const FrenchSivFormat().display(plate),
    formatId: 'FR-SIV',
    country: 'FR',
    corrections: corr,
  ),
  at: at,
  ocrConfidence: conf,
);

void main() {
  final t0 = DateTime(2026, 10, 30, 15);
  DateTime t(int ms) => t0.add(Duration(milliseconds: ms));

  test('une lecture isolée ne suffit jamais', () {
    final v = PlateVoter();
    expect(v.add([obs('AA123BB', t(0), conf: 1)], t(0)), isEmpty);
    expect(v.add([obs('AA123BB', t(250), conf: 1)], t(250)), isEmpty);
  });

  test('confirmée après 3 lectures concordantes', () {
    final v = PlateVoter();
    v.add([obs('AA123BB', t(0))], t(0));
    v.add([obs('AA123BB', t(250))], t(250));
    final r = v.add([obs('AA123BB', t(500))], t(500));
    expect(r.single.normalized, 'AA123BB');
    expect(r.single.display, 'AA-123-BB');
    expect(r.single.confidence, inInclusiveRange(0.7, 0.99));
  });

  test('variante concurrente majoritaire : pas de confirmation', () {
    final v = PlateVoter();
    var r = <PlateReading>[];
    for (var i = 0; i < 3; i++) {
      v.add([obs('AA123BB', t(i * 200))], t(i * 200));
      r = v.add([obs('AA123B8', t(i * 200 + 100)), obs('AA123B8', t(i * 200 + 100))], t(i * 200 + 100));
    }
    expect(r.where((e) => e.normalized == 'AA123BB'), isEmpty);
  });

  test('lectures trop espacées : fenêtre glissante', () {
    final v = PlateVoter();
    v.add([obs('AA123BB', t(0))], t(0));
    v.add([obs('AA123BB', t(1500))], t(1500));
    expect(v.add([obs('AA123BB', t(3200))], t(3200)), isEmpty);
  });

  test('confiance trop faible (lectures très corrigées) : rejet', () {
    final v = PlateVoter();
    for (var i = 0; i < 3; i++) {
      expect(v.add([obs('AA123BB', t(i * 200), conf: 0.6, corr: 2)], t(i * 200)), isEmpty);
    }
  });

  test('pas de réémission avant le délai', () {
    final v = PlateVoter();
    for (var i = 0; i < 3; i++) {
      v.add([obs('AA123BB', t(i * 200))], t(i * 200));
    }
    expect(v.add([obs('AA123BB', t(800))], t(800)), isEmpty);
    final again = [
      for (var i = 0; i < 3; i++) ...v.add([obs('AA123BB', t(11000 + i * 200))], t(11000 + i * 200)),
    ];
    expect(again, hasLength(1), reason: 'nouvelle confirmation après 10 s');
  });

  test('plusieurs véhicules à la fois', () {
    final v = PlateVoter();
    final out = <String>{};
    for (var i = 0; i < 4; i++) {
      out.addAll(v.add([obs('AA123BB', t(i * 200)), obs('CC456DD', t(i * 200))], t(i * 200)).map((e) => e.normalized));
    }
    expect(out, {'AA123BB', 'CC456DD'});
  });
}
