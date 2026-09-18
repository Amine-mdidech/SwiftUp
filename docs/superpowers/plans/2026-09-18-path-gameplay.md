# Path — Gameplay Loop (Sub-project C) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the entire remaining Path gameplay loop — spending XP to unlock a stage, a linear slide deck for lesson stages, a shared pass/fail quiz engine reused by lesson stages, track assessments, and the grade regrade quiz, and the actual `SkillLevel` promotion write.

**Architecture:** New, fully decoupled content types (`PathSlide`/`PathQuizQuestion`/`PathStageContent`/`PathRegradeQuiz`) and formula-generated placeholder content (mirroring Sub-project A's track-generation approach) sit behind two new read-only Firestore collections. `PathRepository` gains the spend/complete/promote write paths plus on-demand content fetchers. Two small `@Observable` session types (`PathLessonSession`, `PathQuizSession`) and their views (`PathStageSlidesView`, `PathQuizView`, `PathRegradeQuizView`) are built bottom-up and wired into the already-existing `TrackLadderView`/`PathWheelView` last, exactly the same "build the leaves before the root" sequencing Sub-project B used.

**Tech Stack:** SwiftUI (iOS 17+), Firebase/Firestore, Swift Testing, XcodeGen, Python 3 (content generation scripts).

**Spec:** `docs/superpowers/specs/2026-09-18-path-gameplay-design.md`

## Global Constraints

- 80% is the pass bar everywhere a quiz appears: lesson-stage quizzes, track-assessment quizzes, and the regrade quiz — one consistent rule, no exceptions.
- No XP is ever earned back inside Path. Every quiz is pass/fail only; passing grants zero XP. Path only ever spends `xpBalance` (earned elsewhere, via Daily Quiz / Interview Prep).
- Spending XP on a stage is a one-time unlock. A failed quiz attempt can always be retried for free — no re-charge, ever, for the same stage.
- Track-assessment stages (`PathStage.Kind.assessment`) have **no slides** — they go straight to their quiz.
- The regrade quiz is free to start. Closing every track in the grade is itself the only unlock condition — no additional `xpCost`.
- Both new Firestore collections (`pathStageContent`, `pathRegradeQuizzes`) must get the same read-only rule pattern already used for `pathTracks`: `allow read: if request.auth != null; allow write: if false;`. A missing rule for `pathTracks` was the one Critical bug caught in Sub-project A's final review — this plan must not repeat it.
- Tests run on `-destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6'` (the bare `name=iPhone 16` destination is ambiguous on this machine without pinning `OS=18.6`). A full-app build (no tests) instead uses `-destination 'generic/platform=iOS Simulator'`.
- Every `xcodebuild`/`xcodegen` command must run in the **foreground** — never background a build or test run.
- After adding or removing any file, run `xcodegen generate` from the repo root before building.
- Two pre-existing **untracked** files, `SwiftUp/App/SplashView.swift` and `SwiftUp/Assets.xcassets/`, belong to the user's own separate in-progress work — never commit them, and copy them into any new worktree so the baseline builds.

---

## Task 1: Path content data model and generated placeholder content

**Files:**
- Create: `SwiftUp/Models/PathContent.swift`
- Create: `scripts/generate_path_content.py`
- Create: `scripts/seed_path_content.py`
- Create (generated, run the script in Step 4): `scripts/path-content.json`, `SwiftUp/Resources/path_content.json`, `SwiftUpTests/Fixtures/path_content.json`
- Test: `SwiftUpTests/RepositoryTests.swift`

**Interfaces:**
- Consumes: `PathTrack`/`PathStage` (already merged, `SwiftUp/Models/PathTrack.swift`) — the generation script reads `scripts/path-tracks.json` to enumerate every stage.
- Produces: `PathSlide`, `PathQuizQuestion`, `PathStageContent`, `PathRegradeQuiz`, `PathContentBundle` (all in `PathContent.swift`) — Task 2 (`PathRepository`) and every later task consume these exact types.

- [ ] **Step 1: Write the data model**

Create `SwiftUp/Models/PathContent.swift`:

```swift
import Foundation

struct PathSlide: Codable, Identifiable, Hashable {
    let id: String
    let order: Int
    let title: String
    let body: String
    let example: String?
}

struct PathQuizQuestion: Codable, Identifiable, Hashable {
    let id: String
    let prompt: String
    let options: [QuestionOption]
    let correctOptionID: String
}

struct PathStageContent: Codable, Hashable {
    let stageID: String
    let slides: [PathSlide]
    let quiz: [PathQuizQuestion]
}

struct PathRegradeQuiz: Codable, Hashable {
    let grade: SkillLevel
    let questions: [PathQuizQuestion]
}

/// Decodes the single bundled `path_content.json` resource, which holds every stage's content
/// plus every grade's regrade quiz in one file (mirroring how `path_tracks.json` holds every
/// track in one file).
struct PathContentBundle: Codable {
    let stageContent: [PathStageContent]
    let regradeQuizzes: [PathRegradeQuiz]
}
```

`QuestionOption` already exists in `SwiftUp/Models/Question.swift` (`struct QuestionOption: Codable, Identifiable, Hashable { let id: String; let text: String }`) — reused here rather than duplicated.

- [ ] **Step 2: Write the content-generation script**

Create `scripts/generate_path_content.py`:

```python
#!/usr/bin/env python3
"""Generates scripts/path-content.json (placeholder slides + quiz content for every stage,
plus one regrade quiz per promotable grade) from scripts/path-tracks.json — see design doc
docs/superpowers/specs/2026-09-18-path-gameplay-design.md §2 for why this is formula-generated
placeholder content rather than hand-authored material.

Run: python3 scripts/generate_path_content.py
Re-run any time scripts/path-tracks.json changes; it overwrites scripts/path-content.json
deterministically (same inputs -> same output).
"""
import json
import random
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
TRACKS_PATH = SCRIPT_DIR / "path-tracks.json"

OPTION_LABELS = ["Correct answer", "Incorrect answer 1", "Incorrect answer 2", "Incorrect answer 3"]
OPTION_IDS = ["A", "B", "C", "D"]


def build_quiz_question(stage_id: str, question_index: int, title: str) -> dict:
    # Deterministically seeded so re-running the script produces byte-identical output.
    rng = random.Random(f"{stage_id}-q{question_index}")
    labels = OPTION_LABELS[:]
    rng.shuffle(labels)
    options = [{"id": OPTION_IDS[i], "text": labels[i]} for i in range(4)]
    correct_option_id = next(o["id"] for o in options if o["text"] == "Correct answer")
    return {
        "id": f"{stage_id}-q{question_index:02d}",
        "prompt": f"Placeholder question {question_index} for \"{title}\".",
        "options": options,
        "correctOptionID": correct_option_id,
    }


def build_slide(stage_id: str, slide_index: int, stage_title: str, track_title: str) -> dict:
    has_example = slide_index in (2, 4)
    return {
        "id": f"{stage_id}-slide{slide_index:02d}",
        "order": slide_index,
        "title": f"{stage_title} — part {slide_index} of 4",
        "body": f"This part of {stage_title} continues the {track_title} track.",
        "example": f"// placeholder example for {stage_title}, part {slide_index}" if has_example else None,
    }


def build_stage_content(stage: dict, track_title: str) -> dict:
    stage_id = stage["id"]
    if stage["kind"] == "assessment":
        quiz = [build_quiz_question(stage_id, i, stage["title"]) for i in range(1, 9)]
        return {"stageID": stage_id, "slides": [], "quiz": quiz}
    slides = [build_slide(stage_id, i, stage["title"], track_title) for i in range(1, 5)]
    quiz = [build_quiz_question(stage_id, i, stage["title"]) for i in range(1, 6)]
    return {"stageID": stage_id, "slides": slides, "quiz": quiz}


def build_regrade_quiz(grade: str) -> dict:
    questions = [build_quiz_question(f"regrade-{grade.lower()}", i, f"{grade} regrade") for i in range(1, 11)]
    return {"grade": grade, "questions": questions}


def main() -> None:
    tracks = json.loads(TRACKS_PATH.read_text())

    stage_content = []
    for track in tracks:
        for stage in track["stages"]:
            stage_content.append(build_stage_content(stage, track["title"]))

    # Distinguished has no `.next` grade (SkillLevel.swift) — there is nothing to regrade into,
    # so it gets no regrade quiz.
    grades_with_next = ["Junior", "Mid", "Senior"]
    regrade_quizzes = [build_regrade_quiz(grade) for grade in grades_with_next]

    content = json.dumps(
        {"stageContent": stage_content, "regradeQuizzes": regrade_quizzes},
        indent=2, ensure_ascii=False,
    ) + "\n"

    repo_root = SCRIPT_DIR.parent
    out_paths = [
        SCRIPT_DIR / "path-content.json",
        repo_root / "SwiftUp" / "Resources" / "path_content.json",
        repo_root / "SwiftUpTests" / "Fixtures" / "path_content.json",
    ]
    for out_path in out_paths:
        out_path.write_text(content)
    print(
        f"Wrote {len(stage_content)} stage-content docs and {len(regrade_quizzes)} regrade "
        f"quizzes to {len(out_paths)} files: " + ", ".join(str(p) for p in out_paths)
    )


if __name__ == "__main__":
    main()
```

- [ ] **Step 3: Write the seed script (not run against live Firestore in this task)**

Create `scripts/seed_path_content.py`:

```python
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
```

Do not run this script — it requires a live service-account key and writes to production Firestore. Leave it unexecuted, matching every other seed script in this project.

- [ ] **Step 4: Run the generation script and verify its output**

Run: `python3 scripts/generate_path_content.py`
Expected: prints `Wrote 141 stage-content docs and 3 regrade quizzes to 3 files: ...` and creates `scripts/path-content.json`, `SwiftUp/Resources/path_content.json`, `SwiftUpTests/Fixtures/path_content.json` (three identical copies).

If the printed count is not `141` stage-content docs and `3` regrade quizzes, stop and check `scripts/path-tracks.json` still has 20 tracks / 141 total stages (Sub-project A's own generated count) before proceeding — a mismatch means `scripts/path-tracks.json` has drifted and this task's script needs to be re-examined, not the count silently accepted.

- [ ] **Step 5: Write the failing tests**

Add to `SwiftUpTests/RepositoryTests.swift` (inside the `RepositoryTests` struct, after the existing `pathWheelDiagramNodePositionsAreEvenlySpacedStartingAtTwelveOClock` test):

```swift
    @Test func pathStageContentBundledFixtureDecodesAllStagesWithCorrectQuizSizes() throws {
        let bundle = try #require(decodeJSONResource(PathContentBundle.self, filename: "path_content", bundle: testBundle))
        #expect(bundle.stageContent.count == 141)

        let tracks = decodeJSONResource([PathTrack].self, filename: "path_tracks", bundle: testBundle) ?? []
        let allStages = tracks.flatMap(\.stages)
        #expect(allStages.count == 141)

        for stage in allStages {
            let content = try #require(bundle.stageContent.first { $0.stageID == stage.id })
            if stage.kind == .assessment {
                #expect(content.slides.isEmpty)
                #expect(content.quiz.count == 8)
            } else {
                #expect(content.slides.count == 4)
                #expect(content.quiz.count == 5)
            }
        }

        #expect(bundle.regradeQuizzes.count == 3)
        #expect(Set(bundle.regradeQuizzes.map(\.grade)) == [.junior, .mid, .senior])
        for quiz in bundle.regradeQuizzes {
            #expect(quiz.questions.count == 10)
        }
    }

    @Test func pathQuizQuestionsAlwaysHaveTheirCorrectOptionIDAmongTheirOwnFourOptions() throws {
        let bundle = try #require(decodeJSONResource(PathContentBundle.self, filename: "path_content", bundle: testBundle))
        for content in bundle.stageContent {
            for question in content.quiz {
                #expect(question.options.count == 4)
                #expect(question.options.contains { $0.id == question.correctOptionID })
            }
        }
        for quiz in bundle.regradeQuizzes {
            for question in quiz.questions {
                #expect(question.options.count == 4)
                #expect(question.options.contains { $0.id == question.correctOptionID })
            }
        }
    }
```

- [ ] **Step 6: Run tests to verify they fail**

Run: `xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:SwiftUpTests/RepositoryTests`
Expected: FAIL — `PathContentBundle`/`PathStageContent`/etc. don't exist yet if Step 1 wasn't done first, or the fixture file doesn't exist yet if run before Step 4. Since Steps 1 and 4 come first in this task, this step is a sanity check that the test file itself compiles and the assertions are meaningful — if everything above was done in order, this may already PASS. If so, note that in your report rather than treating it as a problem; the strict red-green-refactor ordering matters less here since the "implementation" (the generated JSON) already exists by the time the test is written.

- [ ] **Step 7: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:SwiftUpTests/RepositoryTests`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add SwiftUp/Models/PathContent.swift scripts/generate_path_content.py scripts/seed_path_content.py scripts/path-content.json SwiftUp/Resources/path_content.json SwiftUpTests/Fixtures/path_content.json SwiftUpTests/RepositoryTests.swift
git commit -m "Add Path content data model and generated placeholder slide/quiz content"
```

---

## Task 2: `PathRepository` spend, complete, promote, and content fetch

**Files:**
- Modify: `SwiftUp/Data/PathRepository.swift`
- Modify: `firestore.rules`
- Test: `SwiftUpTests/RepositoryTests.swift`

**Interfaces:**
- Consumes: `PathStageContent`, `PathRegradeQuiz`, `PathContentBundle` (Task 1).
- Produces:
  - `PathRepository.startedStageIDs: Set<String>` (read-only property)
  - `PathRepository.isStageStarted(_ stage: PathStage) -> Bool`
  - `PathRepository.SpendResult` enum: `.started(newBalance: Int)`, `.alreadyStarted`, `.insufficientXP(balance: Int)`, `.failed`
  - `PathRepository.startStage(_ stage: PathStage, cost: Int, for uid: String) async -> SpendResult`
  - `PathRepository.completeStage(_ stage: PathStage, for uid: String) async`
  - `PathRepository.promoteGrade(from currentGrade: SkillLevel, for uid: String) async`
  - `PathRepository.fetchStageContent(for stage: PathStage) async -> PathStageContent?`
  - `PathRepository.fetchRegradeQuiz(for grade: SkillLevel) async -> PathRegradeQuiz?`
  — all consumed by Task 6 (`TrackLadderView`) and Task 7 (`PathWheelView`/`PathRegradeQuizView`).

- [ ] **Step 1: Write the failing tests**

Add to `SwiftUpTests/RepositoryTests.swift`, after Task 1's tests:

```swift
    @Test func pathRepositoryIsStageStartedFalseOnAFreshRepository() {
        let stage = PathStage(id: "t-s01", order: 1, title: "One", xpCost: 50, kind: .lesson)
        let repo = PathRepository()
        #expect(repo.isStageStarted(stage) == false)
    }

    @Test func pathRepositoryPromoteGradeIsANoOpAtTheTopGrade() async {
        // `.distinguished.next` is `nil`, so `promoteGrade` returns before touching Firestore —
        // the one branch of this method safely testable without a live network call (same
        // limitation already accepted for every other Firestore write in this project).
        let repo = PathRepository()
        await repo.promoteGrade(from: .distinguished, for: "any-uid")
        #expect(repo.grade == .junior)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:SwiftUpTests/RepositoryTests`
Expected: FAIL — `isStageStarted`/`promoteGrade` don't exist yet.

- [ ] **Step 3: Implement the additions**

In `SwiftUp/Data/PathRepository.swift`, add a new stored property alongside the existing ones:

```swift
    private(set) var startedStageIDs: Set<String> = []
```

In `load(for uid:)`, add one line after `completedStageIDs = Self.completedStageIDs(from: userDoc)`:

```swift
        completedStageIDs = Self.completedStageIDs(from: userDoc)
        startedStageIDs = Self.startedStageIDs(from: userDoc)
        grade = Self.grade(from: userDoc)
```

Add a new private static decoder next to the existing `completedStageIDs(from:)`:

```swift
    private static func startedStageIDs(from snapshot: DocumentSnapshot?) -> Set<String> {
        guard let map = snapshot?.get("startedPathStageIDs") as? [String: Timestamp] else {
            return []
        }
        return Set(map.keys)
    }
```

Add a new public method next to `isStageCompleted`:

```swift
    func isStageStarted(_ stage: PathStage) -> Bool {
        startedStageIDs.contains(stage.id)
    }
```

Add the spend/complete/promote/content-fetch API at the end of the class, before the closing brace:

```swift
    enum SpendResult: Equatable {
        case started(newBalance: Int)
        case alreadyStarted
        case insufficientXP(balance: Int)
        case failed
    }

    /// Spends `cost` xp to unlock `stage`, or returns `.alreadyStarted` for free if it's already
    /// unlocked (or already completed) — spending is a one-time cost, never repeated for the same
    /// stage (design doc §3). The already-started/already-completed check happens before any
    /// Firestore access, so a retry never even attempts a re-charge.
    ///
    /// Not independently unit-tested beyond `isStageStarted`'s own coverage: every other branch
    /// here requires live Firestore state, matching the accepted limitation already in place for
    /// every other Firestore write in this project (see design doc §7).
    func startStage(_ stage: PathStage, cost: Int, for uid: String) async -> SpendResult {
        if completedStageIDs.contains(stage.id) || startedStageIDs.contains(stage.id) {
            return .alreadyStarted
        }

        let userRef = Firestore.firestore().collection("users").document(uid)
        guard let snapshot = try? await userRef.getDocument() else { return .failed }

        let totalXP = (snapshot.get("totalXP") as? Int) ?? 0
        let currentBalance = (snapshot.get("xpBalance") as? Int) ?? totalXP
        guard currentBalance >= cost else { return .insufficientXP(balance: currentBalance) }

        let newBalance = currentBalance - cost
        do {
            try await userRef.setData(
                ["xpBalance": newBalance, "startedPathStageIDs": [stage.id: FieldValue.serverTimestamp()]],
                merge: true
            )
            startedStageIDs.insert(stage.id)
            return .started(newBalance: newBalance)
        } catch {
            return .failed
        }
    }

    /// Marks `stage` as completed after a passing quiz attempt. No XP is written here — passing
    /// grants no XP (design doc §3); this call only records progress.
    func completeStage(_ stage: PathStage, for uid: String) async {
        let userRef = Firestore.firestore().collection("users").document(uid)
        do {
            try await userRef.setData(
                ["completedPathStageIDs": [stage.id: FieldValue.serverTimestamp()]],
                merge: true
            )
            completedStageIDs.insert(stage.id)
        } catch {
            // Non-blocking — matches this project's accepted best-effort posture for Firestore writes.
        }
    }

    /// Promotes the user to `currentGrade.next` after a passing regrade quiz — the only place
    /// `SkillLevel` is written outside onboarding (design doc §6). A no-op at the top grade
    /// (`.distinguished.next == nil`), returning before touching Firestore.
    func promoteGrade(from currentGrade: SkillLevel, for uid: String) async {
        guard let next = currentGrade.next else { return }
        let userRef = Firestore.firestore().collection("users").document(uid)
        do {
            try await userRef.setData(["skillLevel": next.rawValue], merge: true)
            grade = next
        } catch {
            // Non-blocking — matches this project's accepted best-effort posture for Firestore writes.
        }
    }

    /// Fetches one stage's slide/quiz content, falling back to the bundled placeholder content
    /// (mirroring `fetchTracks`' own bundled-fallback pattern) if Firestore is unreachable.
    func fetchStageContent(for stage: PathStage) async -> PathStageContent? {
        if let snapshot = try? await Firestore.firestore().collection("pathStageContent").document(stage.id).getDocument(),
           let content = try? snapshot.data(as: PathStageContent.self) {
            return content
        }
        return Self.loadBundledStageContent().first { $0.stageID == stage.id }
    }

    /// Fetches one grade's regrade quiz, same bundled-fallback pattern as `fetchStageContent`.
    func fetchRegradeQuiz(for grade: SkillLevel) async -> PathRegradeQuiz? {
        let docID = grade.rawValue.lowercased()
        if let snapshot = try? await Firestore.firestore().collection("pathRegradeQuizzes").document(docID).getDocument(),
           let quiz = try? snapshot.data(as: PathRegradeQuiz.self) {
            return quiz
        }
        return Self.loadBundledRegradeQuizzes().first { $0.grade == grade }
    }

    private static func loadBundledStageContent(bundle: Bundle = .main) -> [PathStageContent] {
        decodeJSONResource(PathContentBundle.self, filename: "path_content", bundle: bundle)?.stageContent ?? []
    }

    private static func loadBundledRegradeQuizzes(bundle: Bundle = .main) -> [PathRegradeQuiz] {
        decodeJSONResource(PathContentBundle.self, filename: "path_content", bundle: bundle)?.regradeQuizzes ?? []
    }
```

- [ ] **Step 4: Add the Firestore security rules**

In `firestore.rules`, add two new collection blocks after the existing `pathTracks` block and before the `leaderboardEntries` comment block:

```
    match /pathStageContent/{stageId} {
      allow read: if request.auth != null;
      allow write: if false;
    }
    match /pathRegradeQuizzes/{grade} {
      allow read: if request.auth != null;
      allow write: if false;
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:SwiftUpTests/RepositoryTests`
Expected: PASS.

- [ ] **Step 6: Full build check**

Run: `xcodebuild build -scheme SwiftUp -destination 'generic/platform=iOS Simulator'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add SwiftUp/Data/PathRepository.swift firestore.rules SwiftUpTests/RepositoryTests.swift
git commit -m "Add PathRepository spend/complete/promote and content-fetch methods"
```

---

## Task 3: `ProfileRepository.applyExternalXPBalance`

**Files:**
- Modify: `SwiftUp/Data/ProfileRepository.swift`
- Test: `SwiftUpTests/RepositoryTests.swift`

**Interfaces:**
- Consumes: `UserProfile` (existing, unchanged).
- Produces: `ProfileRepository.applyExternalXPBalance(_ newBalance: Int)` — consumed by Task 6 (`TrackLadderView`, after a successful `PathRepository.startStage` call).

- [ ] **Step 1: Write the failing test**

Add to `SwiftUpTests/RepositoryTests.swift`, after Task 2's tests:

```swift
    @Test func profileRepositoryApplyExternalXPBalanceUpdatesOnlyXPBalance() {
        let repo = ProfileRepository.preview(bundle: testBundle)
        let originalXP = repo.profile.xp
        let originalLevel = repo.profile.level
        let originalName = repo.profile.name

        repo.applyExternalXPBalance(500)

        #expect(repo.profile.xpBalance == 500)
        #expect(repo.profile.xp == originalXP)
        #expect(repo.profile.level == originalLevel)
        #expect(repo.profile.name == originalName)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:SwiftUpTests/RepositoryTests`
Expected: FAIL — `applyExternalXPBalance` doesn't exist yet.

- [ ] **Step 3: Implement it**

In `SwiftUp/Data/ProfileRepository.swift`, add this method to the `ProfileRepository` class (anywhere among the other public methods, e.g. right after `recordCompletion`):

```swift
    /// Updates only the in-memory `xpBalance` mirror after `PathRepository.startStage` has
    /// already written the real decrement to Firestore — avoids a full `load(for:)` round trip
    /// just to reflect a balance this repository didn't itself compute (design doc §3).
    func applyExternalXPBalance(_ newBalance: Int) {
        profile = UserProfile(
            name: profile.name, initials: profile.initials, level: profile.level, levelTitle: profile.levelTitle,
            xp: profile.xp, xpBalance: newBalance, xpForCurrentLevel: profile.xpForCurrentLevel, xpForNextLevel: profile.xpForNextLevel,
            streakDays: profile.streakDays, freezesAvailable: profile.freezesAvailable, freezesTotal: profile.freezesTotal,
            answeredCount: profile.answeredCount, accuracyPercent: profile.accuracyPercent, memberSinceDisplay: profile.memberSinceDisplay
        )
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:SwiftUpTests/RepositoryTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add SwiftUp/Data/ProfileRepository.swift SwiftUpTests/RepositoryTests.swift
git commit -m "Add ProfileRepository.applyExternalXPBalance for cross-repository XP sync"
```

---

## Task 4: `PathQuizSession` and `PathQuizView` — the shared quiz engine

**Files:**
- Create: `SwiftUp/Features/Path/PathQuizSession.swift`
- Create: `SwiftUp/Features/Path/PathQuizView.swift`
- Test: `SwiftUpTests/RepositoryTests.swift`

**Interfaces:**
- Consumes: `PathQuizQuestion` (Task 1).
- Produces: `PathQuizSession` (init, `currentQuestion`, `isFinished`, `correctCount`, `scorePercent`, `passed`, `selectedOptionID(for:)`, `isAnswered(_:)`, `selectOption(_:)`, `advance()`, `retry()`) and `PathQuizView(title:session:onPassed:onFinished:)` — both consumed by Task 5 (`PathStageSlidesView`), Task 6 (`TrackLadderView`, for assessment stages), and Task 7 (`PathRegradeQuizView`).

- [ ] **Step 1: Write the failing tests**

Add to `SwiftUpTests/RepositoryTests.swift`, after Task 3's test:

```swift
    @Test func pathQuizSessionScorePercentAndPassedBoundary() {
        func question(_ id: String) -> PathQuizQuestion {
            PathQuizQuestion(
                id: id, prompt: "P",
                options: [QuestionOption(id: "A", text: "Correct answer"), QuestionOption(id: "B", text: "Incorrect answer 1")],
                correctOptionID: "A"
            )
        }
        let questions = (1...5).map { question("q\($0)") }
        let session = PathQuizSession(questions: questions)

        for _ in 0..<4 {
            session.selectOption("A")   // correct
            session.advance()
        }
        session.selectOption("B")   // wrong, 5th question
        session.advance()

        #expect(session.isFinished == true)
        #expect(session.correctCount == 4)
        #expect(session.scorePercent == 80)
        #expect(session.passed == true)
    }

    @Test func pathQuizSessionBelowEightyPercentFails() {
        func question(_ id: String) -> PathQuizQuestion {
            PathQuizQuestion(
                id: id, prompt: "P",
                options: [QuestionOption(id: "A", text: "Correct answer"), QuestionOption(id: "B", text: "Incorrect answer 1")],
                correctOptionID: "A"
            )
        }
        let questions = (1...5).map { question("q\($0)") }
        let session = PathQuizSession(questions: questions)

        session.selectOption("A"); session.advance()
        session.selectOption("A"); session.advance()
        session.selectOption("A"); session.advance()
        session.selectOption("B"); session.advance()
        session.selectOption("B"); session.advance()

        #expect(session.scorePercent == 60)
        #expect(session.passed == false)
    }

    @Test func pathQuizSessionRetryResetsAnswersButKeepsTheSameQuestions() {
        func question(_ id: String) -> PathQuizQuestion {
            PathQuizQuestion(id: id, prompt: "P", options: [QuestionOption(id: "A", text: "Correct answer")], correctOptionID: "A")
        }
        let questions = [question("q1"), question("q2")]
        let session = PathQuizSession(questions: questions)

        session.selectOption("A"); session.advance()
        session.selectOption("A"); session.advance()
        #expect(session.isFinished == true)

        session.retry()

        #expect(session.isFinished == false)
        #expect(session.currentIndex == 0)
        #expect(session.isAnswered(questions[0]) == false)
        #expect(session.questions.count == 2)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:SwiftUpTests/RepositoryTests`
Expected: FAIL — `PathQuizSession` doesn't exist yet.

- [ ] **Step 3: Implement `PathQuizSession`**

Create `SwiftUp/Features/Path/PathQuizSession.swift`:

```swift
import Foundation

/// The shared pass/fail quiz engine reused by a lesson stage's quiz (after its slides), a
/// track-assessment stage's quiz (no slides), and the grade regrade quiz — only the `questions`
/// array, and the title/callbacks `PathQuizView` is constructed with, differ per use. Unlike
/// `QuizSession` (Daily Quiz), this grants no XP: passing is its own reward (design doc §0/§3).
@Observable
final class PathQuizSession {
    let questions: [PathQuizQuestion]
    private(set) var currentIndex = 0
    private var answers: [String: String] = [:]

    init(questions: [PathQuizQuestion]) {
        self.questions = questions
    }

    var currentQuestion: PathQuizQuestion? {
        guard currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }

    var isFinished: Bool { currentIndex >= questions.count }

    var correctCount: Int {
        questions.filter { answers[$0.id] == $0.correctOptionID }.count
    }

    var scorePercent: Int {
        questions.isEmpty ? 0 : (correctCount * 100) / questions.count
    }

    var passed: Bool { scorePercent >= 80 }

    func selectedOptionID(for question: PathQuizQuestion) -> String? {
        answers[question.id]
    }

    func isAnswered(_ question: PathQuizQuestion) -> Bool {
        answers[question.id] != nil
    }

    func selectOption(_ optionID: String) {
        guard let question = currentQuestion, answers[question.id] == nil else { return }
        answers[question.id] = optionID
    }

    func advance() {
        currentIndex += 1
    }

    /// Resets to the first question with every answer cleared, keeping the same `questions`
    /// array — a free retry, never a re-fetch (design doc §0: retries never re-charge XP).
    func retry() {
        currentIndex = 0
        answers = [:]
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:SwiftUpTests/RepositoryTests`
Expected: PASS.

- [ ] **Step 5: Implement `PathQuizView`**

Create `SwiftUp/Features/Path/PathQuizView.swift`:

```swift
import SwiftUI

/// The shared quiz UI for a lesson stage's quiz, a track-assessment stage's quiz, and the grade
/// regrade quiz (`PathRegradeQuizView`). `title` labels the header (a stage/track title, or
/// "Regrade quiz"). `onPassed` fires once, the moment a passing score is reached, to record
/// progress (`PathRepository.completeStage`/`.promoteGrade` — the caller decides which).
/// `onFinished` fires only when the user taps "Back to <title>" after passing, popping back to
/// wherever this view was pushed from.
struct PathQuizView: View {
    let title: String
    let session: PathQuizSession
    let onPassed: () async -> Void
    let onFinished: () -> Void

    var body: some View {
        Group {
            if session.isFinished {
                resultContent
            } else if let question = session.currentQuestion {
                questionContent(question)
            }
        }
        .padding(24)
        .background(Theme.Colors.bg)
        .navigationBarBackButtonHidden()
    }

    @ViewBuilder
    private func questionContent(_ question: PathQuizQuestion) -> some View {
        let answered = session.isAnswered(question)
        let selected = session.selectedOptionID(for: question)
        let isCorrect = selected == question.correctOptionID

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.system(size: 11)).foregroundStyle(Theme.Colors.neutral700)
                Spacer()
                Text("Question \(String(format: "%02d", session.currentIndex + 1)) / \(String(format: "%02d", session.questions.count))")
                    .font(.system(size: 10)).foregroundStyle(Theme.Colors.neutral700)
            }

            HStack(spacing: 4) {
                ForEach(0..<session.questions.count, id: \.self) { i in
                    Rectangle().fill(tickColor(at: i)).frame(height: 4)
                }
            }
            .padding(.top, 6)

            Text(question.prompt)
                .font(answered ? Theme.Fonts.heading(21) : Theme.Fonts.heading(26))
                .foregroundStyle(answered ? Theme.Colors.neutral700 : Theme.Colors.text)
                .padding(.top, answered ? 24 : 34)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(question.options) { option in
                        optionRow(option, question: question, answered: answered, selected: selected)
                    }
                }
            }
            .padding(.top, 30)

            if answered {
                Text(isCorrect ? "Correct." : "Not quite.")
                    .font(Theme.Fonts.heading(20))
                    .foregroundStyle(isCorrect ? Theme.Colors.accent700 : Theme.Colors.accent2800)
                    .padding(.top, 20)

                Button(action: { session.advance() }) {
                    Text(session.currentIndex == session.questions.count - 1 ? "See results" : "Next question")
                        .font(Theme.Fonts.heading(17))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .background(Theme.Colors.accent)
                .foregroundStyle(Theme.Colors.bg)
                .padding(.top, 20)
            } else {
                Spacer(minLength: 20)
                HStack {
                    Spacer()
                    EyebrowLabel("Tap an answer")
                }
            }
        }
    }

    private func tickColor(at index: Int) -> Color {
        guard index <= session.currentIndex else { return Theme.Colors.neutral300 }
        guard index < session.currentIndex || session.isAnswered(session.questions[index]) else {
            return Theme.Colors.text
        }
        let q = session.questions[index]
        guard let picked = session.selectedOptionID(for: q) else { return Theme.Colors.text }
        return picked == q.correctOptionID ? Theme.Colors.accent : Theme.Colors.accent2
    }

    @ViewBuilder
    private func optionRow(_ option: QuestionOption, question: PathQuizQuestion, answered: Bool, selected: String?) -> some View {
        let isSelected = selected == option.id
        let isCorrectOption = option.id == question.correctOptionID
        let showAsCorrect = answered && isCorrectOption
        let showAsWrong = answered && isSelected && !isCorrectOption

        HStack(alignment: .top, spacing: 12) {
            Text(option.id)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(showAsCorrect ? Theme.Colors.accent700 : (showAsWrong ? Theme.Colors.accent2800 : Theme.Colors.neutral600))
                .frame(width: 14, alignment: .leading)
            Text(option.text)
                .font(Theme.Fonts.body(15.5))
                .foregroundStyle(Theme.Colors.text)
        }
        .padding(.vertical, 13)
        .padding(.horizontal, showAsCorrect || showAsWrong ? 11 : 2)
        .background(showAsCorrect ? Theme.Colors.accent100 : (showAsWrong ? Theme.Colors.accent2100 : Color.clear))
        .opacity(answered && !isSelected && !isCorrectOption ? 0.4 : 1)
        .overlay(Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .bottom)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .onTapGesture {
            guard !answered else { return }
            session.selectOption(option.id)
        }
    }

    private var resultContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(session.passed ? "Passed." : "Not yet.")
                .font(Theme.Fonts.heading(30))
            Text("\(session.correctCount) of \(session.questions.count) correct — \(session.scorePercent)%")
                .font(Theme.Fonts.body(15))
                .foregroundStyle(Theme.Colors.neutral800)
                .padding(.top, 12)

            if session.passed {
                Text("80% or higher passes.")
                    .font(Theme.Fonts.body(13))
                    .foregroundStyle(Theme.Colors.neutral700)
                    .padding(.top, 6)
                Button(action: onFinished) {
                    Text("Back to \(title)")
                        .font(Theme.Fonts.heading(17))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .background(Theme.Colors.accent)
                .foregroundStyle(Theme.Colors.bg)
                .padding(.top, 24)
            } else {
                Text("80% or higher passes — try again, it's free.")
                    .font(Theme.Fonts.body(13))
                    .foregroundStyle(Theme.Colors.neutral700)
                    .padding(.top, 6)
                Button(action: { session.retry() }) {
                    Text("Try again")
                        .font(Theme.Fonts.heading(17))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .background(Theme.Colors.accent)
                .foregroundStyle(Theme.Colors.bg)
                .padding(.top, 24)
            }
            Spacer(minLength: 20)
        }
        // Fires exactly once per genuine pass: this branch of the view only exists once
        // `isFinished` is true, and the retry button (the only way `passed` flips back to false)
        // lives in the opposite branch below — so `passed` transitions false -> true at most once
        // per session lifetime before a possible future retry resets it.
        .task(id: session.passed) {
            guard session.isFinished, session.passed else { return }
            await onPassed()
        }
    }
}

#Preview("Unanswered") {
    let questions = [
        PathQuizQuestion(
            id: "q1", prompt: "Which of these is correct?",
            options: [
                QuestionOption(id: "A", text: "Correct answer"),
                QuestionOption(id: "B", text: "Incorrect answer 1"),
                QuestionOption(id: "C", text: "Incorrect answer 2"),
                QuestionOption(id: "D", text: "Incorrect answer 3"),
            ],
            correctOptionID: "A"
        )
    ]
    return PathQuizView(title: "Preview stage", session: PathQuizSession(questions: questions), onPassed: {}, onFinished: {})
}
```

- [ ] **Step 6: Full build check**

Run: `xcodegen generate && xcodebuild build -scheme SwiftUp -destination 'generic/platform=iOS Simulator'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add SwiftUp/Features/Path/PathQuizSession.swift SwiftUp/Features/Path/PathQuizView.swift SwiftUpTests/RepositoryTests.swift
git commit -m "Add PathQuizSession and PathQuizView, the shared quiz engine"
```

---

## Task 5: `PathLessonSession` and `PathStageSlidesView`

**Files:**
- Create: `SwiftUp/Features/Path/PathLessonSession.swift`
- Create: `SwiftUp/Features/Path/PathStageSlidesView.swift`
- Test: `SwiftUpTests/RepositoryTests.swift`

**Interfaces:**
- Consumes: `PathSlide`, `PathStageContent` (Task 1), `PathQuizSession`/`PathQuizView` (Task 4).
- Produces: `PathLessonSession` (init, `currentSlide`, `isFinished`, `isFirstSlide`, `isLastSlide`, `advance()`, `goBack()`) and `PathStageSlidesView(stage:content:onPassed:onFinished:)` — consumed by Task 6 (`TrackLadderView`, for lesson-kind stages only).

- [ ] **Step 1: Write the failing test**

Add to `SwiftUpTests/RepositoryTests.swift`, after Task 4's tests:

```swift
    @Test func pathLessonSessionAdvanceAndGoBackStayWithinBounds() {
        let slides = (1...3).map { PathSlide(id: "s\($0)", order: $0, title: "T\($0)", body: "B", example: nil) }
        let session = PathLessonSession(slides: slides)

        #expect(session.isFirstSlide == true)
        session.goBack()
        #expect(session.isFirstSlide == true)   // already at slide 0, goBack is a no-op

        session.advance()
        session.advance()
        #expect(session.isLastSlide == true)
        #expect(session.isFinished == false)

        session.advance()
        #expect(session.isFinished == true)
        #expect(session.currentSlide == nil)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:SwiftUpTests/RepositoryTests`
Expected: FAIL — `PathLessonSession` doesn't exist yet.

- [ ] **Step 3: Implement `PathLessonSession`**

Create `SwiftUp/Features/Path/PathLessonSession.swift`:

```swift
import Foundation

/// Paging state for a lesson stage's slide deck. Assessment stages never construct one of these —
/// they skip straight to `PathQuizView` (design doc §5).
@Observable
final class PathLessonSession {
    let slides: [PathSlide]
    private(set) var currentIndex = 0

    init(slides: [PathSlide]) {
        self.slides = slides
    }

    var currentSlide: PathSlide? {
        guard currentIndex < slides.count else { return nil }
        return slides[currentIndex]
    }

    var isFinished: Bool { currentIndex >= slides.count }
    var isFirstSlide: Bool { currentIndex == 0 }
    var isLastSlide: Bool { currentIndex == slides.count - 1 }

    func advance() {
        currentIndex = min(currentIndex + 1, slides.count)
    }

    func goBack() {
        currentIndex = max(currentIndex - 1, 0)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:SwiftUpTests/RepositoryTests`
Expected: PASS.

- [ ] **Step 5: Implement `PathStageSlidesView`**

Create `SwiftUp/Features/Path/PathStageSlidesView.swift`:

```swift
import SwiftUI

/// A lesson stage's slide deck, paged Next/Back. On the last slide, "Next" becomes "Start the
/// quiz" and pushes `PathQuizView` fed this stage's `content.quiz` — `onPassed`/`onFinished` are
/// threaded straight through to that nested view unchanged, so whichever pushed this view (only
/// `TrackLadderView`, for a lesson-kind stage) can pop all the way back with one state reset when
/// `onFinished` fires, regardless of whether that happens from the slides or from the quiz nested
/// beneath them.
struct PathStageSlidesView: View {
    let stage: PathStage
    let content: PathStageContent
    let onPassed: () async -> Void
    let onFinished: () -> Void

    @State private var session: PathLessonSession
    @State private var showQuiz = false

    init(stage: PathStage, content: PathStageContent, onPassed: @escaping () async -> Void, onFinished: @escaping () -> Void) {
        self.stage = stage
        self.content = content
        self.onPassed = onPassed
        self.onFinished = onFinished
        _session = State(initialValue: PathLessonSession(slides: content.slides))
    }

    var body: some View {
        Group {
            if let slide = session.currentSlide {
                slideContent(slide)
            }
        }
        .padding(24)
        .background(Theme.Colors.bg)
        .navigationBarBackButtonHidden()
        .navigationDestination(isPresented: $showQuiz) {
            PathQuizView(
                title: stage.title,
                session: PathQuizSession(questions: content.quiz),
                onPassed: onPassed,
                onFinished: onFinished
            )
        }
    }

    private func slideContent(_ slide: PathSlide) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(stage.title).font(.system(size: 11)).foregroundStyle(Theme.Colors.neutral700)
                Spacer()
                Text("Slide \(slide.order) / \(session.slides.count)")
                    .font(.system(size: 10)).foregroundStyle(Theme.Colors.neutral700)
            }

            Text(slide.title)
                .font(Theme.Fonts.heading(26))
                .foregroundStyle(Theme.Colors.text)
                .padding(.top, 30)

            Text(slide.body)
                .font(Theme.Fonts.body(15.5))
                .foregroundStyle(Theme.Colors.neutral800)
                .padding(.top, 16)

            if let example = slide.example {
                Text(example)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Theme.Colors.neutral800)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .top)
                    .overlay(Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .bottom)
                    .padding(.top, 20)
            }

            Spacer(minLength: 20)

            HStack(spacing: 12) {
                Button("Back") { session.goBack() }
                    .disabled(session.isFirstSlide)
                    .frame(minHeight: 44)
                Spacer()
                Button(action: {
                    if session.isLastSlide {
                        showQuiz = true
                    } else {
                        session.advance()
                    }
                }) {
                    Text(session.isLastSlide ? "Start the quiz" : "Next")
                        .font(Theme.Fonts.heading(17))
                        .frame(maxWidth: 200)
                        .padding(.vertical, 16)
                }
                .background(Theme.Colors.accent)
                .foregroundStyle(Theme.Colors.bg)
            }
        }
    }
}

#Preview {
    let content = PathStageContent(
        stageID: "preview-s01",
        slides: [
            PathSlide(id: "s1", order: 1, title: "Value semantics", body: "Structs copy on assignment.", example: nil),
            PathSlide(id: "s2", order: 2, title: "Value semantics", body: "Classes share a reference.", example: "let a = Point(); let b = a"),
        ],
        quiz: [
            PathQuizQuestion(
                id: "q1", prompt: "Preview question?",
                options: [QuestionOption(id: "A", text: "Correct answer"), QuestionOption(id: "B", text: "Incorrect answer 1")],
                correctOptionID: "A"
            )
        ]
    )
    let stage = PathStage(id: "preview-s01", order: 1, title: "Value semantics", xpCost: 50, kind: .lesson)
    return NavigationStack {
        PathStageSlidesView(stage: stage, content: content, onPassed: {}, onFinished: {})
    }
}
```

- [ ] **Step 6: Full build check**

Run: `xcodegen generate && xcodebuild build -scheme SwiftUp -destination 'generic/platform=iOS Simulator'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add SwiftUp/Features/Path/PathLessonSession.swift SwiftUp/Features/Path/PathStageSlidesView.swift SwiftUpTests/RepositoryTests.swift
git commit -m "Add PathLessonSession and PathStageSlidesView"
```

---

## Task 6: Wire `TrackLadderView` — the real spend action

**Files:**
- Modify: `SwiftUp/Features/Path/TrackLadderView.swift`

**Interfaces:**
- Consumes: `PathRepository.startStage`/`.fetchStageContent`/`.completeStage` (Task 2), `ProfileRepository.applyExternalXPBalance` (Task 3), `PathQuizView`/`PathQuizSession` (Task 4), `PathStageSlidesView` (Task 5).
- Produces: nothing further downstream — Task 7 does not depend on any new type from this task.

- [ ] **Step 1: Add the navigation state, alert type, and `AuthRepository` environment**

In `SwiftUp/Features/Path/TrackLadderView.swift`, replace:

```swift
struct TrackLadderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ProfileRepository.self) private var profileRepo
    @Environment(PathRepository.self) private var pathRepo
    let track: PathTrack
```

with:

```swift
struct TrackLadderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ProfileRepository.self) private var profileRepo
    @Environment(PathRepository.self) private var pathRepo
    @Environment(AuthRepository.self) private var authRepo
    let track: PathTrack

    @State private var activeAttempt: StageAttempt?
    @State private var spendAlert: SpendAlert?
```

Add these two new types at the bottom of the same file, after the closing brace of `TrackLadderView` and before the `#Preview`:

```swift
/// Bundles a stage with the content already fetched for it, so `TrackLadderView`'s single
/// `.navigationDestination(item:)` has everything it needs to route to slides (lesson) or
/// straight to a quiz (assessment) without a second async fetch mid-navigation.
private struct StageAttempt: Identifiable, Hashable {
    let stage: PathStage
    let content: PathStageContent
    var id: String { stage.id }
}

private enum SpendAlert: Identifiable {
    case insufficientXP(balance: Int, cost: Int)
    case contentUnavailable
    case writeFailed

    var id: String {
        switch self {
        case .insufficientXP: "insufficientXP"
        case .contentUnavailable: "contentUnavailable"
        case .writeFailed: "writeFailed"
        }
    }

    var message: String {
        switch self {
        case .insufficientXP(let balance, let cost): "You have \(balance) xp — this stage costs \(cost)."
        case .contentUnavailable: "This stage's content isn't available right now. Try again in a moment."
        case .writeFailed: "Couldn't reach the server. Try again."
        }
    }
}
```

- [ ] **Step 2: Wire the real spend button action**

Replace:

```swift
                if let nextStage {
                    Button(action: {}) {
                        Text("Spend \(nextStage.xpCost) xp · start stage \(String(format: "%02d", nextStage.order))")
                            .font(Theme.Fonts.heading(17))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .background(Theme.Colors.accent)
                    .foregroundStyle(Theme.Colors.bg)
                    .padding(.top, 16)
                }
```

with:

```swift
                if let nextStage {
                    Button(action: { spend(nextStage) }) {
                        Text("Spend \(nextStage.xpCost) xp · start stage \(String(format: "%02d", nextStage.order))")
                            .font(Theme.Fonts.heading(17))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .background(Theme.Colors.accent)
                    .foregroundStyle(Theme.Colors.bg)
                    .padding(.top, 16)
                }
```

- [ ] **Step 3: Add the navigation destination and alert modifiers**

Replace:

```swift
        .background(Theme.Colors.bg)
        .navigationBarBackButtonHidden()
    }
```

with:

```swift
        .background(Theme.Colors.bg)
        .navigationBarBackButtonHidden()
        .navigationDestination(item: $activeAttempt) { attempt in
            if attempt.stage.kind == .assessment {
                PathQuizView(
                    title: attempt.stage.title,
                    session: PathQuizSession(questions: attempt.content.quiz),
                    onPassed: { await pathRepo.completeStage(attempt.stage, for: authRepo.currentUser?.uid ?? "") },
                    onFinished: { activeAttempt = nil }
                )
            } else {
                PathStageSlidesView(
                    stage: attempt.stage, content: attempt.content,
                    onPassed: { await pathRepo.completeStage(attempt.stage, for: authRepo.currentUser?.uid ?? "") },
                    onFinished: { activeAttempt = nil }
                )
            }
        }
        .alert(item: $spendAlert) { alert in
            Alert(title: Text("Can't start this stage"), message: Text(alert.message))
        }
    }
```

- [ ] **Step 4: Implement the `spend` method**

Add this private method to `TrackLadderView`, alongside its other private helpers (e.g. right after `nextStage`):

```swift
    private func spend(_ stage: PathStage) {
        guard let uid = authRepo.currentUser?.uid else { return }
        Task {
            let result = await pathRepo.startStage(stage, cost: stage.xpCost, for: uid)
            switch result {
            case .started(let newBalance):
                profileRepo.applyExternalXPBalance(newBalance)
                await openContent(for: stage)
            case .alreadyStarted:
                await openContent(for: stage)
            case .insufficientXP(let balance):
                spendAlert = .insufficientXP(balance: balance, cost: stage.xpCost)
            case .failed:
                spendAlert = .writeFailed
            }
        }
    }

    private func openContent(for stage: PathStage) async {
        guard let content = await pathRepo.fetchStageContent(for: stage) else {
            spendAlert = .contentUnavailable
            return
        }
        activeAttempt = StageAttempt(stage: stage, content: content)
    }
```

- [ ] **Step 5: Full build check**

Run: `xcodegen generate && xcodebuild build -scheme SwiftUp -destination 'generic/platform=iOS Simulator'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Run the full test suite**

Run: `xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6'`
Expected: BUILD SUCCEEDED, all tests pass (no test changes in this task — this just confirms nothing broke).

- [ ] **Step 7: Manual verification in the simulator**

No iOS Simulator UI automation tool is available in this environment (same accepted limitation as every prior UI task in this project) — build and run manually, then check:
1. Tapping "Spend N xp · start stage 01" on a reachable track's first (lesson) stage, with sufficient xp balance, opens the slide deck.
2. Paging through all 4 slides and tapping "Start the quiz" opens a 5-question quiz.
3. Passing the quiz (choose "Correct answer" on every question) shows "Passed." and, after tapping "Back to <stage title>", returns all the way to the track ladder (not just one level back) with the stage now showing a checkmark.
4. Tapping the same stage's spend button again (after `startedPathStageIDs` already has it, before completion, or after completion) does not re-prompt for XP — it reopens the content directly with no XP re-deduction shown in the balance chip.
5. Failing a quiz (pick a wrong answer on purpose) shows "Not yet." with a "Try again" button that resets to question 1 with no navigation change and no new charge.
6. Spending on a track's final (assessment) stage skips slides entirely and opens the quiz directly.
7. With an xp balance below a stage's cost, tapping its spend button shows the "Can't start this stage" alert and does not navigate anywhere.

Report any mismatch before proceeding.

- [ ] **Step 8: Commit**

```bash
git add SwiftUp/Features/Path/TrackLadderView.swift
git commit -m "Wire TrackLadderView's spend button to the real spend/complete flow"
```

---

## Task 7: Regrade quiz and grade promotion

**Files:**
- Create: `SwiftUp/Features/Path/PathRegradeQuizView.swift`
- Modify: `SwiftUp/Features/Path/PathWheelView.swift`

**Interfaces:**
- Consumes: `PathRepository.fetchRegradeQuiz`/`.promoteGrade` (Task 2), `PathQuizView`/`PathQuizSession` (Task 4).
- Produces: nothing further downstream — this is the last task in this plan.

- [ ] **Step 1: Create `PathRegradeQuizView`**

Create `SwiftUp/Features/Path/PathRegradeQuizView.swift`:

```swift
import SwiftUI

/// Thin wrapper around `PathQuizView` for the grade regrade quiz — free to start (closing every
/// track in the grade is the only unlock condition, design doc §6), fetched on appear rather than
/// passed in, since `PathWheelView` only knows the *grade*, not its quiz content.
struct PathRegradeQuizView: View {
    @Environment(PathRepository.self) private var pathRepo
    @Environment(AuthRepository.self) private var authRepo
    @Environment(\.dismiss) private var dismiss
    let grade: SkillLevel

    @State private var quiz: PathRegradeQuiz?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let quiz {
                PathQuizView(
                    title: "Regrade quiz",
                    session: PathQuizSession(questions: quiz.questions),
                    onPassed: {
                        guard let uid = authRepo.currentUser?.uid else { return }
                        await pathRepo.promoteGrade(from: grade, for: uid)
                    },
                    onFinished: { dismiss() }
                )
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Colors.bg)
            } else {
                VStack {
                    Text("This grade's regrade quiz isn't available right now.")
                        .font(Theme.Fonts.body(15))
                        .multilineTextAlignment(.center)
                    Button("Back") { dismiss() }.padding(.top, 16)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.Colors.bg)
            }
        }
        .task {
            quiz = await pathRepo.fetchRegradeQuiz(for: grade)
            isLoading = false
        }
    }
}

#Preview {
    NavigationStack {
        PathRegradeQuizView(grade: .junior)
    }
    .environment(PathRepository.preview())
    .environment(AuthRepository(isPreview: true, signedIn: true))
}
```

- [ ] **Step 2: Add the "ready to regrade" terminal state to `PathWheelView`**

In `SwiftUp/Features/Path/PathWheelView.swift`, replace:

```swift
    var body: some View {
        Group {
            if pathRepo.isLoading && pathRepo.tracks.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Colors.bg)
            } else if isAtTopGrade {
                topGradeContent
            } else {
                wheelContent
            }
        }
```

with:

```swift
    var body: some View {
        Group {
            if pathRepo.isLoading && pathRepo.tracks.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Colors.bg)
            } else if isAtTopGrade {
                topGradeContent
            } else if isReadyToRegrade {
                readyToRegradeContent
            } else {
                wheelContent
            }
        }
```

Replace:

```swift
    private var currentGradeTracks: [PathTrack] { pathRepo.tracks(for: pathRepo.grade) }
    private var closedCount: Int { currentGradeTracks.filter(pathRepo.isTrackClosed).count }
    private var isAtTopGrade: Bool {
        pathRepo.grade == .distinguished && !currentGradeTracks.isEmpty && currentGradeTracks.allSatisfy(pathRepo.isTrackClosed)
    }
```

with:

```swift
    private var currentGradeTracks: [PathTrack] { pathRepo.tracks(for: pathRepo.grade) }
    private var closedCount: Int { currentGradeTracks.filter(pathRepo.isTrackClosed).count }
    private var allCurrentGradeTracksClosed: Bool {
        !currentGradeTracks.isEmpty && currentGradeTracks.allSatisfy(pathRepo.isTrackClosed)
    }
    private var isAtTopGrade: Bool {
        pathRepo.grade == .distinguished && allCurrentGradeTracksClosed
    }
    private var isReadyToRegrade: Bool {
        pathRepo.grade != .distinguished && allCurrentGradeTracksClosed
    }
```

Replace:

```swift
    private var totalTracksEverywhere: Int { pathRepo.tracks.count }

    private func gradeSeal(size: CGFloat) -> some View {
```

with:

```swift
    private var totalTracksEverywhere: Int { pathRepo.tracks.count }

    // MARK: - Ready-to-regrade state (all of the current grade's tracks are closed, but this
    // isn't the top grade — the regrade quiz promotes to `pathRepo.grade.next`)

    private var readyToRegradeContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Rectangle().fill(Theme.Colors.text).frame(height: 3)
                HStack {
                    EyebrowLabel(pathRepo.grade.rawValue)
                    Spacer()
                }
                .padding(.vertical, 7)
                Rectangle().fill(Theme.Colors.text).frame(height: 1)

                Text("Ready to\nregrade.").font(Theme.Fonts.heading(34)).padding(.top, 22)
                Text("All \(currentGradeTracks.count) \(pathRepo.grade.rawValue) tracks are closed. Pass the regrade quiz to become \(pathRepo.grade.next?.rawValue ?? "—").")
                    .font(Theme.Fonts.body(15))
                    .foregroundStyle(Theme.Colors.neutral800)
                    .padding(.top, 14)

                NavigationLink {
                    PathRegradeQuizView(grade: pathRepo.grade)
                } label: {
                    Text("Start the regrade quiz")
                        .font(Theme.Fonts.heading(17))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .background(Theme.Colors.accent)
                .foregroundStyle(Theme.Colors.bg)
                .padding(.top, 26)

                Spacer(minLength: 20)
            }
            .padding(24)
        }
    }

    private func gradeSeal(size: CGFloat) -> some View {
```

- [ ] **Step 3: Full build check**

Run: `xcodegen generate && xcodebuild build -scheme SwiftUp -destination 'generic/platform=iOS Simulator'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Run the full test suite**

Run: `xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6'`
Expected: BUILD SUCCEEDED, all tests pass.

- [ ] **Step 5: Manual verification in the simulator**

No iOS Simulator UI automation tool is available — build and run manually, then check (this may require temporarily marking stages complete via Firestore console/a test account, since closing every track in a grade through the real UI is a long path):
1. Once every track in the current grade is closed, `PathWheelView` shows "Ready to regrade" instead of the normal wheel or the Distinguished terminal state.
2. Tapping "Start the regrade quiz" opens a 10-question quiz.
3. Passing it promotes the grade — back on `PathWheelView`, the header now reads the new grade's name and shows that grade's wheel (or, if newly promoted into Distinguished with no Distinguished tracks closed yet, the normal Distinguished wheel, not its terminal state).
4. Failing it shows "Try again" with no promotion and no re-navigation.
5. At Distinguished with all tracks closed, the existing top-grade terminal state still shows (not the regrade screen) — `isAtTopGrade` is checked before `isReadyToRegrade` in the `body`.

Report any mismatch before proceeding.

- [ ] **Step 6: Commit**

```bash
git add SwiftUp/Features/Path/PathRegradeQuizView.swift SwiftUp/Features/Path/PathWheelView.swift
git commit -m "Add PathRegradeQuizView and PathWheelView's ready-to-regrade state"
```
