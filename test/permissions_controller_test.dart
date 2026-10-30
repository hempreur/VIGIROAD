import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vigiroad/app/providers.dart';
import 'package:vigiroad/core/permissions/permission_service.dart';

import 'helpers/fakes.dart';

void main() {
  test('charge les états puis met à jour après une demande', () async {
    final service = FakePermissionService.allDenied();
    final container = ProviderContainer(
      overrides: [permissionServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    final initial = await container.read(permissionsProvider.future);
    expect(initial.values, everyElement(CapabilityStatus.denied));
    expect(container.read(permissionsProvider.notifier).allGranted, isFalse);

    final notifier = container.read(permissionsProvider.notifier);
    for (final c in AppCapability.values) {
      await notifier.request(c);
    }
    expect(notifier.allGranted, isTrue);
  });

  test('ouvre les réglages système', () async {
    final service = FakePermissionService.allDenied();
    final container = ProviderContainer(
      overrides: [permissionServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    await container.read(permissionsProvider.notifier).openSettings();
    expect(service.settingsOpened, 1);
  });
}
