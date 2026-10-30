import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vigiroad/features/plates/application/alert_service.dart';
import 'package:vigiroad/features/plates/application/plate_scanning_controller.dart';
import 'package:vigiroad/features/navigation/application/navigation_session.dart';
import 'package:vigiroad/features/settings/application/settings_controller.dart';
import 'package:vigiroad/features/settings/domain/app_settings.dart';

import '../helpers/fakes.dart';

void main() {
  group('AppSettings', () {
    test('aller-retour JSON', () {
      const s = AppSettings(
        performance: PerformanceMode.economy,
        minConfidence: 0.9,
        minVotes: 4,
        retention: Retention.days7,
        alertSound: false,
        allowExport: true,
      );
      final back = AppSettings.fromJson(s.toJson());
      expect(back.toJson(), s.toJson());
    });

    test('valeurs invalides ou absentes : défauts et bornes', () {
      final s = AppSettings.fromJson({
        'performance': 'turbo',
        'minConfidence': 3,
        'minVotes': 1,
        'alertVolume': 'fort',
        'retention': 'days7',
      });
      expect(s.performance, PerformanceMode.balanced);
      expect(s.minConfidence, 0.95);
      expect(s.minVotes, 2);
      expect(s.alertVolume, 1.0);
      expect(s.retention, Retention.days7);
      expect(s.allowExport, isFalse, reason: 'export désactivé par défaut');
    });
  });

  group('SettingsController', () {
    late MemorySettingsStore store;
    late ProviderContainer c;

    setUp(() {
      store = MemorySettingsStore();
      c = ProviderContainer(overrides: [settingsStoreProvider.overrideWithValue(store)]);
    });
    tearDown(() => c.dispose());

    test('persiste les modifications', () async {
      await c.read(settingsControllerProvider.future);
      await c.read(settingsControllerProvider.notifier).change((s) => s.copyWith(minVotes: 5));
      expect(store.value.minVotes, 5);
      expect(c.read(appSettingsProvider).minVotes, 5);
    });

    test('les réglages pilotent les modules', () async {
      await c.read(settingsControllerProvider.future);
      await c.read(settingsControllerProvider.notifier).change(
        (s) => s.copyWith(minVotes: 4, minConfidence: 0.9, alertSound: false, retention: Retention.days7, voiceGuidance: false),
      );
      expect(c.read(voterSettingsProvider).minVotes, 4);
      final a = c.read(alertSettingsProvider);
      expect(a.policy.minConfidence, 0.9);
      expect(a.sound, isFalse);
      expect(a.retention, const Duration(days: 7));
      expect(c.read(voiceGuidanceProvider), isFalse);
    });

    test('réinitialisation', () async {
      await c.read(settingsControllerProvider.future);
      await c.read(settingsControllerProvider.notifier).change((s) => s.copyWith(drive3d: false));
      await c.read(settingsControllerProvider.notifier).reset();
      expect(store.value.drive3d, isTrue);
    });
  });
}
