# VIGIROAD Control Center

Écosystème d'administration de VIGIROAD : deux logiciels **natifs** (aucune interface web
d'administration) qui pilotent le même backend central hébergé sur le VPS.

| Logiciel | Système | Livraison | Rôle principal |
|---|---|---|---|
| **VIGIROAD ADMIN MANAGER** | Windows 10/11 | installateur `.exe` (Inno Setup) + version portable | utilisateurs, appareils, sessions, statistiques, géographie, état du serveur |
| **VIGIROAD SERVER CONTROL** | Ubuntu / Debian | `.deb`, AppImage | supervision du VPS, processus, Docker, services VIGIROAD, maintenance, sauvegardes, mises à jour |

Les deux partagent le même module (`admin/shared`) : connexion, double authentification, thème DARK,
graphiques, journal d'audit, gestion des administrateurs, paramètres. Selon le rôle de
l'administrateur, chaque logiciel affiche ou masque les actions (le serveur vérifie toujours les droits).

## Architecture

```
  Windows (ADMIN MANAGER)        Ubuntu / VPS (SERVER CONTROL)        Téléphones VIGIROAD
            │  HTTPS + jeton admin (TOTP)        │                         │ HTTPS + clé appli
            └───────────────────┬────────────────┘                         │ + jeton de session
                                ▼                                          ▼
                    ┌────────────────── Caddy (443, Let's Encrypt) ──────────────────┐
                    │  /admin/*  /v1/account/*  → admin-api      /v1/*  → traffic   │
                    └────────────────────────────────────────────────────────────────┘
       réseau « default » (Internet sortant)          réseau « backend » (interne, sans Internet)
        traffic ── admin-api ─────────────────────────┬──── postgres (PostgreSQL 16)
                                                       ├──── agent (métriques hôte, Docker limité)
                                                       └──── backup (pg_dump nocturne, tests de restauration)
```

- **PostgreSQL** n'est jamais exposé : seule l'API y accède, par le réseau interne.
- **L'agent de supervision** lit `/proc`, `/sys` et le disque de l'hôte en lecture seule et parle au
  socket Docker ; il n'écoute que sur le réseau interne, exige un jeton partagé et n'accepte qu'une
  liste fermée d'opérations (démarrer/arrêter le serveur de trafic, redémarrer les autres services ;
  jamais d'arrêt de PostgreSQL, de l'API, de Caddy ou de l'agent ; aucune commande arbitraire).
- **Mises à jour du serveur** depuis les applications : l'agent dépose une demande dans
  `/opt/vigiroad/run` ; une unité systemd de l'hôte relance `install.sh --update`.
- **Temps réel** : flux Server-Sent Events (`/admin/events`) toutes les 5 s, reconnexion automatique.

## Code source

| Dossier | Contenu |
|---|---|
| `server/admin_api/` | API d'administration et des comptes (Dart, shelf) |
| `server/monitoring/` | agent local de supervision (Dart, sans dépendance) |
| `server/database/` | migrations SQL, sauvegarde/restauration, vérificateur SQL |
| `server/deploy/` | Docker Compose, Caddy, `install.sh`, `install-desktop.sh` |
| `admin/shared/` | module Flutter commun aux deux logiciels |
| `admin/windows/` | VIGIROAD ADMIN MANAGER (Flutter Desktop, runner Win32, installateur) |
| `admin/linux/` | VIGIROAD SERVER CONTROL (Flutter Desktop, runner GTK, paquets) |
| `lib/features/account/` | comptes dans l'application mobile |

Documents : [INSTALLATION.md](INSTALLATION.md) · [SECURITE.md](SECURITE.md) ·
[SAUVEGARDES.md](SAUVEGARDES.md) · [API.md](API.md) · [VALIDATION.md](VALIDATION.md)
