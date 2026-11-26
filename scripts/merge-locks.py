#!/usr/bin/env python3
"""Merges the sources locks of several builds (one per platform) into one.
    merge-locks.py <lock to update> <lock>...
A name with different hashes on two platforms is an error."""
import json
import sys

target, others = sys.argv[1], sys.argv[2:]
with open(target, encoding="utf-8") as f:
    doc = json.load(f)
merged = dict(doc.get("sources", {}))
fresh = {}
for path in others:
    with open(path, encoding="utf-8") as f:
        for name, entry in json.load(f)["sources"].items():
            if name in fresh and fresh[name] != entry:
                sys.exit(f"::error title=sources lock::{name} differs between platforms: {fresh[name]} vs {entry}")
            fresh[name] = entry
merged.update(fresh)
doc["sources"] = dict(sorted(merged.items()))
with open(target, "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
print(f"{len(fresh)} sources from {len(others)} build(s); lock has {len(merged)}")
