import 'package:flutter_test/flutter_test.dart';
import 'package:vigiroad/features/navigation/domain/geo_fix.dart';
import 'package:vigiroad/features/navigation/domain/instructions.dart';
import 'package:vigiroad/features/navigation/domain/route.dart';

RouteStep step(
  ManeuverKind k, [
  ManeuverDirection d = ManeuverDirection.none,
  String name = '',
  String ref = '',
  String dest = '',
  String? exit,
  int? rbExit,
]) => RouteStep(
  kind: k,
  direction: d,
  location: const GeoPoint(0, 0),
  distanceM: 0,
  durationS: 0,
  roadName: name,
  roadRef: ref,
  destinations: dest,
  exitNumber: exit,
  roundaboutExit: rbExit,
);

void main() {
  test('consignes affichées', () {
    expect(Instructions.headline(step(ManeuverKind.turn, ManeuverDirection.right, 'Rue de Rivoli')),
        'Tournez à droite sur Rue de Rivoli');
    expect(Instructions.headline(step(ManeuverKind.offRamp, ManeuverDirection.slightRight, '', 'D120')),
        'Prenez la sortie D120');
    expect(Instructions.headline(step(ManeuverKind.offRamp, ManeuverDirection.right, '', '', '', '12')),
        'Prenez la sortie 12');
    expect(Instructions.headline(step(ManeuverKind.roundabout, ManeuverDirection.right, '', '', '', null, 2)),
        'Au rond-point, prenez la deuxième sortie');
    expect(Instructions.headline(step(ManeuverKind.arrive)), 'Vous êtes arrivé');
    expect(Instructions.headline(step(ManeuverKind.turn, ManeuverDirection.uturn)), 'Faites demi-tour');
    expect(Instructions.road(step(ManeuverKind.turn, ManeuverDirection.left, 'Avenue X', 'D7')), 'Avenue X (D7)');
  });

  test('direction affichée', () {
    expect(Instructions.towards(step(ManeuverKind.turn, ManeuverDirection.left, '', '', 'Centre-ville')),
        'vers Centre-ville');
    expect(Instructions.towards(step(ManeuverKind.turn)), isNull);
  });

  test('phrases vocales', () {
    final s = step(ManeuverKind.turn, ManeuverDirection.right, 'Rue de Rivoli', '', 'Centre-ville');
    expect(Instructions.spoken(s, inMeters: 312),
        'Dans 300 mètres, tournez à droite sur Rue de Rivoli, vers Centre-ville.');
    expect(Instructions.spoken(s, inMeters: 1480), startsWith('Dans 1,5 kilomètre,'));
    expect(Instructions.spoken(s, inMeters: 2000), startsWith('Dans 2 kilomètres,'));
    expect(Instructions.spoken(s, inMeters: 87), startsWith('Dans 90 mètres,'));
    expect(Instructions.spoken(s, inMeters: 0), 'Tournez à droite sur Rue de Rivoli.');
    expect(Instructions.spoken(step(ManeuverKind.arrive), inMeters: 10), 'Vous êtes arrivé à destination.');
  });
}
