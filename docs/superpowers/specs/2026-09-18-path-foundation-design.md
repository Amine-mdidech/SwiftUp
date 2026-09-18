# Path — Foundation (Sub-project A) — Design

Source design: Claude Design project "SwiftUP" (`SwiftUp Daily Quiz.dc.html`), turns `t13`/`13c` ("Four grades"), `t14`/`14a`/`14b` ("The path — node trail and xp economy"), `t15`/`15a` ("Distinguished engineer — the path, finished").

## 0. Context and phasing

The user wants the Ranks tab replaced by a "Path" tab: a class-and-quiz progression system where users climb four grades (Junior → Intermediate → Senior → Distinguished Engineer) by closing "tracks" (chapters), each built from "stages" (a stage is class-flashcard slides + an 80%-to-pass quiz), gated by spending XP to start each one. Finishing all tracks in a grade unlocks a general "regrade" quiz; passing it promotes the user's grade. Actual slide/quiz content is explicitly deferred ("we will revisit the actual quiz / class content later") — this pass builds the structure only.

Given the size, this is split into three sub-projects. **This spec covers only Sub-project A (Foundation)**: the data model, Firestore schema, the XP lifetime/spendable split, extending `SkillLevel` to four grades, and removing today's silent auto-promotion. No new screens, no tab bar change, no spending, no leaderboard removal — those are Sub-projects B (navigation screens) and C (the actual gameplay loop, tab swap, leaderboard removal), confirmed as separate follow-up passes.

Confirmed with the user:
- XP spent on a stage comes out of the same XP a user already earns everywhere else — but see §3: this cannot mean directly decrementing `totalXP`, since that field drives the existing Level ladder, which must never go down. The resolution (approved as part of this design) is a lifetime/spendable split.
- Grade promotion becomes the same `SkillLevel` field already used for daily-quiz/interview-prep difficulty. Today's silent bank-exhaustion auto-promotion is removed; Path's regrade (Sub-project C) becomes the only promotion path.
- The leaderboard is dropped entirely (removal itself is Sub-project C's job, since it's a UI-facing change tied to the tab bar swap).

## 1. `SkillLevel` — four grades

`SwiftUp/Models/SkillLevel.swift`:

```swift
import Foundation

enum SkillLevel: String, CaseIterable, Identifiable, Codable {
    case junior = "Junior", mid = "Mid", senior = "Senior", distinguished = "Distinguished"
    var id: String { rawValue }

    var blurb: String {
        switch self {
        case .junior: "Shipping with SwiftUI, still meeting the SDK. Under two years."
        case .mid: "Comfortable in UIKit and SwiftUI, reaching for concurrency and architecture. Two to five years."
        case .senior: "Leading work, designing systems, interviewing others. Five years and up."
        case .distinguished: "Platform strategy, cross-team architecture, technical direction."
        }
    }

    /// The next grade Path's regrade quiz promotes to (Sub-project C). `nil` at the ceiling —
    /// matches design turn 15's "no grade above this one."
    var next: SkillLevel? {
        switch self {
        case .junior: .mid
        case .mid: .senior
        case .senior: .distinguished
        case .distinguished: nil
        }
    }

    /// Grades the onboarding assessment offers. Nobody starts at Distinguished — it's only
    /// reachable by climbing every track in every earlier grade.
    static let onboardingChoices: [SkillLevel] = [.junior, .mid, .senior]
}
```

Two call sites depend on `SkillLevel` being exhaustively 3 cases and must be updated:

**`SwiftUp/Features/Onboarding/SkillAssessmentView.swift`** — replace both `SkillLevel.allCases` references (the `ForEach` and the `showBottomRule: level == SkillLevel.allCases.last` comparison) with `SkillLevel.onboardingChoices`.

**`SwiftUp/Models/DailyQuizDocument.swift`** — `questions(for:)`'s switch gains the new case, routed to the existing Senior bank (no Distinguished-specific daily-quiz content exists yet, and none is being authored in this phase):

