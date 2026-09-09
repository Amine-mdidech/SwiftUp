# Remote Question Bank Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the daily quiz question bank from bundled JSON to Firestore, with a real per-level bank, per-user daily rotation (4 new + 1 oldest-repeat), and skill-level promotion when a level's bank is exhausted.

**Architecture:** A pure, Firebase-free `QuestionSelector` (testable via Swift Testing) implements the rotation/promotion algorithm. `QuestionRepository` becomes async and Firestore-backed, calling `QuestionSelector` with data it fetched, falling back to bundled JSON if Firestore is unreachable with nothing cached. A one-time Python seed script populates Firestore from an authored JSON file — that script and its input are dev tooling, never shipped in the app.

**Tech Stack:** SwiftUI, Swift Testing, FirebaseFirestore (already a dependency), Python 3 + `firebase-admin` (seed script only, not part of the app).

**Spec:** `docs/superpowers/specs/2026-09-09-remote-question-bank-design.md`

## Global Constraints

- Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`), never XCTest.
- `SwiftUp.xcodeproj/` is gitignored — `project.yml` is the source of truth for project configuration (no changes needed this plan; `FirebaseFirestore` is already a target dependency from sub-project 1).
- Firestore's `Codable` support (`document.data(as:)`) is part of the main `FirebaseFirestore` product as of SDK 11+ (already the pinned floor) — no new SPM package needed.
- Any Firebase-touching repository method must be safe to call from a `#Preview` — this codebase's established pattern (`AuthRepository`) is to never touch Firebase in `init`, only in explicitly-invoked async methods; previews that need real data use bundled JSON directly, never a live Firestore call.
- A repository that owns live/loaded state (not just a static bundle decode) must be held as `@State private var`, not `let`, wherever a View owns one — established from the whole-branch review finding on `AuthRepository` in `RootView`.
- `SkillLevel`'s `rawValue`s are `"Junior"`, `"Mid"`, `"Senior"` (capitalized) — this already exists in the codebase (`SkillAssessmentView.swift`); Firestore storage uses these exact strings, not lowercase, to avoid a needless translation layer. The design spec's schema sketch used lowercase as illustrative shorthand only.
- Service account keys are never committed. The seed script's key path must be gitignored before the key is ever downloaded.

---

## Task 1: `SkillLevel` model + Firestore rules for `questions`

**Files:**
- Create: `SwiftUp/Models/SkillLevel.swift`
- Modify: `SwiftUp/Features/Onboarding/SkillAssessmentView.swift:1-14` (remove the now-duplicate enum, keep everything else)
- Modify: `firestore.rules`

**Interfaces:**
- Produces: `enum SkillLevel: String, CaseIterable, Identifiable, Codable { case junior = "Junior", mid = "Mid", senior = "Senior" }` with `var blurb: String` (moved as-is) and `var next: SkillLevel?` (new) — used by Task 2's `QuestionSelector` and Task 5's `QuestionRepository`.

- [ ] **Step 1: Move `SkillLevel` into Models, add `next`**

Create `SwiftUp/Models/SkillLevel.swift`:

```swift
import Foundation

enum SkillLevel: String, CaseIterable, Identifiable, Codable {
    case junior = "Junior", mid = "Mid", senior = "Senior"
    var id: String { rawValue }

    var blurb: String {
        switch self {
        case .junior: "Shipping with SwiftUI, still meeting the SDK. Under two years."
        case .mid: "Comfortable in UIKit and SwiftUI, reaching for concurrency and architecture. Two to five years."
        case .senior: "Leading work, designing systems, interviewing others. Five years and up."
        }
    }

    /// The next level to promote to when this level's question bank is exhausted. `nil` at the ceiling (senior).
    var next: SkillLevel? {
        switch self {
        case .junior: .mid
        case .mid: .senior
        case .senior: nil
        }
    }
}
```

- [ ] **Step 2: Remove the duplicate definition from `SkillAssessmentView.swift`**

In `SwiftUp/Features/Onboarding/SkillAssessmentView.swift`, delete lines 3-14 (the `enum SkillLevel { ... }` block) — everything from `enum SkillLevel: String, CaseIterable, Identifiable {` through its closing `}`. The file's `struct SkillAssessmentView: View { ... }` and everything after is unchanged; it already references `SkillLevel` by name, which now resolves to the Models version (same target, no import needed).

- [ ] **Step 3: Verify it still builds**

Run: `cd "/Users/thorfinn/Documents/Professional & Career material/iOS Prep App" && xcodegen generate && xcodebuild -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Add the `questions` collection rule**

In `firestore.rules`, add a new `match` block as a sibling of the existing `match /users/{uid}` block (inside the same `match /databases/{database}/documents` block):

```
match /questions/{questionId} {
  allow read: if request.auth != null;
  allow write: if false;
}
```

The full file becomes:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{uid} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }
    match /questions/{questionId} {
      allow read: if request.auth != null;
      allow write: if false;
    }
  }
}
```

Writes to `questions` only ever happen via the Task 4 seed script, which uses an admin service-account key that bypasses these client rules entirely — `allow write: if false` is correct and intentional, not a placeholder.

- [ ] **Step 5: Commit**

```bash
git add SwiftUp/Models/SkillLevel.swift SwiftUp/Features/Onboarding/SkillAssessmentView.swift firestore.rules
git commit -m "$(cat <<'EOF'
Move SkillLevel to Models, add questions Firestore rule

SkillLevel now needs to be referenced from the Question model and
QuestionRepository, not just the onboarding view that originated it.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01CaptiqdMadpBz1ALN56ytu
EOF
)"
```

---

## Task 2: `QuestionSelector` (pure rotation/promotion algorithm)

