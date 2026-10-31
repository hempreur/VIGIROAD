import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/theme/vr_colors.dart';
import '../../../core/theme/vr_typography.dart';
import '../../../core/widgets/glow_panel.dart';
import '../../../core/widgets/vr_page.dart';
import '../../plates/application/alert_service.dart';
import '../../plates/application/watchlist_controller.dart';
import '../../plates/domain/watchlist_import.dart';
import '../../sentrix/application/sentrix_controller.dart';
import '../application/settings_controller.dart';
import '../domain/app_settings.dart';

/// Enregistrement d'un fichier exporté (remplaçable en test).
final fileSaverProvider = Provider<Future<bool> Function(String name, String content)>(
  (ref) => (name, content) async =>
      await FilePicker.saveFile(fileName: name, bytes: Uint8List.fromList(utf8.encode(content)), mimeType: 'text/csv') != null,
);

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static String _statusLabel(CapabilityStatus? s) => switch (s) {
    CapabilityStatus.granted => 'Autorisé',
    CapabilityStatus.permanentlyDenied => 'Refusé — à modifier dans les réglages',
    CapabilityStatus.restricted => 'Restreint par le système',
    CapabilityStatus.denied => 'Non autorisé',
    null => 'Vérification…',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final perms = ref.watch(permissionsProvider).value;
    final permCtrl = ref.read(permissionsProvider.notifier);
    final s = ref.watch(appSettingsProvider);
    final ctrl = ref.read(settingsControllerProvider.notifier);
    void set(AppSettings Function(AppSettings) f) => ctrl.change(f).ignore();

    final messenger = ScaffoldMessenger.of(context);
    void snack(String t) => messenger.showSnackBar(SnackBar(content: Text(t)));

    Future<bool> confirm(String title, String body, String action) async =>
        await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
              TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(action, style: const TextStyle(color: VrColors.alert)),
              ),
            ],
          ),
        ) ??
        false;

    return VrPage(
      title: 'Réglages',
      children: [
        const _Section('LECTURE DES PLAQUES'),
        _Panel([
          _Switch(
            'Démarrer la lecture automatiquement',
            'Active la caméra arrière à l\'ouverture de la navigation',
            s.autoStartDetection,
            (v) => set((x) => x.copyWith(autoStartDetection: v)),
          ),
          _Choice<PerformanceMode>(
            'Performance',
            'Économie : moins de batterie et de chaleur, lecture plus lente',
            PerformanceMode.values,
            s.performance,
            (m) => m.label,
            (m) => set((x) => x.copyWith(performance: m)),
          ),
          _Slider(
            'Seuil de confiance des alertes',
            '${(s.minConfidence * 100).round()} %',
            s.minConfidence,
            0.6,
            0.95,
            7,
            (v) => set((x) => x.copyWith(minConfidence: v)),
          ),
          _Slider(
            'Lectures concordantes exigées',
            '${s.minVotes} images',
            s.minVotes.toDouble(),
            2,
            6,
            4,
            (v) => set((x) => x.copyWith(minVotes: v.round())),
          ),
        ]),

        const _Section('ALERTES'),
        _Panel([
          _Switch('Son d\'alerte', null, s.alertSound, (v) => set((x) => x.copyWith(alertSound: v))),
          if (s.alertSound)
            _Slider(
              'Volume',
              '${(s.alertVolume * 100).round()} %',
              s.alertVolume,
              0,
              1,
              10,
              (v) => set((x) => x.copyWith(alertVolume: v)),
            ),
          _Switch('Annonce vocale par SENTRIX', null, s.sentrixAnnounce, (v) => set((x) => x.copyWith(sentrixAnnounce: v))),
        ]),

        const _Section('NAVIGATION'),
        _Panel([
          _Switch('Guidage vocal', null, s.voiceGuidance, (v) => set((x) => x.copyWith(voiceGuidance: v))),
          _Switch('Vue conduite 3D par défaut', null, s.drive3d, (v) => set((x) => x.copyWith(drive3d: v))),
          _Switch(
            'Guidage en arrière-plan',
            'Consignes vocales écran éteint ou dans une autre application (notification « Guidage en cours »)',
            s.backgroundGuidance,
            (v) => set((x) => x.copyWith(backgroundGuidance: v)),
          ),
        ]),

        const _Section('HISTORIQUE ET DONNÉES'),
        _Panel([
          _Switch(
            'Enregistrer les correspondances',
            'Seules les plaques de votre liste sont enregistrées',
            s.logHistory,
            (v) => set((x) => x.copyWith(logHistory: v)),
          ),
          _Switch('Enregistrer la position GPS', null, s.saveLocation, (v) => set((x) => x.copyWith(saveLocation: v))),
          _Choice<Retention>(
            'Conservation',
            'Les correspondances plus anciennes sont effacées',
            Retention.values,
            s.retention,
            (r) => r.label,
            (r) => set((x) => x.copyWith(retention: r)),
          ),
          _Switch(
            'Autoriser l\'export de l\'historique',
            'Données personnelles : à n\'activer qu\'en cas de besoin',
            s.allowExport,
            (v) => set((x) => x.copyWith(allowExport: v)),
          ),
          _Action('Exporter la liste de plaques (CSV)', Icons.download_rounded, () async {
            final list = await ref.read(watchlistProvider.future);
            final ok = await ref.read(fileSaverProvider)('vigiroad_plaques.csv', exportWatchlistCsv(list));
            if (ok) snack('${list.length} plaque(s) exportée(s)');
          }),
          _Action('Effacer l\'historique', Icons.delete_sweep_rounded, () async {
            if (!await confirm('Effacer l\'historique ?', 'Toutes les correspondances enregistrées seront supprimées.', 'Effacer')) return;
            await (await ref.read(detectionLogProvider.future)).clear();
            ref.invalidate(detectionsProvider);
            snack('Historique effacé');
          }, danger: true),
          _Action('Supprimer toutes les plaques', Icons.delete_forever_rounded, () async {
            if (!await confirm('Supprimer toutes les plaques ?', 'La liste de surveillance sera vidée.', 'Supprimer')) return;
            await ref.read(watchlistProvider.notifier).clear();
            snack('Liste de plaques vidée');
          }, danger: true),
        ]),

        const _Section('LANGUES'),
        const _Panel([
          InfoRow(label: 'Langue de l\'interface', value: 'Français (seule langue disponible)'),
          InfoRow(label: 'Langue de SENTRIX', value: 'Français (reconnaissance fr-FR, synthèse fr-FR)'),
        ]),

        const _Section('AUTORISATIONS'),
        _Panel([
          for (final c in AppCapability.values)
            InfoRow(
              label: c.title,
              value: _statusLabel(perms?[c]),
              trailing: perms?[c] == CapabilityStatus.granted
                  ? const Icon(Icons.check_circle_rounded, color: VrColors.trafficFluid)
                  : TextButton(
                      onPressed: perms?[c] == CapabilityStatus.denied ? () => permCtrl.request(c) : permCtrl.openSettings,
                      child: const Text('Modifier', style: TextStyle(color: VrColors.cyan)),
                    ),
            ),
        ]),

        const _Section('COMMANDES VOCALES'),
        const Text(
          'Touchez SENTRIX sur l\'écran de navigation puis parlez. Liste provisoire, à valider avec le propriétaire du projet.',
          style: VrText.caption,
        ),
        const SizedBox(height: 8),
        _Panel([
          for (final c in ref.watch(sentrixCommandsProvider)) InfoRow(label: c.label, value: '« ${c.phrases.first} »'),
        ]),

        const _Section('SERVICES'),
        _Panel([
          InfoRow(label: 'Fond de carte', value: Uri.parse(config.mapStyleUrl).host),
          InfoRow(label: 'Itinéraires', value: Uri.parse(config.routingBaseUrl).host),
          InfoRow(label: 'Recherche d\'adresses', value: Uri.parse(config.geocodingBaseUrl).host),
          InfoRow(
            label: 'Trafic en temps réel',
            value: config.trafficEnabled ? Uri.parse(config.trafficApiUrl).host : 'Aucun serveur configuré',
          ),
          InfoRow(
            label: 'Synchronisation des plaques',
            value: config.platesSyncEnabled ? Uri.parse(config.platesSyncUrl).host : 'Désactivée',
          ),
        ]),

        const _Section('À PROPOS'),
        _Panel([
          InfoRow(label: 'Environnement', value: config.environment.name),
          const InfoRow(label: 'Version', value: '1.1.0'),
          const InfoRow(label: 'Éditeur', value: 'VIGIROAD INC (CODEX HEMPREUR)'),
          const InfoRow(label: 'Données cartographiques', value: '© contributeurs OpenStreetMap, style © CARTO'),
          _Action('Réinitialiser les réglages', Icons.restart_alt_rounded, () async {
            if (!await confirm('Réinitialiser ?', 'Les réglages reprendront leurs valeurs par défaut.', 'Réinitialiser')) return;
            await ctrl.reset();
          }),
        ]),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 10),
    child: Text(title, style: VrText.sectionTitle),
  );
}

