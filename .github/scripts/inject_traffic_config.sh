#!/usr/bin/env bash
# Renseigne le serveur de trafic dans un fichier config/<env>.env à partir des
# secrets GitHub VR_TRAFFIC_API_URL / VR_TRAFFIC_API_KEY (jamais committés).
# Sans secret, le trafic reste désactivé (« source non configurée »).
set -euo pipefail
file="$1"
if [ -z "${VR_TRAFFIC_API_URL:-}" ] || [ -z "${VR_TRAFFIC_API_KEY:-}" ]; then
  echo "Trafic : aucun serveur configuré (secrets VR_TRAFFIC_API_URL / VR_TRAFFIC_API_KEY absents)"
  exit 0
fi
grep -v -E '^VR_TRAFFIC_API_(URL|KEY)=' "$file" > "$file.tmp" || true
printf 'VR_TRAFFIC_API_URL=%s\nVR_TRAFFIC_API_KEY=%s\n' "$VR_TRAFFIC_API_URL" "$VR_TRAFFIC_API_KEY" >> "$file.tmp"
mv "$file.tmp" "$file"
echo "Trafic : serveur configuré pour $file"
