#!/usr/bin/env bash
set -euo pipefail

TINYCAST_SIGNING_IDENTITY="${1:?usage: $0 SIGNING_IDENTITY TEAM_ID}"
TINYCAST_DEVELOPMENT_TEAM="${2:?usage: $0 SIGNING_IDENTITY TEAM_ID}"
TINYCAST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TINYCAST_BUILD="$TINYCAST_ROOT/build/release"

cd "$TINYCAST_ROOT"
xcodegen generate
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Release \
  -derivedDataPath "$TINYCAST_BUILD" CODE_SIGN_IDENTITY="$TINYCAST_SIGNING_IDENTITY" \
  DEVELOPMENT_TEAM="$TINYCAST_DEVELOPMENT_TEAM" OTHER_CODE_SIGN_FLAGS=--timestamp build
./Scripts/verify-signature.sh "$TINYCAST_BUILD/Build/Products/Release/Tinycast Fork.app"
