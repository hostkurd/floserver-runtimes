#!/usr/bin/env python3
"""Sends one FastCGI request for a PHP file and prints the reply (smoke test).
    fcgi_get.py <port> <script path>"""
import socket, struct, sys

def record(kind, content, req=1):
    return struct.pack("!BBHHBx", 1, kind, req, len(content), 0) + content

def pair(k, v):
    k, v = k.encode(), v.encode()
    enc = lambda n: bytes([n]) if n < 128 else struct.pack("!I", n | 0x80000000)
    return enc(len(k)) + enc(len(v)) + k + v

port, script = int(sys.argv[1]), sys.argv[2]
params = b"".join(pair(k, v) for k, v in {
    "SCRIPT_FILENAME": script, "REQUEST_METHOD": "GET", "SCRIPT_NAME": "/i.php",
    "REQUEST_URI": "/i.php", "SERVER_PROTOCOL": "HTTP/1.1", "GATEWAY_INTERFACE": "CGI/1.1",
    "REDIRECT_STATUS": "200", "SERVER_NAME": "localhost", "SERVER_PORT": "80"}.items())
s = socket.create_connection(("127.0.0.1", port), timeout=10)
s.sendall(record(1, struct.pack("!HB5x", 1, 0)) + record(4, params) + record(4, b"") + record(5, b""))
out = b""
while True:
    head = s.recv(8)
    if len(head) < 8:
        break
    _, kind, _, length, pad = struct.unpack("!BBHHBx", head)
    body = b""
    while len(body) < length + pad:
        body += s.recv(length + pad - len(body))
    if kind == 6:
        out += body[:length]
    if kind == 3:
        break
sys.stdout.write(out.decode("utf-8", "replace"))
