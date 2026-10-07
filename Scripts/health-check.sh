#!/bin/zsh
# One command to see whether the project is in good shape. Exit 0 = all green.
# Usage: Scripts/health-check.sh [--engines-only] [--quick]   (--quick skips the test run)
cd "$(dirname "$0")/.."
ENGINE_BACKUP="${ENGINE_BACKUP:-$(cd .. && pwd)/engine-backup}"
FAIL=0
ok()   { print -P "%F{green}✔%f $1"; }
bad()  { print -P "%F{red}✘%f $1"; FAIL=1; }
warn() { print -P "%F{yellow}!%f $1"; }

engines() {
  python3 - "$ENGINE_BACKUP" <<'PY'
import json, glob, hashlib, os, sys
b = sys.argv[1]; bad = 0; n = 0
for mf in ['spike/engine-manifest.json'] + sorted(glob.glob('spike/engines/*.json')):
    m = json.load(open(mf))
    for name, c in m['components'].items():
        if 'apple' in c.get('license', '').lower() or c.get('acceptance'): continue   # D3DMetal is never mirrored
        p = os.path.join(b, c['url'].split('/')[-1])
        if not os.path.exists(p): continue          # only the engines we back up
        n += 1
        if hashlib.sha256(open(p, 'rb').read()).hexdigest() != c['sha256']:
            print('  checksum mismatch:', p); bad += 1
print(f'  {n} component files checked'); sys.exit(1 if bad else 0)
PY
}
if [ "${1:-}" = --engines-only ]; then engines; exit $?; fi

# 1. git state
git diff-index --quiet HEAD -- && ok "working tree clean" || warn "uncommitted changes"
git fetch -q origin 2>/dev/null
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main 2>/dev/null)" ] && ok "HEAD matches origin/main (backed up on GitHub)" || warn "HEAD differs from origin/main (push or pull)"

# 2. secrets in tracked files
if git grep -InE -- '-----BEGIN [A-Z ]*PRIVATE KEY|ghp_[A-Za-z0-9]{20,}|github_pat_|AKIA[0-9A-Z]{16}|xox[bp]-[0-9A-Za-z-]{10,}|password *= *"[^"]+"' -- . ':!db' ':!recipes' ':!Scripts/health-check.sh' >/tmp/klyc-secrets.txt; then bad "possible secrets: $(head -3 /tmp/klyc-secrets.txt)"; else ok "no secrets in tracked files"; fi

# 3. leftovers of the old name (engine download URLs, the manifest tests and the credits and the Atlas texts, which name the Highball project as the source of the trials, are the known exceptions: Highball is thanked by name)
LEFT=$(git grep -Iil 'highball\|gauthier\|piarrette' -- . ':!spike/engine-manifest.json' ':!spike/engines' ':!Tests/Fixtures' ':!Tests/KLYCKitTests/BundledEngineTests.swift' ':!NOTICE.md' ':!CHANGELOG.md' ':!README.md' ':!spike/patches' ':!Scripts/build-moltenvk.sh' ':!spike/nvapi-stub' ':!Scripts/health-check.sh' ':!Sources/KLYCKit/Credits.swift' ':!Sources/KLYCKit/L10nTRKit.swift' ':!Tests/KLYCKitTests/CreditsTests.swift' ':!Scripts/stage-engine-mirror.py' ':!Scripts/check-engine-urls.py' ':!Sources/KLYCKit/AtlasFeed.swift' ':!Tests/KLYCKitTests/AtlasFeedTests.swift' | head -5)
[ -z "$LEFT" ] && ok "no old-name leftovers outside the known exceptions" || bad "old name still in: $LEFT"

# 4. build, warnings, tests
touch Sources/*/*.swift
OUT=$(swift build 2>&1); echo "$OUT" | grep -q "Build complete" && ok "builds" || bad "build failed"
W=$(echo "$OUT" | sed 's/\x1b\[[0-9;]*m//g' | grep -c "^/.*warning:")
[ "$W" -le 8 ] && ok "compiler warnings: $W (the 5 known concurrency ones)" || warn "compiler warnings: $W"
if [ "${1:-}" != --quick ]; then
  swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1 | grep -q " 0 failures" && ok "all tests pass" || bad "tests fail"
fi

# 5. recipes and game database decode
swift build --product klycbox >/dev/null 2>&1
R=0; for f in recipes/launchers/*.json recipes/games/*.json recipes/tweaks/*.json; do .build/debug/klycbox recipe show "$f" >/dev/null 2>&1 || { bad "recipe does not decode: $f"; R=1; }; done
[ $R = 0 ] && ok "all recipes decode"
python3 - <<'PY' && ok "game database entries are valid JSON" || bad "game database has invalid JSON"
import json, glob, sys
for f in glob.glob('db/games/*.json') + ['db/anticheat.json']: json.load(open(f))
PY

# 6. engine backup
if [ -d "$ENGINE_BACKUP" ]; then engines >/dev/null && ok "engine component backup matches the manifests" || bad "engine backup is damaged"; else warn "no engine backup at $ENGINE_BACKUP"; fi

# 7. installed app
APP=/Applications/KLYC-Box.app
[ -d "$APP" ] && ok "installed: $(defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null)" || warn "not installed in /Applications (Scripts/install-app.sh)"
[ $FAIL = 0 ] && print -P "%F{green}all green%f" || print -P "%F{red}problems found%f"
exit $FAIL
