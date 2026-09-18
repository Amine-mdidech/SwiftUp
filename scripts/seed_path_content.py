#!/usr/bin/env python3
"""
One-time (and re-runnable) script to load scripts/path-content.json into the
`pathStageContent` and `pathRegradeQuizzes` collections in Firestore.

Setup:
  1. pip install firebase-admin
  2. Firebase console -> Project settings -> Service accounts ->
     "Generate new private key" -> save the downloaded file as
     scripts/serviceAccountKey.json (this exact path is gitignored — never
     commit it).
  3. python3 scripts/seed_path_content.py

Safe to re-run: it overwrites each document by its own id/grade, so
re-running after regenerating path-content.json just updates the changed
fields rather than creating duplicates.
"""
import json
import sys
from pathlib import Path

import firebase_admin
from firebase_admin import credentials, firestore

SCRIPT_DIR = Path(__file__).resolve().parent
KEY_PATH = SCRIPT_DIR / "serviceAccountKey.json"
SEED_PATH = SCRIPT_DIR / "path-content.json"


def main() -> int:
    if not KEY_PATH.exists():
        print(f"Missing {KEY_PATH}.", file=sys.stderr)
        print("Download it from Firebase console -> Project settings -> "
              "Service accounts -> Generate new private key.", file=sys.stderr)
        return 1

    with open(SEED_PATH) as f:
        data = json.load(f)

    cred = credentials.Certificate(str(KEY_PATH))
    firebase_admin.initialize_app(cred)
    db = firestore.client()

    batch = db.batch()
    for content in data["stageContent"]:
        doc_ref = db.collection("pathStageContent").document(content["stageID"])
        batch.set(doc_ref, content)
    for quiz in data["regradeQuizzes"]:
        doc_ref = db.collection("pathRegradeQuizzes").document(quiz["grade"].lower())
        batch.set(doc_ref, quiz)
    batch.commit()

    print(
        f"Seeded {len(data['stageContent'])} stage-content docs and "
        f"{len(data['regradeQuizzes'])} regrade quizzes into Firestore."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
