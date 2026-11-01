# API d'administration et des comptes

Servie par `server/admin_api` derrière Caddy (HTTPS). Réponses JSON ; erreurs
`{"error": "message en français", "code": "…"}`.

## Comptes (application mobile) — `/v1/account/*`

En-tête `X-Api-Key` (clé de l'application) ; après connexion, `Authorization: Bearer vrs_…`.

| Méthode | Chemin | Rôle |
|---|---|---|
| POST | `/v1/account/register` | inscription (`pseudonym`, `password`, `email?`, `displayName?`, `consents`, `device?`) |
| POST | `/v1/account/login` | connexion (`login` = pseudonyme ou e-mail, `password`, `device?`) |
| POST | `/v1/account/reset` | nouveau mot de passe avec le code d'un administrateur |
| POST | `/v1/account/heartbeat` | battement de cœur (60 s, application au premier plan), `location?` avec consentement |
| GET / PATCH | `/v1/account/me` | profil, consentements |
| POST | `/v1/account/me/delete` | suppression définitive (mot de passe) |
| GET | `/v1/account/data` | export de toutes les données |
| POST / DELETE | `/v1/account/device` | enregistrer / retirer cet appareil |
| GET | `/v1/account/sessions` | sessions ouvertes ; `POST …/sessions/{id}/revoke` |
| DELETE | `/v1/account/location` | effacer l'historique de positions |
| POST | `/v1/account/logout` | déconnexion |

Temps d'utilisation : chaque battement ajoute l'intervalle écoulé s'il est ≤ 90 s (sinon
l'application était fermée). « Connecté » = battement depuis moins de 150 s.

## Administration — `/admin/*`

Connexion : `POST /admin/auth/login` → `{"mfa": "required"|"enroll", "ticket"}` puis
`POST /admin/auth/mfa {"ticket", "code"}` → jeton `vra_…` (`Authorization: Bearer`).
Premier administrateur : `GET/POST /admin/setup` (jeton d'installation).

| Domaine | Points d'accès |
|---|---|
| Tableau de bord | `GET /admin/dashboard`, `GET /admin/stats/activity?period=24h|7d|30d` |
| Utilisateurs | `GET /admin/users?q=&status=&online=&sort=&limit=&offset=`, `GET/PATCH/DELETE /admin/users/{id}`, `POST …/disable|enable|revoke-sessions|reset-access`, `GET …/export`, `GET /admin/users/export` (CSV) |
| Appareils | `GET /admin/devices`, `GET /admin/devices/{id}`, `POST …/revoke` |
| Sessions | `GET /admin/sessions?state=online|open|ended|all`, `GET /admin/sessions/concurrent`, `POST …/{id}/revoke`, `GET /admin/login-events` |
| Géographie | `GET /admin/geo?days=` |
| Serveur | `GET /admin/server/overview|history|processes`, `GET /admin/docker/containers|volumes|networks|images`, `GET …/containers/{id}/logs`, `POST …/containers/{id}/start|stop|restart` |
| VIGIROAD | `GET /admin/vigiroad/status|requests|sources/history`, `GET /admin/alerts` |
| Maintenance | `GET /admin/diagnostics|errors|backups|updates`, `POST /admin/backups`, `POST /admin/updates/deploy`, `POST /admin/maintenance/retention` |
| Temps réel | `GET /admin/events` (Server-Sent Events, instantané toutes les 5 s) |
| Administration | `GET/PUT /admin/settings`, `GET /admin/audit`, `GET/POST/PATCH/DELETE /admin/admins`, `POST /admin/me/password` |

Droits par rôle : `read` (tous), `serverControl` et `backups` (Opérateur+), `usersManage`,
`usersDelete`, `export`, `settings` (Administrateur+), `adminsManage` et `deploy` (Propriétaire).
