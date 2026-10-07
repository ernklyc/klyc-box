#!/bin/zsh
# Local backup of everything that cannot be rebuilt from the repo: a git bundle of the whole history,
# the small settings files of the data folder, and a check that the engine component backup is intact.
# Usage: Scripts/backup.sh [backup-root]     (default: a "backups" folder next to this repository, last 10 kept)
# Not included on purpose: games and Wine prefixes (huge, re-downloadable) and Epic/Steam logins.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="${1:-$(cd .. && pwd)/backups}"
STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="$ROOT/$STAMP"; mkdir -p "$DEST"
git bundle create "$DEST/klyc-box.bundle" --all >/dev/null 2>&1
git bundle verify "$DEST/klyc-box.bundle" >/dev/null 2>&1 || { echo "bundle failed verification" >&2; exit 1; }
HOME_DIR="$(.build/debug/klycbox config 2>/dev/null | sed -n 's/^home: \(.*\) (.*)$/\1/p; s/^home: \(.*\)$/\1/p' | head -1)"
if [ -n "$HOME_DIR" ] && [ -d "$HOME_DIR" ]; then
  mkdir -p "$DEST/data"
  for f in "$HOME_DIR"/*.json; do [ -f "$f" ] && cp "$f" "$DEST/data/"; done
  for b in "$HOME_DIR"/bottles/*/; do
    n="$(basename "$b")"; mkdir -p "$DEST/data/bottles/$n"
    [ -f "$b/bottle.json" ] && cp "$b/bottle.json" "$DEST/data/bottles/$n/"
  done
fi
CFG="$HOME/Library/Application Support/KLYC-Box/config.json"
[ -f "$CFG" ] && cp "$CFG" "$DEST/config.json"
Scripts/health-check.sh --engines-only >/dev/null || { echo "engine backup check failed (run Scripts/health-check.sh)" >&2; exit 1; }
echo "backup written to $DEST ($(du -sh "$DEST" | cut -f1))"
# keep the newest 10
ls -1d "$ROOT"/*/ 2>/dev/null | sort -r | tail -n +11 | while read -r old; do rm -rf "$old"; done
