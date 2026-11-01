import 'package:flutter/material.dart';
import 'package:vigiroad_admin_core/vigiroad_admin_core.dart';

const appName = 'VIGIROAD ADMIN MANAGER';
const appVersion = '1.0.0';

/// Administration à distance : tableau de bord, utilisateurs, appareils,
/// sessions, géographie, état du serveur, journal et administrateurs.
List<AdminPage> adminManagerPages(DesktopUpdater updater) => [
  AdminPage(id: 'dashboard', label: 'Tableau de bord', icon: Icons.space_dashboard_rounded, builder: (_) => const DashboardPage()),
  AdminPage(id: 'users', label: 'Utilisateurs', icon: Icons.people_alt_rounded, builder: (_) => const UsersPage()),
  AdminPage(id: 'devices', label: 'Appareils', icon: Icons.smartphone_rounded, builder: (_) => const DevicesPage()),
  AdminPage(id: 'sessions', label: 'Connexions et sessions', icon: Icons.timelapse_rounded, builder: (_) => const SessionsPage()),
  AdminPage(id: 'geo', label: 'Géographie', icon: Icons.public_rounded, builder: (_) => const GeoPage()),
  AdminPage(id: 'server', label: 'Serveur', icon: Icons.dns_rounded, builder: (_) => const ServerSummaryPage()),
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
  final u = updater ?? DesktopUpdater(appId: 'admin-manager', currentVersion: appVersion);
  return AdminApp(
    appName: appName,
    subtitle: 'Gestion des comptes, appareils et sessions VIGIROAD',
    session: session ?? AdminSession(clientName: 'windows'),
    updater: u,
    pages: adminManagerPages(u),
  );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(buildApp());
}
