#!/usr/bin/env bash
# Bureau graphique léger sur le VPS pour VIGIROAD SERVER CONTROL.
#   sudo bash /opt/vigiroad/server/deploy/install-desktop.sh
#
# - XFCE (environnement léger, ~300 Mo de RAM pendant une session) ;
# - bureau à distance xrdp qui n'écoute QUE sur 127.0.0.1 : aucun port
#   supplémentaire ouvert sur Internet, accès uniquement par tunnel SSH ;
# - compte « vigiroad » dédié aux sessions graphiques ;
# - application VIGIROAD SERVER CONTROL (.deb de la dernière version).
# Le serveur VIGIROAD (Docker) n'est ni arrêté ni modifié.
set -euo pipefail

[ "$(id -u)" = 0 ] || { echo "Lancez ce script en root (sudo bash install-desktop.sh)."; exit 1; }
say() { printf '\n\033[1;36m▶ %s\033[0m\n' "$*"; }
USER_NAME=${VR_DESKTOP_USER:-vigiroad}
REPO=hempreur/VIGIROAD

say "Vérification des ressources"
mem_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
avail_mb=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)
disk_mb=$(df -Pm / | awk 'NR==2 {print $4}')
echo "RAM : ${mem_mb} Mo (disponible ${avail_mb} Mo) — disque libre : ${disk_mb} Mo"
if [ "$mem_mb" -lt 1800 ] || [ "$disk_mb" -lt 3000 ]; then
  echo "Ressources insuffisantes (2 Go de RAM et 3 Go de disque libres recommandés). Installation annulée."
  exit 1
fi
if [ -n "${DISPLAY:-}" ] || systemctl is-active --quiet gdm3 lightdm sddm 2> /dev/null; then
  echo "Un environnement graphique est déjà présent : seuls xrdp et l'application seront ajoutés."
fi

say "Environnement graphique XFCE et xrdp (sans paquets superflus)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  xfce4 xfce4-terminal xfce4-taskmanager dbus-x11 xorgxrdp xrdp fonts-dejavu-core fonts-noto-color-emoji \
  libgtk-3-0t64 adwaita-icon-theme-full curl ca-certificates > /dev/null 2>&1 \
  || apt-get install -y -qq --no-install-recommends \
    xfce4 xfce4-terminal xfce4-taskmanager dbus-x11 xorgxrdp xrdp fonts-dejavu-core libgtk-3-0 curl ca-certificates > /dev/null

say "Bureau à distance limité à l'ordinateur local (127.0.0.1:3389)"
sed -i -E 's|^port=.*|port=tcp://127.0.0.1:3389|' /etc/xrdp/xrdp.ini
grep -q '^port=tcp://127.0.0.1:3389' /etc/xrdp/xrdp.ini
adduser xrdp ssl-cert > /dev/null 2>&1 || true
# Évite la demande d'authentification « profil de couleur » dans les sessions distantes.
mkdir -p /etc/polkit-1/rules.d
cat > /etc/polkit-1/rules.d/45-vigiroad-xrdp-colord.rules <<'RULE'
polkit.addRule(function(action, subject) {
  if (action.id.indexOf("org.freedesktop.color-manager.") === 0 && subject.isInGroup("users")) {
    return polkit.Result.YES;
  }
});
RULE
systemctl enable --now xrdp > /dev/null
systemctl restart xrdp
# Le port 3389 reste fermé au pare-feu (il n'écoute de toute façon que localement).
ufw deny 3389 > /dev/null 2>&1 || true

say "Compte des sessions graphiques : $USER_NAME"
if ! id "$USER_NAME" > /dev/null 2>&1; then
  adduser --disabled-password --gecos "VIGIROAD Desktop" "$USER_NAME" > /dev/null
  PASS=$(openssl rand -base64 18 | tr -d '/+=' | cut -c1-16)
  echo "$USER_NAME:$PASS" | chpasswd
  NEW_PASS=$PASS
fi
usermod -aG users "$USER_NAME"
HOME_DIR=$(getent passwd "$USER_NAME" | cut -d: -f6)
echo "xfce4-session" > "$HOME_DIR/.xsession"
chown "$USER_NAME:$USER_NAME" "$HOME_DIR/.xsession"

say "Application VIGIROAD SERVER CONTROL"
URL=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
  | grep -o '"browser_download_url": *"[^"]*-server-control-amd64\.deb"' | head -1 | cut -d'"' -f4 || true)
if [ -n "$URL" ]; then
  curl -fsSL "$URL" -o /tmp/vigiroad-server-control.deb
  apt-get install -y -qq /tmp/vigiroad-server-control.deb > /dev/null
  rm -f /tmp/vigiroad-server-control.deb
  mkdir -p "$HOME_DIR/Desktop" "$HOME_DIR/Bureau"
  for d in Desktop Bureau; do
    cp /usr/share/applications/fr.vigiroad.ServerControl.desktop "$HOME_DIR/$d/"
    chmod +x "$HOME_DIR/$d/fr.vigiroad.ServerControl.desktop"
  done
  chown -R "$USER_NAME:$USER_NAME" "$HOME_DIR/Desktop" "$HOME_DIR/Bureau"
  echo "Installée : $(dpkg-query -W -f='${Version}' vigiroad-server-control)"
else
  echo "Aucun paquet publié pour le moment : relancez ce script après la prochaine version."
fi

DOMAIN=$(grep -s '^VR_DOMAIN=' /opt/vigiroad/server/deploy/.domain | cut -d= -f2 || true)
IP=$(curl -fsS4 https://api.ipify.org || hostname -I | awk '{print $1}')
SSH_USER=${SUDO_USER:-ubuntu}
cat <<FIN

──────────────────────────────────────────────────────────────
 Bureau graphique prêt (aucun port supplémentaire ouvert).

 1. Depuis votre ordinateur, ouvrez le tunnel SSH (laisser la fenêtre ouverte) :
      ssh -L 3389:127.0.0.1:3389 $SSH_USER@$IP
 2. Ouvrez « Connexion Bureau à distance » (mstsc) vers :  localhost:3389
    (Linux : Remmina ; macOS : Windows App)
 3. Session : Xorg — utilisateur : $USER_NAME
FIN
[ -n "${NEW_PASS:-}" ] && echo "    Mot de passe (à changer avec : sudo passwd $USER_NAME) : $NEW_PASS"
cat <<FIN
 4. Lancez « VIGIROAD Server Control » (bureau ou menu Système) et
    connectez-vous à : https://${DOMAIN:-<votre domaine>}
──────────────────────────────────────────────────────────────
FIN
