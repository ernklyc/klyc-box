# Contributing

Thanks for helping. KLYC-Box is GPL-3.0; by contributing you agree your work is released under the same license. The game data in `db/` and `recipes/` is CC0.

## Ways to help

- **Test a game and tell us.** Send a report from the app (anonymous), or open an issue with the "report" template: game, Mac chip, macOS version, result.
- **Fix or add a recipe** in `recipes/` or a record in `db/games/` (see the existing files for the shape).
- **Code.** Read `ARCHITECTURE.md` first: layers, the view-model rule, how to add a feature.

## Before a pull request

```sh
swift build && swift test
python3 Scripts/check-l10n.py        # Turkish strings must be complete and not repeated
Scripts/health-check.sh --quick
```

Keep the UI text in English in code, wrapped in `L("...")`, and add the Turkish in `Sources/KLYCKit/L10nTR*.swift`. Small, focused pull requests are easier to review.

Do not add analytics, tracking or anything that sends data without an explicit click.
