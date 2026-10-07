#!/usr/bin/env python3
"""Checks that every download of the default engine is still there (a HEAD request each), and says
whose server it lives on, so a dependency that disappears is noticed before a user's install fails.
Needs the network; run it from time to time, not in the quick health check.

Usage: Scripts/check-engine-urls.py [manifest.json]
"""
import json, sys, urllib.request

def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "spike/engine-manifest.json"
    manifest = json.load(open(path))
    seen, bad = set(), 0
    for name, comp in manifest["components"].items():
        url = comp["url"]
        if url in seen:
            continue
        seen.add(url)
        owner = "/".join(url.split("/")[3:5])
        try:
            req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": "klyc-check"})
            with urllib.request.urlopen(req, timeout=30) as r:
                ok, note = r.status == 200, f"HTTP {r.status}"
        except Exception as e:  # noqa: BLE001
            ok, note = False, str(e)[:60]
        bad += not ok
        mine = "bizim" if owner.startswith("ernklyc/") else "BAŞKASININ"
        print(f"{'ok ' if ok else 'YOK'}  {name:16} {mine:10} {owner:28} {note}")
    print(f"\n{len(seen)} indirme, {bad} ulaşılamayan")
    sys.exit(1 if bad else 0)

if __name__ == "__main__":
    main()