**Files:**
- Modify: `SwiftUp/Models/Question.swift` (add `level` field)
- Modify: `SwiftUpTests/QuizSessionTests.swift:4-13` (the only other place in the codebase that constructs `Question(...)` directly via its memberwise init — must add the new required `level:` argument or it won't compile)
- Create: `SwiftUp/Data/QuestionSelector.swift`
- Test: `SwiftUpTests/QuestionSelectorTests.swift`
- Modify: `SwiftUp/Resources/questions.json` and `SwiftUpTests/Fixtures/questions.json` (add `"level": "Mid"` to each of the 5 existing entries, so the bundled-fallback path — used by Task 5 — still decodes)

**Interfaces:**
- Consumes: `SkillLevel` (Task 1).
- Produces (used by Task 5's `QuestionRepository`):
  - `Question.level: SkillLevel` (new stored property)
  - `enum QuestionSelector`
  - `static func shouldPromote(bank: [Question], answered: [String: Date]) -> Bool`
  - `static func pickFive(bank: [Question], answered: [String: Date], seed: String) -> [Question]`
  - `static func todaySeed(uid: String, level: SkillLevel, date: Date = Date()) -> String`

- [ ] **Step 1: Add `level` to the `Question` model**

In `SwiftUp/Models/Question.swift`, add `let level: SkillLevel` as a new stored property, inserted right after `topic` — every other property stays in its exact existing order:

```swift
struct Question: Codable, Identifiable {
    let id: String
    let topic: String
    let level: SkillLevel
    let format: QuestionFormat
    let prompt: String
    let codeSnippet: String?
    let options: [QuestionOption]
    let correctOptionID: String
    let explanation: String
    let xp: Int
}
```

This changes the synthesized memberwise initializer's parameter list (a new required `level:` argument, positioned after `topic:`) — Swift requires call sites to supply arguments in this exact declared order, so **every** existing direct call to `Question(...)` needs updating, not just new code. There is exactly one such call site in the codebase (`Question` is otherwise always produced via JSON decoding, which matches by key name and isn't affected by property order):

In `SwiftUpTests/QuizSessionTests.swift`, update `makeQuestions()` — replace:

```swift
private func makeQuestions() -> [Question] {
    (1...5).map { i in
        Question(
            id: "q\(i)", topic: "Topic", format: .multipleChoice,
            prompt: "Prompt \(i)", codeSnippet: nil,
            options: [QuestionOption(id: "A", text: "A"), QuestionOption(id: "B", text: "B")],
            correctOptionID: "A", explanation: "Because.", xp: 15
        )
    }
}
```

with:

```swift
private func makeQuestions() -> [Question] {
    (1...5).map { i in
        Question(
            id: "q\(i)", topic: "Topic", level: .junior, format: .multipleChoice,
            prompt: "Prompt \(i)", codeSnippet: nil,
            options: [QuestionOption(id: "A", text: "A"), QuestionOption(id: "B", text: "B")],
            correctOptionID: "A", explanation: "Because.", xp: 15
        )
    }
}
```

- [ ] **Step 2: Add `"level"` to the existing bundled JSON fixtures**

Both `SwiftUp/Resources/questions.json` and `SwiftUpTests/Fixtures/questions.json` currently hold the same 5 entries (`q1`-`q5`). Add `"level": "Mid"` to each of the 5 objects in both files — e.g. `q1` becomes:

```json
{
  "id": "q1", "topic": "Concurrency", "level": "Mid", "format": "multipleChoice",
  ...
```

Do this for all 5 entries (`q1` through `q5`) in both files identically (`"level": "Mid"` for all 5 — they're an arbitrary legacy fallback set, level doesn't need to vary here).

- [ ] **Step 3: Write the failing tests**

Create `SwiftUpTests/QuestionSelectorTests.swift`:

```swift
import Testing
import Foundation
@testable import SwiftUp

private func makeQuestion(_ id: String, level: SkillLevel = .junior) -> Question {
    Question(
        id: id, topic: "Test", level: level, format: .multipleChoice,
        prompt: "Prompt \(id)", codeSnippet: nil,
        options: [QuestionOption(id: "A", text: "A"), QuestionOption(id: "B", text: "B")],
        correctOptionID: "A", explanation: "Because.", xp: 15
    )
}

struct QuestionSelectorTests {
    @Test func shouldPromoteWhenEveryQuestionAnswered() {
        let bank = (1...3).map { makeQuestion("q\($0)") }
        let answered: [String: Date] = ["q1": .now, "q2": .now, "q3": .now]
        #expect(QuestionSelector.shouldPromote(bank: bank, answered: answered))
    }

    @Test func shouldNotPromoteWhenSomeUnanswered() {
        let bank = (1...3).map { makeQuestion("q\($0)") }
        let answered: [String: Date] = ["q1": .now]
        #expect(!QuestionSelector.shouldPromote(bank: bank, answered: answered))
    }

    @Test func shouldNotPromoteEmptyBank() {
        #expect(!QuestionSelector.shouldPromote(bank: [], answered: [:]))
    }

    @Test func pickFivePicksAllUnseenWhenNoneAnswered() {
        let bank = (1...10).map { makeQuestion("q\($0)") }
        let picks = QuestionSelector.pickFive(bank: bank, answered: [:], seed: "seed-a")
        #expect(picks.count == 5)
        #expect(Set(picks.map(\.id)).count == 5)
    }

    @Test func pickFiveIncludesExactlyOneOldestRepeatWhenEnoughUnseenExist() {
        let bank = (1...10).map { makeQuestion("q\($0)") }
        let now = Date()
        let answered: [String: Date] = [
            "q1": now.addingTimeInterval(-1000),
            "q2": now.addingTimeInterval(-500),
        ]
        let picks = QuestionSelector.pickFive(bank: bank, answered: answered, seed: "seed-b")
        #expect(picks.count == 5)
        let pickedIDs = Set(picks.map(\.id))
        // Exactly one of the two previously-answered questions should appear — the oldest one (q1).
        #expect(pickedIDs.contains("q1"))
        #expect(!pickedIDs.contains("q2"))
        // The other 4 are unseen.
        let unseenPicks = pickedIDs.subtracting(["q1"])
        #expect(unseenPicks.allSatisfy { !answered.keys.contains($0) })
        #expect(unseenPicks.count == 4)
    }

    @Test func pickFiveFillsFromRepeatsWhenFewerThanFourUnseen() {
        // Bank of 3, 1 unseen, 2 answered — can't get 4 new, so it should fill from repeats
        // rather than returning fewer than 5.
        let bank = (1...3).map { makeQuestion("q\($0)") }
        let now = Date()
        let answered: [String: Date] = [
            "q1": now.addingTimeInterval(-1000),
            "q2": now.addingTimeInterval(-500),
        ]
        let picks = QuestionSelector.pickFive(bank: bank, answered: answered, seed: "seed-c")
        #expect(picks.count == 3) // can't exceed bank size
        #expect(Set(picks.map(\.id)) == Set(["q1", "q2", "q3"]))
    }

    @Test func pickFiveIsDeterministicForSameSeed() {
        let bank = (1...10).map { makeQuestion("q\($0)") }
        let picksA = QuestionSelector.pickFive(bank: bank, answered: [:], seed: "same-seed")
        let picksB = QuestionSelector.pickFive(bank: bank, answered: [:], seed: "same-seed")
        #expect(picksA.map(\.id) == picksB.map(\.id))
    }

    @Test func pickFiveDiffersForDifferentSeeds() {
        let bank = (1...20).map { makeQuestion("q\($0)") }
        let picksA = QuestionSelector.pickFive(bank: bank, answered: [:], seed: "seed-x")
        let picksB = QuestionSelector.pickFive(bank: bank, answered: [:], seed: "seed-y")
        #expect(picksA.map(\.id) != picksB.map(\.id))
    }

    @Test func todaySeedIsStableForSameDayAndDiffersByUID() {
        let date = Date()
        let seedA = QuestionSelector.todaySeed(uid: "user-a", level: .junior, date: date)
        let seedB = QuestionSelector.todaySeed(uid: "user-b", level: .junior, date: date)
        #expect(seedA != seedB)
        // Same uid/level/date -> same seed, called twice.
        let seedA2 = QuestionSelector.todaySeed(uid: "user-a", level: .junior, date: date)
        #expect(seedA == seedA2)
    }

    @Test func todaySeedDiffersByLevel() {
        let date = Date()
        let juniorSeed = QuestionSelector.todaySeed(uid: "user-a", level: .junior, date: date)
        let midSeed = QuestionSelector.todaySeed(uid: "user-a", level: .mid, date: date)
        #expect(juniorSeed != midSeed)
    }
}
```

- [ ] **Step 4: Run tests to verify they fail**

Run:
```bash
cd "/Users/thorfinn/Documents/Professional & Career material/iOS Prep App"
xcodegen generate
xcodebuild test -project SwiftUp.xcodeproj -scheme SwiftUp \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SwiftUpTests/QuestionSelectorTests
```
Expected: FAIL — `QuestionSelector` doesn't exist yet (compile error; `Question`'s `level:` field and the `QuizSessionTests.swift` fix from Step 1 are already in place by this point, so that part compiles fine).

- [ ] **Step 5: Implement `QuestionSelector`**

Create `SwiftUp/Data/QuestionSelector.swift`:

