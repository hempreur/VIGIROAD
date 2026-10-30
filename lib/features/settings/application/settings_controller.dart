import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/app_settings.dart';

/// Stockage des réglages (préférences du système).
abstract interface class SettingsStore {
  Future<AppSettings> load();
  Future<void> save(AppSettings s);
}

class PrefsSettingsStore implements SettingsStore {
  static const _key = 'vigiroad_settings_v1';

  @override
  Future<AppSettings> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return const AppSettings();
    try {
      return AppSettings.fromJson((jsonDecode(raw) as Map).cast<String, Object?>());
    } on Object {
      return const AppSettings();
    }
  }

  @override
  Future<void> save(AppSettings s) async =>
      (await SharedPreferences.getInstance()).setString(_key, jsonEncode(s.toJson()));
}

final settingsStoreProvider = Provider<SettingsStore>((ref) => PrefsSettingsStore());

final settingsControllerProvider = AsyncNotifierProvider<SettingsController, AppSettings>(SettingsController.new);

/// Réglages courants (valeurs par défaut tant qu'ils ne sont pas chargés).
final appSettingsProvider = Provider<AppSettings>(
  (ref) => ref.watch(settingsControllerProvider).value ?? const AppSettings(),
);

class SettingsController extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() => ref.watch(settingsStoreProvider).load();

  Future<void> update(AppSettings Function(AppSettings s) change) async {
    final next = change(state.value ?? const AppSettings());
    state = AsyncData(next);
    await ref.read(settingsStoreProvider).save(next);
  }

  Future<void> reset() => update((_) => const AppSettings());
}
