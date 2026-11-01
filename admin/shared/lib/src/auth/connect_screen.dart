import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../api/session.dart';
import '../theme.dart';
import '../widgets/panel.dart';

/// Écrans de connexion : serveur, premier administrateur, mot de passe,
/// double authentification (TOTP) et enrôlement de l'application
/// d'authentification.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key, required this.appName, required this.appSubtitle});
  final String appName;
  final String appSubtitle;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _server = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  final _name = TextEditingController();
  final _token = TextEditingController();
  final _code = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = SessionScope.read(context);
    if (_server.text.isEmpty && s.server != null) _server.text = s.server.toString();
    if (_email.text.isEmpty && s.lastEmail != null) _email.text = s.lastEmail!;
  }

  @override
  void dispose() {
    for (final c in [_server, _email, _password, _password2, _name, _token, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.6, -0.8),
            radius: 1.6,
            colors: [Color(0xFF06243A), VrColors.background],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [BoxShadow(color: VrColors.cyan.withValues(alpha: 0.35), blurRadius: 40)],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: Image.asset('packages/vigiroad_admin_core/assets/vigiroad_logo.png', width: 120, height: 120),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(widget.appName, style: VrText.display, textAlign: TextAlign.center),
                  Text(widget.appSubtitle, style: VrText.caption, textAlign: TextAlign.center),
                  const SizedBox(height: 26),
                  Panel(glow: true, padding: const EdgeInsets.all(26), child: _form(s)),
                  const SizedBox(height: 18),
                  Text('VIGIROAD INC (CODEX HEMPREUR)', style: VrText.caption, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _messages(AdminSession s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (s.info != null) _note(s.info!, VrColors.cyan, Icons.info_outline_rounded),
      if (s.error != null) _note(s.error!, VrColors.criticalText, Icons.error_outline_rounded, key: const Key('connect-error')),
    ],
  );

  Widget _note(String text, Color color, IconData icon, {Key? key}) => Padding(
    key: key,
    padding: const EdgeInsets.only(bottom: 14),
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: VrText.body)),
        ],
      ),
    ),
  );

  Widget _title(String t, String sub) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t, style: VrText.title),
        const SizedBox(height: 4),
        Text(sub, style: VrText.caption),
      ],
    ),
  );

  Widget _field(TextEditingController c, String label, {bool obscure = false, String? key, VoidCallback? onSubmit, IconData? icon, bool autofocus = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          key: key == null ? null : Key(key),
          controller: c,
          obscureText: obscure,
          autofocus: autofocus,
          onSubmitted: onSubmit == null ? null : (_) => onSubmit(),
          decoration: InputDecoration(labelText: label, prefixIcon: icon == null ? null : Icon(icon, size: 18)),
        ),
      );

  Widget _form(AdminSession s) {
    switch (s.stage) {
      case SessionStage.server:
        void go() => unawaited(s.connectServer(_server.text));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title('Connexion au serveur', 'Adresse de votre VPS VIGIROAD (HTTPS), par exemple 15-235-120-182.sslip.io'),
            _messages(s),
            _field(_server, 'Adresse du serveur', key: 'server-url', onSubmit: go, icon: Icons.dns_rounded, autofocus: true),
            const SizedBox(height: 6),
            VrButton(key: const Key('server-connect'), label: 'Se connecter au serveur', icon: Icons.link_rounded, busy: s.busy, onPressed: go),
          ],
        );
      case SessionStage.setup:
        void go() {
          if (_password.text != _password2.text) {
            setState(() => s.error = 'Les deux mots de passe ne correspondent pas');
            return;
          }
          unawaited(s.setup(token: _token.text.trim(), email: _email.text.trim(), name: _name.text.trim(), password: _password.text));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title(
              'Créer le premier administrateur',
              s.setupAvailable
                  ? 'Saisissez le jeton d\'installation affiché par install.sh sur le VPS. Ce compte sera « Propriétaire ».'
                  : 'Aucun administrateur n\'existe et le jeton d\'installation n\'est pas configuré sur le serveur (relancez install.sh).',
            ),
            _messages(s),
            _field(_token, 'Jeton d\'installation', key: 'setup-token', icon: Icons.key_rounded, autofocus: true),
            _field(_name, 'Nom affiché', key: 'setup-name', icon: Icons.badge_outlined),
            _field(_email, 'Adresse e-mail', key: 'setup-email', icon: Icons.alternate_email_rounded),
            _field(_password, 'Mot de passe (12 caractères minimum)', key: 'setup-password', obscure: true, icon: Icons.lock_outline_rounded),
            _field(_password2, 'Confirmer le mot de passe', key: 'setup-password2', obscure: true, onSubmit: go, icon: Icons.lock_outline_rounded),
            VrButton(key: const Key('setup-submit'), label: 'Créer le compte', icon: Icons.person_add_alt_1_rounded, busy: s.busy, onPressed: go),
            TextButton(onPressed: s.changeServer, child: Text('Changer de serveur (${s.server?.host})')),
          ],
        );
      case SessionStage.login:
        void go() => unawaited(s.login(_email.text.trim(), _password.text));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title('Connexion administrateur', s.server?.host ?? ''),
            _messages(s),
            _field(_email, 'Adresse e-mail', key: 'login-email', icon: Icons.alternate_email_rounded, autofocus: _email.text.isEmpty),
            _field(_password, 'Mot de passe', key: 'login-password', obscure: true, onSubmit: go, icon: Icons.lock_outline_rounded, autofocus: _email.text.isNotEmpty),
            VrButton(key: const Key('login-submit'), label: 'Continuer', icon: Icons.login_rounded, busy: s.busy, onPressed: go),
            TextButton(onPressed: s.changeServer, child: const Text('Changer de serveur')),
          ],
        );
      case SessionStage.mfa:
        void go() => unawaited(s.verify(_code.text.replaceAll(' ', '')));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title('Double authentification', 'Code à 6 chiffres de votre application d\'authentification'),
            _messages(s),
            _codeField(go),
            VrButton(key: const Key('mfa-submit'), label: 'Valider', icon: Icons.verified_user_rounded, busy: s.busy, onPressed: go),
            TextButton(onPressed: s.backToLogin, child: const Text('Retour')),
          ],
        );
      case SessionStage.enroll:
        void go() => unawaited(s.verify(_code.text.replaceAll(' ', '')));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title(
              'Activer la double authentification',
              'Obligatoire pour les administrateurs. Scannez ce QR code avec Google Authenticator, Microsoft '
                  'Authenticator, Aegis ou 1Password, puis saisissez le code affiché.',
            ),
            _messages(s),
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: QrImageView(data: s.enrollUri ?? '', size: 190, backgroundColor: Colors.white),
              ),
            ),
            const SizedBox(height: 12),
            Text('Ou saisissez cette clé :', style: VrText.caption, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: SelectableText(
                    _group(s.enrollSecret ?? ''),
                    key: const Key('totp-secret'),
                    style: VrText.mono.copyWith(fontSize: 14, letterSpacing: 1.2),
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  tooltip: 'Copier la clé',
                  onPressed: () => unawaited(Clipboard.setData(ClipboardData(text: s.enrollSecret ?? ''))),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _codeField(go),
            VrButton(key: const Key('mfa-submit'), label: 'Activer et se connecter', icon: Icons.verified_user_rounded, busy: s.busy, onPressed: go),
          ],
        );
      case SessionStage.ready:
        return const SizedBox();
    }
  }

  Widget _codeField(VoidCallback go) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      key: const Key('mfa-code'),
      controller: _code,
      autofocus: true,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')), LengthLimitingTextInputFormatter(7)],
      textAlign: TextAlign.center,
      style: VrText.display.copyWith(letterSpacing: 10),
      onSubmitted: (_) => go(),
      decoration: const InputDecoration(hintText: '000000'),
    ),
  );

  static String _group(String s) => [for (var i = 0; i < s.length; i += 4) s.substring(i, (i + 4).clamp(0, s.length))].join(' ');
}
