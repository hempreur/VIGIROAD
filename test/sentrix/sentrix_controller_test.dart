import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vigiroad/core/permissions/permission_service.dart';
import 'package:vigiroad/features/history/presentation/history_screen.dart';
import 'package:vigiroad/features/navigation/presentation/navigation_screen.dart';
import 'package:vigiroad/features/plates/application/plate_scanning_controller.dart';
import 'package:vigiroad/features/sentrix/application/sentrix_controller.dart';
import 'package:vigiroad/features/sentrix/data/speech_input.dart';
import 'package:vigiroad/features/sentrix/domain/sentrix_state.dart';
import 'package:vigiroad/features/sentrix/presentation/sentrix_head.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

ProviderContainer _c(WidgetTester t) => ProviderScope.containerOf(t.element(find.byType(NavigationScreen)));

Finder _head() => find.descendant(of: find.byType(NavigationScreen), matching: find.byType(SentrixHead));

void main() {
  testWidgets('appui sur SENTRIX : écoute, exécution, réponse vocale', (tester) async {
    usePhoneSurface(tester);
    final speech = FakeSpeechInput()..next = 'Active la détection';
    final speaker = FakeSpeaker();
    final scanner = FakePlateScanner();
    await pumpVigiroad(tester, FakePermissionService.allGranted(), speech: speech, speaker: speaker, scanner: scanner);
    await passSplash(tester);

    await tester.tap(_head());
    await tester.pump();
    await tester.pump();

    expect(scanner.starts, 1);
    expect(_c(tester).read(plateScanningProvider).status, ScanStatus.running);
    expect(speaker.spoken.last, 'Lecture des plaques activée.');
  });

  testWidgets('commande de navigation vers l\'historique', (tester) async {
    usePhoneSurface(tester);
    final speech = FakeSpeechInput()..next = 'ouvre l\'historique';
    await pumpVigiroad(tester, FakePermissionService.allGranted(), speech: speech);
    await passSplash(tester);
    await tester.tap(_head());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(HistoryScreen), findsOneWidget);
  });

  testWidgets('phrase non comprise : état erreur et aide', (tester) async {
    usePhoneSurface(tester);
    final speech = FakeSpeechInput()..next = 'chante une chanson';
    await pumpVigiroad(tester, FakePermissionService.allGranted(), speech: speech);
    await passSplash(tester);
    await tester.tap(_head());
    await tester.pump();
    await tester.pump();
    final ui = _c(tester).read(sentrixProvider);
    expect(ui.visual, SentrixState.error);
    expect(ui.reply, contains('Dites « aide »'));
  });

  testWidgets('trafic : réponse honnête', (tester) async {
    usePhoneSurface(tester);
    await pumpVigiroad(tester, FakePermissionService.allGranted());
    await passSplash(tester);
    final r = await _c(tester).read(sentrixProvider.notifier).execute('afficher le trafic');
    expect(r.success, isFalse);
    expect(r.reply, contains('pas disponible'));
  });

  testWidgets('micro refusé : pas d\'écoute', (tester) async {
    usePhoneSurface(tester);
    final perms = FakePermissionService.allGranted();
    final speech = FakeSpeechInput()..next = 'aide';
    await pumpVigiroad(tester, perms, speech: speech);
    await passSplash(tester);
    perms.statuses[AppCapability.microphone] = CapabilityStatus.permanentlyDenied;
    await tester.tap(_head());
    await tester.pump();
    await tester.pump();
    expect(_c(tester).read(sentrixProvider).reply, 'Autorisez le microphone pour me parler.');
  });

  testWidgets('reconnaissance indisponible : message', (tester) async {
    usePhoneSurface(tester);
    final speech = FakeSpeechInput()..error = const SpeechUnavailable('Reconnaissance vocale indisponible sur ce téléphone.');
    await pumpVigiroad(tester, FakePermissionService.allGranted(), speech: speech);
    await passSplash(tester);
    await tester.tap(_head());
    await tester.pump();
    await tester.pump();
    expect(_c(tester).read(sentrixProvider).reply, contains('indisponible'));
  });
}
