#!/usr/bin/env python3
"""
One-time (and re-runnable) script to load scripts/seed-questions.json into
the `questions` collection in Firestore.

Setup:
  1. pip install firebase-admin
  2. Firebase console -> Project settings -> Service accounts ->
     "Generate new private key" -> save the downloaded file as
     scripts/serviceAccountKey.json (this exact path is gitignored — never
     commit it).
  3. python3 scripts/seed_questions.py

Safe to re-run: it overwrites each question document by its `id`, so
re-running after editing seed-questions.json just updates the changed
fields rather than creating duplicates.
"""
import json
import sys
from pathlib import Path

import firebase_admin
from firebase_admin import credentials, firestore

SCRIPT_DIR = Path(__file__).resolve().parent
KEY_PATH = SCRIPT_DIR / "serviceAccountKey.json"
SEED_PATH = SCRIPT_DIR / "seed-questions.json"


def main() -> int:
    if not KEY_PATH.exists():
        print(f"Missing {KEY_PATH}.", file=sys.stderr)
        print("Download it from Firebase console -> Project settings -> "
              "Service accounts -> Generate new private key.", file=sys.stderr)
        return 1

    with open(SEED_PATH) as f:
        questions = json.load(f)

    cred = credentials.Certificate(str(KEY_PATH))
    firebase_admin.initialize_app(cred)
    db = firestore.client()

    batch = db.batch()
    for question in questions:
        doc_ref = db.collection("questions").document(question["id"])
        batch.set(doc_ref, question)
    batch.commit()

    print(f"Seeded {len(questions)} questions into Firestore.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
