#!/usr/bin/env bash
# Checks a built PHP folder the way FloServer uses it.
#   scripts/smoke-php.sh <php folder>
set -euo pipefail
DIR=$(cd "$1" && pwd)
ROOT=$(cd "$(dirname "$0")/.." && pwd)
fail() { echo "::error title=PHP smoke test::$1"; exit 1; }
PHP="$DIR/bin/php"; CGI="$DIR/bin/php-cgi"
"$PHP" -n -v | head -1
"$CGI" -n -v | grep -q "(cgi-fcgi)" || fail "php-cgi isn't the CGI/FastCGI SAPI"
"$PHP" -n -r 'exit(php_ini_loaded_file() === false && php_ini_scanned_files() === false ? 0 : 1);' \
  || fail "a php.ini or conf.d is read without being named"
MODS=$("$PHP" -n -m | tr 'A-Z' 'a-z')
for ext in $(grep -v '^#' "$ROOT/php/extensions.txt"); do
  echo "$MODS" | grep -qx "$ext" || fail "built-in extension $ext is missing"
done
echo "$MODS" | grep -qx "zend opcache" || fail "opcache is missing"
for so in $(grep -v '^#' "$ROOT/php/shared-extensions.txt"); do
  [ -f "$DIR/ext/$so.so" ] || fail "ext/$so.so missing"
done
"$PHP" -n -d extension_dir="$DIR/ext" -d extension=redis -r 'exit(extension_loaded("redis") ? 0 : 1);' || fail "redis.so doesn't load"
"$PHP" -n -d zend_extension="$DIR/ext/xdebug.so" -v | grep -q "Xdebug" || fail "xdebug.so doesn't load"
"$PHP" -n -d extension_dir="$DIR/ext" -d extension=pcov -r 'exit(extension_loaded("pcov") ? 0 : 1);' || fail "pcov.so doesn't load"
"$PHP" -n -r 'exit(openssl_get_cert_locations()["default_cert_file"] !== "" ? 0 : 1);' || fail "openssl has no default certificate file"
"$PHP" -n -r 'exit(function_exists("curl_init") && curl_version()["ssl_version"] !== "" ? 0 : 1);' || fail "curl without TLS"
"$PHP" -n -r 'exit(json_encode(["a"=>"ü"]) === "{\"a\":\"\\u00fc\"}" && mb_strlen("ئەم") === 3 ? 0 : 1);' || fail "json/mbstring"
"$PHP" -n -r 'exit(class_exists("IntlDateFormatter") && (new NumberFormatter("ar", NumberFormatter::DECIMAL))->format(1) !== "" ? 0 : 1);' || fail "intl without ICU data"
# FastCGI: php-cgi answering on a socket, as FloServer runs it.
WORK=$(mktemp -d); trap 'kill $CGIPID 2>/dev/null || true; rm -rf "$WORK"' EXIT
echo '<?php echo "fcgi ", PHP_VERSION;' > "$WORK/i.php"
PORT=$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])')
PHP_FCGI_CHILDREN=0 "$CGI" -n -b "127.0.0.1:$PORT" & CGIPID=$!
sleep 1
python3 "$(dirname "$0")/fcgi_get.py" "$PORT" "$WORK/i.php" | grep -q "fcgi " || fail "php-cgi didn't answer over FastCGI"
echo "PHP smoke test passed: $("$PHP" -n -r 'echo PHP_VERSION, " ", php_uname("s"), " ", php_uname("m");')"