```swift
import Foundation

enum QuestionSelector {
    /// True once every question in the bank has been answered — the trigger for skill-level promotion.
    static func shouldPromote(bank: [Question], answered: [String: Date]) -> Bool {
        guard !bank.isEmpty else { return false }
        return bank.allSatisfy { answered[$0.id] != nil }
    }

    /// Picks today's 5: up to 4 never-answered questions (seeded, so stable for a given seed),
    /// plus 1 repeat — the answered question with the oldest timestamp. If fewer than 4 unseen
    /// questions exist, fills the remaining slots from the answered pool (oldest first) instead
    /// of returning fewer than requested — the "4 new" target relaxes gracefully when the bank
    /// is small relative to how much the user has already answered.
    static func pickFive(bank: [Question], answered: [String: Date], seed: String) -> [Question] {
        let unseen = bank.filter { answered[$0.id] == nil }
        let seenOldestFirst = bank
            .filter { answered[$0.id] != nil }
            .sorted { answered[$0.id]! < answered[$1.id]! }

        var generator = StableSeededGenerator(seed: seed)
        let shuffledUnseen = unseen.shuffled(using: &generator)

        var picks = Array(shuffledUnseen.prefix(4))
        let remainingSlots = min(5, bank.count) - picks.count
        if remainingSlots > 0 {
            picks.append(contentsOf: seenOldestFirst.prefix(remainingSlots))
        }
        return picks
    }

    /// A seed that's stable across app launches (unlike Swift's randomized String.hashValue)
    /// for a given user/level/day, and changes at the next calendar day.
    static func todaySeed(uid: String, level: SkillLevel, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(uid)-\(level.rawValue)-\(formatter.string(from: date))"
    }
}

/// A deterministic RandomNumberGenerator seeded by a string, using FNV-1a (not Swift's
/// String.hashValue, which is randomized per-process and would silently break "same 5
/// questions all day" every time the app relaunches).
private struct StableSeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: String) {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        state = hash == 0 ? 0x9E3779B97F4A7C15 : hash
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run the same command as Step 4.
Expected: all 10 tests in `QuestionSelectorTests` PASS.

- [ ] **Step 7: Run the full suite to confirm the `level` field addition didn't break existing decoding tests**

Run: `xcodebuild test -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: all tests pass, including `ModelDecodingTests` and `RepositoryTests` (which decode `questions.json` — now with the added `level` field).

- [ ] **Step 8: Commit**

```bash
git add SwiftUp/Models/Question.swift SwiftUpTests/QuizSessionTests.swift SwiftUp/Data/QuestionSelector.swift SwiftUpTests/QuestionSelectorTests.swift SwiftUp/Resources/questions.json SwiftUpTests/Fixtures/questions.json
git commit -m "$(cat <<'EOF'
Add QuestionSelector: pure daily-rotation and promotion algorithm

Deterministic per (uid, level, day) via a stable FNV-1a-seeded
shuffle — not String.hashValue, which is randomized per process and
would break "same 5 questions all day" on every relaunch.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01CaptiqdMadpBz1ALN56ytu
EOF
)"
```

---

## Task 3: Author the seed content (36 questions)

**Files:**
- Create: `scripts/seed-questions.json`