class _Panel extends StatelessWidget {
  const _Panel(this.children);
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => GlowPanel(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    child: Column(children: children),
  );
}

class _Switch extends StatelessWidget {
  const _Switch(this.label, this.detail, this.value, this.onChanged);
  final String label;
  final String? detail;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label, style: VrText.label),
    subtitle: detail == null ? null : Text(detail!, style: VrText.caption),
    value: value,
    onChanged: onChanged,
  );
}

class _Slider extends StatelessWidget {
  const _Slider(this.label, this.valueLabel, this.value, this.min, this.max, this.divisions, this.onChanged);
  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [Expanded(child: Text(label, style: VrText.label)), Text(valueLabel, style: VrText.caption)]),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          activeColor: VrColors.cyan,
          inactiveColor: VrColors.cyan.withValues(alpha: 0.2),
          label: valueLabel,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

class _Choice<T> extends StatelessWidget {
  const _Choice(this.label, this.detail, this.values, this.value, this.name, this.onChanged);
  final String label;
  final String detail;
  final List<T> values;
  final T value;
  final String Function(T) name;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: VrText.label),
        Text(detail, style: VrText.caption),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final v in values)
              ChoiceChip(
                label: Text(name(v)),
                selected: v == value,
                onSelected: (_) => onChanged(v),
                selectedColor: VrColors.cyan.withValues(alpha: 0.25),
                side: BorderSide(color: VrColors.border(v == value ? 0.9 : 0.3)),
                labelStyle: VrText.caption.copyWith(color: VrColors.textPrimary),
                showCheckmark: false,
              ),
          ],
        ),
      ],
    ),
  );
}

class _Action extends StatelessWidget {
  const _Action(this.label, this.icon, this.onTap, {this.danger = false});
  final String label;
  final IconData icon;
  final Future<void> Function() onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: danger ? VrColors.alert : VrColors.cyan),
    title: Text(label, style: VrText.label.copyWith(color: danger ? VrColors.alertText : VrColors.textPrimary)),
    onTap: () => onTap().ignore(),
  );
}
