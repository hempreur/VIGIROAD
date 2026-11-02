import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api/session.dart';
import 'auth/connect_screen.dart';
import 'shell/shell.dart';
import 'theme.dart';
import 'update/updater.dart';

/// Application d'administration VIGIROAD (fenêtre native Windows ou Linux).
class AdminApp extends StatefulWidget {
  const AdminApp({
    super.key,
    required this.appName,
    required this.subtitle,
    required this.session,
    required this.updater,
    required this.pages,
  });

  final String appName;
  final String subtitle;
  final AdminSession session;
  final DesktopUpdater updater;
  final List<AdminPage> pages;

  @override
  State<AdminApp> createState() => _AdminAppState();
}

class _AdminAppState extends State<AdminApp> {
  Object? _attached;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_sync);
    widget.session.requiredUpdate.addListener(_required);
    unawaited(widget.session.init());
  }

  @override
  void dispose() {
    widget.session.removeListener(_sync);
    widget.session.requiredUpdate.removeListener(_required);
    widget.updater.detach();
    super.dispose();
  }

  /// Mises à jour vérifiées auprès du serveur dès la connexion.
  void _sync() {
    final c = widget.session.client;
    final ready = widget.session.stage == SessionStage.ready;
    final key = ready ? c : null;
    if (identical(key, _attached)) return;
    _attached = key;
    if (c != null && ready) {
      widget.updater.attach(c);
    } else {
      widget.updater.detach();
    }
  }

  /// Version refusée par le serveur (426) : installation immédiate, même
  /// depuis l'écran de connexion.
  void _required() {
    final u = widget.session.requiredUpdate.value;
    final c = widget.session.client;
    if (u == null || c == null) return;
    widget.updater.prepare(c);
    unawaited(widget.updater.installRequired(u));
  }

  @override
  Widget build(BuildContext context) => SessionScope(
    session: widget.session,
    child: MaterialApp(
      title: widget.appName,
      debugShowCheckedModeBanner: false,
      theme: vrTheme(),
      darkTheme: vrTheme(),
      themeMode: ThemeMode.dark,
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // Toute action de l'utilisateur repousse le verrouillage d'inactivité.
      builder: (context, child) => Listener(
        onPointerDown: (_) => widget.session.touch(),
        onPointerSignal: (_) => widget.session.touch(),
        child: Focus(
          onKeyEvent: (_, _) {
            widget.session.touch();
            return KeyEventResult.ignored;
          },
          child: child!,
        ),
      ),
      home: ListenableBuilder(
        listenable: widget.session,
        builder: (context, _) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: widget.session.stage == SessionStage.ready
              ? AdminShell(key: const ValueKey('shell'), appName: widget.appName, pages: widget.pages, updater: widget.updater)
              : ConnectScreen(key: const ValueKey('connect'), appName: widget.appName, appSubtitle: widget.subtitle),
        ),
      ),
    ),
  );
}