**Interfaces:** None (static content, consumed by Task 4's seed script).

- [ ] **Step 1: Create the seed content file**

Create `scripts/seed-questions.json` with exactly this content (12 Junior, 12 Mid, 12 Senior — 36 total):

```json
[
  {"id":"jr01","topic":"Swift language","level":"Junior","format":"multipleChoice","codeSnippet":null,"prompt":"What's the key difference between `let` and `var` in Swift?","options":[{"id":"A","text":"let declares a constant; var declares a variable that can be reassigned"},{"id":"B","text":"let is for classes, var is for structs"},{"id":"C","text":"They're identical; it's a style choice"},{"id":"D","text":"var is faster at runtime"}],"correctOptionID":"A","explanation":"let binds a name to a value once; reassigning it is a compile error. var allows reassignment.","xp":15},
  {"id":"jr02","topic":"Swift language","level":"Junior","format":"trueFalse","codeSnippet":null,"prompt":"Force-unwrapping a nil Optional with `!` crashes the app at runtime.","options":[{"id":"true","text":"True"},{"id":"false","text":"False"}],"correctOptionID":"true","explanation":"Force-unwrapping nil traps immediately — there's no recoverable error, the process terminates.","xp":15},
  {"id":"jr03","topic":"Memory · ARC","level":"Junior","format":"multipleChoice","codeSnippet":null,"prompt":"What does ARC automatically manage for class instances?","options":[{"id":"A","text":"Retain counts, deallocating an instance once nothing references it"},{"id":"B","text":"Struct copying"},{"id":"C","text":"Thread scheduling"},{"id":"D","text":"View layout"}],"correctOptionID":"A","explanation":"Automatic Reference Counting tracks strong references to class instances and deallocates them once the count hits zero.","xp":15},
  {"id":"jr04","topic":"SwiftUI state","level":"Junior","format":"fillInTheBlank","codeSnippet":"struct CounterView: View {\n    @____ private var count = 0\n\n    var body: some View {\n        Button(\"Count: \\(count)\") { count += 1 }\n    }\n}","prompt":"Complete the line. This view owns and mutates its own local value.","options":[{"id":"state","text":"State"},{"id":"binding","text":"Binding"},{"id":"observable","text":"Observable"},{"id":"environment","text":"Environment"}],"correctOptionID":"state","explanation":"@State is for value-type state a view owns locally; @Binding would be for a value passed in from a parent.","xp":15},
  {"id":"jr05","topic":"Swift language","level":"Junior","format":"multipleChoice","codeSnippet":null,"prompt":"You need a collection that guarantees no duplicate elements and doesn't preserve insertion order. Which do you use?","options":[{"id":"A","text":"Array"},{"id":"B","text":"Set"},{"id":"C","text":"Dictionary"},{"id":"D","text":"Tuple"}],"correctOptionID":"B","explanation":"Set enforces uniqueness and is unordered; Array preserves order but allows duplicates.","xp":15},
  {"id":"jr06","topic":"App lifecycle","level":"Junior","format":"multipleChoice","codeSnippet":null,"prompt":"In a SwiftUI App, where does one-time setup code (like configuring a third-party SDK) typically go?","options":[{"id":"A","text":"The App struct's init()"},{"id":"B","text":"Inside every View's body"},{"id":"C","text":"AppDelegate's viewDidLoad"},{"id":"D","text":"A Preview macro"}],"correctOptionID":"A","explanation":"init() on the App struct runs once at launch, before any Scene/View is built — the standard place for app-wide setup like Firebase configuration.","xp":15},
  {"id":"jr07","topic":"Memory · ARC","level":"Junior","format":"spotTheBug","codeSnippet":"final class ImageLoader {\n    var onComplete: (() -> Void)?\n    func start() {\n        network.fetch { result in\n            self.image = result\n            self.onComplete?()\n        }\n    }\n}","prompt":"Spot the bug. Which line risks a retain cycle?","options":[{"id":"A","text":"Line 2 — the closure property declaration"},{"id":"B","text":"Line 4 — the escaping closure capturing self strongly"},{"id":"C","text":"Line 5 — assigning to self.image"}],"correctOptionID":"B","explanation":"The escaping closure passed to fetch captures self strongly by default; if ImageLoader is also retained by network, that's a cycle. [weak self] on line 4 breaks it.","xp":15},
  {"id":"jr08","topic":"Networking","level":"Junior","format":"multipleChoice","codeSnippet":null,"prompt":"What's the simplest way to make a GET request and decode JSON with URLSession in modern Swift?","options":[{"id":"A","text":"URLSession.shared.data(from:) with async/await, then JSONDecoder"},{"id":"B","text":"NSURLConnection synchronously on the main thread"},{"id":"C","text":"Directly parsing raw bytes with String(data:encoding:)"},{"id":"D","text":"CFNetwork's low-level socket API"}],"correctOptionID":"A","explanation":"URLSession's async data(from:) returns (Data, URLResponse); feeding the Data into JSONDecoder is the standard modern pattern.","xp":15},
  {"id":"jr09","topic":"Testing","level":"Junior","format":"trueFalse","codeSnippet":null,"prompt":"In Swift Testing, a test function is marked with the @Test attribute rather than needing to start with \"test\" in its name.","options":[{"id":"true","text":"True"},{"id":"false","text":"False"}],"correctOptionID":"true","explanation":"Swift Testing (unlike XCTest) uses the @Test macro to identify tests — naming conventions aren't required.","xp":15},
  {"id":"jr10","topic":"Xcode · tooling","level":"Junior","format":"multipleChoice","codeSnippet":null,"prompt":"What's a breakpoint used for?","options":[{"id":"A","text":"Pausing program execution at a specific line to inspect state"},{"id":"B","text":"Marking a line for later refactoring"},{"id":"C","text":"Splitting a file into two targets"},{"id":"D","text":"Formatting code automatically"}],"correctOptionID":"A","explanation":"A breakpoint halts execution at that line so you can inspect variables, the call stack, and step through code.","xp":15},
  {"id":"jr11","topic":"Swift language","level":"Junior","format":"multipleChoice","codeSnippet":null,"prompt":"What does conforming a type to Codable actually give you?","options":[{"id":"A","text":"Both Encodable and Decodable — the ability to convert to/from formats like JSON"},{"id":"B","text":"Automatic Equatable conformance"},{"id":"C","text":"Thread-safety guarantees"},{"id":"D","text":"A default initializer with no parameters"}],"correctOptionID":"A","explanation":"Codable is a type alias for Encodable & Decodable — it doesn't imply equality, thread-safety, or a specific initializer.","xp":15},
  {"id":"jr12","topic":"Swift language","level":"Junior","format":"multipleChoice","codeSnippet":null,"prompt":"You copy a struct instance and mutate the copy. What happens to the original?","options":[{"id":"A","text":"Nothing — structs are value types, the original is unaffected"},{"id":"B","text":"The original changes too, since both point to the same storage"},{"id":"C","text":"A runtime error is thrown"},{"id":"D","text":"It depends on whether the struct is public"}],"correctOptionID":"A","explanation":"Structs are value types — assignment copies the value, so mutating the copy never affects the original. Classes (reference types) would behave differently.","xp":15},

  {"id":"mid01","topic":"Concurrency","level":"Mid","format":"multipleChoice","codeSnippet":null,"prompt":"What problem does Swift's actor model primarily solve?","options":[{"id":"A","text":"Serializing access to mutable state to prevent data races"},{"id":"B","text":"Making network requests faster"},{"id":"C","text":"Reducing binary size"},{"id":"D","text":"Automatic memory management for structs"}],"correctOptionID":"A","explanation":"An actor guarantees only one task touches its mutable state at a time, isolating it from concurrent access without manual locks.","xp":20},
  {"id":"mid02","topic":"Architecture","level":"Mid","format":"multipleChoice","codeSnippet":null,"prompt":"In an MVVM SwiftUI app, what does the ViewModel typically own?","options":[{"id":"A","text":"Presentation state and logic, exposing data the View observes"},{"id":"B","text":"UIKit view controller lifecycle callbacks"},{"id":"C","text":"The app's Core Data stack configuration directly inside every screen"},{"id":"D","text":"SwiftUI's rendering pipeline"}],"correctOptionID":"A","explanation":"The ViewModel adapts model/domain data into view-friendly state and exposes it (often via @Observable) — the View stays a thin renderer of that state.","xp":20},
  {"id":"mid03","topic":"SwiftUI state","level":"Mid","format":"trueFalse","codeSnippet":null,"prompt":"A class marked @Observable automatically triggers SwiftUI view updates when any of its stored properties change, without needing @Published.","options":[{"id":"true","text":"True"},{"id":"false","text":"False"}],"correctOptionID":"true","explanation":"The @Observable macro (Observation framework) tracks property access directly — no @Published wrapper is needed, unlike the older ObservableObject approach.","xp":20},
  {"id":"mid04","topic":"Memory · ARC","level":"Mid","format":"multipleChoice","codeSnippet":null,"prompt":"When should you use `unowned` instead of `weak` for a closure capture?","options":[{"id":"A","text":"When the captured reference is guaranteed to outlive the closure, and you don't want Optional-unwrapping overhead"},{"id":"B","text":"Always — unowned is strictly safer than weak"},{"id":"C","text":"When the closure escapes and might outlive the object"},{"id":"D","text":"Never — unowned is deprecated"}],"correctOptionID":"A","explanation":"unowned avoids the Optional wrapper weak requires, but crashes if accessed after deallocation — only safe when the captured object's lifetime is guaranteed to exceed the closure's.","xp":20},
  {"id":"mid05","topic":"Core Data · SwiftData","level":"Mid","format":"multipleChoice","codeSnippet":null,"prompt":"In SwiftData, what does the @Model macro do to a class?","options":[{"id":"A","text":"Makes it a persistent, queryable model backed by SwiftData's storage"},{"id":"B","text":"Marks it as thread-safe automatically"},{"id":"C","text":"Converts it into a SwiftUI View"},{"id":"D","text":"Generates a Codable conformance only"}],"correctOptionID":"A","explanation":"@Model turns a plain class into a persisted, schema-managed SwiftData entity you can insert, fetch, and query via ModelContext.","xp":20},
  {"id":"mid06","topic":"Networking","level":"Mid","format":"spotTheBug","codeSnippet":"func loadUser() async throws -> User {\n    let (data, response) = try await URLSession.shared.data(from: url)\n    let user = try JSONDecoder().decode(User.self, from: data)\n    return user\n}","prompt":"Spot the bug. What's missing before decoding?","options":[{"id":"A","text":"Nothing — this is correct as written"},{"id":"B","text":"A check that response is a successful HTTP status before decoding"},{"id":"C","text":"A retry loop"},{"id":"D","text":"An explicit Task { }"}],"correctOptionID":"B","explanation":"data(from:) doesn't throw on HTTP error statuses (404, 500) — it only throws on transport failures. Without checking the response's status code, a server error page could be decoded as if it were valid JSON.","xp":20},
  {"id":"mid07","topic":"Testing","level":"Mid","format":"multipleChoice","codeSnippet":null,"prompt":"Why inject a protocol-typed dependency (e.g. a NetworkClient protocol) into a ViewModel rather than using URLSession.shared directly?","options":[{"id":"A","text":"It lets tests substitute a fake/mock implementation without hitting the real network"},{"id":"B","text":"Protocols are always faster than concrete types"},{"id":"C","text":"It's required by SwiftUI's compiler"},{"id":"D","text":"It removes the need for async/await"}],"correctOptionID":"A","explanation":"Depending on an abstraction (protocol) rather than a concrete singleton is what makes substituting a test double possible — the core enabler of unit-testable networking code.","xp":20},
  {"id":"mid08","topic":"Architecture","level":"Mid","format":"trueFalse","codeSnippet":null,"prompt":"Protocol-oriented programming in Swift means you should avoid classes and inheritance entirely.","options":[{"id":"true","text":"True"},{"id":"false","text":"False"}],"correctOptionID":"false","explanation":"POP favors composition via protocols (and protocol extensions) over class inheritance hierarchies where it fits better, but it doesn't mean classes are forbidden — they're still the right tool for reference-semantics and identity.","xp":20},
  {"id":"mid09","topic":"Swift language","level":"Mid","format":"multipleChoice","codeSnippet":null,"prompt":"What's the main benefit of a generic function over one that takes `Any`?","options":[{"id":"A","text":"Type safety is preserved at compile time — no runtime casting needed"},{"id":"B","text":"Generics always run faster than any concrete type"},{"id":"C","text":"Generics support fewer types than Any"},{"id":"D","text":"There's no difference in practice"}],"correctOptionID":"A","explanation":"A generic function's type is resolved at compile time and checked by the compiler; Any erases type information, pushing failures to runtime casts.","xp":20},
  {"id":"mid10","topic":"Error handling","level":"Mid","format":"multipleChoice","codeSnippet":null,"prompt":"When should a function's error type be a custom enum conforming to Error rather than a generic NSError?","options":[{"id":"A","text":"When callers need to distinguish and handle specific, known failure cases"},{"id":"B","text":"Custom enums are required by the compiler for all throwing functions"},{"id":"C","text":"NSError can't be thrown in Swift"},{"id":"D","text":"Only when interoperating with Objective-C"}],"correctOptionID":"A","explanation":"A domain-specific error enum lets callers switch over precise cases (e.g. .invalidCredentials vs .networkUnavailable); NSError's userInfo dictionary loses that compile-time precision.","xp":20},
  {"id":"mid11","topic":"UIKit · SwiftUI interop","level":"Mid","format":"multipleChoice","codeSnippet":null,"prompt":"What's UIViewRepresentable for?","options":[{"id":"A","text":"Wrapping a UIKit view so it can be used inside SwiftUI"},{"id":"B","text":"Converting a SwiftUI View into a UIViewController"},{"id":"C","text":"Making a UIView conform to Codable"},{"id":"D","text":"Registering a view for Instruments profiling"}],"correctOptionID":"A","explanation":"UIViewRepresentable is the bridge protocol that lets a UIKit UIView participate in a SwiftUI view hierarchy, with makeUIView/updateUIView as the sync points.","xp":20},
  {"id":"mid12","topic":"Concurrency","level":"Mid","format":"multipleChoice","codeSnippet":null,"prompt":"What happens if you try to call an async function directly from synchronous code (e.g. a plain button action), without wrapping it in a Task?","options":[{"id":"A","text":"Compile error — an async function can only be called from an async context or inside Task { }"},{"id":"B","text":"It runs synchronously, blocking the calling thread until it finishes"},{"id":"C","text":"It silently no-ops"},{"id":"D","text":"It throws a runtime exception the first time it's called"}],"correctOptionID":"A","explanation":"Swift enforces this at compile time, not runtime — calling an async function from sync code needs an async context, which Task { await ... } provides.","xp":20},

  {"id":"sr01","topic":"Concurrency","level":"Senior","format":"multipleChoice","codeSnippet":null,"prompt":"What does Sendable conformance signal about a type?","options":[{"id":"A","text":"It's safe to pass across concurrency domains (e.g. into a Task or actor) without data races"},{"id":"B","text":"It conforms to Codable"},{"id":"C","text":"It's thread-safe for UI updates specifically"},{"id":"D","text":"It has no stored properties"}],"correctOptionID":"A","explanation":"Sendable is a marker protocol the compiler uses to verify a value can cross actor/task boundaries safely — typically because it's a value type, immutable, or internally synchronized.","xp":25},
  {"id":"sr02","topic":"Performance","level":"Senior","format":"multipleChoice","codeSnippet":null,"prompt":"You suspect a SwiftUI view is re-rendering far more often than necessary. What's the right first diagnostic step?","options":[{"id":"A","text":"Profile with Instruments' SwiftUI template to see actual view body invocation counts"},{"id":"B","text":"Rewrite the whole screen in UIKit"},{"id":"C","text":"Add @MainActor to every type"},{"id":"D","text":"Assume it's fine since SwiftUI is declarative"}],"correctOptionID":"A","explanation":"Instruments' SwiftUI instrument shows exactly which views recompute and why — guessing at optimizations without profiling first risks fixing the wrong thing.","xp":25},
  {"id":"sr03","topic":"Modularization","level":"Senior","format":"trueFalse","codeSnippet":null,"prompt":"Splitting an app into multiple Swift Package Manager local packages can meaningfully improve incremental build times.","options":[{"id":"true","text":"True"},{"id":"false","text":"False"}],"correctOptionID":"true","explanation":"Well-drawn module boundaries let the build system skip recompiling packages whose source didn't change — a single monolithic target must often rebuild much more on small edits.","xp":25},
  {"id":"sr04","topic":"Memory · ARC","level":"Senior","format":"multipleChoice","codeSnippet":null,"prompt":"What's the purpose of an autorelease pool in a tight loop creating many temporary Objective-C-bridged objects?","options":[{"id":"A","text":"It drains accumulated temporary objects periodically, capping peak memory instead of letting them all pile up until the loop ends"},{"id":"B","text":"It prevents retain cycles"},{"id":"C","text":"It's required for all Swift code to compile"},{"id":"D","text":"It makes ARC synchronous instead of asynchronous"}],"correctOptionID":"A","explanation":"Autorelease pools batch-release autoreleased objects; wrapping loop iterations in an inner pool drains memory per-iteration rather than accumulating until the outer scope exits.","xp":25},
  {"id":"sr05","topic":"Testing","level":"Senior","format":"multipleChoice","codeSnippet":null,"prompt":"What's the main tradeoff of snapshot testing SwiftUI views?","options":[{"id":"A","text":"High confidence in visual regressions, but brittle to intentional design changes and platform rendering differences"},{"id":"B","text":"It replaces the need for unit tests entirely"},{"id":"C","text":"It only works with UIKit, never SwiftUI"},{"id":"D","text":"It has no downsides compared to unit tests"}],"correctOptionID":"A","explanation":"Snapshot tests catch pixel-level regressions cheaply, but every deliberate visual change requires re-recording snapshots, and results can vary subtly across OS/simulator versions.","xp":25},
  {"id":"sr06","topic":"SwiftUI performance","level":"Senior","format":"spotTheBug","codeSnippet":"struct RowList: View {\n    let items: [Item]\n    var body: some View {\n        VStack {\n            ForEach(items) { item in\n                RowView(item: item)\n            }\n        }\n    }\n}","prompt":"Spot the issue. This list is rendered inside a ScrollView and has hundreds of items.","options":[{"id":"A","text":"VStack eagerly lays out every row up front; LazyVStack would only build visible rows"},{"id":"B","text":"ForEach can't be used inside VStack"},{"id":"C","text":"Item must conform to Codable"},{"id":"D","text":"RowView needs to be a class, not a struct"}],"correctOptionID":"A","explanation":"VStack instantiates all children immediately regardless of visibility; for long scrollable lists, LazyVStack defers building rows until they're about to appear.","xp":25},
  {"id":"sr07","topic":"Security","level":"Senior","format":"multipleChoice","codeSnippet":null,"prompt":"Where should a long-lived auth token be stored on-device?","options":[{"id":"A","text":"The Keychain — encrypted, sandboxed, survives app deletion per its accessibility setting"},{"id":"B","text":"UserDefaults, since it's simplest"},{"id":"C","text":"A plain file in the app's Documents directory"},{"id":"D","text":"Hardcoded in the app binary"}],"correctOptionID":"A","explanation":"UserDefaults and plain files aren't encrypted at rest in a way suited for secrets; Keychain is specifically designed for credentials and tokens.","xp":25},
  {"id":"sr08","topic":"Core Data · SwiftData","level":"Senior","format":"multipleChoice","codeSnippet":null,"prompt":"You need to add a new required, non-optional property to an existing Core Data entity that already has production data. What's the safe approach?","options":[{"id":"A","text":"A lightweight migration with a default value, or a custom mapping model if the default isn't meaningful"},{"id":"B","text":"Just add the property — Core Data infers defaults for existing rows automatically with no configuration"},{"id":"C","text":"Delete and recreate the store on every app update"},{"id":"D","text":"Required properties can't be added after a store has data"}],"correctOptionID":"A","explanation":"A lightweight migration handles simple additive changes with an explicit default value; anything requiring real data transformation needs a custom mapping model — silently doing nothing risks a migration crash.","xp":25},
  {"id":"sr09","topic":"API design","level":"Senior","format":"trueFalse","codeSnippet":null,"prompt":"A well-designed Swift API should make illegal states unrepresentable where practical (e.g. via enums instead of multiple optional/boolean flags).","options":[{"id":"true","text":"True"},{"id":"false","text":"False"}],"correctOptionID":"true","explanation":"Modeling mutually-exclusive states as an enum with associated values (rather than several independent optionals that could combine nonsensically) moves invalid-state bugs from runtime to compile time.","xp":25},
  {"id":"sr10","topic":"Concurrency","level":"Senior","format":"multipleChoice","codeSnippet":null,"prompt":"What's a common pitfall when migrating a completion-handler-based API to async/await?","options":[{"id":"A","text":"Forgetting that a completion handler called more than once (a pre-existing bug) will crash or hang the continuation-based wrapper"},{"id":"B","text":"async/await is always slower, so migration should be avoided"},{"id":"C","text":"Completion handlers can't be wrapped at all"},{"id":"D","text":"async functions can't call throwing functions"}],"correctOptionID":"A","explanation":"withCheckedContinuation/withCheckedThrowingContinuation traps if resumed more than once — a completion handler that was accidentally called twice in the old code becomes a hard crash once wrapped, rather than a silent double-invocation.","xp":25},
  {"id":"sr11","topic":"App architecture","level":"Senior","format":"multipleChoice","codeSnippet":null,"prompt":"In a large app with multiple feature teams, what's the main argument for defining feature boundaries as separate local Swift packages rather than folders in one target?","options":[{"id":"A","text":"Enforced API boundaries — a package's internals genuinely can't be reached from outside it, unlike folder conventions which are just social agreements"},{"id":"B","text":"Packages compile to smaller binaries automatically"},{"id":"C","text":"It's required for App Store submission"},{"id":"D","text":"There's no real benefit over folders"}],"correctOptionID":"A","explanation":"Swift's access control is enforced at the module boundary — a local package genuinely can't reach into another package's internal types, whereas a folder split inside one target relies entirely on developer discipline.","xp":25},
  {"id":"sr12","topic":"Build system","level":"Senior","format":"trueFalse","codeSnippet":null,"prompt":"Whole-module optimization can change how long incremental (single-file) debug builds take, not just release build behavior.","options":[{"id":"true","text":"True"},{"id":"false","text":"False"}],"correctOptionID":"true","explanation":"Whole-module optimization changes the compiler's unit of work from per-file to the whole module, which affects incremental compilation granularity — it's not purely a release-only concern, though it's most commonly enabled for Release configurations specifically.","xp":25}
]
```

- [ ] **Step 2: Validate the JSON is well-formed and has exactly 36 entries, 12 per level**

Run:
```bash
cd "/Users/thorfinn/Documents/Professional & Career material/iOS Prep App"
python3 -c "
import json
d = json.load(open('scripts/seed-questions.json'))
assert len(d) == 36, f'expected 36, got {len(d)}'
from collections import Counter
counts = Counter(q['level'] for q in d)
assert counts == {'Junior': 12, 'Mid': 12, 'Senior': 12}, counts
ids = [q['id'] for q in d]
assert len(ids) == len(set(ids)), 'duplicate ids found'
for q in d:
    assert q['correctOptionID'] in [o['id'] for o in q['options']], f\"{q['id']}: correctOptionID not in options\"
print('OK: 36 questions, 12 per level, unique ids, all correctOptionIDs valid')
"
```
Expected: `OK: 36 questions, 12 per level, unique ids, all correctOptionIDs valid`

- [ ] **Step 3: Commit**

```bash
git add scripts/seed-questions.json
git commit -m "$(cat <<'EOF'
Author 36-question seed content for the remote question bank

12 questions per skill level (Junior/Mid/Senior), spanning the
topics already established in the app. Dev-tooling input for the
Task 4 seed script — not bundled into the app.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01CaptiqdMadpBz1ALN56ytu
EOF
)"
```

---

## Task 4: Python seed script

**Files:**
- Create: `scripts/seed_questions.py`
- Create: `scripts/README.md`
- Modify: `.gitignore`

**Interfaces:** None (standalone script, run manually once — not part of the app or its test suite).

- [ ] **Step 1: Gitignore the service account key path *before* it can ever be downloaded into the repo**

Add this line to `.gitignore` (append to the existing file, don't remove anything):

```
scripts/serviceAccountKey.json
```

- [ ] **Step 2: Write the seed script**

Create `scripts/seed_questions.py`:

```python
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
```

- [ ] **Step 3: Write the setup instructions**

Create `scripts/README.md`:

```markdown
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
```

- [ ] **Step 4: Verify the gitignore actually excludes the key path**

Run: `cd "/Users/thorfinn/Documents/Professional & Career material/iOS Prep App" && touch scripts/serviceAccountKey.json && git status --porcelain scripts/`
Expected: only `scripts/seed_questions.py`, `scripts/README.md` show as untracked (`??`) — `scripts/serviceAccountKey.json` must NOT appear in the output at all (confirming it's ignored). Then delete the placeholder: `rm scripts/serviceAccountKey.json`.

- [ ] **Step 5: Commit**

```bash
git add .gitignore scripts/seed_questions.py scripts/README.md
git commit -m "$(cat <<'EOF'
Add one-time Firestore seed script for the question bank

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01CaptiqdMadpBz1ALN56ytu
EOF
)"
```

- [ ] **Step 6: Manual step (not verifiable by the implementer) — flag to the user**

This task cannot be fully verified by an automated implementer: actually running the script requires the user to generate and place their own service account key, then run `pip install firebase-admin && python3 scripts/seed_questions.py` themselves, and confirm in the Firebase console that the `questions` collection now has 36 documents. Note this clearly in the task report — don't claim the seed actually ran against real Firestore.

---

## Task 5: `QuestionRepository` rewrite (Firestore-backed, async, with fallback)

**Files:**
- Modify: `SwiftUp/Data/QuestionRepository.swift` (full rewrite)
- Modify: `SwiftUpTests/RepositoryTests.swift:9-12` (update the one test that constructs `QuestionRepository` directly)

**Interfaces:**
- Consumes: `Question`, `SkillLevel`, `QuestionSelector` (Tasks 1-2).
- Produces (used by Tasks 6-8):
  - `@Observable final class QuestionRepository`
  - `init()` — no Firebase touch, `todayQuestions` starts empty
  - `static func preview(bundle: Bundle = .main) -> QuestionRepository` — synchronously loads the bundled fallback, safe for `#Preview`, never touches Firestore
  - `private(set) var todayQuestions: [Question]`
  - `private(set) var isLoading: Bool`
  - `func load(for uid: String) async`
  - `func saveInitialSkillLevel(_ level: SkillLevel, for uid: String) async`
  - `private(set) var levelOverride: SkillLevel?` (read after `load(for:)` has run at least once)
  - `func setLevelOverride(_ level: SkillLevel?, for uid: String) async`
  - `func recordAnswered(_ questions: [Question], for uid: String) async`

- [ ] **Step 1: Rewrite `QuestionRepository.swift`**

Replace `SwiftUp/Data/QuestionRepository.swift` entirely:

```swift
import Foundation
import FirebaseFirestore

@Observable
final class QuestionRepository {
    private(set) var todayQuestions: [Question] = []
    private(set) var isLoading = false
    private(set) var levelOverride: SkillLevel?

    init() {}

    /// Synchronously loads the bundled fallback set — safe for #Preview, never touches Firestore.
    static func preview(bundle: Bundle = .main) -> QuestionRepository {
        let repo = QuestionRepository()
        repo.todayQuestions = loadBundledFallback(bundle: bundle)
        return repo
    }

    static func loadBundledFallback(bundle: Bundle = .main) -> [Question] {
        decodeJSONResource([Question].self, filename: "questions", bundle: bundle) ?? []
    }

    /// Fetches today's five for `uid`: reads their skill level/override/answer-history from
    /// Firestore, fetches that level's bank, promotes if it's exhausted, and runs
    /// QuestionSelector. Falls back to the bundled set only if Firestore is unreachable with
    /// nothing cached locally yet.
    func load(for uid: String) async {
        isLoading = true
        defer { isLoading = false }

        let userDoc = Firestore.firestore().collection("users").document(uid)

        var storedLevel = SkillLevel.junior
        var override: SkillLevel?
        var answered: [String: Date] = [:]

        do {
            let snapshot = try await userDoc.getDocument()
            if let raw = snapshot.get("skillLevel") as? String, let level = SkillLevel(rawValue: raw) {
                storedLevel = level
            }
            if let raw = snapshot.get("levelOverride") as? String, let level = SkillLevel(rawValue: raw) {
                override = level
            }
            if let map = snapshot.get("answeredQuestionIDs") as? [String: Timestamp] {
                answered = map.mapValues { $0.dateValue() }
            }
        } catch {
            // No user doc data available (offline, first launch) — proceed with defaults;
            // the Firestore question fetch below will fall back to bundled JSON if it also fails.
        }

        levelOverride = override
        let effectiveLevel = override ?? storedLevel

        guard var bank = try? await fetchBank(level: effectiveLevel), !bank.isEmpty else {
            todayQuestions = Self.loadBundledFallback()
            return
        }

        var selectionLevel = effectiveLevel
        if QuestionSelector.shouldPromote(bank: bank, answered: answered), let next = effectiveLevel.next {
            if let nextBank = try? await fetchBank(level: next), !nextBank.isEmpty {
                bank = nextBank
                selectionLevel = next
                storedLevel = next
                try? await userDoc.updateData(["skillLevel": next.rawValue])
            }
        }

        let seed = QuestionSelector.todaySeed(uid: uid, level: selectionLevel)
        todayQuestions = QuestionSelector.pickFive(bank: bank, answered: answered, seed: seed)
    }

    private func fetchBank(level: SkillLevel) async throws -> [Question] {
        let snapshot = try await Firestore.firestore()
            .collection("questions")
            .whereField("level", isEqualTo: level.rawValue)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: Question.self) }
    }

    /// Called once, right after onboarding's skill assessment.
    func saveInitialSkillLevel(_ level: SkillLevel, for uid: String) async {
        do {
            try await Firestore.firestore().collection("users").document(uid)
                .setData(["skillLevel": level.rawValue], merge: true)
        } catch {
            // Non-blocking, matches AuthRepository's write-failure pattern — retried lazily
            // next time load(for:) runs, since it just re-reads whatever's there.
        }
    }

    /// Called from Settings when the user picks a specific difficulty, or clears back to "Adaptive".
    func setLevelOverride(_ level: SkillLevel?, for uid: String) async {
        levelOverride = level
        do {
            try await Firestore.firestore().collection("users").document(uid)
                .setData(["levelOverride": level?.rawValue as Any], merge: true)
        } catch {
            // Non-blocking.
        }
    }

    /// Records today's five as answered (seen), so they're excluded from future "unseen" picks.
    func recordAnswered(_ questions: [Question], for uid: String) async {
        guard !questions.isEmpty else { return }
        var updates: [String: Any] = [:]
        let now = Timestamp(date: Date())
        for question in questions {
            updates["answeredQuestionIDs.\(question.id)"] = now
        }
        do {
            try await Firestore.firestore().collection("users").document(uid).updateData(updates)
        } catch {
            // Non-blocking — worst case one of today's questions can be re-selected later.
        }
    }
}

func decodeJSONResource<T: Decodable>(_ type: T.Type, filename: String, bundle: Bundle) -> T? {
    guard let url = bundle.url(forResource: filename, withExtension: "json") else {
        assertionFailure("Missing bundled resource: \(filename).json")
        return nil
    }
    guard let data = try? Data(contentsOf: url) else {
        assertionFailure("Could not read bundled resource: \(filename).json")
        return nil
    }
    do {
        return try JSONDecoder().decode(T.self, from: data)
    } catch {
        assertionFailure("Failed to decode \(filename).json as \(T.self): \(error)")
        return nil
    }
}
```

(`decodeJSONResource` is moved here verbatim from the old file — it's the shared bundled-JSON decoder every repository uses; keeping it in this file matches where it already lived.)

- [ ] **Step 2: Update the existing repository test**

In `SwiftUpTests/RepositoryTests.swift`, replace:

```swift
    @Test func questionRepositoryLoadsFiveQuestions() {
        let repo = QuestionRepository(bundle: testBundle)
        #expect(repo.todayQuestions.count == 5)
    }
```

with:

```swift
    @Test func questionRepositoryBundledFallbackLoadsFiveQuestions() {
        let questions = QuestionRepository.loadBundledFallback(bundle: testBundle)
        #expect(questions.count == 5)
    }
```

- [ ] **Step 3: Run the full test suite**

Run:
```bash
cd "/Users/thorfinn/Documents/Professional & Career material/iOS Prep App"
xcodegen generate
xcodebuild test -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 17'
```
Expected: all tests pass. (This task adds no new tests of its own — `QuestionRepository`'s Firestore-touching methods aren't unit-tested, same established pattern as `AuthRepository`; its testable logic already lives in the pure `QuestionSelector` from Task 2.)

- [ ] **Step 4: Fix every `#Preview` and call site that constructed `QuestionRepository()` expecting synchronous bundle data**

Search for every use: `grep -rn "QuestionRepository()" "SwiftUp" "SwiftUpTests"`. For each `#Preview` block that calls `QuestionRepository()` and expects `todayQuestions` to already be populated (e.g. `DailyQuizEntryView`, `QuizQuestionView`, `QuizSummaryView`, `TodayFlowView` previews, and `RootView`'s environment injection), replace `QuestionRepository()` with `QuestionRepository.preview()`. Do this for every match `grep` finds — there is no placeholder here; read each file grep points at and make the substitution directly. `RootView.swift`'s non-preview `questionRepository` property (used by the real app, not a preview) is handled separately in Task 8 — don't change it in this step.

- [ ] **Step 5: Verify build succeeds after the Preview fixups**

Run: `xcodebuild -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add SwiftUp/Data/QuestionRepository.swift SwiftUpTests/RepositoryTests.swift
git commit -m "$(cat <<'EOF'
Rewrite QuestionRepository as async Firestore-backed with fallback

todayQuestions now comes from load(for:) — Firestore fetch + the
QuestionSelector rotation/promotion algorithm — falling back to the
bundled JSON only if Firestore is unreachable with nothing cached.
Every #Preview that needs real question data now uses the new
.preview() constructor instead, which never touches Firestore.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01CaptiqdMadpBz1ALN56ytu
EOF
)"
```

---

## Task 6: Persist skill level from onboarding

**Files:**
- Modify: `SwiftUp/Features/Onboarding/OnboardingFlowView.swift`

**Interfaces:**
- Consumes: `QuestionRepository.saveInitialSkillLevel(_:for:)` (Task 5), `AuthRepository.currentUser` (existing).

- [ ] **Step 1: Wire the save into `OnboardingFlowView`**

Replace `SwiftUp/Features/Onboarding/OnboardingFlowView.swift` entirely:

```swift
import SwiftUI

struct OnboardingFlowView: View {
    enum Step { case welcome, skill, topics }

    @Environment(QuestionRepository.self) private var questionRepository
    @Environment(AuthRepository.self) private var authRepository
    @State private var step: Step = .welcome
    let onComplete: () -> Void

    var body: some View {
        switch step {
        case .welcome:
            WelcomeView(onContinue: { step = .skill })
        case .skill:
            SkillAssessmentView(onContinue: { level in
                if let uid = authRepository.currentUser?.uid {
                    Task { await questionRepository.saveInitialSkillLevel(level, for: uid) }
                }
                step = .topics
            })
        case .topics:
            TopicInterestsView(onFinish: onComplete)
        }
    }
}

#Preview {
    OnboardingFlowView(onComplete: {})
        .environment(QuestionRepository.preview())
        .environment(AuthRepository(isPreview: true, signedIn: true))
}
```

- [ ] **Step 2: Verify build succeeds**

Run: `xcodebuild -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add SwiftUp/Features/Onboarding/OnboardingFlowView.swift
git commit -m "$(cat <<'EOF'
Persist the chosen skill level from onboarding to Firestore

Previously discarded entirely (onContinue: { _ in ... }) — now saved
via QuestionRepository so daily question selection can use it.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01CaptiqdMadpBz1ALN56ytu
EOF
)"
```

---

## Task 7: Wire Settings' difficulty picker to `levelOverride`

**Files:**
- Modify: `SwiftUp/Features/Settings/SettingsView.swift`

**Interfaces:**
- Consumes: `QuestionRepository.levelOverride`, `QuestionRepository.setLevelOverride(_:for:)` (Task 5).

- [ ] **Step 1: Add the environment property and initialize `difficulty` from the real value**

In `SwiftUp/Features/Settings/SettingsView.swift`, replace:

```swift
struct SettingsView: View {
    @State private var difficulty = "Adaptive"
    @State private var cacheOffline = true
    @State private var showOnLeaderboards = true
    @State private var shareStats = false
    @Environment(AuthRepository.self) private var authRepository
```

with:

```swift
struct SettingsView: View {
    @State private var difficulty = "Adaptive"
    @State private var cacheOffline = true
    @State private var showOnLeaderboards = true
    @State private var shareStats = false
    @Environment(AuthRepository.self) private var authRepository
    @Environment(QuestionRepository.self) private var questionRepository
```

- [ ] **Step 2: Make the picker read and write the real override**

Replace:

```swift
                EyebrowLabel("Difficulty").padding(.top, 22)
                SegmentedPicker(options: ["Adaptive", "Junior", "Mid", "Senior"], selection: $difficulty)
                    .padding(.top, 10)
                Text("Adaptive weights your next five toward topics under 60%.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.Colors.neutral700)
                    .padding(.top, 8)
```

with:

```swift
                EyebrowLabel("Difficulty").padding(.top, 22)
                SegmentedPicker(
                    options: ["Adaptive", "Junior", "Mid", "Senior"],
                    selection: Binding(
                        get: { difficulty },
                        set: { newValue in
                            difficulty = newValue
                            guard let uid = authRepository.currentUser?.uid else { return }
                            let level = SkillLevel(rawValue: newValue)
                            Task { await questionRepository.setLevelOverride(level, for: uid) }
                        }
                    )
                )
                    .padding(.top, 10)
                Text("Adaptive uses the level you set at onboarding. Junior/Mid/Senior overrides it for tomorrow's five.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.Colors.neutral700)
                    .padding(.top, 8)
```

(`SkillLevel(rawValue: "Adaptive")` is `nil` — matching `setLevelOverride(nil, ...)`'s "use the stored skillLevel" meaning exactly, since `SkillLevel`'s cases are only `"Junior"`/`"Mid"`/`"Senior"`.)

- [ ] **Step 3: Initialize `difficulty` from the repository's actual current override on appear**

Add an `.onAppear` to the outer `ScrollView` — find:

```swift
        .background(Theme.Colors.bg)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Notifications") { NotificationSettingsView() }
            }
        }
    }
}
```

and change it to:

```swift
        .background(Theme.Colors.bg)
        .onAppear {
            difficulty = questionRepository.levelOverride?.rawValue ?? "Adaptive"
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Notifications") { NotificationSettingsView() }
            }
        }
    }
}
```

- [ ] **Step 4: Update the `#Preview`**

Replace:

```swift
#Preview {
    NavigationStack { SettingsView() }
        .environment(AuthRepository(isPreview: true, signedIn: true))
}
```

with:

```swift
#Preview {
    NavigationStack { SettingsView() }
        .environment(AuthRepository(isPreview: true, signedIn: true))
        .environment(QuestionRepository.preview())
}
```

- [ ] **Step 5: Verify build succeeds**

Run: `xcodebuild -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add SwiftUp/Features/Settings/SettingsView.swift
git commit -m "$(cat <<'EOF'
Wire Settings' difficulty picker to a real Firestore levelOverride

Previously a visual-only mock (local @State, no effect). Selecting
a specific level now overrides the onboarding-derived skillLevel for
question selection; "Adaptive" clears the override.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01CaptiqdMadpBz1ALN56ytu
EOF
)"
```

---

## Task 8: Load questions on launch + record answers on completion

**Files:**
- Modify: `SwiftUp/App/RootView.swift`
- Modify: `SwiftUp/Features/DailyQuiz/TodayFlowView.swift`

**Interfaces:**
- Consumes: `QuestionRepository.load(for:)`, `.recordAnswered(_:for:)`, `.isLoading` (Task 5); `AuthRepository.currentUser` (existing).

- [ ] **Step 1: Hold `questionRepository` as `@State`, not `let`, in `RootView`**

In `SwiftUp/App/RootView.swift`, replace:

```swift
    private let questionRepository = QuestionRepository()
```

with:

```swift
    @State private var questionRepository = QuestionRepository()
```

(Same reasoning as `authRepository` in this file: `QuestionRepository` now owns loaded/mutable state across its lifetime, not just a static bundle decode — matches this codebase's established `@State`-for-stateful-repositories convention. The other three repositories in this file stay `let`, unchanged.)

- [ ] **Step 2: Trigger the load and gate on it in `TodayFlowView`, record answers on completion**

Replace `SwiftUp/Features/DailyQuiz/TodayFlowView.swift` entirely:

```swift
import SwiftUI

struct TodayFlowView: View {
    enum Stage { case entry, question, summary }

    @Environment(QuestionRepository.self) private var questionRepo
    @Environment(AuthRepository.self) private var authRepo
    @State private var stage: Stage = .entry
    @State private var session: QuizSession?

    var body: some View {
        NavigationStack {
            Group {
                if questionRepo.isLoading && questionRepo.todayQuestions.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.Colors.bg)
                } else {
                    switch stage {
                    case .entry:
                        DailyQuizEntryView(onBegin: startQuiz)
                    case .question:
                        if let session {
                            QuizQuestionView(session: session, onAdvance: advance)
                        }
                    case .summary:
                        if let session {
                            QuizSummaryView(session: session, onDone: finish)
                        }
                    }
                }
            }
        }
        .task {
            guard let uid = authRepo.currentUser?.uid else { return }
            await questionRepo.load(for: uid)
        }
    }

    private func startQuiz() {
        session = QuizSession(questions: questionRepo.todayQuestions)
        stage = .question
    }

    private func advance() {
        session?.advance()
        if session?.isFinished == true {
            stage = .summary
        }
    }

    private func finish() {
        if let session, let uid = authRepo.currentUser?.uid {
            Task { await questionRepo.recordAnswered(session.questions, for: uid) }
        }
        session = nil
        stage = .entry
    }
}

#Preview {
    TodayFlowView()
        .environment(ProfileRepository())
        .environment(QuestionRepository.preview())
        .environment(AuthRepository(isPreview: true, signedIn: true))
}
```

- [ ] **Step 3: Verify build succeeds**

Run: `xcodebuild -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Run the full test suite**

Run: `xcodebuild test -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: all tests pass.

- [ ] **Step 5: Manual end-to-end verification**

This requires the Task 4 seed script to have actually been run against real Firestore first (a manual prerequisite — see Task 4 Step 6). With that done:
1. Build and run the app in Simulator, signed in as a fresh test user.
2. Complete onboarding, picking a skill level (e.g. Mid) — confirm in the Firebase console that `users/{uid}.skillLevel` is set to `"Mid"`.
3. Confirm the Today tab shows 5 real questions from the seeded Mid-level bank (not the old bundled 5).
4. Complete the quiz. Confirm in the console that `users/{uid}.answeredQuestionIDs` now has 5 entries with timestamps.
5. Force-quit and relaunch. Confirm the day's five stayed the same (same seed, same day).
6. In Settings, switch Difficulty to "Senior". Confirm `users/{uid}.levelOverride` is set to `"Senior"` in the console, and that a subsequent load pulls from the Senior bank.

- [ ] **Step 6: Commit**

```bash
git add SwiftUp/App/RootView.swift SwiftUp/Features/DailyQuiz/TodayFlowView.swift
git commit -m "$(cat <<'EOF'
Load today's questions from Firestore, record answers on completion

TodayFlowView now triggers QuestionRepository.load(for:) on appear
and shows a loading state until it resolves; finishing a quiz session
records the 5 questions as answered so they're excluded from future
"unseen" picks.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01CaptiqdMadpBz1ALN56ytu
EOF
)"
```
