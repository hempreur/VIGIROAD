import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'client.dart';

enum SessionStage { server, setup, login, mfa, enroll, ready }

enum LiveState { off, connecting, live, offline }

/// Connexion à l'API d'administration : serveur, création du premier
/// administrateur, mot de passe, code TOTP, session, flux temps réel et
/// verrouillage après inactivité.
class AdminSession extends ChangeNotifier {
  AdminSession({
    required this.clientName,
    http.Client Function()? httpFactory,
    this.inactivity = const Duration(minutes: 30),
    DateTime Function()? clock,
  }) : _httpFactory = httpFactory,
       _now = clock ?? DateTime.now;

  /// « windows » / « linux » (journal des connexions).
  final String clientName;
  final http.Client Function()? _httpFactory;
  final Duration inactivity;
  final DateTime Function() _now;

  SessionStage stage = SessionStage.server;
  Uri? server;
  AdminClient? client;
  String? error;
  String? info;
  bool busy = false;
  bool setupAvailable = false;
  String? lastEmail;
  String? _ticket;
  String? enrollSecret;
  String? enrollUri;
  Map<String, dynamic>? admin;

  /// Dernier instantané temps réel (métriques, compteurs, alertes).
  final snapshot = ValueNotifier<Map<String, dynamic>?>(null);
  final live = ValueNotifier<LiveState>(LiveState.off);
  StreamSubscription<(String, Map<String, dynamic>)>? _sse;
  Timer? _reconnect;
  Timer? _idleTimer;
  late DateTime _lastInput = _now();
  int _retries = 0;

  AdminClient get api => client ?? (throw StateError('Non connecté'));
  Set<String> get permissions => {...((admin?['permissions'] as List<dynamic>?) ?? const []).cast<String>()};
  bool can(String perm) => permissions.contains(perm);
  String get role => admin?['roleLabel'] as String? ?? '';

  Future<void> init() async {
    try {
      final p = await SharedPreferences.getInstance();
      lastEmail = p.getString('admin.email');
      final saved = p.getString('admin.server');
      if (saved != null) {
        await connectServer(saved);
        return;
      }
    } catch (_) {}
    notifyListeners();
  }

  void _set(VoidCallback f) {
    f();
    notifyListeners();
  }

  Future<T?> _run<T>(Future<T> Function() f) async {
    _set(() {
      busy = true;
      error = null;
      info = null;
    });
    try {
      return await f();
    } on ApiException catch (e) {
      _set(() => error = e.message);
      return null;
    } catch (e) {
      _set(() => error = '$e');
      return null;
    } finally {
      _set(() => busy = false);
    }
  }

  /// Vérifie le serveur et choisit l'étape suivante (création du premier
  /// administrateur ou connexion).
  Future<void> connectServer(String input) async {
    await _run(() async {
      final url = AdminClient.parseServer(input);
      if (url == null) throw const ApiException(0, 'Adresse du serveur invalide');
      final c = AdminClient(url, client: _httpFactory?.call());
      final health = await c.get('/admin/health');
      if (health['status'] != 'ok') throw const ApiException(0, 'Ce serveur n\'est pas une API VIGIROAD');
      final setup = await c.get('/admin/setup');
      client?.close();
      client = c..onUnauthorized = _expired;
      server = url;
      setupAvailable = setup['needed'] == true && setup['enabled'] == true;
      stage = setup['needed'] == true ? SessionStage.setup : SessionStage.login;
      try {
        final p = await SharedPreferences.getInstance();
        await p.setString('admin.server', url.toString());
      } catch (_) {}
    });
  }

  void changeServer() => _set(() {
    _stopLive();
    stage = SessionStage.server;
    error = null;
  });

  Future<void> setup({required String token, required String email, required String name, required String password}) =>
      _run(() async {
        final r = await api.post('/admin/setup', {
          'setupToken': token,
          'email': email,
          'displayName': name,
          'password': password,
          'client': clientName,
        });
        _enroll(r);
        await _remember(email);
      });

