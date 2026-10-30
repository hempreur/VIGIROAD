import 'package:vigiroad/core/permissions/permission_service.dart';

/// Service d'autorisations simulé, pour les tests uniquement.
class FakePermissionService implements PermissionService {
  FakePermissionService(this.statuses, {this.onRequest});

  final Map<AppCapability, CapabilityStatus> statuses;
  final CapabilityStatus Function(AppCapability)? onRequest;
  int settingsOpened = 0;

  static FakePermissionService allGranted() => FakePermissionService({
    for (final c in AppCapability.values) c: CapabilityStatus.granted,
  });

  static FakePermissionService allDenied() => FakePermissionService(
    {for (final c in AppCapability.values) c: CapabilityStatus.denied},
    onRequest: (_) => CapabilityStatus.granted,
  );

  @override
  Future<CapabilityStatus> status(AppCapability c) async =>
      statuses[c] ?? CapabilityStatus.denied;

  @override
  Future<CapabilityStatus> request(AppCapability c) async {
    final s = onRequest?.call(c) ?? statuses[c] ?? CapabilityStatus.denied;
    statuses[c] = s;
    return s;
  }

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return true;
  }
}
