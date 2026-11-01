import 'package:flutter/material.dart';
import 'package:vigiroad_admin_core/vigiroad_admin_core.dart';

const appName = 'VIGIROAD SERVER CONTROL';
const appVersion = '1.0.0';

/// Supervision et administration du VPS : ressources, processus, Docker,
/// services VIGIROAD, maintenance, sauvegardes et mises à jour.
List<AdminPage> serverControlPages(DesktopUpdater updater) => [
  AdminPage(id: 'overview', label: 'Supervision', icon: Icons.monitor_heart_rounded, builder: (_) => const OverviewPage()),
  AdminPage(id: 'processes', label: 'Processus et services', icon: Icons.memory_rounded, builder: (_) => const ProcessesPage()),
  AdminPage(id: 'docker', label: 'Docker', icon: Icons.view_in_ar_rounded, builder: (_) => const DockerPage()),
  AdminPage(id: 'vigiroad', label: 'Services VIGIROAD', icon: Icons.traffic_rounded, builder: (_) => const VigiroadPage()),
  AdminPage(id: 'maintenance', label: 'Maintenance', icon: Icons.build_circle_rounded, builder: (_) => const MaintenancePage()),
  AdminPage(id: 'audit', label: 'Journal', icon: Icons.receipt_long_rounded, builder: (_) => const AuditPage()),
  AdminPage(
    id: 'admins',
    label: 'Administrateurs',
    icon: Icons.admin_panel_settings_rounded,
    permission: 'adminsManage',
    builder: (_) => const AdminsPage(),
  ),
  AdminPage(
    id: 'settings',
    label: 'Paramètres',
    icon: Icons.settings_rounded,
    builder: (_) => SettingsPage(appName: appName, updater: updater),
  ),
];

Widget buildApp({AdminSession? session, DesktopUpdater? updater}) {
  final u = updater ?? DesktopUpdater(appId: 'server-control', currentVersion: appVersion);
  return AdminApp(
    appName: appName,
    subtitle: 'Administration et surveillance du serveur VIGIROAD',
    session: session ?? AdminSession(clientName: 'linux'),
    updater: u,
    pages: serverControlPages(u),
  );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(buildApp());
}