```swift
func questions(for level: SkillLevel) -> [Question] {
    switch level {
    case .junior: junior
    case .mid: mid
    case .senior, .distinguished: senior
    }
}
```

Interview prep does **not** need a change: `InterviewBankView`/`InterviewRepository` filter by a UI-level `String` ("All"/"Junior"/"Mid"/"Senior"), not by the `SkillLevel` enum — that filter is independent of the user's stored grade.

## 2. Remove today's silent auto-promotion

Delete `SwiftUp/Data/QuestionSelector.swift` and `SwiftUpTests/QuestionSelectorTests.swift` entirely.

In `SwiftUp/Data/QuestionRepository.swift`'s `load(for uid:)`, remove the `answered` parsing block and the promotion-check block, and delete the now-unused `fetchBank(level:)` method. The method becomes:

```swift
func load(for uid: String) async {
    isLoading = true
    defer { isLoading = false }

    let userDoc = Firestore.firestore().collection("users").document(uid)

    var storedLevel = SkillLevel.junior
    var override: SkillLevel?

    do {
        let snapshot = try await userDoc.getDocument()
        if let raw = snapshot.get("skillLevel") as? String, let level = SkillLevel(rawValue: raw) {
            storedLevel = level
        }
        if let raw = snapshot.get("levelOverride") as? String, let level = SkillLevel(rawValue: raw) {
            override = level
        }
    } catch {
        // No user doc data available (offline, first launch) — proceed with defaults.
    }

    levelOverride = override
    let effectiveLevel = override ?? storedLevel

    guard let daily = try? await fetchDailyQuiz() else {
        todayQuestions = Self.loadBundledFallback()
        editionNumber = nil
        return
    }

    todayQuestions = daily.questions(for: effectiveLevel)
    editionNumber = daily.edition
    self.effectiveLevel = effectiveLevel
}
```