  Future<void> login(String email, String password) => _run(() async {
    final r = await api.post('/admin/auth/login', {'email': email, 'password': password, 'client': clientName});
    await _remember(email);
    if (r['mfa'] == 'enroll') {
      _enroll(r);
    } else {
      _ticket = r['ticket'] as String;
      stage = SessionStage.mfa;
    }
  });

  void _enroll(Map<String, dynamic> r) {
    _ticket = r['ticket'] as String;
    final e = r['enrollment'] as Map<String, dynamic>;
    enrollSecret = e['secret'] as String;
    enrollUri = e['uri'] as String;
    stage = SessionStage.enroll;
  }

  Future<void> _remember(String email) async {
    lastEmail = email;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('admin.email', email);
    } catch (_) {}
  }

  /// Code à 6 chiffres de l'application d'authentification.
  Future<void> verify(String code) => _run(() async {
    final r = await api.post('/admin/auth/mfa', {'ticket': _ticket, 'code': code});
    api.token = r['token'] as String;
    admin = r['admin'] as Map<String, dynamic>;
    enrollSecret = null;
    enrollUri = null;
    _ticket = null;
    stage = SessionStage.ready;
    _lastInput = _now();
    _startLive();
    _idleTimer?.cancel();
    _idleTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_now().difference(_lastInput) > inactivity) {
        unawaited(logout(message: 'Session fermée après ${inactivity.inMinutes} minutes d\'inactivité.'));
      }
    });
  });

  void backToLogin() => _set(() {
    stage = SessionStage.login;
    error = null;
  });

  /// Activité de l'utilisateur (clavier, souris).
  void touch() => _lastInput = _now();

  Future<void> logout({String? message}) async {
    _stopLive();
    _idleTimer?.cancel();
    final c = client;
    if (c != null && c.token != null) {
      try {
        await c.post('/admin/auth/logout');
      } catch (_) {}
      c.token = null;
    }
    _set(() {
      admin = null;
      snapshot.value = null;
      stage = SessionStage.login;
      error = null;
      info = message;
    });
  }

  void _expired(ApiException e) {
    if (stage != SessionStage.ready) return;
    _stopLive();
    _idleTimer?.cancel();
    client?.token = null;
    _set(() {
      admin = null;
      stage = SessionStage.login;
      info = e.message;
    });
  }

  // ------------------------------------------------------------ temps réel

  void _startLive() {
    _stopLive();
    live.value = LiveState.connecting;
    final c = client;
    if (c == null) return;
    _sse = c.events('/admin/events').listen(
      (e) {
        _retries = 0;
        live.value = LiveState.live;
        if (e.$1 == 'snapshot') snapshot.value = e.$2;
      },
      onError: (Object _) => _scheduleReconnect(),
      onDone: _scheduleReconnect,
      cancelOnError: true,
    );
  }

  void _scheduleReconnect() {
    if (stage != SessionStage.ready) return;
    live.value = LiveState.offline;
    _reconnect?.cancel();
    final delay = Duration(seconds: (2 << _retries.clamp(0, 4)).clamp(2, 30));
    _retries++;
    _reconnect = Timer(delay, () {
      if (stage == SessionStage.ready) _startLive();
    });
  }

  void _stopLive() {
    _reconnect?.cancel();
    unawaited(_sse?.cancel());
    _sse = null;
    live.value = LiveState.off;
  }

  @override
  void dispose() {
    _stopLive();
    _idleTimer?.cancel();
    client?.close();
    super.dispose();
  }
}

/// Accès à la session depuis les widgets.
class SessionScope extends InheritedNotifier<AdminSession> {
  const SessionScope({super.key, required AdminSession session, required super.child}) : super(notifier: session);

  static AdminSession of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SessionScope>()!.notifier!;

  /// Sans abonnement aux changements.
  static AdminSession read(BuildContext context) => context.getInheritedWidgetOfExactType<SessionScope>()!.notifier!;
}
