# Tests et procédures de validation

Chaque modification est vérifiée par la CI GitHub Actions (workflow « Administration ») :

| Étape | Ce qui est vérifié |
|---|---|
| API (unitaires) | TOTP (vecteurs officiels RFC 6238), Argon2id, chiffrement AES-GCM, GeoIP, routeur, statistiques |
| API (PostgreSQL réel) | inscription, connexion, temps d'utilisation, localisation consentie, rôles, désactivation, réinitialisation, révocation, export CSV, audit, conservation, suppression en cascade, supervision, Docker, sauvegardes, diagnostic, SSE |
| Requêtes SQL | chaque requête de l'API est préparée sur une base migrée |
| Agent | lecture de /proc, journaux Docker, politique des conteneurs, déploiement |
| Pile complète | Docker Compose comme sur le VPS, HTTPS via Caddy, seul Caddy publie des ports |
| Bout en bout | premier administrateur + TOTP, comptes mobiles, **Docker réel** (redémarrage contrôlé, refus d'arrêt de PostgreSQL), sauvegarde puis test de restauration, mise à jour à distance, SSE |
| Charge | 60 utilisateurs simultanés (inscription + 20 battements chacun) et un administrateur : 0 erreur, battement p95 < 500 ms |
| Restauration | `restore.sh` complet : retour exact à l'état sauvegardé |
| Applications (tests) | connexion, TOTP, toutes les pages, rôles, alertes, inactivité ; captures de chaque écran |
| Linux natif | compilation GTK, `.deb` installé et lancé, AppImage, test de bout en bout réel sous Xvfb (agent, Docker, PostgreSQL) |
| Windows natif | compilation Win32, installateur Inno Setup installé silencieusement, test de bout en bout réel sur Windows (PostgreSQL, API) |

## Validation manuelle après déploiement

1. `sudo bash install.sh` sur le VPS : le résumé indique « Administration : {"status":"ok"…} ».
2. Créer le propriétaire depuis une application, scanner le QR code, se connecter.
3. Supervision : les jauges bougent toutes les 5 s (point « Temps réel actif » vert).
4. Docker : six conteneurs VIGIROAD « en fonctionnement ».
5. Maintenance → « Sauvegarder maintenant » puis « Tester la restauration » : deux lignes « réussie ».
6. Sur un téléphone 1.4 : créer un compte ; il apparaît « connecté » dans ADMIN MANAGER en moins d'une minute.
7. Désactiver ce compte dans ADMIN MANAGER : le téléphone est déconnecté au battement suivant.
