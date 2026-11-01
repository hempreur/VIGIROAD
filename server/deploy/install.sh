#!/usr/bin/env bash
# Installation (ou mise à jour) du serveur de trafic VIGIROAD sur un VPS
# Debian / Ubuntu. À lancer en root :
#   curl -fsSL https://raw.githubusercontent.com/hempreur/VIGIROAD/main/server/deploy/install.sh -o install.sh
#   sudo bash install.sh                      # adresse automatique <ip>.sslip.io
#   sudo bash install.sh trafic.mondomaine.fr # ou votre nom de domaine (DNS déjà pointé vers le VPS)
# Relancer la même commande met le serveur à jour (la clé et les réglages sont conservés).
set -euo pipefail

REPO=https://github.com/hempreur/VIGIROAD.git
DIR=/opt/vigiroad
DEPLOY=$DIR/server/deploy

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

say "Code du serveur"
if [ -d "$DIR/.git" ]; then
  git -C "$DIR" fetch -q --depth 1 origin main
  git -C "$DIR" reset -q --hard origin/main
else
  git clone -q --depth 1 "$REPO" "$DIR"
fi

say "Configuration"
ENV=$DEPLOY/.env
if [ ! -f "$ENV" ]; then
  KEY=$(openssl rand -hex 24)
  cat > "$ENV" <<CONF
# Clés autorisées à interroger le serveur (séparées par des virgules, 16 caractères minimum).
VR_API_KEYS=$KEY
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
  chmod 600 "$ENV"
fi
IP=$(curl -fsS4 https://api.ipify.org || hostname -I | awk '{print $1}')
DOMAIN=${1:-$(grep -s '^VR_DOMAIN=' "$DEPLOY/.domain" | cut -d= -f2 || true)}
[ -n "${DOMAIN:-}" ] || DOMAIN="$(echo "$IP" | tr . -).sslip.io"
echo "VR_DOMAIN=$DOMAIN" > "$DEPLOY/.domain"

say "Pare-feu (SSH, HTTP, HTTPS)"
ufw allow OpenSSH > /dev/null
ufw allow 80/tcp > /dev/null
ufw allow 443 > /dev/null
ufw --force enable > /dev/null

say "Construction et démarrage (première fois : quelques minutes)"
cd "$DEPLOY"
VR_DOMAIN=$DOMAIN docker compose --env-file "$DEPLOY/.domain" up -d --build --remove-orphans
docker image prune -f > /dev/null

say "Vérification"
KEY=$(grep '^VR_API_KEYS=' "$ENV" | cut -d= -f2 | cut -d, -f1)
ok=""
for _ in $(seq 1 30); do
  if curl -fsS "https://$DOMAIN/health" > /tmp/vr_health 2> /dev/null; then ok=1; break; fi
  sleep 5
done
if [ -n "$ok" ]; then
  echo "Santé : $(cat /tmp/vr_health)"
  curl -fsS -H "X-Api-Key: $KEY" "https://$DOMAIN/v1/events?bbox=2.2,48.8,2.5,48.95" -o /tmp/vr_events || true
  echo "Événements (extrait) : $(head -c 300 /tmp/vr_events 2> /dev/null)"
else
  echo "Le serveur ne répond pas encore en HTTPS. Journaux : cd $DEPLOY && docker compose logs --tail 50"
fi

cat <<FIN

──────────────────────────────────────────────────────────────
 Serveur de trafic VIGIROAD installé.

 À ajouter dans GitHub → Settings → Secrets and variables → Actions :

   VR_TRAFFIC_API_URL = https://$DOMAIN
   VR_TRAFFIC_API_KEY = $KEY

 Ne partagez pas cette clé publiquement. Mise à jour : relancer
 sudo bash install.sh   (clé et réglages conservés)
──────────────────────────────────────────────────────────────
FIN
