#!/usr/bin/env bash
# Packs a built runtime folder as <folder>-<platform>.tar.gz with a .sha256
# next to it, the way FloServer installs it (one top folder, exec bits kept).
#   scripts/package.sh <built folder> <platform> <out folder>
set -euo pipefail
SRC=$(cd "$1" && pwd); PLATFORM=$2; OUT=$3
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
NAME=$(basename "$SRC")-$PLATFORM.tar.gz
# Owner, group and times made neutral, so the archive says nothing about the
# machine it was built on (and macOS adds no ._ files or extended attributes).
STAMP=${SOURCE_DATE_EPOCH:-1767225600}  # 2026-01-01
TAR_VERSION=$(tar --version 2>/dev/null || true)
case "$TAR_VERSION" in
  *GNU*)
    tar --owner=0 --group=0 --numeric-owner --sort=name --mtime="@$STAMP" \
      -C "$(dirname "$SRC")" -czf "$OUT/$NAME" "$(basename "$SRC")" ;;
  *)
    find "$SRC" -exec touch -h -t "$(date -u -r "$STAMP" +%Y%m%d%H%M.%S)" {} +
    COPYFILE_DISABLE=1 tar --uid 0 --gid 0 --no-mac-metadata --no-xattrs \
      -C "$(dirname "$SRC")" -czf "$OUT/$NAME" "$(basename "$SRC")" ;;
esac
( cd "$OUT" && (sha256sum "$NAME" 2>/dev/null || shasum -a 256 "$NAME") > "$NAME.sha256" )
echo "$OUT/$NAME"
