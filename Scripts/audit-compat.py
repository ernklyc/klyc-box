#!/usr/bin/env python3
"""Compare db/games statuses with what the Steam store says about a Mac build.

A game the store lists for macOS must never be shown as "unsupported" on a Mac, and a status that claims
something the store contradicts needs a human look. Read-only: prints a report, changes nothing.
Usage: Scripts/audit-compat.py
"""
import glob, json, sys, urllib.parse, urllib.request

ALLOWED = {"verified-local", "reported-upstream", "community", "blocked-anticheat", "blocked-publisher"}

def entries():
    for path in sorted(glob.glob("db/games/*.json")):
        d = json.load(open(path))
        yield path, d

def mac_flags(appids):
    out = {}
    for i in range(0, len(appids), 100):
        chunk = appids[i:i + 100]
        inp = {"ids": [{"appid": a} for a in chunk], "context": {"language": "english", "country_code": "US"},
               "data_request": {"include_platforms": True}}
        url = "https://api.steampowered.com/IStoreBrowseService/GetItems/v1/?input_json=" + urllib.parse.quote(json.dumps(inp))
        data = json.load(urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "klyc-box-audit"}), timeout=30))
        for item in data.get("response", {}).get("store_items", []):
            out[item.get("appid") or item.get("id")] = bool((item.get("platforms") or {}).get("mac"))
    return out

rows = [(p, d) for p, d in entries()]
bad = [(p, d["status"]) for p, d in rows if d.get("status") not in ALLOWED]
for p, s in bad:
    print(f"UNKNOWN STATUS  {p}: {s}")
ids = sorted({d["steam_appid"] for _, d in rows if d.get("steam_appid")})
flags = mac_flags(ids)
conflicts = 0
for p, d in rows:
    appid = d.get("steam_appid")
    if not appid or appid not in flags:
        continue
    if d["status"].startswith("blocked-") and flags[appid]:
        conflicts += 1
        print(f"BLOCKED BUT HAS A MAC BUILD  {d['title']} ({appid}) {d['status']}  -> label must say: Mac build exists; Windows build blocked")
no_source = [d["title"] for _, d in rows if d["status"] in ("community", "reported-upstream") and not (d.get("provenance") or "").strip()]
for t in no_source:
    print(f"NO PROVENANCE  {t}")
print(f"\n{len(rows)} entries, {len(ids)} with a Steam id, {len(flags)} answered by the store; "
      f"{conflicts} blocked-with-Mac-build, {len(no_source)} without provenance, {len(bad)} unknown statuses")
sys.exit(1 if bad else 0)
