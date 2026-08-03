# Trading Up — documentation

Everything that isn't the public [README](../README.md).

| Doc | What's in it |
| --- | --- |
| [DESIGN.md](DESIGN.md) | The full game design document — the Sprytes world, all five sets, rarity value bands, the complete economy and grading tables, booster‑box guarantees, bonus payouts, win/lose rules |
| [DEVELOPMENT.md](DEVELOPMENT.md) | Build and run the app, project layout, where the balance knobs live, how to regenerate cards / art / icon / sound effects |
| [TESTING.md](TESTING.md) | The XCTest suite, the Foundation‑only simulation harness, and what CI runs |
| [APP_STORE.md](APP_STORE.md) | Producing submission artifacts: real device screenshots, icon checks, privacy manifest |
| [app-store-listing.md](app-store-listing.md) | Ready‑to‑paste App Store Connect metadata for every field, plus the pre‑submission checklist |

Other things in this folder:

- `mockups/` — interactive HTML card‑style mockups. `cd docs/mockups && python3 -m http.server 8787`
- `mockups/ui/` — proposed pack + Shop home screen directions (three options each). Same server, `/ui/`
- `screenshots/` — the rendered marketing shots the README embeds
