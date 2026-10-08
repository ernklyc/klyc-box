#!/bin/zsh
# Assemble dist/KLYC-Box.app from the SwiftPM build.
# Usage: Scripts/make-app.sh [debug|release] [version]
# Signs with Developer ID when available (hardened runtime); notarizes + staples when a
# notarytool keychain profile named "klycbox" exists.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
VERSION="${2:-0.0.0-dev}"
FEED_URL="https://raw.githubusercontent.com/ernklyc/klyc-box/main/appcast.xml"
ED_PUBLIC_KEY="SJG8fZRT7aQhmx6Bi2j1PE76NRwUxbjzWQPVc0w7NQM="   # KLYC-Box update key; the private half is in the login keychain (generate_keys)
NOTARY_PROFILE="${NOTARY_PROFILE:-klycbox}"

# A duplicate key in L10n's dictionary literal crashes the app at launch (2026-09-15); refuse to build one.
python3 - <<'PY' || exit 1
import re, collections, glob
for f in sorted(glob.glob("Sources/KLYCKit/L10n*.swift")):
    keys = re.findall(r'^\s*"((?:[^"\\]|\\.)*)"\s*:\s*"', open(f).read(), re.M)
    dups = [k for k, c in collections.Counter(keys).items() if c > 1]
    if dups: print(f"error: duplicate keys in {f}:", dups); raise SystemExit(1)
PY
# SwiftPM's Bundle.module accessor looks for the resource bundle next to the executable or at the
# absolute build path of the machine that compiled it, never under Contents/Resources, so an app
# that reads it runs on the builder's Mac and crashes at launch everywhere else (PR #230,
# 2026-10-01). App resources go through Bundle.main, from the files this script copies.
if grep -rq "Bundle\.module" Sources/KLYCBoxApp; then echo "error: Sources/KLYCBoxApp reads Bundle.module; use Bundle.main and copy the file here" >&2; exit 1; fi
swift build -c "$CONFIG" --product KLYCBoxApp
APP=dist/KLYC-Box.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp ".build/$CONFIG/KLYCBoxApp" "$APP/Contents/MacOS/KLYC-Box"
# Empty .lproj folders: they are what makes macOS show the standard menus (File, Edit, Window, Help) in the user's language.
for lang in en tr fr; do mkdir -p "$APP/Contents/Resources/$lang.lproj"; done

# Sparkle framework (SwiftPM artifact) — embedded, rpath is baked into the binary.
SPARKLE_FW=$(ls -d .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-*/Sparkle.framework | head -1)
cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/"

