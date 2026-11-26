#!/usr/bin/env bash
# Builds a portable PHP (cli + cgi) for FloServer with static-php-cli.
#
#   scripts/build-php.sh <php version> <platform> <out folder>
#   e.g. scripts/build-php.sh 8.5.12 linux-x64 dist
#
# Linux: glibc build in static-php-cli's CentOS 7 container (glibc 2.17, so
# it runs on every supported distribution) — needs Docker. macOS: built on
# the Mac itself (Homebrew tools, PHP for static-php-cli).
#
# The extensions in extensions.txt are built in and always on (D36.3); the
# ones in shared-extensions.txt are .so files in ext/ that FloServer turns
# on per project. The folder made is what FloServer installs
# (runtimes/php/<version>): bin/php, bin/php-cgi, ext/*.so, licenses/,
# floserver-build.json.
set -euo pipefail

if [ $# -ne 3 ]; then
  sed -n '2,15p' "$0" >&2
  exit 2
fi
PHP=$1 PLATFORM=$2 OUT=$3
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
case "$PHP" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "PHP version must be x.y.z, not $PHP" >&2; exit 2 ;;
esac
SPC_VERSION=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["static-php-cli"]["version"])' "$ROOT/sources.json")
SPC_COMMIT=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["static-php-cli"]["commit"])' "$ROOT/sources.json")
# check: every source must match php/sources.lock.json (the default);
# update: write the lock for this build's sources to $OUT/sources.lock.json.
LOCK_MODE=${LOCK_MODE:-check}
STATIC=$(grep -v '^#' "$ROOT/php/extensions.txt" | tr -s ' \n' ',' | sed 's/^,//; s/,$//')
SHARED=$(grep -v '^#' "$ROOT/php/shared-extensions.txt" | tr -s ' \n' ',' | sed 's/^,//; s/,$//')

# opcache is part of PHP itself from 8.5, an extension to name before that.
case "$PHP" in
  8.2.*|8.3.*|8.4.*) STATIC="$STATIC,opcache" ;;
esac

SPC=${SPC_DIR:-$OUT/.spc}
if [ ! -d "$SPC/.git" ]; then
  git clone --quiet https://github.com/crazywhalecc/static-php-cli "$SPC"
fi
git -C "$SPC" fetch --quiet --depth 1 origin "$SPC_COMMIT"
git -C "$SPC" checkout --quiet "$SPC_COMMIT"
cd "$SPC"

case "$PLATFORM" in
  linux-*) CMD=(./bin/spc-gnu-docker) ;;
  macos-*)
    composer install --no-dev --classmap-authoritative --quiet
    ./bin/spc doctor --auto-fix
    CMD=(./bin/spc) ;;
  *) echo "unknown platform $PLATFORM" >&2; exit 2 ;;
esac

# Sources only (no pre-built libraries: everything is compiled here), then
# every downloaded file checked before anything is built from it.
PINNED=()
while read -r name url; do
  case "$name" in ''|'#'*) continue ;; esac
  case "$url" in https://*) ;; *) echo "php/pinned-sources.txt: $name needs an https address" >&2; exit 2 ;; esac
  PINNED+=(--custom-url="$name:$url")
done < "$ROOT/php/pinned-sources.txt"
"${CMD[@]}" download --with-php="$PHP" --for-extensions="$STATIC,$SHARED" --ignore-cache-sources=php-src ${PINNED[@]+"${PINNED[@]}"}
if [ "$LOCK_MODE" = update ]; then
  python3 "$HERE/check-spc-lock.py" update "$SPC" "$PHP" "$OUT/sources.lock.json"
else
  python3 "$HERE/check-spc-lock.py" check "$SPC" "$PHP"
fi
# FloServer always names its own php.ini (-c). The compiled-in path is a
# root-only folder nothing creates, and no conf.d is scanned, so a php.ini
# left by another install is never read.
"${CMD[@]}" build "$STATIC" --build-shared="$SHARED" --build-cli --build-cgi \
  --with-config-file-path=/etc/floserver-php-none --with-config-file-scan-dir=
"${CMD[@]}" dump-license --for-extensions="$STATIC,$SHARED" --dump-dir=buildroot/floserver-licenses

DEST="$OUT/php-$PHP"
rm -rf "$DEST"
mkdir -p "$DEST/bin" "$DEST/ext" "$DEST/licenses"
cp buildroot/bin/php buildroot/bin/php-cgi "$DEST/bin/"
for so in $(echo "$SHARED" | tr ',' ' '); do
  cp "buildroot/modules/$so.so" "$DEST/ext/"
done
cp -R buildroot/floserver-licenses/. "$DEST/licenses/"

# Each shared extension's own version, from PHP itself.
SHARED_VERSIONS=""
for so in $(echo "$SHARED" | tr ',' ' '); do
  load="-d extension=$DEST/ext/$so.so"
  [ "$so" = xdebug ] && load="-d zend_extension=$DEST/ext/$so.so"
  v=$("$DEST/bin/php" -n $load -r "echo phpversion('$so');" 2>/dev/null || true)
  SHARED_VERSIONS="$SHARED_VERSIONS$so=$v,"
done
python3 - "$DEST/floserver-build.json" "$STATIC" "$SHARED_VERSIONS" <<PY
import json, sys
json.dump({
    "schema": 1,
    "name": "php",
    "version": "$PHP",
    "platform": "$PLATFORM",
    "variant": "nts",
    "built_in_extensions": sorted(sys.argv[2].split(",")),
    "shared_extensions": dict(sorted(kv.split("=", 1) for kv in sys.argv[3].split(",") if kv)),
    "built_with": {"static-php-cli": "$SPC_VERSION ($SPC_COMMIT)"},
    "sources_lock": json.load(open("$ROOT/php/sources.lock.json"))["sources"] if "$LOCK_MODE" == "check" else None,
    "source": "https://github.com/hostkurd/floserver-runtimes",
}, open(sys.argv[1], "w"), indent=2)
PY
echo "$DEST"
