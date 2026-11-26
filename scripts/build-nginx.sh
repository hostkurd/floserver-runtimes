#!/usr/bin/env bash
# Builds a portable nginx for FloServer on Linux or macOS.
#
#   scripts/build-nginx.sh <nginx> <openssl> <pcre2> <zlib> <platform> <out folder>
#   e.g. scripts/build-nginx.sh 1.30.6 3.5.9 10.49 1.3.2 linux-x64 dist
#
# OpenSSL, PCRE2 and zlib are built into the program (static), so it needs
# only the system's C library. The folder it makes is what FloServer installs
# (runtimes/nginx/<version>): `nginx`, `conf/` (mime.types, fastcgi_params…),
# `licenses/` and `floserver-build.json`. FloServer always starts it with its
# own -p and -c, so the paths compiled in don't matter.
set -euo pipefail

if [ $# -ne 6 ]; then
  sed -n '2,10p' "$0" >&2
  exit 2
fi
NGINX=$1 OPENSSL=$2 PCRE2=$3 ZLIB=$4 PLATFORM=$5 OUT=$6
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

for pair in "nginx $NGINX" "openssl $OPENSSL" "pcre2 $PCRE2" "zlib $ZLIB"; do
  set -- $pair
  file=$("$HERE/fetch.py" "$1" "$2" "$WORK/download")
  tar -xzf "$file" -C "$WORK"
done
SRC="$WORK/nginx-$NGINX"
JOBS=$( (nproc || sysctl -n hw.ncpu) 2>/dev/null || echo 2)

cd "$SRC"
# --with-cc-opt / --with-ld-opt: hardening, as distributions build it.
CC_OPT="-O2 -fstack-protector-strong -fPIE"
LD_OPT=""
EXTRA=()
case "$PLATFORM" in
  linux-*) CC_OPT="$CC_OPT -D_FORTIFY_SOURCE=2"; LD_OPT="-pie -Wl,-z,relro -Wl,-z,now"; EXTRA=(--with-file-aio) ;;
  macos-*) ;;
  *) echo "unknown platform $PLATFORM" >&2; exit 2 ;;
esac
./configure \
  --prefix=. \
  --sbin-path=nginx \
  --conf-path=conf/nginx.conf \
  --pid-path=logs/nginx.pid \
  --error-log-path=logs/error.log \
  --http-log-path=logs/access.log \
  --http-client-body-temp-path=temp/client_body \
  --http-proxy-temp-path=temp/proxy \
  --http-fastcgi-temp-path=temp/fastcgi \
  --http-uwsgi-temp-path=temp/uwsgi \
  --http-scgi-temp-path=temp/scgi \
  --with-threads \
  --with-http_ssl_module \
  --with-http_v2_module \
  --with-http_realip_module \
  --with-http_gzip_static_module \
  --with-http_gunzip_module \
  --with-http_stub_status_module \
  --with-http_sub_module \
  --with-pcre="$WORK/pcre2-$PCRE2" --with-pcre-jit \
  --with-zlib="$WORK/zlib-$ZLIB" \
  --with-openssl="$WORK/openssl-$OPENSSL" \
  --with-openssl-opt="no-shared no-tests no-docs" \
  --with-cc-opt="$CC_OPT" \
  --with-ld-opt="$LD_OPT" \
  ${EXTRA[@]+"${EXTRA[@]}"}
make -j"$JOBS"

DEST="$OUT/nginx-$NGINX"
rm -rf "$DEST"
mkdir -p "$DEST/conf" "$DEST/licenses"
cp objs/nginx "$DEST/nginx"
strip "$DEST/nginx" 2>/dev/null || strip -x "$DEST/nginx"
cp conf/* "$DEST/conf/"
cp LICENSE "$DEST/licenses/nginx-LICENSE" 2>/dev/null || cp docs/text/LICENSE "$DEST/licenses/nginx-LICENSE"
cp "$WORK/openssl-$OPENSSL/LICENSE.txt" "$DEST/licenses/openssl-LICENSE.txt"
cp "$WORK/pcre2-$PCRE2/LICENCE.md" "$DEST/licenses/pcre2-LICENCE.md" 2>/dev/null || cp "$WORK/pcre2-$PCRE2/LICENCE" "$DEST/licenses/pcre2-LICENCE"
cp "$WORK/zlib-$ZLIB/LICENSE" "$DEST/licenses/zlib-LICENSE" 2>/dev/null || sed -n '/Copyright/,$p' "$WORK/zlib-$ZLIB/README" > "$DEST/licenses/zlib-LICENSE"

python3 - "$DEST/floserver-build.json" <<PY
import json, sys
json.dump({
    "schema": 1,
    "name": "nginx",
    "version": "$NGINX",
    "platform": "$PLATFORM",
    "built_with": {"openssl": "$OPENSSL", "pcre2": "$PCRE2", "zlib": "$ZLIB"},
    "source": "https://github.com/hostkurd/floserver-runtimes",
}, open(sys.argv[1], "w"), indent=2)
PY
echo "$DEST"
