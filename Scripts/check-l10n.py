#!/usr/bin/env python3
"""Find repeated keys in the Turkish tables (a repeat crashes the app at launch) and UI strings with no Turkish.
Usage: Scripts/check-l10n.py   (exit 1 when a key is repeated)"""
import collections, glob, re, sys
tables = ("Sources/KLYCKit/L10nTR.swift", "Sources/KLYCKit/L10nTRKit.swift")
pair = re.compile(r'"((?:[^"\\]|\\.)*)"\s*:\s*"(?:[^"\\]|\\.)*"')
seen = collections.Counter()
dup = []
for f in tables:
    inside = collections.Counter(pair.findall(open(f).read()))   # a key in both tables is fine: the first table answers
    dup += [k for k, n in inside.items() if n > 1]
    for k in inside: seen[k] += 1
dup = sorted(set(dup))
for k in dup: print("DUPLICATE KEY:", k[:100])
missing = set()
for f in glob.glob("Sources/**/*.swift", recursive=True):
    if "L10n" in f: continue
    for m in re.finditer(r'\bL\("((?:[^"\\]|\\.)*)"\)', open(f).read()):
        if m.group(1) not in seen: missing.add(m.group(1))
for k in sorted(missing): print("NO TURKISH:", k[:100].replace("\n", " "))
print(f"{len(seen)} Turkish keys, {len(dup)} repeated, {len(missing)} UI strings without Turkish")
sys.exit(1 if dup else 0)
