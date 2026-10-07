<div align="center">

<img src="docs/media/icon.png" width="128" alt="KLYC-Box">

# KLYC-Box

**Windows games and apps on your Mac.**<br>
A free, open source macOS app that runs your Steam and Epic Games library on Apple Silicon.

<sub>🇹🇷 [Türkçe oku](README.md)</sub>

[![Release](https://img.shields.io/github/v/release/ernklyc/klyc-box?style=flat-square&color=6f8fd8&label=release)](https://github.com/ernklyc/klyc-box/releases/latest)
[![License](https://img.shields.io/badge/license-GPL--3.0-c3cde3?style=flat-square)](LICENSE)
[![Platform](https://img.shields.io/badge/macOS-14%2B%20·%20Apple%20Silicon-4cc98a?style=flat-square)](#install)
[![Diller](https://img.shields.io/badge/languages-TR%20·%20EN%20·%20中文%20·%20日本語-b79df7?style=flat-square)](#features)

[**⬇ Download (.dmg)**](https://github.com/ernklyc/klyc-box/releases/latest/download/KLYC-Box.dmg) &nbsp;·&nbsp; [Game guide & site](https://klycbox.ernklyc.dev) &nbsp;·&nbsp; [Changelog](CHANGELOG.md) &nbsp;·&nbsp; [Security](SECURITY.md)

<br>

<img src="docs/media/home.jpg" width="860" alt="KLYC-Box home">

</div>

---

## What is it?
KLYC-Box runs Windows games and programs on your Mac with **Wine, DXMT and D3DMetal**, and gathers them with your Steam and Epic libraries in one app. Installing it is as easy as dragging a file.

You can see whether a game opens on a Mac **before you buy it**: the app reads the data of the [game guide site](https://klycbox.ernklyc.dev) (the Atlas). For every game it says who tried it, when and on which Mac, with player reports, predictions and the games an anti-cheat blocks.

## Install
1. Download **[KLYC-Box.dmg](https://github.com/ernklyc/klyc-box/releases/latest/download/KLYC-Box.dmg)** (the SHA-256 and the source code are on the [release page](https://github.com/ernklyc/klyc-box/releases)).
2. Open it and drag **KLYC-Box** to **Applications**.
3. Open the app from Applications. It is not notarized by Apple yet, so if macOS warns you on first launch: **right-click the app › Open › Open**. You only need to do this once.
4. You sign in to Steam and Epic **on their own pages**, inside the app; KLYC-Box never sees your password.

**Requirements:** Apple Silicon (M1 or later), macOS 14 or newer.

## Screenshots
<table>
<tr>
<td width="50%"><img src="docs/media/library.jpg" alt="Library"><br><sub><b>Library</b>: your Steam and Epic games together.</sub></td>
<td width="50%"><img src="docs/media/store.jpg" alt="Steam store"><br><sub><b>The Steam store</b>, inside the app, with what works on a Mac up front.</sub></td>
</tr>
<tr>
<td width="50%"><img src="docs/media/profile.jpg" alt="Profile"><br><sub><b>Profile</b>: your hours and friends, from Steam's own record.</sub></td>
<td width="50%"><img src="docs/media/settings.jpg" alt="Settings"><br><sub><b>Settings</b>: four languages, one place.</sub></td>
</tr>
<tr>
<td width="50%"><img src="docs/media/game-details.jpg" alt="Game page"><br><sub><b>A game page</b>: system requirements checked against your Mac.</sub></td>
<td width="50%"><img src="docs/media/mods.jpg" alt="Mods"><br><sub><b>Mods</b>: the game folder, the Windows path and DLL overrides.</sub></td>
</tr>
</table>

## Features
- **Four languages:** Türkçe, English, 简体中文, 日本語 (Settings › General › Language; "Automatic" follows your Mac).
- **Atlas:** the game guide's data in the app. A **"On this Mac"** filter in the Steam store (tested, player reports, predicted, does not run) and badges on game cards.
- **Steam and Epic** together: library, store, downloads (pause, resume, cancel), friends and profile.
- **Per-game settings:** graphics mode, frame rate cap, launch options, mods, save backups.
- **Near-black and steel-blue theme;** Liquid Glass on macOS 26 and later.
- **Its own update channel** (Sparkle, its own signing key) and its own engine repository; every download is verified with SHA-256.

## Security and privacy
- Steam sign-in happens only in Steam's own client and pages; Epic sign-in uses Epic's page and a single-use code. KLYC-Box never sees or stores your password or keys.
- Player reports and crash reports are **opt-in**, anonymous, and you see everything in them before anything is sent.
- Details: [SECURITY.md](SECURITY.md) and the site's [privacy page](https://klycbox.ernklyc.dev/privacy/).

## Development
<details>
<summary><b>Build, install, maintenance and releases</b> (for developers)</summary>

```sh
swift build && swift test          # development loop
Scripts/make-app.sh debug          # dist/KLYC-Box.app
Scripts/install-app.sh             # builds, installs as /Applications/KLYC-Box.app and opens it
Scripts/health-check.sh            # git, secrets, build, tests, recipes, engine backup
```
Requirements: Apple Silicon, macOS 14+, Xcode command line tools. `brew install mingw-w64` for Epic games. Choose where data lives with `klycbox config home <folder>`; the command-line tool is `.build/debug/klycbox`. Architecture: [ARCHITECTURE.md](ARCHITECTURE.md).

**Cutting a release (maintainer):**
1. developer.apple.com → Certificates → create a **Developer ID Application** certificate and add it to the Keychain.
2. Save the notarization profile: `xcrun notarytool store-credentials klycbox --apple-id <id> --team-id <team>`.
3. `KLYC_UPDATES=1 Scripts/release-klyc.sh <version> "summary" notes.md` tests, builds, runs the first-run install test, makes the DMG, zip and source archive, tags and publishes. Try `--dry-run` first.

Published versions update from inside the app with Sparkle (the feed is `appcast.xml` in this repository). History: [CHANGELOG.md](CHANGELOG.md).
</details>

## Credits and license
GPL-3.0, free and open source. KLYC-Box started as a **fork** of [Highball](https://github.com/gauthierpiarrette/highball) by Gauthier Piarrette and is developed further on top of it; thank you for the work. Credits for Wine, Sikarugir, DXMT, DXVK, MoltenVK, Winetricks, Legendary, Sparkle and every other project are in [NOTICE.md](NOTICE.md) and on the app's **Settings › About** page.

> KLYC-Box is not affiliated with or approved by Valve (Steam), Epic Games or Apple. Steam, Epic Games and Apple are their owners' trademarks. D3DMetal belongs to Apple and is not distributed here; you accept Apple's license yourself, inside the app. KLYC-Box is not for running pirated games or getting around anti-cheat. It is free and will stay non-commercial: it takes no money for any feature.
