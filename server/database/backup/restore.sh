#!/usr/bin/env bash
# Restauration complète de la base VIGIROAD depuis une sauvegarde.
#   sudo bash /opt/vigiroad/server/database/backup/restore.sh                # dernière sauvegarde
#   sudo bash /opt/vigiroad/server/database/backup/restore.sh vigiroad-20261101-033000.dump
# L'API est arrêtée pendant l'opération ; la base actuelle est d'abord
# sauvegardée (fichier « avant-restauration-… »).
set -euo pipefail
cd "${VR_DEPLOY_DIR:-/opt/vigiroad/server/deploy}"
BACKUPS=${VR_BACKUP_DIR:-/opt/vigiroad/backups}
DBNAME=$(grep -s '^VR_DB_NAME=' .env | cut -d= -f2 || true)
DBNAME=${DBNAME:-vigiroad}
FILE=${1:-$(ls -1t "$BACKUPS"/vigiroad-*.dump | head -1 | xargs basename)}
[ -f "$BACKUPS/$FILE" ] || { echo "Sauvegarde introuvable : $BACKUPS/$FILE"; exit 1; }
(cd "$BACKUPS" && sha256sum -c "$FILE.sha256") || { echo "Empreinte invalide : fichier altéré, restauration annulée."; exit 1; }

dc() { docker compose --env-file .env --env-file .domain "$@"; }
echo "▶ Sauvegarde de sécurité de la base actuelle"
# Connexion à PostgreSQL avec les variables du conteneur de sauvegarde.
PG='export PGHOST="$VR_DB_HOST" PGUSER="$VR_DB_USER" PGPASSWORD="$VR_DB_PASSWORD";'
dc exec -T backup sh -c "$PG pg_dump -Fc -d $DBNAME -f /backups/avant-restauration-$(date -u +%Y%m%d-%H%M%S).dump"
echo "▶ Arrêt de l'API d'administration"
dc stop admin-api
echo "▶ Restauration de $FILE"
dc exec -T backup sh -c "$PG psql -X -q -d postgres -c 'DROP DATABASE IF EXISTS $DBNAME WITH (FORCE)' && createdb $DBNAME && pg_restore --no-owner -d $DBNAME /backups/$FILE"
echo "▶ Redémarrage"
dc start admin-api
echo "✅ Base restaurée depuis $FILE"
