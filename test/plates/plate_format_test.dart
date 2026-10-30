import 'package:flutter_test/flutter_test.dart';
import 'package:vigiroad/features/plates/domain/plate_format.dart';

void main() {
  const siv = FrenchSivFormat();
  const fni = FrenchFniFormat();

  group('SIV', () {
    test('validité', () {
      expect(siv.isValid('AA123BB'), isTrue);
      expect(siv.isValid('WW123AA'), isTrue, reason: 'WW : immatriculation provisoire');
      expect(siv.isValid('AI123BB'), isFalse, reason: 'I interdit');
      expect(siv.isValid('AA123BO'), isFalse, reason: 'O interdit');
      expect(siv.isValid('UA123BB'), isFalse, reason: 'U interdit');
      expect(siv.isValid('SS123BB'), isFalse);
      expect(siv.isValid('AA000BB'), isFalse);
      expect(siv.isValid('AA12BB'), isFalse);
    });

    test('affichage', () => expect(siv.display('AA123BB'), 'AA-123-BB'));

    test('extraction depuis une ligne OCR avec bande « F »', () {
      final c = PlateFormats.extract('F AA-123-BB');
      expect(c.first.normalized, 'AA123BB');
      expect(c.first.corrections, 0);
    });

    test('corrige les confusions selon la position', () {
      final c = PlateFormats.extract('AA-I23-8B').single;
      expect(c.normalized, 'AA123BB');
      expect(c.corrections, 2);
    });

    test('au-delà de 2 corrections : rejet', () {
      expect(PlateFormats.extract('A4-I2Z-8B'), isEmpty);
    });

    test('textes sans plaque ignorés', () {
      for (final t in ['SORTIE 12', 'PARKING', 'PARIS 75', 'A6 LYON', '50']) {
        expect(PlateFormats.extract(t), isEmpty, reason: t);
      }
    });
  });

  group('FNI', () {
    test('validité et affichage', () {
      expect(fni.isValid('1234AB75'), isTrue);
      expect(fni.isValid('123ABC2A'), isTrue);
      expect(fni.isValid('12AB974'), isTrue);
      expect(fni.isValid('1234AB99'), isFalse, reason: 'département 99 inexistant');
      expect(fni.isValid('0AB75'), isFalse);
      expect(fni.display('1234AB75'), '1234 AB 75');
    });

    test('extraction seulement avec séparateurs nets', () {
      expect(PlateFormats.extract('1234 AB 75').single.display, '1234 AB 75');
      expect(PlateFormats.extract('1234AB75'), isEmpty);
    });
  });

  test('reconnaissance de format pour la saisie', () {
    expect(PlateFormats.match('AA123BB')?.id, 'FR-SIV');
    expect(PlateFormats.match('1234AB75')?.id, 'FR-FNI');
    expect(PlateFormats.match('XYZ'), isNull);
  });
}
