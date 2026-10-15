#!/usr/bin/env bash
# Records one promo scene, re-running flutter_tester after random crashes
# until the scene is complete. Usage: tool/promo_capture.sh <scene> [out]
scene=$1; out=${2:-build/promo}
rm -rf "$out/$scene" "$out/$scene.mp4"
for i in $(seq 1 40); do
  flutter test tool/promo_capture_test.dart --plain-name "$scene" \
    --dart-define=PROMO="$out" > "$out/$scene.log" 2>&1
  if [ -f "$out/$scene/complete" ]; then
    echo "$scene: selesai ($(cat "$out/$scene/complete") bingkai, $i kali jalan)"; exit 0
  fi
  if grep -q "EXCEPTION CAUGHT" "$out/$scene.log"; then
    echo "$scene: kesalahan nyata, lihat $out/$scene.log"; exit 1
  fi
done
echo "$scene: belum selesai setelah 40 kali"; exit 1
