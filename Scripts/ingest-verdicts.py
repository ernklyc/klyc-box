#!/usr/bin/env python3
"""Fold exported "your results" (Settings -> General -> Export your results) into db/games.

A result that works becomes a "verified-local" row for that game: chip, macOS, engine, the frame rate the
player saw, and the date. A game the database does not know yet gets a new file. Results that did not work
are listed, never written. Run with --dry-run to see what would change.

Usage: Scripts/ingest-verdicts.py [--dry-run] klycbox-my-results.json
"""
import json, re, sys, glob, os

def slug(title):
    return re.sub(r'[^a-z0-9]+', '-', title.lower()).strip('-')

def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    dry = '--dry-run' in sys.argv
    if len(args) != 1:
        sys.exit(__doc__)
    results = json.load(open(args[0]))
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'db', 'games')
    by_appid = {}
    for path in glob.glob(os.path.join(root, '*.json')):
        row = json.load(open(path))
        if row.get('steam_appid'):
            by_appid[row['steam_appid']] = (path, row)
    for key, v in sorted(results.items()):
        title = v.get('title') or key
        if not key.startswith('steam:'):
            print(f'skip {title}: only Steam games are folded in for now'); continue
        if not v.get('works'):
            print(f'not written ({title}): it did not work on {v["chip"]}, macOS {v["macos"]}'); continue
        appid = int(key.split(':')[1])
        date = v['date'][:10]
        fps = f'about {v["fps"]}' if v.get('fps') else None
        path, row = by_appid.get(appid, (None, None))
        created = row is None
        if created:
            row = {'id': slug(title), 'title': title, 'steam_appid': appid, 'renderer': v.get('renderer'), 'anticheat': None,
                   'notes': None, 'knownIssues': [], 'launchArgs': None}
            path = os.path.join(root, row['id'] + '.json')
        row['status'] = 'verified-local'
        row['verified'] = {'chip': v['chip'], 'macos': v['macos'], 'engine': v['engine'], 'fps': fps}
        row['lastVerified'] = date
        row['provenance'] = f'Verified by the maintainer on {v["chip"]}, macOS {v["macos"]}, engine {v["engine"]}, {date}.'
        if not row.get('renderer') and v.get('renderer'):
            row['renderer'] = v['renderer']
        print(('new   ' if created else 'update'), os.path.relpath(path), '<-', title, v['chip'], fps or '')
        if not dry:
            with open(path, 'w') as f:
                json.dump(row, f, indent=2, ensure_ascii=False); f.write('\n')

main()
