#!/usr/bin/env bash
# Installe l'APK release de test OCR sur l'émulateur et vérifie que ML Kit
# lit la plaque dessinée. Échoue si le résultat n'est pas « OK ».
set -u
APK="$1"; OUT="$2"; TAG="${3:-VIGIROAD_OCR_SMOKE}"
adb install -r "$APK"
adb logcat -c
adb shell am start -n fr.vigiroad.vigiroad/.MainActivity
for _ in $(seq 1 90); do
  if adb logcat -d -s flutter:I | grep -q "$TAG"; then break; fi
  sleep 2
done
adb logcat -d > "$OUT/logcat-$TAG.txt"
grep -A20 "$TAG" "$OUT/logcat-$TAG.txt" | head -40 || true
grep -E "AndroidRuntime|MlKit|mlkit" "$OUT/logcat-$TAG.txt" | tail -40 || true
grep -q "$TAG OK" "$OUT/logcat-$TAG.txt"