(`effectiveLevel` becomes `let` — nothing mutates it anymore. `storedLevel` stays `var` only because it's still assigned once from the snapshot read above.)

## 3. XP: lifetime vs. spendable

`ProfileRepository`'s `recordCompletion` currently writes a single `totalXP` that drives the existing 12-level ladder (`LevelCalculator`) via `UserProfile.level`/`xpForCurrentLevel`/`xpForNextLevel`. If Path spending decremented `totalXP` directly, a user's Level number could go backwards after spending on a stage — a real regression the existing ladder code doesn't expect and the user never asked for ("shared XP" means one coherent ledger, not "Level can drop").

The resolution: `totalXP` keeps its current meaning exactly (lifetime earned, monotonic, drives the Level ladder — untouched by spending). A new field, `xpBalance`, is the spendable currency: every earn event credits both `totalXP` and `xpBalance` by the same amount; only Path spending (Sub-project C) debits `xpBalance`. This is still "the same shared XP" in the sense the user asked for — one ledger, spending reduces what you have left to spend — it just doesn't let spending move the unrelated Level number.

**Backfill:** an existing user has `totalXP` but no `xpBalance` field yet. The first time `xpBalance` is read and found absent, it's treated as equal to the user's `totalXP` at that moment (they haven't spent anything yet, so their full lifetime total is still spendable) — same backfill-on-first-touch pattern `AuthRepository.ensureUserDocument` already uses for `displayName`/`email`.

### `UserProfile` (`SwiftUp/Models/UserProfile.swift`)

Add one field:

```swift
struct UserProfile: Codable {
    let name: String
    let initials: String
    let level: Int
    let levelTitle: String
    let xp: Int
    let xpBalance: Int   // NEW — spendable balance, see design doc §3
    let xpForCurrentLevel: Int
    let xpForNextLevel: Int
    let streakDays: Int
    let freezesAvailable: Int
    let freezesTotal: Int
    let answeredCount: Int
    let accuracyPercent: Int
    let memberSinceDisplay: String

    var xpToNextLevel: Int { max(0, xpForNextLevel - xp) }

    var levelProgressFraction: Double {
        let span = Double(xpForNextLevel - xpForCurrentLevel)
        guard span > 0 else { return 0 }
        return max(0, min(1, Double(xp - xpForCurrentLevel) / span))
    }
}
```

### `ProfileRepository` (`SwiftUp/Data/ProfileRepository.swift`)

`apply(snapshot:recentCompletions:)` (the plain-read path, used by `load(for:)`) reads `xpBalance` with the backfill fallback, **without writing anything** — `load(for:)` is read-only today and this phase doesn't change that:

```swift
let xpBalance = (snapshot.get("xpBalance") as? Int) ?? totalXP
```

passed through to `buildProfile(...)`'s new `xpBalance:` parameter, which just forwards it into `UserProfile(..., xpBalance: xpBalance, ...)`.

`recordCompletion(_:for:)` performs the real backfill-and-persist, alongside the existing `totalXP` update:

```swift
let previousXPBalance = (snapshot.get("xpBalance") as? Int) ?? ((snapshot.get("totalXP") as? Int) ?? 0)
let newXPBalance = previousXPBalance + session.totalXPEarned
```

added to `userUpdates`:

```swift
userUpdates["xpBalance"] = newXPBalance
```

and threaded into the local-state mirror at the end of the method (`profile = Self.buildProfile(..., xpBalance: newXPBalance, ...)`), matching how every other field there is already mirrored locally after the batch commit.

`applyBundledFallback` (used by `.preview()`) needs a value too — `SwiftUp/Resources/profile.json`'s bundled fixture gains an `"xpBalance"` field (pick a plausible number, e.g. matching or slightly below its existing `"xp"` value), decoded automatically since `UserProfile` is `Codable`.

Two more call sites need the new field, since `UserProfile` gains a non-optional member (both are exhaustive memberwise-init call sites, so the compiler catches any missed one — but implementers should know to expect these):
- `ProfileRepository.init`'s zeroed default `profile = UserProfile(...)` (line ~20 today) — pass `xpBalance: 0`, matching its existing `xp: 0`.
- `SwiftUpTests/ModelDecodingTests.swift`'s `decodesUserProfile()` test — its inline JSON literal needs an `"xpBalance"` key added (e.g. `"xpBalance": 3240`, matching its existing `"xp": 3240`) or the decode fails on a missing key.

## 4. Path data model

New file `SwiftUp/Models/PathTrack.swift`:

```swift
import Foundation

struct PathStage: Codable, Identifiable {
    enum Kind: String, Codable { case lesson, assessment }
    let id: String
    let order: Int
    let title: String
    let xpCost: Int
    let kind: Kind
}

struct PathTrack: Codable, Identifiable {
    let id: String
    let grade: SkillLevel
    let order: Int
    let title: String
    let stages: [PathStage]
}
```

## 5. Firestore schema and seed data

New collection `pathTracks/{trackId}`, one document per track, `trackId` = `"\(grade.rawValue.lowercased())-\(order, zero-padded to 2 digits)"` (e.g. `junior-01`, `distinguished-04`). Document shape matches `PathTrack`/`PathStage` directly (`grade` as the `SkillLevel` raw string, `stages` as an array of maps). Each stage's `id` = `"\(trackId)-s\(order, zero-padded to 2 digits)"` (e.g. `junior-02-s04`) — globally unique, since it's later used as the key into the user's completed-stages map (§6).

**Content is placeholder, structure is real.** All 20 tracks (5 Junior + 6 Intermediate + 5 Senior + 4 Distinguished, matching the design's per-grade counts and named topics) get real titles and a real stage count/XP shape — except no actual slide/quiz material exists yet (that's Sub-project C at the earliest, and real authored content later still). One track is hand-authored directly from the design (it's fully specified there); the other 19 are generated by a fixed formula so the placeholder nature is explicit and consistent rather than 19 invented-but-pretend-precise numbers.

**Hand-authored exception** — Junior track 2, "Object-oriented Swift" (`junior-02`), taken verbatim from design turn `14b`:

| stage | title | xpCost | kind |
|---|---|---|---|
| 1 | Classes, structs and value semantics | 45 | lesson |
| 2 | Initialisers and inheritance | 45 | lesson |
| 3 | Protocols as interfaces | 45 | lesson |
| 4 | Protocol-oriented design | 200 | lesson |
| 5 | Generics and associated types | 200 | lesson |
| 6 | Composition over inheritance | 200 | lesson |
| 7 | Error handling and typed throws | 200 | lesson |
| 8 | Track assessment | 400 | assessment |

**Formula for every other track:** 6 lesson stages + 1 closing assessment stage. Lesson stage title: `"<track title> — lesson <n> of 6"`. Assessment title: always `"Track assessment"`. XP costs scale by a per-grade multiplier (junior ×1, mid ×1.5, senior ×2, distinguished ×2.5) applied to a base lesson cost of 50 and base assessment cost of 400, rounded to the nearest 5:

| grade | lesson xpCost | assessment xpCost |
|---|---|---|
| Junior | 50 | 400 |
| Mid | 75 | 600 |
| Senior | 100 | 800 |
| Distinguished | 125 | 1000 |

**The 20 tracks** (grade, order, title — topics taken directly from the design; Distinguished's 4th topic isn't named in the source design and is invented here, flagged as such):

- Junior: 1 Swift fundamentals, 2 Object-oriented Swift *(hand-authored, see above)*, 3 Architecture basics, 4 Memory & ARC, 5 SwiftUI state
- Mid: 1 Concurrency, 2 Testing, 3 Networking, 4 Persistence, 5 Performance, 6 App lifecycle
- Senior: 1 System design, 2 Module boundaries, 3 Migration strategy, 4 Code review, 5 Mentoring
- Distinguished: 1 Platform strategy, 2 Cross-team architecture, 3 Technical direction, 4 Engineering culture *(invented — not in the source design, which only names 3 of the 4 stated topics)*

**Generation script**, `scripts/generate_path_tracks.py` — a small, declarative generator (not hand-typed JSON) that writes `scripts/path-tracks.json`:

```python
#!/usr/bin/env python3
"""Generates scripts/path-tracks.json from the table below — see design doc
docs/superpowers/specs/2026-09-18-path-foundation-design.md §5 for why this
is formula-generated placeholder content rather than hand-authored data."""
import json
from pathlib import Path

GRADES = [
    ("Junior", 1.0, ["Swift fundamentals", "Object-oriented Swift", "Architecture basics", "Memory & ARC", "SwiftUI state"]),
    ("Mid", 1.5, ["Concurrency", "Testing", "Networking", "Persistence", "Performance", "App lifecycle"]),
    ("Senior", 2.0, ["System design", "Module boundaries", "Migration strategy", "Code review", "Mentoring"]),
    ("Distinguished", 2.5, ["Platform strategy", "Cross-team architecture", "Technical direction", "Engineering culture"]),
]

# Hand-authored exception, taken verbatim from the design (junior-02).
JUNIOR_02_STAGES = [
    {"title": "Classes, structs and value semantics", "xpCost": 45, "kind": "lesson"},
    {"title": "Initialisers and inheritance", "xpCost": 45, "kind": "lesson"},
    {"title": "Protocols as interfaces", "xpCost": 45, "kind": "lesson"},
    {"title": "Protocol-oriented design", "xpCost": 200, "kind": "lesson"},
    {"title": "Generics and associated types", "xpCost": 200, "kind": "lesson"},
    {"title": "Composition over inheritance", "xpCost": 200, "kind": "lesson"},
    {"title": "Error handling and typed throws", "xpCost": 200, "kind": "lesson"},
    {"title": "Track assessment", "xpCost": 400, "kind": "assessment"},
]


def round5(n: float) -> int:
    return int(round(n / 5.0) * 5)


def build_stages(track_id: str, title: str, multiplier: float) -> list[dict]:
    if track_id == "junior-02":
        stages = JUNIOR_02_STAGES
    else:
        lesson_cost = round5(50 * multiplier)
        assessment_cost = round5(400 * multiplier)
        stages = [
            {"title": f"{title} — lesson {n} of 6", "xpCost": lesson_cost, "kind": "lesson"}
            for n in range(1, 7)
        ] + [{"title": "Track assessment", "xpCost": assessment_cost, "kind": "assessment"}]
    return [
        {"id": f"{track_id}-s{i:02d}", "order": i, "title": s["title"], "xpCost": s["xpCost"], "kind": s["kind"]}
        for i, s in enumerate(stages, start=1)
    ]


def main() -> None:
    tracks = []
    for grade, multiplier, titles in GRADES:
        grade_slug = grade.lower()
        for order, title in enumerate(titles, start=1):
            track_id = f"{grade_slug}-{order:02d}"
            tracks.append({
                "id": track_id,
                "grade": grade,
                "order": order,
                "title": title,
                "stages": build_stages(track_id, title, multiplier),
            })
    out_path = Path(__file__).resolve().parent / "path-tracks.json"
    out_path.write_text(json.dumps(tracks, indent=2) + "\n")
    print(f"Wrote {len(tracks)} tracks to {out_path}")


if __name__ == "__main__":
    main()
```

Run once at implementation time to produce the checked-in `scripts/path-tracks.json` (20 tracks, 142 stages total: 8 + 19×7 = 141... — the implementer runs the script and commits whatever it actually outputs; this spec's job is the formula, not hand-counting its output).

`scripts/seed_path_tracks.py` then loads `scripts/path-tracks.json` and writes each track to `pathTracks/{id}`, following the exact structure of `scripts/seed_questions.py` (service-account-key check, one `set()` per document keyed by `id`, safe to re-run/idempotent, same error messaging).

**Bundled fallback**, for previews and offline use, mirroring the `interview_bank.json` pattern: copy `scripts/path-tracks.json` to `SwiftUp/Resources/path_tracks.json` (checked into the app bundle) and `SwiftUpTests/Fixtures/path_tracks.json` (test fixture) — same file, three locations, same convention already established for the interview bank.

## 6. User progress

A new flat map on the user document, `completedPathStageIDs: [String: Timestamp]` — same shape and convention as the existing `answeredQuestionIDs`. A track is "closed" when every one of its stage IDs (all lesson stages plus its assessment) is a key in this map. Nothing writes to this map in this phase (completing a stage is Sub-project C) — `PathRepository` (§7) only reads it.

## 7. `PathRepository` — read-only for this phase

New file `SwiftUp/Data/PathRepository.swift`:

```swift
import Foundation
import FirebaseFirestore

@Observable
final class PathRepository {
    private(set) var tracks: [PathTrack] = []
    private(set) var completedStageIDs: Set<String> = []
    private(set) var isLoading = false

    init() {}

    static func preview(bundle: Bundle = .main) -> PathRepository {
        let repo = PathRepository()
        repo.tracks = loadBundledFallback(bundle: bundle)
        return repo
    }

    static func loadBundledFallback(bundle: Bundle = .main) -> [PathTrack] {
        decodeJSONResource([PathTrack].self, filename: "path_tracks", bundle: bundle) ?? []
    }

    /// Fetches every track (all four grades — a fixed, small collection, same "load it all at
    /// once" approach `InterviewRepository` already takes for its bank) and this user's completed
    /// stage IDs.
    func load(for uid: String) async {
        isLoading = true
        defer { isLoading = false }

        async let tracksResult = Self.fetchTracks()
        async let completedResult = Self.fetchCompletedStageIDs(uid: uid)
        let (fetchedTracks, fetchedCompleted) = await (tracksResult, completedResult)

        tracks = fetchedTracks.isEmpty ? Self.loadBundledFallback() : fetchedTracks
        completedStageIDs = fetchedCompleted
    }

    func tracks(for grade: SkillLevel) -> [PathTrack] {
        tracks.filter { $0.grade == grade }.sorted { $0.order < $1.order }
    }

    func isStageCompleted(_ stage: PathStage) -> Bool {
        completedStageIDs.contains(stage.id)
    }

    func isTrackClosed(_ track: PathTrack) -> Bool {
        !track.stages.isEmpty && track.stages.allSatisfy { isStageCompleted($0) }
    }

    /// A stage unlocks once every earlier stage (by `order`) in its own track is completed. The
    /// first stage in a track is always unlocked by this method's own logic — whether the *track*
    /// itself is reachable (e.g. "you need 3 of 5 Junior tracks closed before this one shows") is
    /// a Sub-project B/C concern, not this repository's.
    func isStageUnlocked(_ stage: PathStage, in track: PathTrack) -> Bool {
        track.stages.filter { $0.order < stage.order }.allSatisfy { isStageCompleted($0) }
    }

    private static func fetchTracks() async -> [PathTrack] {
        guard let snapshot = try? await Firestore.firestore().collection("pathTracks").getDocuments() else {
            return []
        }
        return snapshot.documents.compactMap { try? $0.data(as: PathTrack.self) }
    }

    private static func fetchCompletedStageIDs(uid: String) async -> Set<String> {
        guard let snapshot = try? await Firestore.firestore().collection("users").document(uid).getDocument(),
              let map = snapshot.get("completedPathStageIDs") as? [String: Timestamp]
        else {
            return []
        }
        return Set(map.keys)
    }
}
```

`RootView.swift` gains `@State private var pathRepository = PathRepository()` and `.environment(pathRepository)`, matching every other repository already wired there — even though no screen consumes it yet, so Sub-project B's screens have it available via `@Environment(PathRepository.self)` without another root-wiring task.

## 8. Testing

- `SkillLevel.next`/`.onboardingChoices`: a couple of direct assertions (`.distinguished.next == nil`, `.senior.next == .distinguished`, `.onboardingChoices` excludes `.distinguished`).
- `DailyQuizDocument.questions(for:)`: existing tests (if any target this directly) still pass unmodified; add one asserting `.distinguished` returns the same array as `.senior`.
- `PathTrack`/`PathStage` decode from the bundled fixture JSON (mirrors `InterviewRepository`'s bundled-fallback test): count check (20 tracks), one spot-check of `junior-02`'s hand-authored stage costs.
- `PathRepository.isTrackClosed`/`.isStageUnlocked`: pure-logic tests against hand-built `PathTrack`/`PathStage` values and a `completedStageIDs` set — no Firestore needed, same style as `ProfileRepository.buildCalendarDays`'s tests.
- `ProfileRepository`'s `xpBalance` backfill: a test asserting `apply(snapshot:...)` reads `xpBalance` from a snapshot lacking that key as equal to `totalXP` (backfill-on-read for the display path) — Firestore-touching `recordCompletion`'s own backfill-and-persist isn't independently unit-tested, same limitation already accepted for every other Firestore write in this project.
- `QuestionRepository`/`QuestionSelector`: `QuestionSelectorTests.swift` is deleted wholesale (the code it tests no longer exists), not modified.

## 9. Out of scope (explicitly deferred)

- Any new screen (Four grades, the wheel, the track ladder, stage/assessment/regrade quiz-taking) — Sub-projects B and C.
- The tab bar swap (Path replacing Ranks) and `LeaderboardView`/`LeaderboardRepository` removal — Sub-project C, since it's tied to the tab bar change.
- Spending XP, completing a stage, closing a track, the regrade quiz, and the actual `SkillLevel` promotion write — all Sub-project C.
- Real slide/quiz content for any track — explicitly deferred by the user beyond this whole three-part project.
- Track-level reachability rules (e.g., "does track 3 require track 2 closed, or just enough banked XP?") — the design's wheel shows solid spokes to "reachable" tracks and dashed to locked ones, but doesn't fully specify the gating rule; Sub-project B/C will need this decided when the wheel is actually built. `PathRepository.isStageUnlocked` only handles unlocking *within* an already-reachable track.
