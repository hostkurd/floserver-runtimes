#!/usr/bin/env bash
# Packs a built runtime folder as <folder>-<platform>.tar.gz with a .sha256
# next to it, the way FloServer installs it (one top folder, exec bits kept).
#   scripts/package.sh <built folder> <platform> <out folder>
set -euo pipefail
SRC=$(cd "$1" && pwd); PLATFORM=$2; OUT=$3
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
NAME=$(basename "$SRC")-$PLATFORM.tar.gz
# Owner, group and times made neutral, so the archive says nothing about the
# machine it was built on.
if tar --version 2>/dev/null | grep -q GNU; then
  tar --owner=0 --group=0 --numeric-owner --sort=name -C "$(dirname "$SRC")" -czf "$OUT/$NAME" "$(basename "$SRC")"
else
  tar --uid 0 --gid 0 -C "$(dirname "$SRC")" -czf "$OUT/$NAME" "$(basename "$SRC")"
fi
( cd "$OUT" && (sha256sum "$NAME" 2>/dev/null || shasum -a 256 "$NAME") > "$NAME.sha256" )
echo "$OUT/$NAME"
