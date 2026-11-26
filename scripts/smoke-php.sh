#!/usr/bin/env bash
# Checks a built PHP folder the way FloServer uses it.
#   scripts/smoke-php.sh <php folder> <expected version>
set -euo pipefail
DIR=$(cd "$1" && pwd); WANT=$2
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
CGIPID=""
trap '[ -n "$CGIPID" ] && kill "$CGIPID" 2>/dev/null; rm -rf "$WORK"' EXIT
fail() { echo "::error title=PHP smoke test::$1"; exit 1; }
PHP="$DIR/bin/php"; CGI="$DIR/bin/php-cgi"

GOT=$("$PHP" -n -r 'echo PHP_VERSION;')
[ "$GOT" = "$WANT" ] || fail "php says $GOT"
CGIV=$("$CGI" -n -v)
case "$CGIV" in "PHP $WANT (cgi-fcgi)"*) ;; *) fail "php-cgi isn't $WANT's CGI/FastCGI SAPI: $(echo "$CGIV" | head -1)" ;; esac

# No php.ini or conf.d is read unless one is named (run from an empty folder,
# without PHPRC/PHP_INI_SCAN_DIR, as FloServer starts it).
echo '<?php echo var_export(php_ini_loaded_file(), true), " ", var_export(php_ini_scanned_files(), true);' > "$WORK/ini.php"
for bin in "$PHP" "$CGI"; do
  INI=$(cd "$WORK" && env -u PHPRC -u PHP_INI_SCAN_DIR "$bin" -q ini.php 2>&1)
  [ "$INI" = "false false" ] || fail "$(basename "$bin") reads an ini file nobody named: $INI"
done

MODS=$("$PHP" -n -m | tr 'A-Z' 'a-z')
for ext in $(grep -v '^#' "$ROOT/php/extensions.txt"); do
  printf '%s\n' "$MODS" | grep -qx "$ext" || fail "built-in extension $ext is missing"
done
printf '%s\n' "$MODS" | grep -qx "zend opcache" || fail "opcache is missing"
for so in $(grep -v '^#' "$ROOT/php/shared-extensions.txt"); do
  [ -f "$DIR/ext/$so.so" ] || fail "ext/$so.so missing"
done
# Only stable releases (no alpha, beta or RC) of the .so extensions.
for so in $(grep -v '^#' "$ROOT/php/shared-extensions.txt"); do
  load="-d extension=$DIR/ext/$so.so"; [ "$so" = xdebug ] && load="-d zend_extension=$DIR/ext/$so.so"
  ver=$("$PHP" -n $load -r "echo phpversion('$so');")
  [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "$so $ver isn't a stable release (pin one in php/pinned-sources.txt)"
  echo "$so $ver"
done
"$PHP" -n -d extension_dir="$DIR/ext" -d extension=redis -r 'exit(extension_loaded("redis") ? 0 : 1);' || fail "redis.so doesn't load"
XD=$("$PHP" -n -d zend_extension="$DIR/ext/xdebug.so" -r 'echo extension_loaded("xdebug") ? "yes" : "no";')
[ "$XD" = yes ] || fail "xdebug.so doesn't load"
"$PHP" -n -d extension_dir="$DIR/ext" -d extension=pcov -r 'exit(extension_loaded("pcov") ? 0 : 1);' || fail "pcov.so doesn't load"

# TLS with the system's certificates, as Composer and curl calls need.
"$PHP" -n -r '$l = openssl_get_cert_locations(); exit(is_file($l["default_cert_file"]) || is_dir($l["default_cert_dir"]) ? 0 : 1);' \
  || fail "openssl's default certificate file/folder isn't on this system: $("$PHP" -n -r 'print_r(openssl_get_cert_locations());' | tr '\n' ' ')"
"$PHP" -n -r '$c = curl_init("https://github.com/"); curl_setopt_array($c, [CURLOPT_NOBODY => true, CURLOPT_RETURNTRANSFER => true, CURLOPT_TIMEOUT => 30]); exit(curl_exec($c) !== false && curl_getinfo($c, CURLINFO_RESPONSE_CODE) > 0 ? 0 : 1);' \
  || fail "curl can't make a verified HTTPS request"
"$PHP" -n -r 'exit(file_get_contents("https://github.com/") !== false ? 0 : 1);' 2>/dev/null || fail "an https:// stream can't be opened"
"$PHP" -n -r 'exit(json_encode(["a"=>"ü"]) === "{\"a\":\"\\u00fc\"}" && mb_strlen("ئەم") === 3 ? 0 : 1);' || fail "json/mbstring"
"$PHP" -n -r 'exit(class_exists("IntlDateFormatter") && (new NumberFormatter("ar", NumberFormatter::DECIMAL))->format(1) !== "" ? 0 : 1);' || fail "intl without ICU data"

# FastCGI: php-cgi answering on a socket, as FloServer runs it.
echo '<?php echo "fcgi ", PHP_VERSION;' > "$WORK/i.php"
PORT=$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])')
PHP_FCGI_CHILDREN=0 "$CGI" -n -b "127.0.0.1:$PORT" & CGIPID=$!
for _ in $(seq 50); do python3 -c 'import socket,sys;socket.create_connection(("127.0.0.1",int(sys.argv[1])),1)' "$PORT" 2>/dev/null && break; sleep 0.1; done
REPLY=$(python3 "$(dirname "$0")/fcgi_get.py" "$PORT" "$WORK/i.php")
case "$REPLY" in *"fcgi $WANT") ;; *) fail "php-cgi's FastCGI answer: $(echo "$REPLY" | tail -1)" ;; esac
echo "PHP smoke test passed: $WANT on $("$PHP" -n -r 'echo php_uname("s"), " ", php_uname("m");')"
