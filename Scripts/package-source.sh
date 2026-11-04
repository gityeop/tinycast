#!/usr/bin/env bash
set -euo pipefail

ONCAST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ONCAST_OUTPUT="${1:?usage: $0 OUTPUT_DIRECTORY}"
mkdir -p "$ONCAST_OUTPUT"
ONCAST_OUTPUT="$(cd "$ONCAST_OUTPUT" && pwd)"
cd "$ONCAST_ROOT"

ONCAST_TEMP="$(mktemp -d)"
trap 'rm -rf "$ONCAST_TEMP"' EXIT
export GIT_INDEX_FILE="$ONCAST_TEMP/index"
git read-tree HEAD
git add -A -- .
ONCAST_TREE="$(git write-tree)"
ONCAST_ARCHIVE="$ONCAST_OUTPUT/Oncast-source-$ONCAST_TREE.tar.gz"
git archive --format=tar --mtime=1970-01-01T00:00:00Z --prefix=Oncast-source/ "$ONCAST_TREE" \
    | gzip -n > "$ONCAST_ARCHIVE"
(
    cd "$ONCAST_OUTPUT"
    shasum -a 256 "$(basename "$ONCAST_ARCHIVE")" > "$(basename "$ONCAST_ARCHIVE").sha256"
)
printf '%s\n' "$ONCAST_ARCHIVE"
