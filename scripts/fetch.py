#!/usr/bin/env python3
"""Downloads one source archive listed in sources.json and checks its SHA-256.

    scripts/fetch.py <name> <version> <folder>   -> prints the saved file's path

Refuses (exit 1) when the name or version isn't listed or the hash differs;
a partial or wrong file is deleted.
"""
import hashlib
import json
import os
import sys
import urllib.request

def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__, file=sys.stderr)
        return 2
    name, version, folder = sys.argv[1:]
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, "..", "sources.json"), encoding="utf-8") as f:
        sources = json.load(f)
    entry = sources.get(name, {}).get(version)
    if not entry:
        print(f"::error title=fetch::{name} {version} isn't in sources.json", file=sys.stderr)
        return 1
    url, want = entry["url"], entry["sha256"].lower()
    if not url.startswith("https://"):
        print(f"::error title=fetch::{name} {version}: not an https address", file=sys.stderr)
        return 1
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, url.rsplit("/", 1)[-1])
    digest = hashlib.sha256()
    try:
        with urllib.request.urlopen(url, timeout=60) as reply, open(path + ".part", "wb") as out:
            while True:
                chunk = reply.read(1 << 16)
                if not chunk:
                    break
                digest.update(chunk)
                out.write(chunk)
    except Exception as e:  # noqa: BLE001 - any failure is reported the same way
        print(f"::error title=fetch::{name} {version}: {e}", file=sys.stderr)
        if os.path.exists(path + ".part"):
            os.remove(path + ".part")
        return 1
    got = digest.hexdigest()
    if got != want:
        os.remove(path + ".part")
        print(f"::error title=fetch::{name} {version}: SHA-256 is {got}, sources.json says {want}", file=sys.stderr)
        return 1
    os.replace(path + ".part", path)
    print(path)
    return 0

if __name__ == "__main__":
    sys.exit(main())
