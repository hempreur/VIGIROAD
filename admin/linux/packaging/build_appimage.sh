#!/usr/bin/env bash
# AppImage de VIGIROAD SERVER CONTROL (exécutable unique, sans installation).
#   bash admin/linux/packaging/build_appimage.sh <version> <dossier de sortie> <appimagetool>
set -euo pipefail
VERSION=$1
OUT=$2
TOOL=$3
HERE=$(cd "$(dirname "$0")" && pwd)
APP=$HERE/..
BUNDLE=$APP/build/linux/x64/release/bundle
DIR=$(mktemp -d)/VIGIROAD_Server_Control.AppDir
mkdir -p "$DIR/usr/lib/vigiroad-server-control"
cp -r "$BUNDLE"/. "$DIR/usr/lib/vigiroad-server-control/"
cp "$APP/../shared/assets/vigiroad_logo.png" "$DIR/vigiroad-server-control.png"
sed 's/^Exec=.*/Exec=vigiroad_server_control/' "$HERE/fr.vigiroad.ServerControl.desktop" > "$DIR/fr.vigiroad.ServerControl.desktop"
cat > "$DIR/AppRun" <<'RUN'
#!/bin/sh
HERE=$(dirname "$(readlink -f "$0")")
exec "$HERE/usr/lib/vigiroad-server-control/vigiroad_server_control" "$@"
RUN
chmod +x "$DIR/AppRun"
mkdir -p "$OUT"
ARCH=x86_64 "$TOOL" --appimage-extract-and-run --no-appstream "$DIR" "$OUT/VIGIROAD_Server_Control-$VERSION-x86_64.AppImage"
echo "$OUT/VIGIROAD_Server_Control-$VERSION-x86_64.AppImage"
