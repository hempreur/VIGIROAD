import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/vr_colors.dart';
import '../../../core/theme/vr_typography.dart';
import '../../../core/widgets/glow_panel.dart';
import '../../../core/widgets/vr_button.dart';
import '../../../core/widgets/vr_page.dart';
import '../application/account_controller.dart';

/// Enregistrement de l'export JSON (remplaçable en test).
final accountExportSaverProvider = Provider<Future<bool> Function(String name, String content)>(
  (ref) => (name, content) async =>
      await FilePicker.saveFile(fileName: name, bytes: Uint8List.fromList(utf8.encode(content)), mimeType: 'application/json') !=
      null,
);

/// Compte VIGIROAD facultatif : connexion, inscription, appareil, sessions,
/// consentements, export et suppression des données.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

enum _Mode { login, register, reset }

class _AccountScreenState extends ConsumerState<AccountScreen> {
  _Mode _mode = _Mode.login;
  final _login = TextEditingController();
  final _password = TextEditingController();
  final _pseudonym = TextEditingController();
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _code = TextEditingController();
  bool _region = false;
  bool _location = false;
  bool _device = true;

  @override
  void dispose() {
    for (final c in [_login, _password, _pseudonym, _email, _name, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(accountProvider);
    ref.listen(accountProvider.select((x) => (x.message, x.error)), (_, m) {
      final text = m.$1 ?? m.$2;
      if (text != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    });
    return VrPage(
      title: 'Compte VIGIROAD',
      children: switch (s.status) {
        AccountStatus.unavailable => [
          const GlowPanel(
            padding: EdgeInsets.all(16),
            child: Text(
              'Aucun serveur VIGIROAD n\'est configuré dans cette version : les comptes sont indisponibles. '
              'Toutes les fonctions de l\'application restent utilisables sans compte.',
              style: VrText.caption,
            ),
          ),
        ],
        AccountStatus.loading => [const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))],
        AccountStatus.signedOut => _signedOut(s),
        AccountStatus.signedIn => _signedIn(s),
      },
    );
  }

  Widget _field(TextEditingController c, String label, {bool obscure = false, String? key, TextInputType? type}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      key: key == null ? null : Key(key),
      controller: c,
      obscureText: obscure,
      keyboardType: type,
      autocorrect: false,
      decoration: InputDecoration(labelText: label),
    ),
  );

