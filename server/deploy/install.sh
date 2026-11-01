#!/usr/bin/env bash
# Installation (ou mise à jour) de VIGIROAD sur un VPS Debian / Ubuntu :
# serveur de trafic, API d'administration, PostgreSQL, agent de supervision,
# sauvegardes automatiques et HTTPS (Caddy). À lancer en root :
#   curl -fsSL https://raw.githubusercontent.com/hempreur/VIGIROAD/main/server/deploy/install.sh -o install.sh
#   sudo bash install.sh                      # adresse automatique <ip>.sslip.io
#   sudo bash install.sh trafic.mondomaine.fr # ou votre nom de domaine (DNS déjà pointé vers le VPS)
# Relancer la même commande met à jour (clés, base et réglages conservés).
# `--update` : mise à jour non interactive (demandée depuis les applications
# d'administration) ; aucun secret n'est alors affiché dans le journal.
set -euo pipefail

REPO=https://github.com/hempreur/VIGIROAD.git
DIR=/opt/vigiroad
DEPLOY=$DIR/server/deploy
RUN=$DIR/run
UPDATE=""
DOMAIN_ARG=""
for a in "$@"; do
  case "$a" in
    --update) UPDATE=1 ;;
    *) DOMAIN_ARG="$a" ;;
  esac
done

[ "$(id -u)" = 0 ] || { echo "Lancez ce script en root (sudo bash install.sh)."; exit 1; }
say() { printf '\n\033[1;36m▶ %s\033[0m\n' "$*"; }

say "Paquets système"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates curl git openssl ufw > /dev/null

if ! command -v docker > /dev/null; then
  say "Installation de Docker"
  curl -fsSL https://get.docker.com | sh > /dev/null
fi
systemctl enable --now docker > /dev/null

say "Code"
if [ -d "$DIR/.git" ]; then
  git -C "$DIR" fetch -q --depth 1 origin main
  git -C "$DIR" reset -q --hard origin/main
else
  git clone -q --depth 1 "$REPO" "$DIR"
fi

say "Configuration"
ENV=$DEPLOY/.env
if [ ! -f "$ENV" ]; then
  cat > "$ENV" <<CONF
# Clés autorisées à interroger le serveur (séparées par des virgules, 16 caractères minimum).
VR_API_KEYS=$(openssl rand -hex 24)
# Sources facultatives (laisser vide si pas de clé) — voir server/SOURCES.md.
VR_TFL_APP_KEY=
VR_511_SFBAY_KEY=
VR_AZ511_KEY=
VR_WAZE_FEED_URL=
VR_WAZE_BBOX=
VR_DATEX2_FEEDS=
VR_DISABLE_SOURCES=
VR_OVERPASS_URL=
VR_SPEEDLIMITS=
CONF
fi
# Secrets de l'administration, ajoutés s'ils manquent (installations existantes).
ensure() { grep -q "^$1=" "$ENV" || printf '%s=%s\n' "$1" "$2" >> "$ENV"; }
ensure VR_DB_NAME vigiroad
ensure VR_DB_USER vigiroad
ensure VR_DB_PASSWORD "$(openssl rand -hex 24)"
ensure VR_ADMIN_SECRET "$(openssl rand -hex 32)"
ensure VR_AGENT_TOKEN "$(openssl rand -hex 24)"
ensure VR_ADMIN_SETUP_TOKEN "$(openssl rand -hex 12)"
chmod 600 "$ENV"

