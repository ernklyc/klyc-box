# Security

KLYC-Box is a macOS app that runs Windows programs through Wine. It downloads engine files, checks them against SHA-256 digests kept in the app, and does not send any data unless you press "Send" on a player report.

## Reporting a vulnerability

Please do not open a public issue for a security problem. Write to **ernklyc@gmail.com** with what you found, how to reproduce it, and which version you used. You will get an answer within a few days.

What is in scope: the app, its updater (Sparkle feed and signature check), the engine download and verification, and the player-report path (`reports/`, Firestore rules).
What is not: Wine, DXMT, DXVK, MoltenVK and the games themselves (report those upstream).

## Your Steam and Epic accounts

- **Steam:** you sign in inside Steam's own client, which runs in KLYC-Box's own Windows environment, or on Steam's own web pages. KLYC-Box never sees, asks for or stores your Steam password. It reads only what Steam keeps on disk about the signed-in profile (display name, playtime, friends list) to show your profile screen, and sends none of it anywhere except Valve's own public pages.
- **Epic Games:** you sign in on Epic's own login page and paste back a single-use code. KLYC-Box never sees your password. The session that results is kept by Legendary (the open source Epic client, pinned and checksum-verified) in KLYC-Box's data folder, readable by your macOS user only (folder 0700, files 0600). It is used only to talk to Epic.
- **Nothing leaves your Mac.** There is no account system, no analytics and no crash upload. The only data KLYC-Box can send is an optional player report that you review field by field before pressing Send (see https://klycbox.ernklyc.dev/privacy/).
- **Crashes:** KLYC-Box never uploads a crash report. After an unexpected close, the next launch *offers* to open a pre-filled GitHub issue (it goes to this repository's maintainers). The text contains only the crash type, the KLYC-Box and macOS versions and the names of the functions where it happened: no file paths, games or accounts. You see all of it in your browser and decide whether to submit.
- **`klycbox://` links** carry a per-install secret, so a web page cannot start a game or program on your Mac.
- **Downloads are verified:** engine components and the Epic helper are pinned to SHA-256 digests kept in the app; updates are signed (Sparkle, EdDSA).

## The report database

Player reports go to a Firestore database that nobody, not even the sender, can read back. The rules accept only the anonymous sign-in the app uses, one report per player per game, no faster than every 20 seconds, with the fields and ranges checked; a script run with admin rights publishes totals only for games with at least three reports and ignores any account that floods it. The web key inside the app is restricted to the three Google APIs it needs. See `reports/README.md`.

## What the app sends

Nothing by default. See https://klycbox.ernklyc.dev/privacy/ for the exact list.
