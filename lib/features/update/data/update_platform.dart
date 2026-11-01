import 'dart:async';

import 'package:flutter/services.dart';

import '../domain/update_manifest.dart';

/// Accès à Android pour la mise à jour (MainActivity.kt).
abstract interface class UpdatePlatform {
  Future<InstalledApp> appInfo();

  /// L'utilisateur a autorisé VIGIROAD à installer des applications.
  Future<bool> canInstall();
  Future<void> openInstallSettings();

  /// Lance l'installation ; Android affiche sa confirmation.
  Future<void> install(String apkPath);

  /// Échecs signalés par Android après la confirmation.
  Stream<String> get installFailures;
}

class MethodChannelUpdatePlatform implements UpdatePlatform {
  MethodChannelUpdatePlatform() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'installFailed') {
        final args = (call.arguments as Map<Object?, Object?>?) ?? const {};
        _failures.add('${args['message'] ?? 'installation refusée'}');
      }
    });
  }

  static const _channel = MethodChannel('fr.vigiroad/updater');
  final _failures = StreamController<String>.broadcast();

  @override
  Future<InstalledApp> appInfo() async {
    final m = (await _channel.invokeMapMethod<String, Object?>('appInfo'))!;
    return InstalledApp(
      versionName: m['versionName'] as String? ?? '?',
      versionCode: (m['versionCode'] as num).toInt(),
      abis: [for (final a in m['abis'] as List<Object?>? ?? const []) '$a'],
    );
  }

  @override
  Future<bool> canInstall() async => await _channel.invokeMethod<bool>('canInstall') ?? false;

  @override
  Future<void> openInstallSettings() => _channel.invokeMethod<void>('openInstallSettings');

  @override
  Future<void> install(String apkPath) => _channel.invokeMethod<void>('install', {'path': apkPath});

  @override
  Stream<String> get installFailures => _failures.stream;
}
