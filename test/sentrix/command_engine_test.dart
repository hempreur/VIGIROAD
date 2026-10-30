import 'package:flutter_test/flutter_test.dart';
import 'package:vigiroad/features/sentrix/application/sentrix_commands.dart';
import 'package:vigiroad/features/sentrix/domain/command_engine.dart';

void main() {
  final engine = CommandEngine(sentrixCommands);
  String? id(String said) => engine.match(said)?.command.id;

  test('exemples de l\'image de référence', () {
    expect(id('Lancer la navigation'), 'navigation.start');
    expect(id('Activer la détection'), 'detection.on');
    expect(id('Ouvrir l\'historique'), 'history.open');
    expect(id('Afficher le trafic'), 'traffic.show');
    expect(id('Lire la dernière alerte'), 'alert.last');
  });

  test('formulations naturelles et accents', () {
    expect(id('sentrix, active la detection s\'il te plaît'), 'detection.on');
    expect(id('Désactive la détection'), 'detection.off');
    expect(id('arrête la lecture des plaques'), 'detection.off');
    expect(id('montre-moi l\'historique'), 'history.open');
    expect(id('annule le guidage'), 'navigation.stop');
    expect(id('quelle est ma vitesse'), 'speed.read');
    expect(id('coupe le guidage vocal'), 'voice.off');
    expect(id('dans combien de temps j\'arrive'), 'navigation.eta');
    expect(id('ouvre les paramètres'), 'settings.open');
  });

  test('activer et désactiver ne se confondent pas', () {
    expect(id('activer la détection'), isNot('detection.off'));
    expect(id('désactiver la détection'), isNot('detection.on'));
  });

  test('phrases sans rapport : non comprises', () {
    expect(engine.match('quel temps fait-il demain'), isNull);
    expect(engine.match(''), isNull);
    expect(engine.match('le la les'), isNull);
  });

  test('normalisation', () {
    expect(tokenize('Éteins la CAMÉRA !'), ['desactiver', 'detection']);
  });

  test('identifiants uniques exigés', () {
    expect(
      () => CommandEngine<int>([
        VoiceCommand(id: 'a', label: 'A', phrases: const ['x'], action: (_) async => const CommandResult('')),
        VoiceCommand(id: 'a', label: 'B', phrases: const ['y'], action: (_) async => const CommandResult('')),
      ]),
      throwsArgumentError,
    );
  });

  test('chaque commande se reconnaît par sa phrase d\'exemple', () {
    for (final c in sentrixCommands) {
      expect(id(c.phrases.first), c.id, reason: c.phrases.first);
    }
  });
}
