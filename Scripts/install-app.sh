#!/bin/zsh
# Build KLYC-Box and install it as a normal Mac app in /Applications. Run it again to update:
# your games and settings live outside the app (see `klycbox config`), so they are untouched.
# Usage: Scripts/install-app.sh [--pull] [--test] [--debug]
#   --pull   git pull origin main first
#   --test   run the test suite first and stop if it is not green
#   --debug  install a debug build (faster to build)
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG=release; PULL=0; TEST=0
for a in "$@"; do case "$a" in --pull) PULL=1;; --test) TEST=1;; --debug) CONFIG=debug;; *) echo "unknown option $a" >&2; exit 1;; esac; done
[ "$PULL" = 1 ] && git pull --ff-only origin main
if [ "$TEST" = 1 ]; then
  swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1 | grep -q " 0 failures" || { echo "tests are not green, not installing" >&2; exit 1; }
fi
VERSION="$(git describe --tags --always 2>/dev/null || echo dev)"; VERSION="${VERSION#v}"
# A stable signature is what lets macOS remember the permissions it asked for (the drive prompt) across rebuilds.
# Opt out with KLYC_SIGN_LOCAL=0. The first build asks once for the login password: choose "Always Allow".
KLYC_SIGN_LOCAL="${KLYC_SIGN_LOCAL:-1}" KLYC_UNNOTARIZED=1 Scripts/make-app.sh "$CONFIG" "${VERSION%%-*}" >/dev/null
DEST=/Applications/KLYC-Box.app
if pgrep -x KLYC-Box >/dev/null; then
  echo "closing the running KLYC-Box…"; osascript -e 'tell application "KLYC-Box" to quit' >/dev/null 2>&1 || true
  for i in {1..20}; do pgrep -x KLYC-Box >/dev/null || break; sleep 1; done
  pgrep -x KLYC-Box >/dev/null && { echo "KLYC-Box is still running (a game open?). Quit it and run this again." >&2; exit 1; }
fi
rm -rf "$DEST"
ditto dist/KLYC-Box.app "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
echo "installed $DEST ($CONFIG, $VERSION)"
open "$DEST"
