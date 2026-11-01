import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stockage chiffré du jeton de session et de l'identifiant d'installation
/// (Keystore Android / Trousseau iOS).
abstract interface class AccountStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureAccountStore implements AccountStore {
  const SecureAccountStore([this._storage = const FlutterSecureStorage()]);
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class MemoryAccountStore implements AccountStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// Identifiant d'installation : aléatoire (128 bits), propre à VIGIROAD,
/// jamais dérivé d'un identifiant matériel ; renouvelable à tout moment.
String newInstallationId() {
  final r = Random.secure();
  return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// Marque, modèle et version du système (aucun identifiant permanent).
abstract interface class DeviceInfoSource {
  Future<Map<String, String?>> info();
}

class PlatformDeviceInfo implements DeviceInfoSource {
  const PlatformDeviceInfo();
  static const _channel = MethodChannel('fr.vigiroad/updater');

  @override
  Future<Map<String, String?>> info() async {
    if (Platform.isAndroid) {
      try {
        final m = await _channel.invokeMapMethod<String, Object?>('deviceInfo') ?? const {};
        return {'os': 'android', 'brand': _cap(m['brand'] as String?), 'model': m['model'] as String?, 'osVersion': m['osVersion'] as String?};
      } catch (_) {
        return {'os': 'android'};
      }
    }
    if (Platform.isIOS) {
      final v = RegExp(r'(\d+(\.\d+)*)').firstMatch(Platform.operatingSystemVersion)?.group(1);
      return {'os': 'ios', 'brand': 'Apple', 'model': 'iPhone', 'osVersion': v};
    }
    return {'os': 'other'};
  }

  static String? _cap(String? s) => s == null || s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
