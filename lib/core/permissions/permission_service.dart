import 'package:permission_handler/permission_handler.dart';

/// Capacités matérielles dont VIGIROAD a besoin.
enum AppCapability {
  location('Position GPS', 'Afficher la carte et vous guider'),
  camera('Caméra arrière', 'Lire les plaques, analyse sur le téléphone'),
  microphone('Microphone', 'Commandes vocales SENTRIX, à la demande (ou mot « Sentrix » si activé)');

  const AppCapability(this.title, this.purpose);
  final String title;
  final String purpose;
}

/// État d'une autorisation, indépendant du plugin.
enum CapabilityStatus { granted, denied, permanentlyDenied, restricted }

/// Façade sur `permission_handler`, injectable et simulable en test.
abstract interface class PermissionService {
  Future<CapabilityStatus> status(AppCapability capability);
  Future<CapabilityStatus> request(AppCapability capability);
  Future<bool> openSettings();
}

class PluginPermissionService implements PermissionService {
  const PluginPermissionService();

  /// Sur iOS, la reconnaissance vocale demande une autorisation distincte du
  /// micro ; elle est demandée en même temps.
  List<Permission> _permissions(AppCapability c) => switch (c) {
    AppCapability.location => [Permission.locationWhenInUse],
    AppCapability.camera => [Permission.camera],
    AppCapability.microphone => [Permission.microphone, Permission.speech],
  };

  @override
  Future<CapabilityStatus> status(AppCapability capability) async {
    final perms = _permissions(capability);
    final statuses = [for (final p in perms) await p.status];
    return _combine(statuses);
  }

  @override
  Future<CapabilityStatus> request(AppCapability capability) async {
    final result = await _permissions(capability).request();
    return _combine(result.values.toList());
  }

  @override
  Future<bool> openSettings() => openAppSettings();

  static CapabilityStatus _combine(List<PermissionStatus> statuses) {
    if (statuses.every((s) => s.isGranted || s.isLimited)) {
      return CapabilityStatus.granted;
    }
    if (statuses.any((s) => s.isPermanentlyDenied)) {
      return CapabilityStatus.permanentlyDenied;
    }
    if (statuses.any((s) => s.isRestricted)) {
      return CapabilityStatus.restricted;
    }
    return CapabilityStatus.denied;
  }
}
