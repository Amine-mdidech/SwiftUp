# scripts/

Dev tooling, not shipped in the app.

## seed_questions.py

Loads `seed-questions.json` into the Firestore `questions` collection.

1. `pip install firebase-admin`
2. Firebase console → Project settings → Service accounts → "Generate new
   private key". Save the downloaded file as `scripts/serviceAccountKey.json`
   (this exact filename is gitignored — never commit it; it grants admin
   access to the whole Firebase project).
3. `python3 scripts/seed_questions.py`

Safe to re-run after editing `seed-questions.json` — it overwrites each
question by `id`, so it updates rather than duplicates.
