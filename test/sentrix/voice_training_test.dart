import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vigiroad/app/providers.dart';
import 'package:vigiroad/core/permissions/permission_service.dart';
import 'package:vigiroad/features/sentrix/application/voice_training_controller.dart';
import 'package:vigiroad/features/sentrix/data/stored_zip.dart';
import 'package:vigiroad/features/sentrix/data/voice_samples.dart';
import 'package:vigiroad/features/sentrix/presentation/voice_training_screen.dart';

import '../helpers/fakes.dart';

/// Enregistreur factice : écrit un petit fichier WAV et signale un niveau.
class FakeRecorder implements SampleRecorder {
  final paths = <String>[];
  Object? error;

  @override
  Future<void> record(String path, Duration duration, {void Function(double level)? onLevel}) async {
    if (error != null) throw error!;
    onLevel?.call(0.5);
    await File(path).writeAsBytes(Uint8List.fromList([82, 73, 70, 70, ...List.filled(40, 0)]));
    paths.add(path);
  }

  @override
  Future<void> cancel() async {}
}

/// Lecture minimale d'une archive « stored » : nom → contenu.
Map<String, Uint8List> readZip(Uint8List z) {
  final b = ByteData.sublistView(z);
  final out = <String, Uint8List>{};
  var p = 0;
  while (b.getUint32(p, Endian.little) == 0x04034b50) {
    expect(b.getUint16(p + 8, Endian.little), 0, reason: 'sans compression');
    final crc = b.getUint32(p + 14, Endian.little);
    final size = b.getUint32(p + 18, Endian.little);
    final nameLen = b.getUint16(p + 26, Endian.little);
    final name = utf8.decode(z.sublist(p + 30, p + 30 + nameLen));
    final data = z.sublist(p + 30 + nameLen, p + 30 + nameLen + size);
    expect(crc32(data), crc, reason: 'CRC de $name');
    out[name] = data;
    p += 30 + nameLen + size;
  }
  final end = z.length - 22;
  expect(b.getUint32(end, Endian.little), 0x06054b50);
  expect(b.getUint16(end + 10, Endian.little), out.length);
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('CRC-32 standard', () {
    expect(crc32(utf8.encode('123456789')), 0xCBF43926);
  });

  test('archive ZIP lisible, noms UTF-8, CRC corrects', () {
    final z = storedZip({'a/é.txt': Uint8List.fromList(utf8.encode('bonjour')), 'b.bin': Uint8List(3)});
    final files = readZip(z);
    expect(files.keys, ['a/é.txt', 'b.bin']);
    expect(utf8.decode(files['a/é.txt']!), 'bonjour');
  });

  group('enregistrements', () {
    late Directory tmp;
    late VoiceSampleStore store;
    late FakeRecorder recorder;
    late ProviderContainer c;
    Uint8List? saved;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('vigiroad_voix');
      store = VoiceSampleStore(Directory('${tmp.path}/sentrix_samples'));
      recorder = FakeRecorder();
      saved = null;
      c = ProviderContainer(
        overrides: [
          voiceSampleStoreProvider.overrideWith((ref) async => store),
          sampleRecorderProvider.overrideWithValue(recorder),
          permissionServiceProvider.overrideWithValue(FakePermissionService.allGranted()),
          zipSaverProvider.overrideWithValue((name, bytes) async {
            saved = bytes;
            return true;
          }),
        ],
      );
      c.listen(voiceTrainingProvider, (_, _) {});
    });
    tearDown(() async {
      c.dispose();
      await tmp.delete(recursive: true);
    });

    VoiceTrainingController ctrl() => c.read(voiceTrainingProvider.notifier);

    test('numérotation, comptes, annulation du dernier', () async {
      await ctrl().record(SampleKind.sentrix);
      await ctrl().record(SampleKind.sentrix);
      expect(recorder.paths.map((p) => p.split('/').last), ['sentrix_001.wav', 'sentrix_002.wav']);
      expect(c.read(voiceTrainingProvider).count(SampleKind.sentrix), 2);
      await ctrl().deleteLast(SampleKind.sentrix);
      expect(c.read(voiceTrainingProvider).count(SampleKind.sentrix), 1);
      await ctrl().record(SampleKind.sentrix);
      expect(recorder.paths.last.split('/').last, 'sentrix_002.wav');
    });

    test('export : seulement avec assez d\'enregistrements, archive complète', () async {
      for (var i = 0; i < SampleKind.sentrix.minimum; i++) {
        await ctrl().record(SampleKind.sentrix);
      }
      expect(c.read(voiceTrainingProvider).canExport, isFalse, reason: 'parole normale manquante');
      await ctrl().record(SampleKind.speech);
      expect(c.read(voiceTrainingProvider).canExport, isTrue);

      expect(await ctrl().export(appVersion: '1.1.0'), isTrue);
      final files = readZip(saved!);
      expect(files.keys.where((k) => k.startsWith('sentrix/')), hasLength(30));
      expect(files.keys, contains('speech/speech_001.wav'));
      final manifest = jsonDecode(utf8.decode(files['manifest.json']!)) as Map<String, dynamic>;
      expect(manifest['counts'], {'sentrix': 30, 'speech': 1, 'ambient': 0});
      expect(manifest['sampleRate'], 16000);
    });

    test('tout effacer', () async {
      await ctrl().record(SampleKind.speech);
      await ctrl().clear();
      expect(c.read(voiceTrainingProvider).count(SampleKind.speech), 0);
      expect(await store.root.exists(), isFalse);
    });

    test('micro refusé : rien n\'est enregistré', () async {
      c.dispose();
      c = ProviderContainer(
        overrides: [
          voiceSampleStoreProvider.overrideWith((ref) async => store),
          sampleRecorderProvider.overrideWithValue(recorder),
          permissionServiceProvider.overrideWithValue(
            FakePermissionService({for (final c in AppCapability.values) c: CapabilityStatus.permanentlyDenied}),
          ),
        ],
      );
      c.listen(voiceTrainingProvider, (_, _) {});
      await ctrl().record(SampleKind.sentrix);
      expect(recorder.paths, isEmpty);
      expect(c.read(voiceTrainingProvider).message, contains('micro'));
    });
  });

  testWidgets('écran : étapes et export désactivé au départ', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final tmp = Directory.systemTemp.createTempSync('vigiroad_voix_ui');
    addTearDown(() => tmp.deleteSync(recursive: true));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        voiceSampleStoreProvider.overrideWith((ref) async => VoiceSampleStore(Directory('${tmp.path}/s'))),
        sampleRecorderProvider.overrideWithValue(FakeRecorder()),
        permissionServiceProvider.overrideWithValue(FakePermissionService.allGranted()),
      ],
      child: MaterialApp(theme: ThemeData.dark(), home: const VoiceTrainingScreen()),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.text('1. Dites « Sentrix »'), findsOneWidget);
    expect(find.textContaining('uniquement à l\'arrêt'), findsOneWidget);
    expect(find.textContaining('Exporter (au moins 30'), findsOneWidget);
  });
}
