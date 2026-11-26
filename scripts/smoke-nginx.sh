#!/usr/bin/env bash
# Checks a built nginx folder the way FloServer uses it: started with its own
# -p, -c and -e, serving a file over HTTPS with HTTP/2, then stopped.
#   scripts/smoke-nginx.sh <nginx folder> <expected version>
set -euo pipefail
DIR=$(cd "$1" && pwd); WANT=$2
WORK=$(mktemp -d)
cleanup() { [ -f "$WORK/nginx.pid" ] && kill "$(cat "$WORK/nginx.pid")" 2>/dev/null || true; rm -rf "$WORK"; }
trap cleanup EXIT
fail() { echo "::error title=nginx smoke test::$1"; [ -f "$WORK/logs/error.log" ] && tail -20 "$WORK/logs/error.log"; exit 1; }

V=$("$DIR/nginx" -v 2>&1)
[ "$V" = "nginx version: nginx/$WANT" ] || fail "nginx -v says: $V"
INFO=$("$DIR/nginx" -V 2>&1)
case "$INFO" in *"built with OpenSSL"*) ;; *) fail "nginx -V doesn't name OpenSSL" ;; esac
# Nothing may point into the build machine's temporary folders.
LEAKS=$(strings "$DIR/nginx" | grep -E '^/(tmp|private/var|var/folders|Users|home/runner)/' || true)
[ -z "$LEAKS" ] || fail "build paths compiled in: $(echo "$LEAKS" | head -3 | tr '\n' ' ')"
for f in mime.types fastcgi_params fastcgi.conf; do [ -f "$DIR/conf/$f" ] || fail "conf/$f missing"; done
[ -f "$DIR/floserver-build.json" ] || fail "floserver-build.json missing"
ls "$DIR/licenses/"* >/dev/null || fail "licenses missing"

mkdir -p "$WORK/logs" "$WORK/temp" "$WORK/www"
printf "floserver smoke" > "$WORK/www/index.html"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 \
  -subj "/CN=smoke.localhost" -addext "subjectAltName=DNS:smoke.localhost" \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
PORT=$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])')
USER_LINE=""; [ "$(id -u)" = 0 ] && USER_LINE="user root;"
cat > "$WORK/nginx.conf" <<CONF
$USER_LINE
worker_processes 1;
pid $WORK/nginx.pid;
error_log $WORK/logs/error.log;
events {}
http {
  include $DIR/conf/mime.types;
  access_log off;
  client_body_temp_path $WORK/temp/b; proxy_temp_path $WORK/temp/p; fastcgi_temp_path $WORK/temp/f;
  uwsgi_temp_path $WORK/temp/u; scgi_temp_path $WORK/temp/s;
  server {
    listen 127.0.0.1:$PORT ssl;
    http2 on;
    server_name smoke.localhost;
    ssl_certificate $WORK/cert.pem;
    ssl_certificate_key $WORK/key.pem;
    root $WORK/www;
  }
}
CONF
NG=("$DIR/nginx" -p "$WORK/" -c "$WORK/nginx.conf" -e "$WORK/logs/error.log")
"${NG[@]}" -t -q || fail "nginx -t refused the config"
"${NG[@]}"
for _ in $(seq 50); do [ -f "$WORK/nginx.pid" ] && break; sleep 0.1; done
OUT=$(curl -sS --http2 --cacert "$WORK/cert.pem" --resolve "smoke.localhost:$PORT:127.0.0.1" \
  -w ' %{http_version}' "https://smoke.localhost:$PORT/") || fail "curl failed"
[ "$OUT" = "floserver smoke 2" ] || fail "unexpected answer: $OUT"
"${NG[@]}" -s stop
echo "nginx smoke test passed: $V"
