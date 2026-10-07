#!/bin/zsh
# Cut a KLYC-Box release: build, zip, sign for Sparkle, update appcast.xml, tag, publish on GitHub.
# Usage: Scripts/release-klyc.sh [--dry-run] <version> "One-line summary" [notes-file.md]
#   --dry-run  build and sign the zip and show the appcast item, change and publish nothing.
# Needs: the Sparkle key in the login keychain (generate_keys), gh logged in, a clean git tree.
# Unnotarized unless a Developer ID certificate and a notarytool profile exist (see make-app.sh);
# set KLYC_UNNOTARIZED=1 to build anyway. (The upstream KLYC-Box script, release.sh, stays for reference.)
set -euo pipefail
cd "$(dirname "$0")/.."
DRY=0; [ "${1:-}" = --dry-run ] && { DRY=1; shift; }
VERSION="${1:?usage: release-klyc.sh [--dry-run] <version> <summary> [notes.md]}"
SUMMARY="${2:?summary required}"
NOTES_FILE="${3:-}"
REPO="ernklyc/klyc-box"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must look like 0.1.0" >&2; exit 1; }
if [ "$DRY" = 0 ]; then
  [ "$(git branch --show-current)" = main ] || { echo "release from the main branch: installs read appcast.xml from main" >&2; exit 1; }
  git diff-index --quiet HEAD -- || { echo "tracked files modified; commit before releasing" >&2; exit 1; }
  git rev-parse "v$VERSION" >/dev/null 2>&1 && { echo "tag v$VERSION already exists" >&2; exit 1; }
  grep -q "releases/download/v$VERSION/" appcast.xml && { echo "v$VERSION is already in appcast.xml" >&2; exit 1; }
fi
# The tests are the release gate here: no red build ships.
swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1 | grep -q " 0 failures" || { echo "tests are not green" >&2; exit 1; }

export KLYC_UPDATES=1   # a release build carries the update feed
Scripts/make-app.sh release "$VERSION"
# A release a new user cannot install is worse than no release: install the whole engine from the manifest this build ships, into an
# empty home (downloads ~500 MB). Skip only with KLYC_SKIP_FIRSTRUN=1.
if [ "${KLYC_SKIP_FIRSTRUN:-0}" != 1 ]; then Scripts/firstrun-smoke.sh >/dev/null 2>&1 || { echo "first-run smoke failed: a new user could not install the engine (run Scripts/firstrun-smoke.sh)" >&2; exit 1; }; fi
ZIP="dist/KLYC-Box-$VERSION.zip"
ditto -c -k --keepParent dist/KLYC-Box.app "$ZIP"
# GPL: the exact source of this build goes next to the binary on the release page.
SRC="dist/KLYC-Box-$VERSION-source.zip"
git archive --format=zip --prefix="klyc-box-$VERSION/" -o "$SRC" HEAD
# What people download: the disk image, under a fixed name so https://github.com/ernklyc/klyc-box/releases/latest/download/KLYC-Box.dmg
# always points at the newest one. The zip stays for the updater (Sparkle).
Scripts/make-dmg.sh >/dev/null
DMG="dist/KLYC-Box.dmg"
DMG_SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
echo "$DMG_SHA  KLYC-Box.dmg" > dist/KLYC-Box.dmg.sha256
SIGN=.build/artifacts/sparkle/Sparkle/bin/sign_update
ED_ATTRS=$("$SIGN" "$ZIP" | tr -d '\n')   # sparkle:edSignature="…" length="…"
URL="https://github.com/$REPO/releases/download/v$VERSION/KLYC-Box-$VERSION.zip"
DATE=$(date -R 2>/dev/null || date "+%a, %d %b %Y %H:%M:%S %z")

HB_VERSION="$VERSION" HB_SUMMARY="$SUMMARY" HB_DATE="$DATE" HB_URL="$URL" HB_ED="$ED_ATTRS" HB_DRY="$DRY" python3 - <<'PY'
import os, xml.dom.minidom
v = os.environ['HB_VERSION']
item = f"""    <item>
      <title>KLYC-Box {v}</title>
      <description><![CDATA[{os.environ['HB_SUMMARY']}]]></description>
      <pubDate>{os.environ['HB_DATE']}</pubDate>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure url="{os.environ['HB_URL']}" sparkle:version="{v}" sparkle:shortVersionString="{v}" {os.environ['HB_ED']} type="application/octet-stream"/>
    </item>"""
if os.environ['HB_DRY'] == '1':
    print(item); raise SystemExit
s = open('appcast.xml').read()
anchor = '<description>Windows games on Apple Silicon.</description>'
assert anchor in s, 'appcast anchor missing'
open('appcast.xml', 'w').write(s.replace(anchor, anchor + '\n' + item, 1))
xml.dom.minidom.parse('appcast.xml')
print('appcast.xml updated and valid')
PY
[ "$DRY" = 1 ] && { echo "dry run: built $ZIP, nothing tagged or published"; exit 0; }

# Tag the commit this build came from and push it BEFORE the release, so the tag is not put on the remote head.
git tag "v$VERSION"
git push origin HEAD "v$VERSION"
if [ -n "$NOTES_FILE" ]; then
  gh release create "v$VERSION" "$DMG" dist/KLYC-Box.dmg.sha256 "$ZIP" "$SRC" --repo "$REPO" --title "KLYC-Box $VERSION" --notes-file "$NOTES_FILE"
else
  gh release create "v$VERSION" "$DMG" dist/KLYC-Box.dmg.sha256 "$ZIP" "$SRC" --repo "$REPO" --title "KLYC-Box $VERSION" --notes "$SUMMARY"
fi
git add appcast.xml && git commit -m "release: v$VERSION appcast" && git push origin HEAD
echo "released v$VERSION. Installs see it once appcast.xml on the main branch is readable by them."
