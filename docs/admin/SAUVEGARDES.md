# Sauvegardes et restauration

## Automatique

Le service `backup` (conteneur PostgreSQL) :

- sauvegarde la base **chaque nuit** (vers 3 h UTC) avec `pg_dump -Fc` dans `/opt/vigiroad/backups`
  (droits `600`), avec une empreinte SHA-256 par fichier ;
- **teste la restauration chaque dimanche** : la dernière sauvegarde est restaurée dans une base
  temporaire, vérifiée (version du schéma, tables, comptes), puis supprimée ;
- conserve les 14 dernières sauvegardes (réglage « Sauvegardes conservées »).

Les applications affichent chaque opération (Maintenance → Sauvegardes) et alertent si la dernière
sauvegarde réussie a plus de 30 heures ou si une opération échoue. Les boutons « Sauvegarder
maintenant » et « Tester la restauration » lancent ces opérations à la demande (rôle Opérateur ou plus).

## Restauration complète

Sur le VPS :

```bash
sudo bash /opt/vigiroad/server/database/backup/restore.sh                         # dernière sauvegarde
sudo bash /opt/vigiroad/server/database/backup/restore.sh vigiroad-20261101-030000.dump
```

Le script vérifie l'empreinte du fichier, sauvegarde d'abord la base actuelle
(`avant-restauration-….dump`), arrête l'API, restaure, puis redémarre l'API.

La procédure complète (sauvegarde, ajout de données, restauration, vérification du retour à l'état
sauvegardé) est exécutée à chaque modification par la CI.

## Copie hors du VPS

Recommandé : copier régulièrement `/opt/vigiroad/backups` ailleurs, par exemple depuis Windows :

```powershell
scp -r ubuntu@<IP du VPS>:/opt/vigiroad/backups .\sauvegardes-vigiroad
```

(ou activer l'option de sauvegarde automatique du VPS chez l'hébergeur).
