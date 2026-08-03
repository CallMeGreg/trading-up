#!/usr/bin/env python3
"""Write a Trading Up save file representing a finished collection.

Used by tools/capture_screenshots.sh to reach the late-game screens — the win
celebration, a completed set, a bankroll deep enough for set 5 — that a $100
starting bankroll can't get to inside a short automated playthrough. The app
then renders that state for real; nothing about the UI is faked.

    python3 tools/seed_save.py <destination.json>

Reads data/cards.json for the card ids, so it always matches the shipped set.
"""
import json
import os
import sys
import uuid

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CARDS = os.path.join(REPO, "data", "cards.json")

# Deliberately chosen rather than random so the screenshots are reproducible.
FOIL_EVERY = 21          # ~12 foils sprinkled through the collection
GRADE_EVERY = 7          # grade every 7th rare/ultra
GRADES = [10, 9, 10, 8, 9, 10, 8]
CASH = 4200.0


def build(cards):
    instances = []
    gradable = 0
    for i, card in enumerate(cards):
        inst = {"id": str(uuid.UUID(int=i)), "cardId": card["id"], "foil": i % FOIL_EVERY == 0}
        if card["rarity"] in ("rare", "ultra"):
            if gradable % GRADE_EVERY == 0:
                inst["grade"] = GRADES[(gradable // GRADE_EVERY) % len(GRADES)]
            gradable += 1
        instances.append(inst)

    line_sizes = {}
    for card in cards:
        line_sizes[card["lineId"]] = line_sizes.get(card["lineId"], 0) + 1
    evo_lines = sorted(line for line, size in line_sizes.items() if size > 1)

    # 322 packs x 6 cards = the 1,932 pulls below. Boxes are off the shelf, so a
    # seeded save can't claim any without describing a game nobody can play.
    stats = {
        "packsOpened": 322,
        "boxesOpened": 0,
        "cardsPulled": 1932,
        "foilsPulled": 19,
        "ultrasPulled": 47,
        "cardsSold": 1682,
        "moneySpent": 21460.0,
        "moneyEarned": 25660.0,
        "bestGrade": 10,
        "peakCash": 6120.0,
        "peakCardValue": 940.0,
        "peakSale": 611.0,
    }
    lifetime = dict(stats, runsStarted=3, runsWon=1, bestRunPacks=322)

    core = {
        "cash": CASH,
        "instances": instances,
        "claimedEvoLines": evo_lines,
        "claimedSets": [1, 2, 3, 4, 5],
        "stats": stats,
        "lifetime": lifetime,
        "hasWon": True,
        "winAcknowledged": False,
        "welcomeSeen": True,
    }
    return {"schemaVersion": 2, "core": core}


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: seed_save.py <destination.json>")
    with open(CARDS) as fh:
        cards = json.load(fh)
    with open(sys.argv[1], "w") as fh:
        json.dump(build(cards), fh)
    print(f"seeded a completed {len(cards)}-card collection -> {sys.argv[1]}")


if __name__ == "__main__":
    main()
