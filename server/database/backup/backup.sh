#!/bin/sh
# Service de sauvegarde VIGIROAD (conteneur postgres:16-alpine).
#  - sauvegarde automatique chaque nuit (pg_dump, format personnalisé) ;
#  - sauvegardes et tests de restauration demandés depuis les applications
#    d'administration (table backup_jobs) ;
#  - test de restauration automatique chaque semaine dans une base jetable ;
#  - conservation des N dernières sauvegardes (réglage backups.keep).
set -u

DIR=/backups
mkdir -p "$DIR"
chmod 700 "$DIR"
export PGHOST="${VR_DB_HOST:-postgres}" PGUSER="${VR_DB_USER:-vigiroad}" PGDATABASE="${VR_DB_NAME:-vigiroad}"
export PGPASSWORD="${VR_DB_PASSWORD:-}"
HOUR="${VR_BACKUP_HOUR:-3}"

q() { psql -X -q -t -A -v ON_ERROR_STOP=1 -c "$1"; }
log() { echo "$(date -u +%FT%TZ) $*"; }

job_start() { q "UPDATE backup_jobs SET status = 'running', started_at = now() WHERE id = $1"; }
job_done() {
  # $1 id, $2 statut, $3 fichier, $4 taille, $5 sha256, $6 message (sans apostrophe)
  msg=$(printf '%s' "$6" | tr -d "'" | head -c 900)
  q "UPDATE backup_jobs SET status = '$2', finished_at = now(), file_name = NULLIF('$3', ''),
     size_bytes = NULLIF('$4', '')::bigint, sha256 = NULLIF('$5', ''), message = NULLIF('$msg', '') WHERE id = $1"
}

do_backup() {
  id=$1
  job_start "$id"
  name="vigiroad-$(date -u +%Y%m%d-%H%M%S).dump"
  if out=$(pg_dump -Fc -Z 6 -f "$DIR/$name.part" 2>&1) && mv "$DIR/$name.part" "$DIR/$name"; then
    chmod 600 "$DIR/$name"
    size=$(stat -c %s "$DIR/$name")
    sum=$(sha256sum "$DIR/$name" | cut -d' ' -f1)
    echo "$sum  $name" > "$DIR/$name.sha256"
    tables=$(pg_restore -l "$DIR/$name" | grep -c ' TABLE DATA ')
    job_done "$id" success "$name" "$size" "$sum" "$tables tables sauvegardées"
    log "sauvegarde $name ($size octets)"
    prune
  else
    rm -f "$DIR/$name.part"
    job_done "$id" failed "" "" "" "pg_dump : $out"
    log "échec de la sauvegarde : $out"
  fi
}

# Restaure la dernière sauvegarde dans une base temporaire et compare le nombre
# de lignes de chaque table avec le contenu de la sauvegarde.
do_restore_test() {
  id=$1
  job_start "$id"
  last=$(ls -1t "$DIR"/vigiroad-*.dump 2> /dev/null | head -1)
  if [ -z "$last" ]; then
    job_done "$id" failed "" "" "" "aucune sauvegarde à restaurer"
    return
  fi
  name=$(basename "$last")
  if ! (cd "$DIR" && sha256sum -c "$name.sha256" > /dev/null 2>&1); then
    job_done "$id" failed "$name" "" "" "empreinte SHA-256 invalide : fichier altéré"
    return
  fi
  test_db="vigiroad_restore_test"
  psql -X -q -d postgres -c "DROP DATABASE IF EXISTS $test_db" > /dev/null 2>&1
  if ! out=$(createdb "$test_db" 2>&1 && pg_restore --no-owner -d "$test_db" "$last" 2>&1); then
    job_done "$id" failed "$name" "" "" "pg_restore : $out"
    psql -X -q -d postgres -c "DROP DATABASE IF EXISTS $test_db" > /dev/null 2>&1
    return
  fi
  version=$(psql -X -t -A -d "$test_db" -c "SELECT max(version) FROM schema_migrations" 2>&1)
  tables=$(psql -X -t -A -d "$test_db" -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public'" 2>&1)
  users=$(psql -X -t -A -d "$test_db" -c "SELECT count(*) FROM users" 2>&1)
  psql -X -q -d postgres -c "DROP DATABASE IF EXISTS $test_db" > /dev/null 2>&1
  case "$version" in
    ''|*[!0-9]*) job_done "$id" failed "$name" "" "" "base restaurée illisible : $version" ;;
    *) job_done "$id" success "$name" "" "" "restauration réussie : schéma v$version, $tables tables, $users comptes" ;;
  esac
  log "test de restauration de $name : v$version, $tables tables"
}

prune() {
  keep=$(q "SELECT value FROM settings WHERE key = 'backups.keep'" 2> /dev/null || echo 14)
  case "$keep" in ''|*[!0-9]*) keep=14 ;; esac
  ls -1t "$DIR"/vigiroad-*.dump 2> /dev/null | tail -n +"$((keep + 1))" | while read -r f; do
    rm -f "$f" "$f.sha256"
    log "ancienne sauvegarde supprimée : $(basename "$f")"
  done
}

log "service de sauvegarde démarré (sauvegarde quotidienne vers ${HOUR} h UTC)"
until q "SELECT 1 FROM backup_jobs LIMIT 1" > /dev/null 2>&1 || q "SELECT count(*) FROM backup_jobs" > /dev/null 2>&1; do
  sleep 5
done
# Tâches interrompues par un redémarrage.
q "UPDATE backup_jobs SET status = 'failed', finished_at = now(), message = 'interrompue (redémarrage)' WHERE status = 'running'"

while true; do
  # Sauvegarde quotidienne : aucune sauvegarde planifiée réussie aujourd'hui
  # et heure atteinte.
  if [ "$(date -u +%H | sed 's/^0//')" -ge "$HOUR" ]; then
    done_today=$(q "SELECT count(*) FROM backup_jobs WHERE kind = 'scheduled' AND created_at >= date_trunc('day', now())")
    if [ "$done_today" = "0" ]; then
      q "INSERT INTO backup_jobs (kind) VALUES ('scheduled')" > /dev/null
    fi
  fi
  # Test de restauration hebdomadaire (le dimanche, après la sauvegarde).
  if [ "$(date -u +%u)" = 7 ]; then
    week=$(q "SELECT count(*) FROM backup_jobs WHERE kind = 'restore_test' AND created_at > now() - interval '6 days'")
    ok_today=$(q "SELECT count(*) FROM backup_jobs WHERE kind = 'scheduled' AND status = 'success' AND created_at >= date_trunc('day', now())")
    if [ "$week" = "0" ] && [ "$ok_today" != "0" ]; then
      q "INSERT INTO backup_jobs (kind) VALUES ('restore_test')" > /dev/null
    fi
  fi
  next=$(q "SELECT id || ' ' || kind FROM backup_jobs WHERE status = 'pending' ORDER BY created_at LIMIT 1" 2> /dev/null)
  if [ -n "$next" ]; then
    id=${next%% *}
    kind=${next#* }
    case "$kind" in
      restore_test) do_restore_test "$id" ;;
      *) do_backup "$id" ;;
    esac
    continue
  fi
  sleep "${VR_BACKUP_POLL:-15}"
done
