import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vigiroad/core/theme/vr_colors.dart';
import 'package:vigiroad/features/navigation/application/navigation_providers.dart';
import 'package:vigiroad/features/navigation/presentation/navigation_screen.dart';
import 'package:vigiroad/features/plates/application/plates_providers.dart';
import 'package:vigiroad/features/plates/domain/plate_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

double _lum(Color c) {
  double f(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
}

double contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('contrastes WCAG AA (≥ 4,5:1) — lisibilité en conduite', () {
    final pairs = {
      'texte principal / panneau': (VrColors.textPrimary, VrColors.panel),
      'texte secondaire / panneau': (VrColors.textSecondary, VrColors.panel),
      'texte secondaire / panneau clair': (VrColors.textSecondary, VrColors.panelLight),
      'texte atténué / panneau': (VrColors.textMuted, VrColors.panel),
      'cyan / fond': (VrColors.cyan, VrColors.background),
      'texte d\'alerte / fond d\'alerte': (VrColors.alertText, VrColors.alertBackground),
      'plaque : texte / fond blanc': (const Color(0xFF111418), VrColors.plateWhite),
      'bouton principal : fond / cyan': (VrColors.background, VrColors.cyan),
    };
    for (final MapEntry(key: name, value: (fg, bg)) in pairs.entries) {
      test(name, () => expect(contrast(fg, bg), greaterThanOrEqualTo(4.5)));
    }
  });

  Future<void> stress(WidgetTester tester, Size size, double textScale) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpVigiroad(tester, FakePermissionService.allGranted(), location: FakeLocationSource(testFix()));
    await passSplash(tester);
    final c = ProviderScope.containerOf(tester.element(find.byType(NavigationScreen)));
    c.read(destinationProvider.notifier).set(
      Destination(label: 'Arrivée', detail: '69002 Lyon', point: testRoute().geometry.last),
    );
    const reading = PlateReading(normalized: 'AA123BB', display: 'AA-123-BB', confidence: 0.98, vehicleType: 'VP');
    c.read(lastReadingProvider.notifier).update(reading);
    c.read(activeAlertProvider.notifier).raise(
      PlateAlert(reading: reading, category: 'Surveillance', priority: WatchPriority.high, at: DateTime(2026)),
    );
    await tester.pump();
    await tester.pump();
  }

  // Les débordements de mise en page font échouer ces tests (erreur Flutter).
  testWidgets('petit téléphone (360×640) : écran complet sans débordement', (tester) async {
    await stress(tester, const Size(360, 640), 1.0);
    expect(find.text('Plaque détectée dans la liste de surveillance'), findsOneWidget);
  });

  testWidgets('texte agrandi (×1,3) sans débordement', (tester) async {
    await stress(tester, const Size(393, 852), 1.3);
    expect(find.byType(NavigationScreen), findsOneWidget);
  });

  testWidgets('cibles tactiles ≥ 48 px', (tester) async {
    usePhoneSurface(tester);
    await pumpVigiroad(tester, FakePermissionService.allGranted(), location: FakeLocationSource(testFix()));
    await passSplash(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  });

  testWidgets('boutons libellés pour les lecteurs d\'écran', (tester) async {
    usePhoneSurface(tester);
    await pumpVigiroad(tester, FakePermissionService.allGranted(), location: FakeLocationSource(testFix()));
    await passSplash(tester);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  });
}
