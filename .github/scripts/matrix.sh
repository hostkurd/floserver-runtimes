#!/usr/bin/env bash
# Prints the build matrix for the chosen platforms: GitHub runner per platform.
# Linux builds on Ubuntu 22.04 (glibc 2.35, the oldest FloServer supports, D36.2).
set -euo pipefail
case "$1" in
  linux-x64) list='["linux-x64"]' ;;
  macos-arm64) list='["macos-arm64"]' ;;
  both) list='["linux-x64","macos-arm64"]' ;;
  *) echo "unknown platforms: $1" >&2; exit 1 ;;
esac
python3 - "$list" <<'PY'
import json, sys
runners = {"linux-x64": "ubuntu-22.04", "macos-arm64": "macos-15"}
print(json.dumps({"include": [{"platform": p, "runner": runners[p]} for p in json.loads(sys.argv[1])]}))
PY
