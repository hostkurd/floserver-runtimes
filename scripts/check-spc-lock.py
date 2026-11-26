#!/usr/bin/env python3
"""Checks what static-php-cli downloaded against php/sources.lock.json.

static-php-cli fetches each library's newest release, unverified. This
compares every file and folder it recorded in downloads/.lock.json with the
SHA-256 committed in php/sources.lock.json, so a build only uses sources a
person has looked at; a new or changed source fails the build until the lock
is updated in a pull request. php-src is checked against php.net instead
(its hash is published per release).

    check-spc-lock.py check  <spc folder> <php version>
    check-spc-lock.py update <spc folder> <php version> <new lock file>

`update` writes the lock for what was downloaded (still checking php-src),
for a person to review and commit.
"""
import hashlib
import json
import os
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
LOCK = os.path.join(HERE, "..", "php", "sources.lock.json")


def error(message: str) -> None:
    print(f"::error title=sources lock::{message}", file=sys.stderr)


def file_sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def tree_sha256(root: str) -> str:
    """Every file's path, mode bit and contents, in order (.git left out)."""
    h = hashlib.sha256()
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d != ".git")
        for name in sorted(filenames):
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, root).replace(os.sep, "/")
            if os.path.islink(path):
                h.update(f"L {rel} {os.readlink(path)}\n".encode())
                continue
            executable = os.stat(path).st_mode & 0o111 != 0
            h.update(f"F {rel} {int(executable)} {file_sha256(path)}\n".encode())
    return h.hexdigest()


def php_net_sha256(version: str, filename: str) -> str | None:
    url = f"https://www.php.net/releases/index.php?json&version={version}"
    with urllib.request.urlopen(url, timeout=60) as reply:
        data = json.load(reply)
    for source in data.get("source", []):
        if source.get("filename") == filename:
            return source.get("sha256")
    return None


def main() -> int:
    if len(sys.argv) not in (4, 5) or sys.argv[1] not in ("check", "update"):
        print(__doc__, file=sys.stderr)
        return 2
    mode, spc, version = sys.argv[1:4]
    downloads = os.path.join(spc, "downloads")
    with open(os.path.join(downloads, ".lock.json"), encoding="utf-8") as f:
        spc_lock = json.load(f)
    with open(LOCK, encoding="utf-8") as f:
        ours = json.load(f).get("sources", {})

    seen = {}
    ok = True
    for name, entry in sorted(spc_lock.items()):
        kind = entry.get("source_type")
        if kind == "archive":
            target = entry.get("filename") or ""
            path = os.path.join(downloads, target)
            digest = file_sha256(path)
        elif kind in ("git", "dir", "local"):
            target = entry.get("dirname") or name
            path = os.path.join(downloads, target)
            digest = tree_sha256(path)
        else:
            error(f"{name}: unknown source type {kind!r}")
            ok = False
            continue
        if name == "php-src":
            want = php_net_sha256(version, target) if kind == "archive" else None
            if want is None or want.lower() != digest:
                error(f"php-src {target}: SHA-256 {digest} doesn't match php.net's ({want})")
                ok = False
            continue
        seen[name] = {"type": kind, "name": target, "sha256": digest}
        if mode == "check":
            have = ours.get(name)
            if have is None:
                error(f"{name} ({target}) isn't in php/sources.lock.json: run the workflow with update_lock and review it")
                ok = False
            elif have.get("sha256") != digest or have.get("name") != target:
                error(f"{name}: downloaded {target} {digest}, the lock has {have.get('name')} {have.get('sha256')}")
                ok = False

    if mode == "update":
        merged = dict(ours)
        merged.update(seen)
        with open(sys.argv[4], "w", encoding="utf-8") as f:
            json.dump({"_about": "SHA-256 of every source static-php-cli may use (scripts/check-spc-lock.py). "
                                 "Review changes before merging: they are what goes into FloServer's PHP.",
                       "sources": dict(sorted(merged.items()))}, f, indent=2)
            f.write("\n")
        print(f"lock written: {len(seen)} sources from this build")
    elif ok:
        print(f"all {len(seen)} sources match php/sources.lock.json; php-src matches php.net")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
