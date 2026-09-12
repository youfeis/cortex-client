#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -ne 1 ]]; then
  echo 'Usage: scripts/install-iphone.sh DEVICE_IDENTIFIER' >&2
  echo 'Find the paired iPhone with: xcrun devicectl list devices' >&2
  exit 1
fi
flutter pub get --enforce-lockfile
flutter build ios --release
xcrun devicectl device install app --device "$1" build/ios/iphoneos/Runner.app
xcrun devicectl device process launch --device "$1" com.miaotutu.cortex
