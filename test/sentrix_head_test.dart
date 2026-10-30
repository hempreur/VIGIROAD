import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vigiroad/features/sentrix/domain/sentrix_state.dart';
import 'package:vigiroad/features/sentrix/presentation/sentrix_head.dart';

import 'helpers/pump_app.dart';

void main() {
  test('le peintre dessine chaque état sans erreur', () {
    for (final state in SentrixState.values) {
      for (final t in [0.0, 0.25, 0.9, 0.99]) {
        final recorder = ui.PictureRecorder();
        SentrixPainter(state: state, t: t).paint(Canvas(recorder), const Size(200, 180));
        recorder.endRecording().dispose();
      }
    }
  });

  test('ne redessine que si l\'état ou l\'horloge change', () {
    final a = SentrixPainter(state: SentrixState.idle, t: 0.1);
    expect(a.shouldRepaint(SentrixPainter(state: SentrixState.idle, t: 0.1)), isFalse);
    expect(a.shouldRepaint(SentrixPainter(state: SentrixState.idle, t: 0.2)), isTrue);
    expect(a.shouldRepaint(SentrixPainter(state: SentrixState.error, t: 0.1)), isTrue);
  });

  testWidgets('expose un libellé d\'accessibilité par état', (tester) async {
    await tester.pumpWidget(wrapDark(const SentrixHead(state: SentrixState.listening)));
    expect(find.bySemanticsLabel('SENTRIX, à l\'écoute'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
  });
}
