#!/usr/bin/env python3
"""
Seeds the `dailyQuizzes` collection in Firestore: one document per calendar
date, each holding that day's shared edition number and a 5-question set per
skill level (Junior/Mid/Senior), drawn from scripts/seed-questions.json.

Every user at a given level sees the same edition, same questions, same day —
the app reads today's document and does no selection of its own.

Setup: same as seed_questions.py — needs scripts/serviceAccountKey.json
(Firebase console -> Project settings -> Service accounts -> Generate new
private key). That file is gitignored; never commit it.

Usage:
  python3 scripts/seed_daily_quizzes.py            # seeds today + next 13 days
  python3 scripts/seed_daily_quizzes.py --days 30   # seeds today + next 29 days
  python3 scripts/seed_daily_quizzes.py --start 2026-09-07 --days 5

Safe to re-run: each date's document is fully overwritten, and picks are
seeded by (date, level) — re-running with an unchanged seed-questions.json
reproduces the exact same questions for a date that's already been seeded.
"""
import argparse
import json
import random
import sys
from datetime import date, timedelta
from pathlib import Path

import firebase_admin
from firebase_admin import credentials, firestore

SCRIPT_DIR = Path(__file__).resolve().parent
KEY_PATH = SCRIPT_DIR / "serviceAccountKey.json"
SEED_PATH = SCRIPT_DIR / "seed-questions.json"

# Edition 1 shipped this date — every date after counts up by exactly one
# edition per calendar day. Keep this in sync with any historical editions
# already shown to users; it's otherwise an arbitrary anchor.
EPOCH_DATE = date(2026, 9, 7)

LEVELS = ["Junior", "Mid", "Senior"]
QUESTIONS_PER_LEVEL = 5


def edition_for(target: date) -> int:
    return (target - EPOCH_DATE).days + 1


def pick_five(bank: list[dict], level: str, target: date) -> list[dict]:
    pool = [q for q in bank if q["level"] == level]
    if len(pool) < QUESTIONS_PER_LEVEL:
        raise ValueError(
            f"Only {len(pool)} '{level}' questions in {SEED_PATH.name}, "
            f"need at least {QUESTIONS_PER_LEVEL}."
        )
    rng = random.Random(f"{target.isoformat()}-{level}")
    return rng.sample(pool, QUESTIONS_PER_LEVEL)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--start", type=date.fromisoformat, default=date.today(),
                         help="First date to seed, YYYY-MM-DD (default: today)")
    parser.add_argument("--days", type=int, default=14,
                         help="How many consecutive days to seed (default: 14)")
    args = parser.parse_args()

    if not KEY_PATH.exists():
        print(f"Missing {KEY_PATH}.", file=sys.stderr)
        print("Download it from Firebase console -> Project settings -> "
              "Service accounts -> Generate new private key.", file=sys.stderr)
        return 1

    with open(SEED_PATH) as f:
        bank = json.load(f)

    cred = credentials.Certificate(str(KEY_PATH))
    firebase_admin.initialize_app(cred)
    db = firestore.client()

    batch = db.batch()
    seeded_dates = []
    for offset in range(args.days):
        target = args.start + timedelta(days=offset)
        doc = {"edition": edition_for(target)}
        for level in LEVELS:
            doc[level.lower()] = pick_five(bank, level, target)
        doc_ref = db.collection("dailyQuizzes").document(target.isoformat())
        batch.set(doc_ref, doc)
        seeded_dates.append((target.isoformat(), doc["edition"]))
    batch.commit()

    for date_str, edition in seeded_dates:
        print(f"{date_str}: edition {edition}")
    print(f"Seeded {len(seeded_dates)} daily quizzes into Firestore.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
