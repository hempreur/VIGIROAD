#!/usr/bin/env bash
# Installe l'APK release de test OCR sur l'émulateur et vérifie que ML Kit
# lit la plaque dessinée. Échoue si le résultat n'est pas « OK ».
set -u
APK="$1"; OUT="$2"
adb install -r "$APK"
adb logcat -c
adb shell am start -n fr.vigiroad.vigiroad/.MainActivity
for _ in $(seq 1 90); do
  if adb logcat -d -s flutter:I | grep -q VIGIROAD_OCR_SMOKE; then break; fi
  sleep 2
done
adb logcat -d > "$OUT/logcat.txt"
grep -A20 VIGIROAD_OCR_SMOKE "$OUT/logcat.txt" | head -40 || true
grep -E "AndroidRuntime|MlKit|mlkit" "$OUT/logcat.txt" | tail -40 || true
grep -q "VIGIROAD_OCR_SMOKE OK" "$OUT/logcat.txt"
