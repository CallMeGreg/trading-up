<div align="center">

<img src="TradingUp/Assets.xcassets/AppIcon.appiconset/icon-1024.png" alt="Trading Up" width="128">

# Trading Up

### Rip packs, beat the Quota, rule the Circuit.

**Trade up from a folding table to the Masters Invitational.**

A replayable card‑collecting roguelite for iPhone and iPad.

[![Platform](https://img.shields.io/badge/platform-iOS%2017%2B-lightgrey)](docs/DEVELOPMENT.md#requirements)
[![Made with SwiftUI](https://img.shields.io/badge/made%20with-SwiftUI-orange)](https://developer.apple.com/xcode/swiftui/)
[![Dependencies](https://img.shields.io/badge/dependencies-zero-brightgreen)](#no-catches)
[![CI](https://github.com/CallMeGreg/trading-up/actions/workflows/ci.yml/badge.svg)](https://github.com/CallMeGreg/trading-up/actions/workflows/ci.yml)

</div>

---

## Overview

Trading Up is built around the best part of trading cards: tearing open a fresh
pack and turning it over one card at a time — then turning those pulls into a
career.

You're a card **dealer** climbing **the Circuit**. Each run is a **Season** of
8 Shows, from a folding table at a local show to the **Masters Invitational**.
Every Show sets a rising **Quota**: fill the net‑worth bar with your cash and
collection value before your limited **Rips** run out, then **Make the Cut** and
move on.

The card economy is still the heart of it: packs, foils, ultra rares, duplicates,
selling back at 75%, grading swings and evolution lines. Between Shows, the
**Bazaar** lets you draft new cards, buy extras and find Season‑long **Trainers**,
single‑use **Power‑Ups** and the **Energy** to fire them.

Busts are not dead ends. Clear Shows and unlock **Milestones** to bank **Renown**,
then spend it at the **Collectors' Guild** on permanent upgrades for future
Seasons. Completing all **250 Sprytes** is now the **Master Collector** milestone;
winning means clearing all 8 Shows and becoming Season Champion.

Every creature, name, illustration and line of flavor text is original to the
game, generated from code and shipped inside the app. No accounts, no ads, no
tracking — just the game. Set 1 is free to play in full; one optional one‑time
purchase unlocks the other four sets.

## Screenshots

<table>
<tr>
<td width="20%"><img src="docs/screenshots/app/01-shop.png" alt="The shop: cash, binder progress, and five sets of packs with the later ones still locked"></td>
<td width="20%"><img src="docs/screenshots/app/02-rip-packs.png" alt="A new rare flipping over during a pack reveal"></td>
<td width="20%"><img src="docs/screenshots/app/03-keep-or-sell.png" alt="The pack summary paying out evolution bonuses, with the duplicate ready to sell"></td>
<td width="20%"><img src="docs/screenshots/app/04-grade.png" alt="A card coming back from grading as a PSA 10, worth five times what it was"></td>
<td width="20%"><img src="docs/screenshots/app/05-collect.png" alt="The collection grid filling in, unowned cards still locked"></td>
</tr>
<tr>
<td align="center"><b>Shop</b></td>
<td align="center"><b>Rip packs</b></td>
<td align="center"><b>Keep or sell</b></td>
<td align="center"><b>Grade</b></td>
<td align="center"><b>Collect</b></td>
</tr>
</table>

<sub>Real screenshots from the current iPhone build.</sub>

## How to play

### 🎪 Enter a Show

Each **Season** is a climb through **8 Shows**. Every Show gives you a rising
**Quota** — a net‑worth bar made from your cash plus your collection's value — and
a limited number of **Rips** to get there. Hit the Quota to **Make the Cut** and
advance.

### ✨ Rip it

Spend one Rip and the pack price to tear into 6 cards. Every pack is **3 commons,
2 uncommons, and 1 rare‑or‑ultra**, with the hit slot saved for last and a
**1% chance** for any card to be a shiny **foil** (×3 value).

### 🗂️ Keep, sell or grade

Brand‑new cards grow your collection and your net worth. Duplicates can be kept
or sold at the shop's **buylist spread**: **75%** of market value. You can
**never sell your last copy**, so your binder stays safe while you chase the next
Quota.

Send rares and ultras to grading and roll a PSA‑style grade. A **PSA 10** is ×5,
a **PSA 9** is ×2, and a **PSA 1** is a freak ×10 jackpot — but grades 2–7 are
worth *less* than ungraded. Grading and foils stack.

### 🧰 Visit the Bazaar

Between Shows, draft 1 of 3 new cards for free, then decide whether to spend cash
on more or reroll the offers. The Bazaar also serves up run‑scoped tools:
**Trainers** are passive upgrades for the whole Season, **Power‑Ups** are
single‑use plays, and **Energy** powers them.

### 📖 Build the binder

Browse all 50 cards per set. Owned cards show off your best copy; unowned cards
are locked silhouettes. Filter by **Dupes**, **Foils** and **Rare+** while your
collection feeds the Quota, evolution lines pay bonuses, and big achievements
unlock permanent **Milestones** like **Master Collector** for owning all 250 cards
at once.

### 🏆 Win the Season — or bust forward

Clear all 8 Shows and Make the Cut at the **Masters Invitational** to become
**Season Champion**. Bust if the Show closes and you have no way left to grow
toward the Quota — but busting still banks earned **Renown**.

Spend Renown at the **Collectors' Guild** on permanent upgrades like more starting
cash, more Trainer slots, more Rips and more Energy. Death is progress: every
Season starts stronger.

Your progress **auto‑saves** after every action, and a save is never silently
discarded.

## Five sets, 250 cards

| # | Set | Theme | Pack price |
|---|-----|-------|-----------:|
| 1 | **Emberfall** | Fire / magma | $10 |
| 2 | **Tidecaller** | Water / ice | $30 |
| 3 | **Verdspire** | Grass / nature | $75 |
| 4 | **Voltcrest** | Electric / storm | $160 |
| 5 | **Umbral Reach** | Shadow / cosmic | $400 |

Each set is 50 cards with its own creatures, evolution lines, flavor text and
rarity spread. Set 1 is free; one optional unlock opens the other four sets.

## No catches

- **Set 1 is free to play in full** — the whole roguelite loop: Shows, Quotas,
  Rips, the Bazaar, Trainers, Power‑Ups, Energy, Renown, the Collectors' Guild,
  Milestones, ripping, selling and grading. One optional **one‑time purchase**
  unlocks the other four sets. That's the only thing you can ever buy.
- **No ads, no tracking, no subscriptions.**
- **No real‑money packs and no gambling.** You never spend real money on a
  random pull — every in‑game currency is fictional and earned through play.
- **No account, no sign‑in.** Your collection lives in a single file on your
  device and is never sent anywhere.
- **Plays offline**, on both iPhone and iPad — a connection is only needed the
  once to make or restore the purchase.

## Documentation

For anyone working on the app — including how to
[build and run it from source](docs/DEVELOPMENT.md).

| Doc | What's in it |
| --- | --- |
| [Design](docs/DESIGN.md) | The full game design document: the world, the sets, the economy and grading tables, win/lose rules |
| [Development](docs/DEVELOPMENT.md) | Build and run, project layout, regenerating cards, art, icon and sound |
| [Testing](docs/TESTING.md) | The unit test suite, the Foundation‑only simulation harness, and CI |
| [App Store](docs/APP_STORE.md) | Producing submission artifacts, and the full listing metadata |

## Credits

Created by [@CallMeGreg](https://github.com/CallMeGreg). All 250 creatures, their
names, artwork and flavor text are original works created for this app; no
third‑party or licensed content is used.
