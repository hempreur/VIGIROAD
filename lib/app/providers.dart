import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/permissions/permission_service.dart';

/// Configuration (surchargée dans les tests via `ProviderScope.overrides`).
final appConfigProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment(),
);

final permissionServiceProvider = Provider<PermissionService>(
  (ref) => const PluginPermissionService(),
);

/// État courant des autorisations, rafraîchissable.
final permissionsProvider =
    AsyncNotifierProvider<PermissionsController, Map<AppCapability, CapabilityStatus>>(
      PermissionsController.new,
    );

class PermissionsController
    extends AsyncNotifier<Map<AppCapability, CapabilityStatus>> {
  PermissionService get _service => ref.read(permissionServiceProvider);

  @override
  Future<Map<AppCapability, CapabilityStatus>> build() async => {
    for (final c in AppCapability.values) c: await _service.status(c),
  };

  Future<CapabilityStatus> request(AppCapability capability) async {
    final result = await _service.request(capability);
    final current = state.value ?? const {};
    state = AsyncData({...current, capability: result});
    return result;
  }

  Future<void> openSettings() => _service.openSettings();

  bool get allGranted =>
      state.value?.values.every((s) => s == CapabilityStatus.granted) ?? false;
}
