import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart' show AppLifecycleListener, AppLifecycleState, WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../app/providers.dart';
import '../../../app/version.dart';
import '../../navigation/application/navigation_providers.dart';
import '../data/account_api.dart';
import '../data/account_store.dart';

/// Version affichée au serveur (statistiques des versions).
const accountAppVersion = appVersion;

enum AccountStatus { unavailable, loading, signedOut, signedIn }

class AccountState {
  const AccountState({
    this.status = AccountStatus.loading,
    this.user,
    this.deviceRegistered = false,
    this.busy = false,
    this.error,
    this.message,
    this.sessions = const [],
    this.currentSession,
  });

  final AccountStatus status;
  final Map<String, dynamic>? user;
  final bool deviceRegistered;
  final bool busy;
  final String? error;
  final String? message;
  final List<Map<String, dynamic>> sessions;
  final String? currentSession;

  bool get signedIn => status == AccountStatus.signedIn;
  bool get regionConsent => (user?['consents'] as Map<String, dynamic>?)?['region'] == true;
  bool get locationConsent => (user?['consents'] as Map<String, dynamic>?)?['location'] == true;

  AccountState copyWith({
    AccountStatus? status,
    Map<String, dynamic>? user,
    bool? deviceRegistered,
    bool? busy,
    String? error,
    String? message,
    List<Map<String, dynamic>>? sessions,
    String? currentSession,
  }) => AccountState(
    status: status ?? this.status,
    user: user ?? this.user,
    deviceRegistered: deviceRegistered ?? this.deviceRegistered,
    busy: busy ?? this.busy,
    error: error,
    message: message,
    sessions: sessions ?? this.sessions,
    currentSession: currentSession ?? this.currentSession,
  );
}

final accountStoreProvider = Provider<AccountStore>((ref) => const SecureAccountStore());
final deviceInfoProvider = Provider<DeviceInfoSource>((ref) => const PlatformDeviceInfo());
final accountHttpProvider = Provider<http.Client>((ref) {
  final c = http.Client();
  ref.onDispose(c.close);
  return c;
});

/// Client des comptes, ou null si aucun serveur n'est configuré.
final accountApiProvider = Provider<AccountApi?>((ref) {
  final c = ref.watch(appConfigProvider);
  if (!c.trafficEnabled) return null;
  return AccountApi(baseUrl: c.trafficApiUrl, apiKey: c.trafficApiKey, userAgent: c.userAgent, client: ref.watch(accountHttpProvider));
});

/// Intervalle des battements de cœur (temps d'utilisation réel).
final heartbeatIntervalProvider = Provider<Duration>((ref) => const Duration(seconds: 60));

final accountProvider = NotifierProvider<AccountController, AccountState>(AccountController.new);

/// Compte VIGIROAD facultatif : l'application fonctionne entièrement sans.
/// Une fois connecté, un battement toutes les 60 s (application au premier
/// plan) mesure le temps d'utilisation ; la région et la position
/// approximative ne sont envoyées qu'avec le consentement explicite.
class AccountController extends Notifier<AccountState> {
  static const _kToken = 'account.token';
  static const _kInstallation = 'account.installation';
  static const _kDevice = 'account.device';
  static const _kUser = 'account.user';

  Timer? _beat;
  AppLifecycleListener? _lifecycle;
  bool _foreground = true;

  AccountStore get _store => ref.read(accountStoreProvider);
  AccountApi? get _api => ref.read(accountApiProvider);

  @override
  AccountState build() {
    ref.onDispose(() {
      _beat?.cancel();
      _lifecycle?.dispose();
    });
    if (ref.watch(accountApiProvider) == null) return const AccountState(status: AccountStatus.unavailable);
    _lifecycle = AppLifecycleListener(
      onStateChange: (s) {
        _foreground = s == AppLifecycleState.resumed;
        if (_foreground && state.signedIn) unawaited(heartbeat());
      },
    );
    final binding = WidgetsBinding.instance.lifecycleState;
    _foreground = binding == null || binding == AppLifecycleState.resumed;
    unawaited(Future.microtask(_restore));
    return const AccountState();
  }

  Future<String?> _token() => _store.read(_kToken);