  List<Widget> _signedOut(AccountState s) {
    final c = ref.read(accountProvider.notifier);
    return [
      const Text(
        'Le compte est facultatif : il permet de retrouver vos sessions et vos appareils. VIGIROAD n\'envoie '
        'jamais vos images de caméra, les plaques lues ni vos enregistrements vocaux.',
        style: VrText.caption,
      ),
      const SizedBox(height: 14),
      SegmentedButton<_Mode>(
        segments: const [
          ButtonSegment(value: _Mode.login, label: Text('Connexion')),
          ButtonSegment(value: _Mode.register, label: Text('Créer un compte')),
          ButtonSegment(value: _Mode.reset, label: Text('Code reçu')),
        ],
        selected: {_mode},
        showSelectedIcon: false,
        onSelectionChanged: (m) => setState(() => _mode = m.first),
      ),
      const SizedBox(height: 14),
      GlowPanel(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: switch (_mode) {
            _Mode.login => [
              _field(_login, 'Pseudonyme ou e-mail', key: 'account-login', type: TextInputType.emailAddress),
              _field(_password, 'Mot de passe', key: 'account-password', obscure: true),
              _deviceSwitch(),
              const SizedBox(height: 8),
              VrButton(
                key: const Key('account-login-submit'),
                label: s.busy ? 'Connexion…' : 'Se connecter',
                icon: Icons.login_rounded,
                style: VrButtonStyle.primary,
                expanded: true,
                onPressed: s.busy ? null : () => c.login(_login.text.trim(), _password.text, registerDevice: _device).ignore(),
              ),
            ],
            _Mode.register => [
              _field(_pseudonym, 'Pseudonyme (3 à 32 caractères)', key: 'account-pseudonym'),
              _field(_email, 'E-mail (facultatif)', key: 'account-email', type: TextInputType.emailAddress),
              _field(_name, 'Nom (facultatif)', key: 'account-name'),
              _field(_password, 'Mot de passe (8 caractères, lettres et chiffres)', key: 'account-new-password', obscure: true),
              _deviceSwitch(),
              _switch(
                'Partager ma région approximative',
                'Pays déduit de la connexion, pour les statistiques. Désactivé par défaut.',
                _region,
                (v) => setState(() => _region = v),
              ),
              _switch(
                'Partager ma position approximative',
                'Arrondie à environ 5 km, au plus toutes les 15 minutes. Désactivé par défaut.',
                _location,
                (v) => setState(() => _location = v),
              ),
              const SizedBox(height: 8),
              VrButton(
                key: const Key('account-register-submit'),
                label: s.busy ? 'Création…' : 'Créer mon compte',
                icon: Icons.person_add_alt_1_rounded,
                style: VrButtonStyle.primary,
                expanded: true,
                onPressed: s.busy
                    ? null
                    : () => c
                          .register(
                            pseudonym: _pseudonym.text.trim(),
                            password: _password.text,
                            email: _email.text.trim().isEmpty ? null : _email.text.trim(),
                            displayName: _name.text.trim().isEmpty ? null : _name.text.trim(),
                            regionConsent: _region,
                            locationConsent: _location,
                            registerDevice: _device,
                          )
                          .ignore(),
              ),
            ],
            _Mode.reset => [
              const Text(
                'Un administrateur VIGIROAD vous a transmis un code à usage unique (valable 30 minutes) : '
                'choisissez un nouveau mot de passe.',
                style: VrText.caption,
              ),
              const SizedBox(height: 10),
              _field(_login, 'Pseudonyme ou e-mail', key: 'account-reset-login'),
              _field(_code, 'Code (XXXX-XXXX-XXXX)', key: 'account-reset-code'),
              _field(_password, 'Nouveau mot de passe', key: 'account-reset-password', obscure: true),
              VrButton(
                label: 'Valider',
                icon: Icons.lock_reset_rounded,
                style: VrButtonStyle.primary,
                expanded: true,
                onPressed: s.busy ? null : () => c.resetWithCode(_login.text.trim(), _code.text.trim(), _password.text).ignore(),
              ),
            ],
          },
        ),
      ),
    ];
  }

  Widget _deviceSwitch() => _switch(
    'Enregistrer cet appareil',
    'Marque, modèle et version du système, avec un identifiant aléatoire propre à VIGIROAD (aucun identifiant matériel).',
    _device,
    (v) => setState(() => _device = v),
  );

  Widget _switch(String title, String detail, bool value, ValueChanged<bool> onChanged, {Key? key}) => SwitchListTile(
    key: key,
    contentPadding: EdgeInsets.zero,
    title: Text(title, style: VrText.label),
    subtitle: Text(detail, style: VrText.caption),
    value: value,
    onChanged: onChanged,
  );

  List<Widget> _signedIn(AccountState s) {
    final c = ref.read(accountProvider.notifier);
    final u = s.user ?? const <String, dynamic>{};
    return [
      GlowPanel(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: VrColors.cyan.withValues(alpha: 0.15),
              child: Text(
                '${u['pseudonym'] ?? '?'}'.substring(0, 1).toUpperCase(),
                style: VrText.sectionTitle.copyWith(color: VrColors.cyan, fontSize: 24),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${u['pseudonym'] ?? ''}', key: const Key('account-pseudonym-label'), style: VrText.sectionTitle.copyWith(fontSize: 22)),
                  if (u['email'] != null) Text('${u['email']}', style: VrText.caption),
                  Text('Connecté — temps d\'utilisation mesuré pendant l\'usage', style: VrText.caption.copyWith(color: VrColors.trafficFluid)),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      GlowPanel(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Column(
          children: [
            _switch(
              'Appareil enregistré',
              'Visible dans vos appareils ; vous pouvez le retirer à tout moment.',
              s.deviceRegistered,
              s.busy ? (_) {} : (v) => c.setDeviceRegistered(v).ignore(),
              key: const Key('account-device-switch'),
            ),
            _switch(
              'Région approximative',
              'Pays déduit de la connexion. Le retrait efface les pays enregistrés.',
              s.regionConsent,
              s.busy ? (_) {} : (v) => c.setConsent(region: v).ignore(),
              key: const Key('account-region-switch'),
            ),
            _switch(
              'Position approximative',
              '≈ 5 km, au plus toutes les 15 minutes, pendant l\'utilisation. Le retrait efface l\'historique.',
              s.locationConsent,
              s.busy ? (_) {} : (v) => c.setConsent(location: v).ignore(),
              key: const Key('account-location-switch'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      Text('SESSIONS OUVERTES', style: VrText.sectionTitle.copyWith(fontSize: 16)),
      const SizedBox(height: 8),
      GlowPanel(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (s.sessions.isEmpty)
              TextButton.icon(
                onPressed: () => c.loadSessions().ignore(),
                icon: const Icon(Icons.devices_rounded),
                label: const Text('Afficher mes sessions'),
              ),
            for (final x in s.sessions)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  x['os'] == 'ios' ? Icons.phone_iphone_rounded : Icons.phone_android_rounded,
                  color: x['online'] == true ? VrColors.trafficFluid : VrColors.textMuted,
                ),
                title: Text(
                  '${'${x['brand'] ?? ''} ${x['model'] ?? 'Appareil non enregistré'}'.trim()}'
                  '${x['id'] == s.currentSession ? ' (cet appareil)' : ''}',
                  style: VrText.label,
                ),
                subtitle: Text('Ouverte le ${_date(x['startedAt'])}', style: VrText.caption),
                trailing: x['id'] == s.currentSession
                    ? null
                    : IconButton(
                        tooltip: 'Fermer cette session',
                        icon: const Icon(Icons.logout_rounded, color: VrColors.alertText),
                        onPressed: () => c.revokeSession(x['id'] as String).ignore(),
                      ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      VrButton(
        label: 'Exporter mes données',
        icon: Icons.download_rounded,
        expanded: true,
        onPressed: () async {
          final data = await c.exportData();
          if (data != null) await ref.read(accountExportSaverProvider)('vigiroad-mes-donnees.json', data);
        },
      ),
      const SizedBox(height: 8),
      VrButton(
        label: 'Nouvel identifiant d\'appareil',
        icon: Icons.autorenew_rounded,
        expanded: true,
        onPressed: s.busy ? null : () => c.renewInstallationId().ignore(),
      ),
      const SizedBox(height: 8),
      VrButton(
        key: const Key('account-logout'),
        label: 'Se déconnecter',
        icon: Icons.logout_rounded,
        expanded: true,
        onPressed: () => c.logout().ignore(),
      ),
      const SizedBox(height: 8),
      VrButton(
        key: const Key('account-delete'),
        label: 'Supprimer mon compte et mes données',
        icon: Icons.delete_forever_rounded,
        style: VrButtonStyle.alert,
        expanded: true,
        onPressed: () => _confirmDelete(c).ignore(),
      ),
    ];
  }

  static String _date(Object? v) {
    final d = v is String ? DateTime.tryParse(v)?.toLocal() : null;
    if (d == null) return '—';
    String two(int x) => x.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} à ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _confirmDelete(AccountController c) async {
    final pass = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Supprimer votre compte ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Le compte et toutes les données associées (appareils, sessions, statistiques, positions) seront '
              'définitivement supprimés du serveur.',
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('account-delete-password'),
              controller: pass,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Mot de passe'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Supprimer', style: TextStyle(color: VrColors.alert)),
          ),
        ],
      ),
    );
    final password = pass.text;
    pass.dispose();
    if (ok ?? false) await c.deleteAccount(password);
  }
}
