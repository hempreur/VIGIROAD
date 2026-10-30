@Tags(['screenshots'])
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vigiroad/core/permissions/permission_service.dart';
import 'package:vigiroad/core/theme/vr_colors.dart';
import 'package:vigiroad/core/theme/vr_typography.dart';
import 'package:vigiroad/features/sentrix/domain/sentrix_state.dart';
import 'package:vigiroad/features/sentrix/presentation/sentrix_head.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

/// Captures de l'interface, générées en CI avec `--update-goldens` et publiées
/// comme artefact pour la comparaison avec l'image de référence (§6).
///
/// Les polices réelles (Rajdhani, Inter, Material Icons) sont chargées pour
/// que les captures correspondent au rendu sur téléphone.
Future<void> _loadFonts() async {
  final manifest = json.decode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(entry['family'] as String);
    for (final font in (entry['fonts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('01 splash', (tester) async {
    usePhoneSurface(tester);
    await pumpVigiroad(tester, FakePermissionService.allDenied());
    await tester.pump(const Duration(milliseconds: 1300));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/01_splash.png'));
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('02 autorisations', (tester) async {
    usePhoneSurface(tester);
    final service = FakePermissionService({
      AppCapability.location: CapabilityStatus.granted,
      AppCapability.camera: CapabilityStatus.denied,
      AppCapability.microphone: CapabilityStatus.permanentlyDenied,
    });
    await pumpVigiroad(tester, service);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 800));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/02_permissions.png'));
  });

  testWidgets('03 accueil phase 1', (tester) async {
    usePhoneSurface(tester);
    await pumpVigiroad(tester, FakePermissionService.allGranted());
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 800));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/03_home.png'));
  });

  testWidgets('04 états SENTRIX', (tester) async {
    usePhoneSurface(tester, size: const Size(600, 420));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: VrColors.background,
          body: Center(
            child: Wrap(
              spacing: 24,
              runSpacing: 16,
              alignment: WrapAlignment.center,
              children: [
                for (final s in SentrixState.values)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SentrixHead(size: 150, state: s),
                      const SizedBox(height: 6),
                      Text(s.name.toUpperCase(), style: VrText.caption),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/04_sentrix_states.png'));
  });
}