  Future<void> _restore() async {
    final String? token;
    try {
      token = await _token();
    } catch (_) {
      // Stockage sécurisé indisponible : l'application reste utilisable sans compte.
      if (ref.mounted) state = state.copyWith(status: AccountStatus.signedOut);
      return;
    }
    if (!ref.mounted) return;
    if (token == null) {
      state = state.copyWith(status: AccountStatus.signedOut);
      return;
    }
    Map<String, dynamic>? cached;
    try {
      final raw = await _store.read(_kUser);
      if (raw != null) cached = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {}
    final device = await _store.read(_kDevice) == '1';
    if (!ref.mounted) return;
    state = state.copyWith(status: AccountStatus.signedIn, user: cached, deviceRegistered: device);
    _startBeat();
    unawaited(refresh());
  }

  Future<void> refresh() async {
    final token = await _token();
    final api = _api;
    if (token == null || api == null) return;
    try {
      final me = await api.me(token);
      await _saveUser(me['user'] as Map<String, dynamic>);
      if (ref.mounted) state = state.copyWith(user: me['user'] as Map<String, dynamic>, currentSession: me['sessionId'] as String?);
    } on AccountException catch (e) {
      if (e.sessionEnded) await _ended(e);
    }
  }

  Future<void> _saveUser(Map<String, dynamic> u) => _store.write(_kUser, jsonEncode(u));

  Future<Map<String, Object?>> _device() async {
    var id = await _store.read(_kInstallation);
    if (id == null) {
      id = newInstallationId();
      await _store.write(_kInstallation, id);
    }
    final info = await ref.read(deviceInfoProvider).info();
    return {'installationId': id, ...info, 'appVersion': accountAppVersion};
  }

  Future<bool> _run(Future<void> Function(AccountApi api) action, {String? success}) async {
    final api = _api;
    if (api == null) return false;
    state = state.copyWith(busy: true);
    try {
      await action(api);
      if (ref.mounted) state = state.copyWith(busy: false, message: success);
      return true;
    } on AccountException catch (e) {
      if (!ref.mounted) return false;
      if (e.sessionEnded && state.signedIn) {
        await _ended(e);
      } else {
        state = state.copyWith(busy: false, error: e.message);
      }
      return false;
    }
  }

  Future<void> _signedIn(Map<String, dynamic> r, {required bool device}) async {
    await _store.write(_kToken, r['token'] as String);
    await _store.write(_kDevice, device ? '1' : '0');
    await _saveUser(r['user'] as Map<String, dynamic>);
    if (!ref.mounted) return;
    state = AccountState(
      status: AccountStatus.signedIn,
      user: r['user'] as Map<String, dynamic>,
      deviceRegistered: device,
      currentSession: r['sessionId'] as String?,
    );
    _startBeat();
  }

  Future<bool> register({
    required String pseudonym,
    required String password,
    String? email,
    String? displayName,
    bool regionConsent = false,
    bool locationConsent = false,
    bool registerDevice = true,
  }) => _run((api) async {
    final r = await api.register(
      pseudonym: pseudonym,
      password: password,
      email: email,
      displayName: displayName,
      regionConsent: regionConsent,
      locationConsent: locationConsent,
      device: registerDevice ? await _device() : null,
      appVersion: accountAppVersion,
    );
    await _signedIn(r, device: registerDevice);
  }, success: 'Compte créé. Bienvenue sur VIGIROAD !');

  Future<bool> login(String login, String password, {bool registerDevice = true}) => _run((api) async {
    final r = await api.login(login, password, device: registerDevice ? await _device() : null, appVersion: accountAppVersion);
    await _signedIn(r, device: registerDevice);
  }, success: 'Connecté');

  /// Nouveau mot de passe avec le code transmis par un administrateur.
  Future<bool> resetWithCode(String login, String code, String password) => _run((api) async {
    await api.reset(login, code, password);
    final r = await api.login(login, password, device: await _device(), appVersion: accountAppVersion);
    await _signedIn(r, device: true);
  }, success: 'Mot de passe modifié');

  Future<void> logout() async {
    final token = await _token();
    final api = _api;
    if (token != null && api != null) {
      try {
        await api.logout(token);
      } catch (_) {}
    }
    await _clearLocal();
    if (ref.mounted) state = const AccountState(status: AccountStatus.signedOut, message: 'Déconnecté');
  }

  Future<void> _clearLocal() async {
    _beat?.cancel();
    _beat = null;
    await _store.delete(_kToken);
    await _store.delete(_kUser);
    await _store.delete(_kDevice);
  }

  /// Session terminée côté serveur (révoquée, expirée, compte désactivé).
  Future<void> _ended(AccountException e) async {
    await _clearLocal();
    if (!ref.mounted) return;
    state = AccountState(
      status: AccountStatus.signedOut,
      error: switch (e.code) {
        'expired' => 'Session expirée après une longue inactivité. Reconnectez-vous.',
        'logged_out' => null,
        _ => 'Votre session a été fermée (${e.message}). Reconnectez-vous.',
      },
    );
  }

  Future<bool> deleteAccount(String password) => _run((api) async {
    final token = await _token();
    if (token == null) return;
    await api.delete(token, password);
    await _clearLocal();
    await _store.delete(_kInstallation);
    if (ref.mounted) state = const AccountState(status: AccountStatus.signedOut);
  }, success: 'Compte et données supprimés');

  Future<bool> updateProfile({String? pseudonym, String? displayName, String? email}) => _run((api) async {
    final token = await _token();
    if (token == null) return;
    final r = await api.update(token, {'pseudonym': ?pseudonym, 'displayName': displayName, 'email': email});
    await _saveUser(r['user'] as Map<String, dynamic>);
    if (ref.mounted) state = state.copyWith(user: r['user'] as Map<String, dynamic>);
  }, success: 'Profil mis à jour');

  /// Consentements : le retrait efface aussitôt les données côté serveur.
  Future<bool> setConsent({bool? region, bool? location}) => _run((api) async {
    final token = await _token();
    if (token == null) return;
    final r = await api.update(token, {'consents': {'region': ?region, 'location': ?location}});
    await _saveUser(r['user'] as Map<String, dynamic>);
    if (ref.mounted) state = state.copyWith(user: r['user'] as Map<String, dynamic>);
  });

  /// Enregistrer (ou retirer) cet appareil du compte.
  Future<bool> setDeviceRegistered(bool value) => _run((api) async {
    final token = await _token();
    if (token == null) return;
    if (value) {
      await api.registerDevice(token, await _device());
    } else {
      await api.forgetDevice(token);
    }
    await _store.write(_kDevice, value ? '1' : '0');
    if (ref.mounted) state = state.copyWith(deviceRegistered: value);
  });

  /// Nouvel identifiant d'installation (l'ancien appareil est retiré).
  Future<bool> renewInstallationId() => _run((api) async {
    final token = await _token();
    if (token == null) return;
    if (state.deviceRegistered) await api.forgetDevice(token);
    await _store.write(_kInstallation, newInstallationId());
    if (state.deviceRegistered) await api.registerDevice(token, await _device());
  }, success: 'Nouvel identifiant d\'appareil généré');

  Future<void> loadSessions() async {
    await _run((api) async {
      final token = await _token();
      if (token == null) return;
      final r = await api.sessions(token);
      if (ref.mounted) {
        state = state.copyWith(
          sessions: ((r['sessions'] as List<dynamic>?) ?? const []).cast<Map<String, dynamic>>(),
          currentSession: r['current'] as String?,
        );
      }
    });
  }

  Future<bool> revokeSession(String id) async {
    final ok = await _run((api) async {
      final token = await _token();
      if (token != null) await api.revokeSession(token, id);
    }, success: 'Session fermée');
    if (ok) await loadSessions();
    return ok;
  }

  /// Copie de toutes les données enregistrées sur le compte (JSON).
  Future<String?> exportData() async {
    String? out;
    await _run((api) async {
      final token = await _token();
      if (token == null) return;
      out = const JsonEncoder.withIndent('  ').convert(await api.export(token));
    });
    return out;
  }

  void _startBeat() {
    _beat?.cancel();
    _beat = Timer.periodic(ref.read(heartbeatIntervalProvider), (_) => unawaited(heartbeat()));
    unawaited(heartbeat());
  }

  /// Battement de cœur : uniquement connecté et au premier plan.
  Future<void> heartbeat() async {
    if (!_foreground || !state.signedIn) return;
    final token = await _token();
    final api = _api;
    if (token == null || api == null) return;
    double? lat, lng;
    if (state.locationConsent && ref.exists(positionProvider)) {
      final fix = ref.read(positionProvider).value;
      lat = fix?.point.latitude;
      lng = fix?.point.longitude;
    }
    try {
      await api.heartbeat(token, appVersion: accountAppVersion, lat: lat, lng: lng);
    } on AccountException catch (e) {
      if (e.sessionEnded) await _ended(e);
    }
  }
}
