#!/usr/bin/env bash
# Paquet .deb de VIGIROAD SERVER CONTROL (Ubuntu / Debian, amd64).
#   bash admin/linux/packaging/build_deb.sh <version> <dossier de sortie>
# Prérequis : flutter build linux --release (dans admin/linux).
set -euo pipefail
VERSION=$1
OUT=$2
HERE=$(cd "$(dirname "$0")" && pwd)
APP=$HERE/..
BUNDLE=$APP/build/linux/x64/release/bundle
[ -x "$BUNDLE/vigiroad_server_control" ] || { echo "Construire d'abord : flutter build linux --release"; exit 1; }
ROOT=$(mktemp -d)
mkdir -p "$ROOT/DEBIAN" "$ROOT/opt/vigiroad-server-control" "$ROOT/usr/bin" \
  "$ROOT/usr/share/applications" "$ROOT/usr/share/icons/hicolor/256x256/apps" "$ROOT/usr/share/doc/vigiroad-server-control"
cp -r "$BUNDLE"/. "$ROOT/opt/vigiroad-server-control/"
ln -s /opt/vigiroad-server-control/vigiroad_server_control "$ROOT/usr/bin/vigiroad-server-control"
cp "$HERE/fr.vigiroad.ServerControl.desktop" "$ROOT/usr/share/applications/"
cp "$APP/../shared/assets/vigiroad_logo.png" "$ROOT/usr/share/icons/hicolor/256x256/apps/vigiroad-server-control.png"
cat > "$ROOT/usr/share/doc/vigiroad-server-control/copyright" <<TXT
VIGIROAD SERVER CONTROL — © 2026 VIGIROAD INC (CODEX HEMPREUR)
Polices Rajdhani et Inter : SIL Open Font License 1.1. Carte : Natural Earth (domaine public).
TXT
SIZE=$(du -sk "$ROOT/opt" | cut -f1)
cat > "$ROOT/DEBIAN/control" <<CTRL
Package: vigiroad-server-control
Version: $VERSION
Section: admin
Priority: optional
Architecture: amd64
Installed-Size: $SIZE
Depends: libgtk-3-0 | libgtk-3-0t64, libblkid1, liblzma5, libstdc++6
Maintainer: VIGIROAD INC (CODEX HEMPREUR) <support@vigiroad.fr>
Homepage: https://github.com/hempreur/VIGIROAD
Description: VIGIROAD SERVER CONTROL - administration du serveur VIGIROAD
 Application graphique native de supervision du VPS VIGIROAD : processeur,
 mémoire, disque, réseau, processus, conteneurs Docker, flux routiers,
 requêtes, diagnostic, sauvegardes et mises à jour.
CTRL
cat > "$ROOT/DEBIAN/postinst" <<'POST'
#!/bin/sh
set -e
command -v update-desktop-database > /dev/null && update-desktop-database -q /usr/share/applications || true
command -v gtk-update-icon-cache > /dev/null && gtk-update-icon-cache -q /usr/share/icons/hicolor || true
POST
chmod 755 "$ROOT/DEBIAN/postinst"
find "$ROOT" -type d -exec chmod 755 {} +
mkdir -p "$OUT"
dpkg-deb --root-owner-group --build "$ROOT" "$OUT/vigiroad-server-control_${VERSION}_amd64.deb"
rm -rf "$ROOT"
echo "$OUT/vigiroad-server-control_${VERSION}_amd64.deb"
