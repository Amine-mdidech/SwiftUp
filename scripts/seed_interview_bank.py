#!/usr/bin/env python3
"""
Seeds the `interviewBank` collection in Firestore: one document per interview-prep
category, each holding its Junior/Mid/Senior question lists, from
scripts/interview-bank.json.

Every signed-in user reads the same shared, public bank — this script is how new
content ships without an app release.

Setup: same as seed_daily_quizzes.py — needs scripts/serviceAccountKey.json
(Firebase console -> Project settings -> Service accounts -> Generate new
private key). That file is gitignored; never commit it.

Usage:
  python3 scripts/seed_interview_bank.py

Safe to re-run: each category's document is fully overwritten with whatever is
currently in interview-bank.json.
"""
import json
import sys
from pathlib import Path

import firebase_admin
from firebase_admin import credentials, firestore

SCRIPT_DIR = Path(__file__).resolve().parent
KEY_PATH = SCRIPT_DIR / "serviceAccountKey.json"
BANK_PATH = SCRIPT_DIR / "interview-bank.json"

LEVELS = ["junior", "mid", "senior"]


def main() -> int:
    if not KEY_PATH.exists():
        print(f"Missing {KEY_PATH}.", file=sys.stderr)
        print("Download it from Firebase console -> Project settings -> "
              "Service accounts -> Generate new private key.", file=sys.stderr)
        return 1

    with open(BANK_PATH) as f:
        bank = json.load(f)

    for category in bank:
        missing = [key for key in ("slug", "name", *LEVELS) if key not in category]
        if missing:
            print(f"Category {category.get('name', '?')!r} is missing {missing}", file=sys.stderr)
            return 1

    cred = credentials.Certificate(str(KEY_PATH))
    firebase_admin.initialize_app(cred)
    db = firestore.client()

    batch = db.batch()
    for category in bank:
        doc = {"name": category["name"], **{level: category[level] for level in LEVELS}}
        doc_ref = db.collection("interviewBank").document(category["slug"])
        batch.set(doc_ref, doc)
    batch.commit()

    print(f"Seeded {len(bank)} interview-prep categories into Firestore.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
