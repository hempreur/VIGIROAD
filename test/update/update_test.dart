import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vigiroad/core/widgets/vr_button.dart';
import 'package:vigiroad/features/update/application/update_controller.dart';
import 'package:vigiroad/features/update/data/update_platform.dart';
import 'package:vigiroad/features/update/data/update_source.dart';
import 'package:vigiroad/features/update/domain/update_manifest.dart';
import 'package:vigiroad/features/update/presentation/update_gate.dart';

final apkBytes = utf8.encode('APK factice VIGIROAD 1.3.0');

Map<String, dynamic> manifestJson({int build = 8, String version = '1.3.0', String? sha}) => {
  'version': version,
  'build': build,
  'minBuild': build,
  'notes': ['Corrections de bugs', 'Améliorations des performances', 'Nouvelles fonctionnalités'],
  'apks': {
    'arm64-v8a': {'url': 'https://example.org/v$version/arm64.apk', 'sha256': sha ?? sha256.convert(apkBytes).toString(), 'size': apkBytes.length},
    'armeabi-v7a': {'url': 'https://example.org/v$version/arm32.apk', 'sha256': 'ab', 'size': 1},
  },
};

class FakePlatform implements UpdatePlatform {
  InstalledApp app = const InstalledApp(versionName: '1.2.1', versionCode: 2007, abis: ['arm64-v8a', 'armeabi-v7a']);
  bool allowed = true;
  final installs = <String>[];
  int settingsOpened = 0;
  final failures = StreamController<String>.broadcast();

  @override
  Future<InstalledApp> appInfo() async => app;
  @override
  Future<bool> canInstall() async => allowed;
  @override
  Future<void> openInstallSettings() async => settingsOpened++;
  @override
  Future<void> install(String apkPath) async => installs.add(apkPath);
  @override
  Stream<String> get installFailures => failures.stream;
}

class FakeSource extends UpdateSource {
  FakeSource() : super(manifestUrl: 'https://example.org/update.json', userAgent: 'test');
  Map<String, dynamic>? next = manifestJson();
  int checks = 0;
  bool corrupt = false;

  @override
  Future<UpdateManifest> manifest() async {
    checks++;
    if (next == null) throw const UpdateException('réseau');
    return UpdateManifest.fromJson(next!);
  }