# Resources: engine manifest, GPTK license, recipes and DB entries (from klyc-db).
cp spike/engine-manifest.json "$APP/Contents/Resources/engine-manifest.json"
# Other engines the app can offer (previous ones for rollback, candidates for Advanced).
if ls spike/engines/*.json >/dev/null 2>&1; then mkdir -p "$APP/Contents/Resources/engines"; cp spike/engines/*.json "$APP/Contents/Resources/engines/"; fi
cp spike/d3dmetal-license.txt "$APP/Contents/Resources/d3dmetal-license.txt"
# cabextract for winetricks (the core fonts tweak needs it and macOS has none, upstream#96), built
# from its pinned source by spike/tools/build-cabextract.sh, GPL-3.0-or-later, licence shipped beside it.
spike/tools/build-cabextract.sh >/dev/null 2>&1 || { echo "error: could not build cabextract (spike/tools/build-cabextract.sh)" >&2; exit 1; }
mkdir -p "$APP/Contents/Resources/tools"
cp spike/tools/cabextract "$APP/Contents/Resources/tools/cabextract"
cp spike/tools/cabextract.LICENSE "$APP/Contents/Resources/tools/cabextract.LICENSE"
RECIPES="recipes"   # vendored in this repo (CC0 data, see recipes/LICENSE)
for f in "$RECIPES"/launchers/*.json "$RECIPES"/games/*.json "$RECIPES"/tweaks/*.json; do cp "$f" "$APP/Contents/Resources/"; done
[ -f db/mods.json ] && cp db/mods.json "$APP/Contents/Resources/mods.json"
[ -f db/anticheat.json ] && cp db/anticheat.json "$APP/Contents/Resources/anticheat.json"
DBDIR="db/games"
if [ -d "$DBDIR" ]; then mkdir -p "$APP/Contents/Resources/db-games"; cp "$DBDIR"/*.json "$APP/Contents/Resources/db-games/"; fi

# App icon.
ICONWORK=.build/icon
mkdir -p "$ICONWORK/AppIcon.iconset"
swift Scripts/make-icon.swift "$ICONWORK/AppIcon-1024.png" >/dev/null
for sz in 16 32 128 256 512; do
  sips -z $sz $sz "$ICONWORK/AppIcon-1024.png" --out "$ICONWORK/AppIcon.iconset/icon_${sz}x${sz}.png" >/dev/null
  d=$((sz*2)); sips -z $d $d "$ICONWORK/AppIcon-1024.png" --out "$ICONWORK/AppIcon.iconset/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns "$ICONWORK/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
sips -z 512 512 "$ICONWORK/AppIcon-1024.png" --out "$APP/Contents/Resources/AppIcon.png" >/dev/null

# Sparkle update feed only when asked for (KLYC_UPDATES=1, which Scripts/release-klyc.sh sets): release builds update
# themselves from the public appcast; local development builds have no update menu and Scripts/install-app.sh updates them.
UPDATE_KEYS=""
if [ "${KLYC_UPDATES:-0}" = 1 ]; then
  UPDATE_KEYS="  <key>SUFeedURL</key><string>${FEED_URL}</string>
  <key>SUPublicEDKey</key><string>${ED_PUBLIC_KEY}</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>
"
fi
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>KLYC-Box</string>
  <key>CFBundleIdentifier</key><string>com.klyc.klycbox</string>
  <key>CFBundleName</key><string>KLYC-Box</string>
  <key>CFBundleDisplayName</key><string>KLYC-Box</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>tr</string><string>fr</string></array>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
${UPDATE_KEYS}  <key>SUEnableInstallerLauncherService</key><false/>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Eren Kalaycı. GPL-3.0, derived work (see NOTICE.md).</string>
  <key>CFBundleURLTypes</key>
  <array><dict>
    <key>CFBundleURLName</key><string>KLYC-Box play link</string>
    <key>CFBundleURLSchemes</key><array><string>klycbox</string></array>
  </dict></array>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Windows program</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Default</string>
      <key>LSItemContentTypes</key><array><string>com.microsoft.windows-executable</string></array>
    </dict>
    <dict>
      <key>CFBundleTypeName</key><string>Windows installer or batch file</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>CFBundleTypeExtensions</key><array><string>msi</string><string>bat</string></array>
    </dict>
  </array>
  <key>NSLocalNetworkUsageDescription</key><string>Steam and some games look for other players and devices on your network. macOS asks the first time one does.</string>
  <key>NSMicrophoneUsageDescription</key><string>Windows games and apps running in a bottle need the microphone for voice chat and recording. macOS asks the first time one uses it.</string>
</dict></plist>
PLIST

# Hardened-runtime entitlements: Wine processes are children of the app, so TCC attributes
# their device access to KLYC-Box — without audio-input declared, macOS silently denies the
# microphone to every game and never shows a prompt (user report, 2026-08-25).
cat > dist/entitlements.plist <<'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.device.audio-input</key><true/>
</dict></plist>
ENTITLEMENTS

IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/{print $2; exit}')
if [ -n "$IDENTITY" ]; then
  # The XPC services exist on every Sparkle 2 build; a signing failure here must stop the build.
  # With the errors swallowed, one transient failure left Installer.xpc ad-hoc signed and the
  # notary rejected the whole app (2026-09-17, 0.9.25's first attempt).
  for xpc in Downloader Installer; do
    codesign --force --options runtime --timestamp -s "$IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/$xpc.xpc"
  done
  codesign --force --options runtime --timestamp -s "$IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
  codesign --force --options runtime --timestamp -s "$IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
  codesign --force --options runtime --timestamp -s "$IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework"
  # Bundled command-line tools are Mach-O executables too: notarization rejects them unsigned
  # (cabextract, 2026-09-14: "not signed with a valid Developer ID", no hardened runtime).
  for tool in "$APP"/Contents/Resources/tools/*; do
    case "$tool" in *.LICENSE) ;; *) codesign --force --options runtime --timestamp -s "$IDENTITY" "$tool" ;; esac
  done
  codesign --force --options runtime --timestamp --entitlements dist/entitlements.plist -s "$IDENTITY" "$APP"
else
  # No Developer ID: with KLYC_SIGN_LOCAL=1, sign with the Apple Development certificate (the first time, macOS asks once for the login password and "Always Allow"). A stable identity is
  # what lets macOS remember the permissions the app was granted (removable drive, microphone) across
  # rebuilds; an ad-hoc signature changes with every build and macOS asks again each time.
  LOCAL_ID=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/{print $2; exit}')
  if [ -n "$LOCAL_ID" ] && [ "${KLYC_SIGN_LOCAL:-0}" = 1 ]; then
    for xpc in Downloader Installer; do
      codesign --force -s "$LOCAL_ID" "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/$xpc.xpc"
    done
    codesign --force -s "$LOCAL_ID" "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
    codesign --force -s "$LOCAL_ID" "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
    codesign --force -s "$LOCAL_ID" "$APP/Contents/Frameworks/Sparkle.framework"
    for tool in "$APP"/Contents/Resources/tools/*; do
      case "$tool" in *.LICENSE) ;; *) codesign --force -s "$LOCAL_ID" "$tool" ;; esac
    done
    codesign --force --entitlements dist/entitlements.plist -s "$LOCAL_ID" "$APP"
    echo "note: signed with $LOCAL_ID (local build, not notarized)"
  else
    codesign --force --deep -s - "$APP"
  fi
fi
codesign -dv "$APP" 2>&1 | grep -E "Authority=Developer|flags" | head -2 || true

# Notarize + staple when credentials are stored (xcrun notarytool store-credentials klycbox ...).
# Only a release build is notarized: a debug or e2e bundle is ad-hoc signed and stapling it can
# fail (error 73, 2026-09-13), and it should never look shippable anyway.
# The probe talks to Apple, so its failure is not always a missing profile: an expired developer
# agreement answers 403 here too (2026-10-01), and the old message sent us looking for credentials.
NOTARY_PROBE=""
[ "$CONFIG" = release ] && NOTARY_PROBE=$(xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" 2>&1 >/dev/null) && NOTARY_OK=1 || NOTARY_OK=0
if [ "$CONFIG" = release ] && [ "$NOTARY_OK" = 1 ]; then
  echo "notarizing…"
  ditto -c -k --keepParent "$APP" dist/KLYC-Box-notarize.zip
  xcrun notarytool submit dist/KLYC-Box-notarize.zip --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm dist/KLYC-Box-notarize.zip
  echo "notarized and stapled"
else
  if [ "$CONFIG" = "release" ] && [ "${KLYC_UNNOTARIZED:-0}" = 1 ]; then
    # Personal builds: no Developer ID certificate or notary profile yet. The app is ad-hoc signed,
    # fine for this Mac and for Sparkle updates (they check the EdDSA signature), but another
    # Mac's Gatekeeper will warn on first open.
    echo "note: KLYC_UNNOTARIZED=1, shipping an ad-hoc signed, unnotarized build"
  elif [ "$CONFIG" = "release" ]; then
    # Never ship unnotarized again: 0.1–0.3 went out this way and macOS 15+ showed users
    # the "could not verify it's free of malware" dialog (retro-notarized 2026-08-24).
    if print -r -- "$NOTARY_PROBE" | grep -q "agreement"; then
      echo "error: Apple refuses notarization until the developer account accepts its updated agreement — refusing to ship unnotarized." >&2
      echo "fix: the account holder signs in at https://developer.apple.com/account and accepts the agreement, then run this again" >&2
    else
      echo "error: release build but notarytool cannot use the profile '$NOTARY_PROFILE' — refusing to ship unnotarized (KLYC_UNNOTARIZED=1 to override)." >&2
      echo "notarytool said: ${NOTARY_PROBE:-nothing}" >&2
      echo "fix: xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <id> --team-id <your team id>" >&2
    fi
    exit 1
  fi
  echo "note: no notarytool profile '$NOTARY_PROFILE' — skipping notarization (debug build)"
fi
echo "built $APP ($VERSION)"
