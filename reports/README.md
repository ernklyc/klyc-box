# Player reports

What a player tells KLYC-Box about a game on their Mac: works or not, a 1-5 rating, and optionally a short note. The chip, macOS and engine versions come along automatically. Sending is always the player's own click.

## How it is built

- **Firestore stays private.** `firestore.rules`: a signed-in (anonymous) player can create, change or delete only their own report, `reports/{appid}_{uid}`, with every field checked; nobody can read any report.
- **Totals are published, not reports.** `run.mjs` (admin rights) reads all reports and writes `reports.json`; `aggregate.mjs` is the logic, tested in `aggregate.test.mjs`. A game appears only once it has 3 reports, so one person's answer is never shown alone.
- The app and the website read `reports.json` from a public place. No Cloud Functions, no paid plan.

## Setting it up

Done on 2026-10-06: project `klyc-box-reports` (own project, separate from ernklyc.dev's) and a web app whose public key is in `Sources/KLYCKit/CommunityReport.swift`. Still to do, in the console (the CLI's account has no permission to enable APIs):

1. Firestore Database > Create database > `(default)`, Standard edition, location `eur3` (Europe), **production mode**.
2. Authentication > Get started > Sign-in method > **Anonymous** > Enable.
3. `firebase deploy --only firestore:rules --project klyc-box-reports` (rules in `firestore.rules`).
4. App Check is not on (it needs a notarized, signed app). Instead the rules accept only the anonymous sign-in, refuse an update sooner than 20 seconds after the last write, keep the appid in the real Steam range, and `aggregate.mjs` ignores any account with more than 40 reports and publishes a game only from 3 or more reports. Watch the usage dashboard in the Firebase console (Spark plan = no charges, a spike only pauses reports for the day).

Until step 1 and 2 are done the app says "Player reports are not switched on yet" and sends nothing.

## Tests

```bash
npm install
npm test                 # aggregation (no Java)
npm run test:rules       # real rules in the Firestore emulator (needs JDK 21+, e.g. /opt/homebrew/opt/openjdk/bin on PATH)
```

`rest.test.mjs` posts `fixtures/commit-body.json` to the emulator; `Tests/KLYCKitTests/CommunityReportTests.swift` asserts the app produces exactly that body, so the wire format the app sends is the one the rules were tested with.

## Privacy

No account, no name, no email: an anonymous ID and the answers above. The app says what is sent before it sends it. The page is at https://klycbox.ernklyc.dev/privacy/.
