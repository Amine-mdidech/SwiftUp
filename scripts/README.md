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

## seed_daily_quizzes.py

Loads `seed-questions.json` and writes the `dailyQuizzes` collection: one
document per calendar date (`YYYY-MM-DD`), each with that day's shared
`edition` number and a 5-question set per skill level (`junior`/`mid`/
`senior`). Every user at a given level reads the same document, so they all
see the same edition and the same questions on a given day.

1. Same setup as `seed_questions.py` (needs `scripts/serviceAccountKey.json`).
2. `python3 scripts/seed_daily_quizzes.py` — seeds today + the next 13 days.
   Run it periodically (or with a larger `--days`) to keep a runway of
   upcoming dates seeded; the app falls back to a bundled question set if
   today's document isn't there yet.

Flags: `--days N` (default 14), `--start YYYY-MM-DD` (default today).

Safe to re-run: picks are seeded by `(date, level)`, so re-running with an
unchanged `seed-questions.json` reproduces the same questions for a date
that's already been seeded, rather than reshuffling it.
