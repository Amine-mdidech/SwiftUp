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
currently in interview-bank.json. Removing a category from this file does NOT
delete its Firestore document — that must be done by hand (Firestore console,
or `db.collection('interviewBank').document(slug).delete()`).
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

    seen_slugs = set()
    seen_question_ids = set()
    for category in bank:
        missing = [key for key in ("slug", "name", "order", *LEVELS) if key not in category]
        if missing:
            print(f"Category {category.get('name', '?')!r} is missing {missing}", file=sys.stderr)
            return 1

        slug = category["slug"]
        if slug in seen_slugs:
            print(f"Duplicate slug {slug!r} (category {category['name']!r})", file=sys.stderr)
            return 1
        seen_slugs.add(slug)

        for level in LEVELS:
            expected_difficulty = level.capitalize()
            for question in category[level]:
                qid = question.get("id", "?")
                if question.get("difficulty") != expected_difficulty:
                    print(
                        f"Question {qid!r} in category {category['name']!r} is listed under "
                        f"{level!r} but has difficulty {question.get('difficulty')!r} "
                        f"(expected {expected_difficulty!r})",
                        file=sys.stderr,
                    )
                    return 1
                if question.get("category") != category["name"]:
                    print(
                        f"Question {qid!r} in category {category['name']!r} has category "
                        f"{question.get('category')!r} (expected {category['name']!r})",
                        file=sys.stderr,
                    )
                    return 1
                if qid in seen_question_ids:
                    print(f"Duplicate question id {qid!r} (category {category['name']!r})", file=sys.stderr)
                    return 1
                seen_question_ids.add(qid)

    cred = credentials.Certificate(str(KEY_PATH))
    firebase_admin.initialize_app(cred)
    db = firestore.client()

    batch = db.batch()
    for category in bank:
        doc = {"name": category["name"], "order": category["order"], **{level: category[level] for level in LEVELS}}
        doc_ref = db.collection("interviewBank").document(category["slug"])
        batch.set(doc_ref, doc)
    batch.commit()

    print(f"Seeded {len(bank)} interview-prep categories into Firestore.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