IP=$(curl -fsS4 https://api.ipify.org || hostname -I | awk '{print $1}')
DOMAIN=${DOMAIN_ARG:-$(grep -s '^VR_DOMAIN=' "$DEPLOY/.domain" | cut -d= -f2 || true)}
[ -n "${DOMAIN:-}" ] || DOMAIN="$(echo "$IP" | tr . -).sslip.io"
echo "VR_DOMAIN=$DOMAIN" > "$DEPLOY/.domain"

mkdir -p "$RUN" "$DIR/backups" "$DIR/geoip"
chmod 700 "$RUN" "$DIR/backups"

say "Géolocalisation par pays (DB-IP Lite, CC BY 4.0)"
cat > /etc/cron.monthly/vigiroad-geoip <<'GEO'
#!/bin/sh
# Base libre DB-IP « IP to Country Lite » (https://db-ip.com, CC BY 4.0).
set -e
cd /opt/vigiroad/geoip
for m in "$(date +%Y-%m)" "$(date -d '-1 month' +%Y-%m 2> /dev/null || date +%Y-%m)"; do
  if curl -fsSL "https://download.db-ip.com/free/dbip-country-lite-$m.csv.gz" -o dbip.tmp; then
    mv dbip.tmp dbip-country-lite.csv.gz
    exit 0
  fi
done
rm -f dbip.tmp
GEO
chmod 755 /etc/cron.monthly/vigiroad-geoip
[ -s "$DIR/geoip/dbip-country-lite.csv.gz" ] || /etc/cron.monthly/vigiroad-geoip || echo "Base GeoIP indisponible (pays inconnus)."

say "Mises à jour à distance (depuis les applications d'administration)"
cat > /etc/systemd/system/vigiroad-deploy.service <<UNIT
[Unit]
Description=Mise à jour VIGIROAD demandée depuis l'administration
[Service]
Type=oneshot
ExecStart=/bin/bash -c 'rm -f $RUN/deploy.request; echo running > $RUN/deploy.status; cp $DEPLOY/install.sh /run/vigiroad-install.sh; if bash /run/vigiroad-install.sh --update > $RUN/deploy.log 2>&1; then echo success > $RUN/deploy.status; else echo failed > $RUN/deploy.status; fi'
UNIT
cat > /etc/systemd/system/vigiroad-deploy.path <<UNIT
[Unit]
Description=Surveillance des demandes de mise à jour VIGIROAD
[Path]
PathExists=$RUN/deploy.request
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now vigiroad-deploy.path > /dev/null

say "Pare-feu (SSH, HTTP, HTTPS)"
ufw allow OpenSSH > /dev/null
ufw allow 80/tcp > /dev/null
ufw allow 443 > /dev/null
ufw --force enable > /dev/null

say "Construction et démarrage (première fois : plusieurs minutes)"
cd "$DEPLOY"
dc() { VR_DOMAIN=$DOMAIN docker compose --env-file "$ENV" --env-file "$DEPLOY/.domain" "$@"; }
dc up -d --build --remove-orphans
docker image prune -f > /dev/null
COMMIT=$(git -C "$DIR" rev-parse HEAD)
printf '{"commit":"%s","date":"%s","deployedAt":"%s"}\n' "$COMMIT" "$(git -C "$DIR" log -1 --format=%cI)" "$(date -u +%FT%TZ)" > "$RUN/deployed.json"

say "Vérification"
KEY=$(grep '^VR_API_KEYS=' "$ENV" | cut -d= -f2 | cut -d, -f1)
ok=""
for _ in $(seq 1 40); do
  if curl -fsS "https://$DOMAIN/health" > /tmp/vr_health 2> /dev/null && curl -fsS "https://$DOMAIN/admin/health" > /tmp/vr_admin 2> /dev/null; then
    ok=1
    break
  fi
  sleep 5
done
if [ -n "$ok" ]; then
  echo "Trafic : $(cat /tmp/vr_health)"
  echo "Administration : $(cat /tmp/vr_admin)"
else
  echo "Le serveur ne répond pas encore en HTTPS. Journaux : cd $DEPLOY && docker compose --env-file .env --env-file .domain logs --tail 50"
  [ -z "$UPDATE" ] || exit 1
fi

[ -z "$UPDATE" ] || { echo "Mise à jour terminée : $COMMIT"; exit 0; }

ADMINS=$(dc exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "SELECT count(*) FROM admin_accounts"' 2> /dev/null || echo "?")
SETUP=$(grep '^VR_ADMIN_SETUP_TOKEN=' "$ENV" | cut -d= -f2)
cat <<FIN

──────────────────────────────────────────────────────────────
 VIGIROAD installé sur https://$DOMAIN

 Secrets GitHub (Settings → Secrets and variables → Actions) :
   VR_TRAFFIC_API_URL = https://$DOMAIN
   VR_TRAFFIC_API_KEY = $KEY
FIN
if [ "$ADMINS" = "0" ]; then
  cat <<FIN

 Applications d'administration (Windows / Linux) — première connexion :
   Serveur            : https://$DOMAIN
   Jeton d'installation : $SETUP
   (crée le compte propriétaire ; inutilisable ensuite)
FIN
fi
cat <<FIN

 Sauvegardes : $DIR/backups (chaque nuit, test de restauration hebdomadaire)
 Restauration : sudo bash $DIR/server/database/backup/restore.sh
 Bureau graphique (facultatif) : sudo bash $DEPLOY/install-desktop.sh
 Ne partagez jamais ces clés. Mise à jour : relancer sudo bash install.sh
──────────────────────────────────────────────────────────────
FIN