  @override
  Future<File> download(UpdateApk apk, File dest, {void Function(double progress)? onProgress}) async {
    onProgress?.call(0.5);
    if (corrupt) throw const UpdateException('Fichier téléchargé invalide (empreinte différente)');
    await dest.writeAsBytes(apkBytes);
    onProgress?.call(1);
    return dest;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('version', () {
    test('numéro de compilation sans le décalage d\'architecture', () {
      expect(const InstalledApp(versionName: '1.2.1', versionCode: 2007, abis: []).build, 7);
      expect(const InstalledApp(versionName: '1.2.1', versionCode: 1007, abis: []).build, 7);
    });

    test('nouvelle version, obligatoire, APK de l\'architecture principale', () {
      final m = UpdateManifest.fromJson(manifestJson());
      expect(m.isNewerThan(7), isTrue);
      expect(m.isNewerThan(8), isFalse);
      expect(m.isMandatoryFor(7), isTrue);
      expect(m.apkFor(['arm64-v8a', 'armeabi-v7a'])!.url, contains('arm64'));
      expect(m.apkFor(['armeabi-v7a'])!.url, contains('arm32'));
      expect(m.apkFor(['x86_64']), isNull);
    });
  });

  group('téléchargement vérifié', () {
    late Directory tmp;
    setUp(() async => tmp = await Directory.systemTemp.createTemp('vr_update'));
    tearDown(() async => tmp.delete(recursive: true));

    UpdateSource source(List<int> body) => UpdateSource(
      manifestUrl: 'https://example.org/update.json',
      userAgent: 'test',
      client: MockClient.streaming((req, _) async => http.StreamedResponse(Stream.fromIterable([body]), 200, contentLength: body.length)),
    );

    test('empreinte correcte : fichier conservé, progression', () async {
      final apk = UpdateManifest.fromJson(manifestJson()).apks['arm64-v8a']!;
      final progress = <double>[];
      final f = await source(apkBytes).download(apk, File('${tmp.path}/a.apk'), onProgress: progress.add);
      expect(await f.readAsBytes(), apkBytes);
      expect(progress.last, 1.0);
    });

    test('fichier altéré : refusé et supprimé', () async {
      final apk = UpdateManifest.fromJson(manifestJson()).apks['arm64-v8a']!;
      final dest = File('${tmp.path}/b.apk');
      await expectLater(source(utf8.encode('APK modifié')).download(apk, dest), throwsA(isA<UpdateException>()));
      expect(await dest.exists(), isFalse);
    });
  });

  group('contrôleur', () {
    late FakePlatform platform;
    late FakeSource src;
    late ProviderContainer c;
    late Directory tmp;

    setUp(() async {
      platform = FakePlatform();
      src = FakeSource();
      tmp = await Directory.systemTemp.createTemp('vr_update_c');
      c = ProviderContainer(
        overrides: [
          updatePlatformProvider.overrideWithValue(platform),
          updateSourceProvider.overrideWithValue(src),
          updateDownloadDirProvider.overrideWithValue(() async => tmp),
        ],
      );
      c.listen(updateProvider, (_, _) {});
      await pumpEventQueue();
    });
    tearDown(() async {
      c.dispose();
      await tmp.delete(recursive: true);
    });

    test('nouvelle version au démarrage : fenêtre obligatoire, une seule', () async {
      final s = c.read(updateProvider);
      expect(s.status, UpdateStatus.available);
      expect(s.mandatory, isTrue);
      expect(c.read(updatePromptVisibleProvider), isTrue);
      await c.read(updateProvider.notifier).check();
      expect(src.checks, 1, reason: 'pas de nouvelle vérification ni de seconde fenêtre');
    });

    test('déjà à jour ou hors connexion : rien ne bloque', () async {
      for (final (next, code) in [(manifestJson(build: 7, version: '1.2.1'), 2007), (null, 2007)]) {
        c.dispose();
        src = FakeSource()..next = next;
        platform = FakePlatform()..app = InstalledApp(versionName: '1.2.1', versionCode: code, abis: const ['arm64-v8a']);
        c = ProviderContainer(overrides: [
          updatePlatformProvider.overrideWithValue(platform),
          updateSourceProvider.overrideWithValue(src),
          updateDownloadDirProvider.overrideWithValue(() async => tmp),
        ]);
        c.listen(updateProvider, (_, _) {});
        await pumpEventQueue();
        expect(c.read(updateProvider).status, UpdateStatus.none);
        expect(c.read(updatePromptVisibleProvider), isFalse);
      }
    });

    test('mettre à jour : autorisation demandée une fois, puis téléchargement et installation', () async {
      platform.allowed = false;
      await c.read(updateProvider.notifier).updateNow();
      expect(c.read(updateProvider).status, UpdateStatus.needsPermission);
      expect(platform.installs, isEmpty);

      platform.allowed = true;
      await c.read(updateProvider.notifier).updateNow();
      expect(c.read(updateProvider).status, UpdateStatus.installing);
      expect(platform.installs.single, endsWith('vigiroad-1.3.0.apk'));
    });

    test('fichier invalide ou installation refusée : message et nouvel essai', () async {
      src.corrupt = true;
      await c.read(updateProvider.notifier).updateNow();
      expect(c.read(updateProvider).status, UpdateStatus.failed);
      expect(c.read(updateProvider).message, contains('empreinte'));
      expect(platform.installs, isEmpty, reason: 'jamais d\'installation d\'un fichier non vérifié');

      src.corrupt = false;
      await c.read(updateProvider.notifier).updateNow();
      platform.failures.add('INSTALL_FAILED_UPDATE_INCOMPATIBLE');
      await pumpEventQueue();
      expect(c.read(updateProvider).status, UpdateStatus.failed);
      expect(c.read(updateProvider).message, contains('INSTALL_FAILED'));
    });
  });

  testWidgets('fenêtre centrée : versions, améliorations, boutons', (tester) async {
    // Taille d'un smartphone (393 × 852 pt).
    tester.view.physicalSize = const Size(393, 852) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final platform = FakePlatform();
    final tmp = Directory.systemTemp.createTempSync('vr_update_w');
    addTearDown(() => tmp.deleteSync(recursive: true));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        updatePlatformProvider.overrideWithValue(platform),
        updateSourceProvider.overrideWithValue(FakeSource()),
        updateDownloadDirProvider.overrideWithValue(() async => tmp),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(),
        builder: (context, child) => UpdateGate(child: child!),
        home: const Scaffold(body: Center(child: Text('Écran de navigation'))),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Nouvelle mise à jour disponible !'), findsOneWidget);
    expect(find.text('1.2.1'), findsOneWidget);
    expect(find.text('1.3.0'), findsOneWidget);
    expect(find.text('Corrections de bugs'), findsOneWidget);
    expect(find.text('Mettre à jour maintenant'), findsOneWidget);
    expect(find.textContaining('obligatoire'), findsOneWidget);

    // Toucher l'arrière-plan ne ferme pas la fenêtre.
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    expect(find.text('Nouvelle mise à jour disponible !'), findsOneWidget);

    final button = find.widgetWithText(VrButton, 'Mettre à jour maintenant');
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.tap(button);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(platform.installs, hasLength(1));
    expect(find.text('Installation…'), findsOneWidget);
  });
}
