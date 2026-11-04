#!/usr/bin/env bash
set -euo pipefail

TINYCAST_MODE="${1:-run}"
TINYCAST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TINYCAST_APP="$TINYCAST_ROOT/build/Build/Products/Debug/Oncast.app"
TINYCAST_SIGNING_IDENTITY="${TINYCAST_SIGNING_IDENTITY:-Developer ID Application: Sang Yeop Lim (79Q5RV23F9)}"
TINYCAST_DEVELOPMENT_TEAM="${TINYCAST_DEVELOPMENT_TEAM:-79Q5RV23F9}"

case "$TINYCAST_MODE" in
  run|--debug|--logs|--telemetry|--verify|--build-only) ;;
  *) echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--build-only]" >&2; exit 2 ;;
esac

cd "$TINYCAST_ROOT"
if pgrep -x 'Oncast' >/dev/null; then
  pkill -x 'Oncast'
fi
xcodegen generate
xcodebuild -jobs 2 -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug \
  -derivedDataPath "$TINYCAST_ROOT/build" CODE_SIGN_IDENTITY="$TINYCAST_SIGNING_IDENTITY" \
  DEVELOPMENT_TEAM="$TINYCAST_DEVELOPMENT_TEAM" CODE_SIGNING_REQUIRED=NO \
  'OTHER_SWIFT_FLAGS=$(inherited) -j2' build

/usr/bin/codesign --verify --deep --strict "$TINYCAST_APP"

case "$TINYCAST_MODE" in
  --build-only) exit 0 ;;
  --debug) exec lldb -- "$TINYCAST_APP/Contents/MacOS/Oncast" ;;
  run) /usr/bin/open -n "$TINYCAST_APP" ;;
  --verify)
    /usr/bin/open -n "$TINYCAST_APP"
    sleep 2
    pgrep -x 'Oncast' >/dev/null
    ;;
  --logs|--telemetry)
    /usr/bin/open -n "$TINYCAST_APP"
    exec /usr/bin/log stream --info --style compact --predicate 'process == "Oncast"'
    ;;
esac
