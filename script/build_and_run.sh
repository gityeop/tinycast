#!/usr/bin/env bash
set -euo pipefail

TINYCAST_MODE="${1:-run}"
TINYCAST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TINYCAST_APP="$TINYCAST_ROOT/build/Build/Products/Debug/Oncast.app"
TINYCAST_SIGNING_IDENTITY="${TINYCAST_SIGNING_IDENTITY:--}"
TINYCAST_DEVELOPMENT_TEAM="${TINYCAST_DEVELOPMENT_TEAM:-}"

case "$TINYCAST_MODE" in
  run|--debug|--logs|--telemetry|--verify) ;;
  *) echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
esac

cd "$TINYCAST_ROOT"
if pgrep -x 'Oncast' >/dev/null; then
  pkill -x 'Oncast'
fi
xcodegen generate
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug \
  -derivedDataPath "$TINYCAST_ROOT/build" CODE_SIGN_IDENTITY="$TINYCAST_SIGNING_IDENTITY" \
  DEVELOPMENT_TEAM="$TINYCAST_DEVELOPMENT_TEAM" CODE_SIGNING_REQUIRED=NO build

case "$TINYCAST_MODE" in
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
