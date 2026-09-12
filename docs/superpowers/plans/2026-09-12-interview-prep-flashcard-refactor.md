# Interview Prep Flashcard Session Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Interview Prep tab's flat category → article flow with a flashcard session (flip a question, self-rate Missed/Shaky/Nailed, see a session summary, review the weak cards), backed by real per-user Firestore state for both review scheduling and bookmarking.

**Architecture:** `InterviewQuestion` drops its static `bookmarked` field in favor of a real per-user toggle. A new ephemeral `FlashcardSession` object (not a repository — created per session, discarded after) drives a fixed 10-card deck through `FlashcardSessionView`'s flip UI, then hands off to `SessionSummaryView`. `InterviewRepository` gains the Firestore-backed pieces: `bookmarkedIDs`/`reviewState` (loaded per user), `recordSession`/`toggleBookmark` (batched writes, same non-blocking pattern as `ProfileRepository.recordCompletion`), and pure helpers (`dueDate(for:from:)`, `sessionDeck(in:level:deckSize:)`) that carry their own unit tests. `InterviewQuestionDetailView` becomes the review-queue screen, reached only from the session summary.

**Tech Stack:** Swift 6 / SwiftUI, Firebase Firestore (`FirebaseFirestore` SDK, already a dependency), Swift Testing (`import Testing`, `@Test`, `#expect`).

**Spec:** `docs/superpowers/specs/2026-09-12-interview-prep-flashcard-refactor-design.md`

## Global Constraints

- Firestore schema: `users/{uid}/flashcardReviews/{questionId} = {rating: "missed"|"shaky"|"nailed", dueDate: "yyyy-MM-dd", lastReviewedAt: Timestamp, reviewCount: Int}` and `users/{uid}/bookmarks/{questionId} = {bookmarked: true}` (spec §2).
- Scheduling: Nailed → due in 4 days. Shaky / Missed → due tomorrow (spec §2/§4).
- `bookmarks` docs are **deleted** on un-bookmark, never written `false` (spec §2).
- Session deck is always the **first 10 questions** (content order, no shuffle) from `category.questions(for: level)`, or fewer if the category has less (spec §7).
- `InterviewQuestion.bookmarked` is removed entirely — bookmarking is 100% per-user real-time state now (spec §3/§6).
- Explicitly out of scope this pass: a cross-category "due today" queue, wiring the search field, any XP/achievement hook for flashcard sessions (spec §1).
- `SwiftUp.xcodeproj` is XcodeGen-generated (`project.yml`) and gitignored — never hand-edited. Any task that adds or removes a file under `SwiftUp/` or `SwiftUpTests/` must run `xcodegen generate` before building. `SwiftUp` compiles as **one module**, so every task must leave the whole target (and `SwiftUpTests`, which does `@testable import SwiftUp`) compiling — no task may reference a symbol another, later task hasn't created yet.
- Date-string convention: `DailyEdition.todayKey(for:timeZone:)` (`SwiftUp/Data/DailyEdition.swift`) is the shared `yyyy-MM-dd` formatter — reuse it, don't hand-roll another `DateFormatter`.
- `uid` access pattern in views: `@Environment(AuthRepository.self) private var authRepo`, then `authRepo.currentUser?.uid`, guarded with `if let` — matches `TodayFlowView`, `ProfileHomeView`, `LeaderboardView`, `SettingsView`.

---

## Task 1: Real per-user bookmarking — model cutover, repository, view, rules

Removes `InterviewQuestion.bookmarked` (static content data with no real per-user meaning) and replaces the bookmark star with a live per-user Firestore toggle. This is pulled to the front of the plan, ahead of the flashcard-session work, so no later task has to thread a doomed-to-be-removed field through new code.

**Files:**
- Modify: `SwiftUp/Models/InterviewQuestion.swift`
- Modify: `SwiftUp/Resources/interview_bank.json`, `SwiftUpTests/Fixtures/interview_bank.json`, `scripts/interview-bank.json`
- Modify: `SwiftUp/Data/InterviewRepository.swift`
- Modify: `SwiftUp/Features/InterviewPrep/InterviewQuestionDetailView.swift`
- Modify: `firestore.rules`
- Modify: `SwiftUpTests/RepositoryTests.swift`

**Interfaces:**
- Produces: `InterviewRepository.bookmarkedIDs: Set<String>`, `InterviewRepository.loadUserState(for uid: String) async` (bookmarks only for now — Task 5 extends its body), `InterviewRepository.toggleBookmark(_ question: InterviewQuestion, for uid: String) async`, `InterviewRepository.isBookmarked(_ question: InterviewQuestion) -> Bool`.
- Note: `InterviewBankView` does not call `loadUserState` yet (that lands in Task 8) — this task's manual check confirms the write path and in-session read, not app-launch persistence.

- [ ] **Step 1: Update the interview repository test file's expectations first (nothing new to assert yet — just confirm the baseline still compiles/passes before touching content)**

Run: `xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SwiftUpTests/RepositoryTests 2>&1 | tail -40`
Expected: `** TEST SUCCEEDED **` (baseline, before any edits in this task).

- [ ] **Step 2: Remove `bookmarked` from `InterviewQuestion`**

Edit `SwiftUp/Models/InterviewQuestion.swift` to:

```swift
import Foundation

struct InterviewQuestion: Codable, Identifiable {
    let id: String
    let category: String
    let difficulty: String
    let prompt: String
    let modelAnswer: String
    let talkingPoints: [String]
    let followUps: [String]
}
```

- [ ] **Step 3: Strip `"bookmarked": ...` from all three content JSON files**

In `SwiftUp/Resources/interview_bank.json`, `SwiftUpTests/Fixtures/interview_bank.json`, and `scripts/interview-bank.json`, delete every `"bookmarked": false,` / `"bookmarked": true,` line (6 occurrences per file — one per question). The three files stay byte-identical to each other in shape (minus `scripts/interview-bank.json`'s extra `order`/`slug` keys, which were already only there).

Verify no occurrences remain:
```bash
grep -c bookmarked "SwiftUp/Resources/interview_bank.json" "SwiftUpTests/Fixtures/interview_bank.json" "scripts/interview-bank.json"
```
Expected: `0` for all three.

- [ ] **Step 4: Add the bookmark pieces to `InterviewRepository`**

In `SwiftUp/Data/InterviewRepository.swift`, add a new stored property near `categories`/`isLoading`, and three new methods (placed after `position(of:)`):

```swift
    private(set) var bookmarkedIDs: Set<String> = []
```

```swift
    /// Fetches this user's real per-question state (bookmarks; flashcard review state joins this
    /// method in a later pass). Non-blocking on failure — keeps whatever state is already held
    /// rather than flashing to empty on a transient error, same shape as
    /// `ProfileRepository.load(for:)`.
    func loadUserState(for uid: String) async {
        do {
            let bookmarkDocs = try await Firestore.firestore()
                .collection("users").document(uid).collection("bookmarks").getDocuments()
            bookmarkedIDs = Set(bookmarkDocs.documents.map(\.documentID))
        } catch {
            // Non-blocking — see doc comment above.
        }
    }

    /// Creates or deletes `bookmarks/{questionId}` and updates local state immediately
    /// (optimistic — the star responds instantly, matching the rest of this screen).
    func toggleBookmark(_ question: InterviewQuestion, for uid: String) async {
        let wasBookmarked = bookmarkedIDs.contains(question.id)
        if wasBookmarked { bookmarkedIDs.remove(question.id) } else { bookmarkedIDs.insert(question.id) }
        let ref = Firestore.firestore().collection("users").document(uid).collection("bookmarks").document(question.id)
        do {
            if wasBookmarked {
                try await ref.delete()
            } else {
                try await ref.setData(["bookmarked": true])
            }
        } catch {
            // Revert the optimistic update on failure.
            if wasBookmarked { bookmarkedIDs.insert(question.id) } else { bookmarkedIDs.remove(question.id) }
        }
    }

    func isBookmarked(_ question: InterviewQuestion) -> Bool { bookmarkedIDs.contains(question.id) }
```

- [ ] **Step 5: Add a default-state test**

In `SwiftUpTests/RepositoryTests.swift`, add after `interviewRepositoryPositionReflectsLevelScopedRank`:

```swift
    @Test func interviewRepositoryStartsWithNoBookmarks() {
        let repo = InterviewRepository.preview(bundle: testBundle)
        #expect(repo.bookmarkedIDs.isEmpty)
        #expect(repo.isBookmarked(repo.questions[0]) == false)
    }
```

- [ ] **Step 6: Run the interview repository tests**

```bash
xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:SwiftUpTests/RepositoryTests 2>&1 | tail -40
```
Expected: all `interviewRepository*` tests pass, `** TEST SUCCEEDED **`. (`InterviewQuestionDetailView.swift` still references the now-removed `bookmarked` field, so a full app **build** will fail until Step 7 — that's expected and fixed next; `RepositoryTests` alone doesn't touch that file.)

- [ ] **Step 7: Wire the real bookmark toggle into `InterviewQuestionDetailView`**

Modify `SwiftUp/Features/InterviewPrep/InterviewQuestionDetailView.swift`:

```swift
import SwiftUI

struct InterviewQuestionDetailView: View {
    @Environment(InterviewRepository.self) private var repo
    @Environment(AuthRepository.self) private var authRepo
    @State var question: InterviewQuestion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("← \(question.category)").font(Theme.Fonts.body(15)).foregroundStyle(Theme.Colors.accent700)
                    Spacer()
                    Button {
                        guard let uid = authRepo.currentUser?.uid else { return }
                        Task { await repo.toggleBookmark(question, for: uid) }
                    } label: {
                        Text(repo.isBookmarked(question) ? "★ Bookmarked" : "☆ Bookmark")
                            .font(.system(size: 13)).foregroundStyle(Theme.Colors.accent700)
                    }
                }
```

Leave the rest of the file (the difficulty tag, prompt, model answer, talking points, follow-ups, and the "Mark reviewed"/"Next question" footer) unchanged for now — that footer is replaced in Task 7.

- [ ] **Step 8: Add the Firestore rules for bookmarks**

Modify `firestore.rules`, inside the existing `match /users/{uid} { ... }` block, alongside `dailyCompletions`:

```
    match /users/{uid} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
      match /dailyCompletions/{date} {
        allow read, write: if request.auth != null && request.auth.uid == uid;
      }
      match /bookmarks/{questionId} {
        allow read, write: if request.auth != null && request.auth.uid == uid;
      }
    }
```

- [ ] **Step 9: Build the full app target**

```bash
xcodebuild -scheme SwiftUp -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 10: Commit**

```bash
git add SwiftUp/Models/InterviewQuestion.swift SwiftUp/Resources/interview_bank.json \
  SwiftUpTests/Fixtures/interview_bank.json scripts/interview-bank.json \
  SwiftUp/Data/InterviewRepository.swift SwiftUp/Features/InterviewPrep/InterviewQuestionDetailView.swift \
  firestore.rules SwiftUpTests/RepositoryTests.swift
git commit -m "$(cat <<'EOF'
Wire real per-user bookmarking for interview prep questions

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013qjjTWqmcJt7Z6N6odvUkp
EOF
)"
```

---

## Task 2: `FlashcardRating`, `FlashcardReviewState`, and the due-date helper

Purely additive — new model file, new static helper on `InterviewRepository`. Nothing existing changes.

**Files:**
- Create: `SwiftUp/Models/FlashcardReviewState.swift`
- Modify: `SwiftUp/Data/InterviewRepository.swift`
- Modify: `SwiftUpTests/RepositoryTests.swift`

**Interfaces:**
- Produces: `enum FlashcardRating: String, Codable { case missed, shaky, nailed }`, `struct FlashcardReviewState: Codable { let rating: FlashcardRating; let dueDate: String; let reviewCount: Int }`, `InterviewRepository.dueDate(for: FlashcardRating, from: Date) -> String` (static).
- Consumes: `DailyEdition.todayKey(for:)` (`SwiftUp/Data/DailyEdition.swift`, unchanged).

- [ ] **Step 1: Write the failing decode test**

Add to `SwiftUpTests/RepositoryTests.swift`, after `interviewRepositoryStartsWithNoBookmarks`:

```swift
    @Test func flashcardReviewStateDecodesFromJSON() throws {
        let json = Data("""
        {"rating":"nailed","dueDate":"2026-09-16","reviewCount":2}
        """.utf8)
        let decoded = try JSONDecoder().decode(FlashcardReviewState.self, from: json)
        #expect(decoded.rating == .nailed)
        #expect(decoded.dueDate == "2026-09-16")
        #expect(decoded.reviewCount == 2)
    }

    @Test func dueDateAddsFourDaysForNailedAndOneDayOtherwise() {
        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 12
        let fixedDate = Calendar.current.date(from: components)!
        #expect(InterviewRepository.dueDate(for: .nailed, from: fixedDate) == "2026-09-16")
        #expect(InterviewRepository.dueDate(for: .shaky, from: fixedDate) == "2026-09-13")
        #expect(InterviewRepository.dueDate(for: .missed, from: fixedDate) == "2026-09-13")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:SwiftUpTests/RepositoryTests 2>&1 | tail -60
```
Expected: build error — `FlashcardReviewState`/`FlashcardRating`/`InterviewRepository.dueDate` don't exist yet.

- [ ] **Step 3: Create `FlashcardReviewState.swift`**

```swift
import Foundation

enum FlashcardRating: String, Codable {
    case missed, shaky, nailed
}

/// One user's stored review state for one interview-prep question, decoded from
/// `users/{uid}/flashcardReviews/{questionId}`. `lastReviewedAt` is written but never read back
/// into the app, so it's omitted from this decode target.
struct FlashcardReviewState: Codable {
    let rating: FlashcardRating
    let dueDate: String
    let reviewCount: Int
}
```

- [ ] **Step 4: Add the `dueDate` static helper to `InterviewRepository`**

Add inside the `InterviewRepository` class, near `position(of:)`:

```swift
    /// Nailed cards come back in 4 days; Missed/Shaky come back tomorrow. Pure and static so it's
    /// directly unit-testable without touching Firestore.
    static func dueDate(for rating: FlashcardRating, from date: Date = Date()) -> String {
        let daysUntilDue = rating == .nailed ? 4 : 1
        let due = Calendar.current.date(byAdding: .day, value: daysUntilDue, to: date) ?? date
        return DailyEdition.todayKey(for: due)
    }
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:SwiftUpTests/RepositoryTests 2>&1 | tail -40
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add SwiftUp/Models/FlashcardReviewState.swift SwiftUp/Data/InterviewRepository.swift SwiftUpTests/RepositoryTests.swift
git commit -m "$(cat <<'EOF'
Add flashcard rating model and due-date scheduling helper

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013qjjTWqmcJt7Z6N6odvUkp
EOF
)"
```

---

## Task 3: `sessionDeck` — building a fixed-size deck from content

Purely additive.

**Files:**
- Modify: `SwiftUp/Data/InterviewRepository.swift`
- Modify: `SwiftUpTests/RepositoryTests.swift`

**Interfaces:**
- Produces: `InterviewRepository.sessionDeck(in categoryName: String, level: String, deckSize: Int = 10) -> [InterviewQuestion]`.
- Consumes: `InterviewCategoryContent.questions(for:)` (`SwiftUp/Models/InterviewCategory.swift`, unchanged).

- [ ] **Step 1: Write the failing tests**

Add to `SwiftUpTests/RepositoryTests.swift`:

```swift
    @Test func sessionDeckTakesFirstNQuestionsAtLevel() {
        let repo = InterviewRepository.preview(bundle: testBundle)
        let deck = repo.sessionDeck(in: "Swift fundamentals", level: "Junior", deckSize: 1)
        #expect(deck.map(\.id) == ["sf-j1"])
    }

    @Test func sessionDeckReturnsFewerThanDeckSizeWhenCategoryHasLess() {
        let repo = InterviewRepository.preview(bundle: testBundle)
        let deck = repo.sessionDeck(in: "Swift fundamentals", level: "Junior", deckSize: 10)
        #expect(deck.count == 2)
    }

    @Test func sessionDeckReturnsEmptyForUnknownCategory() {
        let repo = InterviewRepository.preview(bundle: testBundle)
        #expect(repo.sessionDeck(in: "Nope", level: "All").isEmpty)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:SwiftUpTests/RepositoryTests 2>&1 | tail -40
```
Expected: build error — `sessionDeck` doesn't exist yet.

- [ ] **Step 3: Implement `sessionDeck`**

Add inside `InterviewRepository`, near `firstQuestion(in:level:)`:

```swift
    /// First `deckSize` questions at `level` in `categoryName`, in that level's existing content
    /// order (no shuffling — a session deck is stable and deterministic). Fewer than `deckSize` if
    /// the category has less. A category+level combo with zero questions can't be navigated into in
    /// the first place (`InterviewBankView`'s disabled-row handling), so this returning `[]` is
    /// only reachable for a bad `categoryName`.
    func sessionDeck(in categoryName: String, level: String, deckSize: Int = 10) -> [InterviewQuestion] {
        guard let category = categories.first(where: { $0.name == categoryName }) else { return [] }
        return Array(category.questions(for: level).prefix(deckSize))
    }
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:SwiftUpTests/RepositoryTests 2>&1 | tail -40
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add SwiftUp/Data/InterviewRepository.swift SwiftUpTests/RepositoryTests.swift
git commit -m "$(cat <<'EOF'
Add InterviewRepository.sessionDeck for flashcard session decks

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013qjjTWqmcJt7Z6N6odvUkp
EOF
)"
```

---

## Task 4: `FlashcardSession` — ephemeral session state machine

New file, new test file. Purely additive.

**Files:**
- Create: `SwiftUp/Data/FlashcardSession.swift`
- Create: `SwiftUpTests/FlashcardSessionTests.swift`

**Interfaces:**
- Consumes: `InterviewQuestion` (`SwiftUp/Models/InterviewQuestion.swift`, no `bookmarked` field as of Task 1), `FlashcardRating` (Task 2).
- Produces: `FlashcardSession` — `init(category: String, deck: [InterviewQuestion])`, `currentCard: InterviewQuestion?`, `isComplete: Bool`, `progress: [FlashcardRating?]`, `flip()`, `rate(_ rating: FlashcardRating)`, `skip()`, `ratings: [String: FlashcardRating]`, `nailedCount`/`shakyCount`/`missedCount: Int`, `cardsToReview: [InterviewQuestion]`.

- [ ] **Step 1: Write the failing tests**

Create `SwiftUpTests/FlashcardSessionTests.swift`:

```swift
import Testing
@testable import SwiftUp

private func makeQuestion(_ id: String) -> InterviewQuestion {
    InterviewQuestion(
        id: id, category: "Swift fundamentals", difficulty: "Junior",
        prompt: "Prompt \(id)", modelAnswer: "Answer", talkingPoints: [], followUps: []
    )
}

struct FlashcardSessionTests {
    @Test func ratingRecordsAndAdvances() {
        let session = FlashcardSession(category: "Swift fundamentals", deck: [makeQuestion("a"), makeQuestion("b")])
        #expect(session.currentCard?.id == "a")
        session.rate(.nailed)
        #expect(session.ratings["a"] == .nailed)
        #expect(session.currentCard?.id == "b")
        #expect(session.isComplete == false)
    }

    @Test func skipAdvancesWithoutRecording() {
        let session = FlashcardSession(category: "Swift fundamentals", deck: [makeQuestion("a"), makeQuestion("b")])
        session.skip()
        #expect(session.ratings["a"] == nil)
        #expect(session.currentCard?.id == "b")
    }

    @Test func isCompleteAfterLastCard() {
        let session = FlashcardSession(category: "Swift fundamentals", deck: [makeQuestion("a")])
        #expect(session.isComplete == false)
        session.rate(.shaky)
        #expect(session.isComplete)
        #expect(session.currentCard == nil)
    }

    @Test func flipSetsIsFlippedAndRatingResetsItForTheNextCard() {
        let session = FlashcardSession(category: "Swift fundamentals", deck: [makeQuestion("a"), makeQuestion("b")])
        session.flip()
        #expect(session.isFlipped)
        session.rate(.missed)
        #expect(session.isFlipped == false)
    }

    @Test func cardsToReviewOrdersMissedBeforeShakyInDeckOrder() {
        let session = FlashcardSession(
            category: "Swift fundamentals",
            deck: [makeQuestion("a"), makeQuestion("b"), makeQuestion("c"), makeQuestion("d")]
        )
        session.rate(.nailed)   // a
        session.rate(.shaky)    // b
        session.rate(.missed)   // c
        session.rate(.shaky)    // d
        #expect(session.cardsToReview.map(\.id) == ["c", "b", "d"])
        #expect(session.nailedCount == 1)
        #expect(session.shakyCount == 2)
        #expect(session.missedCount == 1)
    }

    @Test func progressReflectsRatingsInDeckOrder() {
        let session = FlashcardSession(category: "Swift fundamentals", deck: [makeQuestion("a"), makeQuestion("b")])
        session.rate(.nailed)
        #expect(session.progress == [.nailed, nil])
    }
}
```

- [ ] **Step 2: Run `xcodegen generate` so the new test file is picked up**

```bash
xcodegen generate
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:SwiftUpTests/FlashcardSessionTests 2>&1 | tail -40
```
Expected: build error — `FlashcardSession` doesn't exist yet.

- [ ] **Step 4: Create `FlashcardSession.swift`**

```swift
import Foundation

/// Ephemeral per-session state for a flashcard run through one category+level deck — created fresh
/// each time a session starts and discarded when the owning view goes away. Deliberately separate
/// from `InterviewRepository` (which owns durable content/state) so an abandoned session can't leak
/// partial state into it; ratings are only persisted once, in a batch, when the deck is exhausted.
@Observable
final class FlashcardSession {
    let category: String
    let deck: [InterviewQuestion]
    private(set) var currentIndex = 0
    private(set) var isFlipped = false
    private(set) var ratings: [String: FlashcardRating] = [:]

    init(category: String, deck: [InterviewQuestion]) {
        self.category = category
        self.deck = deck
    }

    var currentCard: InterviewQuestion? {
        deck.indices.contains(currentIndex) ? deck[currentIndex] : nil
    }

    var isComplete: Bool { currentIndex >= deck.count }

    /// One entry per deck card, in deck order — nil for a card not yet rated. Drives the front's
    /// progress ticks.
    var progress: [FlashcardRating?] {
        deck.map { ratings[$0.id] }
    }

    func flip() { isFlipped = true }

    /// Records a rating for the current card and advances. No-op past the end of the deck.
    func rate(_ rating: FlashcardRating) {
        guard let card = currentCard else { return }
        ratings[card.id] = rating
        advance()
    }

    /// Advances without recording anything — the front's "Skip".
    func skip() { advance() }

    private func advance() {
        currentIndex += 1
        isFlipped = false
    }

    var nailedCount: Int { ratings.values.filter { $0 == .nailed }.count }
    var shakyCount: Int { ratings.values.filter { $0 == .shaky }.count }
    var missedCount: Int { ratings.values.filter { $0 == .missed }.count }

    /// Cards to review now — missed before shaky, each group in the deck order they were rated in.
    var cardsToReview: [InterviewQuestion] {
        deck.filter { ratings[$0.id] == .missed } + deck.filter { ratings[$0.id] == .shaky }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:SwiftUpTests/FlashcardSessionTests 2>&1 | tail -40
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add SwiftUp/Data/FlashcardSession.swift SwiftUpTests/FlashcardSessionTests.swift project.yml 2>/dev/null
git add -A SwiftUp SwiftUpTests
git commit -m "$(cat <<'EOF'
Add FlashcardSession ephemeral session state machine

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013qjjTWqmcJt7Z6N6odvUkp
EOF
)"
```

---

## Task 5: Review-state repository additions — `reviewState`, `hasBeenReviewed`, `recordSession`

Extends the `loadUserState(for:)` method Task 1 created (its body currently fetches only bookmarks) to also fetch flashcard review state, and adds the write path. Only modifies `InterviewRepository.swift` — additive to its existing method bodies, nothing else changes.

**Files:**
- Modify: `SwiftUp/Data/InterviewRepository.swift`
- Modify: `SwiftUpTests/RepositoryTests.swift`

**Interfaces:**
- Consumes: `InterviewRepository.dueDate(for:from:)` (Task 2), `FlashcardReviewState`/`FlashcardRating` (Task 2).
- Produces: `InterviewRepository.reviewState: [String: FlashcardReviewState]`, `InterviewRepository.hasBeenReviewed(_ question: InterviewQuestion) -> Bool`, `InterviewRepository.recordSession(_ ratings: [String: FlashcardRating], for uid: String) async`.

- [ ] **Step 1: Write the failing default-state test**

Add to `SwiftUpTests/RepositoryTests.swift`:

```swift
    @Test func interviewRepositoryStartsWithNoReviewState() {
        let repo = InterviewRepository.preview(bundle: testBundle)
        #expect(repo.reviewState.isEmpty)
        #expect(repo.hasBeenReviewed(repo.questions[0]) == false)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:SwiftUpTests/RepositoryTests 2>&1 | tail -40
```
Expected: build error — `reviewState`/`hasBeenReviewed` don't exist yet.

- [ ] **Step 3: Add the `reviewState` property and `hasBeenReviewed`**

Add next to `bookmarkedIDs` in `InterviewRepository`:

```swift
    private(set) var reviewState: [String: FlashcardReviewState] = [:]
```

Add next to `isBookmarked`:

```swift
    /// Whether this question has ever been rated — what the bank screen's "N of M reviewed" means.
    func hasBeenReviewed(_ question: InterviewQuestion) -> Bool { reviewState[question.id] != nil }
```

- [ ] **Step 4: Extend `loadUserState(for:)` to also fetch review state**

Replace `loadUserState(for:)`'s body (from Task 1) with:

```swift
    func loadUserState(for uid: String) async {
        async let bookmarkDocs = Firestore.firestore()
            .collection("users").document(uid).collection("bookmarks").getDocuments()
        async let reviewDocs = Firestore.firestore()
            .collection("users").document(uid).collection("flashcardReviews").getDocuments()
        do {
            let (bookmarks, reviews) = try await (bookmarkDocs, reviewDocs)
            bookmarkedIDs = Set(bookmarks.documents.map(\.documentID))
            reviewState = Dictionary(uniqueKeysWithValues: reviews.documents.compactMap { doc in
                (try? doc.data(as: FlashcardReviewState.self)).map { (doc.documentID, $0) }
            })
        } catch {
            // Non-blocking — see doc comment above.
        }
    }
```

- [ ] **Step 5: Add `recordSession`**

Add after `toggleBookmark`:

```swift
    /// Persists a finished flashcard session's ratings in one batch, then reflects the result
    /// locally immediately (no re-fetch) — same pattern as `ProfileRepository.recordCompletion`.
    /// Also used for a single-card "Card again" re-rate (a one-entry `ratings` dictionary).
    func recordSession(_ ratings: [String: FlashcardRating], for uid: String) async {
        guard !ratings.isEmpty else { return }
        let batch = Firestore.firestore().batch()
        let userRef = Firestore.firestore().collection("users").document(uid)
        let now = Date()
        for (questionID, rating) in ratings {
            let ref = userRef.collection("flashcardReviews").document(questionID)
            batch.setData([
                "rating": rating.rawValue,
                "dueDate": Self.dueDate(for: rating, from: now),
                "lastReviewedAt": FieldValue.serverTimestamp(),
                "reviewCount": FieldValue.increment(Int64(1)),
            ], forDocument: ref, merge: true)
        }
        do {
            try await batch.commit()
            for (questionID, rating) in ratings {
                let previousCount = reviewState[questionID]?.reviewCount ?? 0
                reviewState[questionID] = FlashcardReviewState(
                    rating: rating, dueDate: Self.dueDate(for: rating, from: now), reviewCount: previousCount + 1
                )
            }
        } catch {
            // Non-blocking — a failed write is invisible to the user; worst case this session's
            // ratings are lost and the next session's batch recomputes from whatever's stored.
        }
    }
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:SwiftUpTests/RepositoryTests 2>&1 | tail -40
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Add the Firestore rule for `flashcardReviews`**

Modify `firestore.rules`, inside `match /users/{uid} { ... }`, alongside `bookmarks`:

```
      match /flashcardReviews/{questionId} {
        allow read, write: if request.auth != null && request.auth.uid == uid;
      }
```

- [ ] **Step 8: Build the full app target**

```bash
xcodebuild -scheme SwiftUp -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Commit**

```bash
git add SwiftUp/Data/InterviewRepository.swift SwiftUpTests/RepositoryTests.swift firestore.rules
git commit -m "$(cat <<'EOF'
Add flashcard review-state loading and session recording

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013qjjTWqmcJt7Z6N6odvUkp
EOF
)"
```

---

## Task 6: `FlashcardSessionView` and `SessionSummaryView` — new session flow screens

New files only. `SessionSummaryView` calls `InterviewQuestionDetailView(question:)` using its existing (post-Task-1) initializer — the queue-aware upgrade lands in Task 7. Nothing existing is modified, so this compiles standalone.

**Files:**
- Create: `SwiftUp/Features/InterviewPrep/FlashcardSessionView.swift`
- Create: `SwiftUp/Features/InterviewPrep/SessionSummaryView.swift`

**Interfaces:**
- Consumes: `InterviewRepository.sessionDeck(in:level:deckSize:)` (Task 3), `InterviewRepository.recordSession(_:for:)` (Task 5), `FlashcardSession` (Task 4), `Theme.Colors`/`Theme.Fonts` (`SwiftUp/DesignSystem/Theme.swift`), `EyebrowLabel`/`RuledRow` (`SwiftUp/DesignSystem/Atoms.swift`), `PlateNumeral` (`SwiftUp/DesignSystem/InteractiveAtoms.swift`), `InterviewQuestionDetailView(question:)` (existing synthesized init).
- Produces: `FlashcardSessionView(category: String, level: String)`, `SessionSummaryView(session: FlashcardSession)`.

- [ ] **Step 1: Create `FlashcardSessionView.swift`**

```swift
import SwiftUI

struct FlashcardSessionView: View {
    @Environment(InterviewRepository.self) private var repo
    @Environment(AuthRepository.self) private var authRepo
    @State private var session: FlashcardSession
    @State private var pushSummary = false

    init(category: String, level: String, repo: InterviewRepository) {
        _session = State(initialValue: FlashcardSession(category: category, deck: repo.sessionDeck(in: category, level: level)))
    }

    var body: some View {
        Group {
            if let card = session.currentCard {
                VStack(spacing: 0) {
                    progressTicks
                    if session.isFlipped {
                        back(for: card)
                    } else {
                        front(for: card)
                    }
                }
                .padding(24)
            }
        }
        .background(Theme.Colors.bg)
        .navigationDestination(isPresented: $pushSummary) {
            SessionSummaryView(session: session)
        }
        .onChange(of: session.isComplete) { _, isComplete in
            guard isComplete else { return }
            if let uid = authRepo.currentUser?.uid {
                Task { await repo.recordSession(session.ratings, for: uid) }
            }
            pushSummary = true
        }
    }

    private var progressTicks: some View {
        HStack(spacing: 3) {
            ForEach(Array(session.progress.enumerated()), id: \.offset) { _, rating in
                Rectangle().fill(tickColor(for: rating)).frame(height: 4)
            }
        }
    }

    private func tickColor(for rating: FlashcardRating?) -> Color {
        switch rating {
        case .missed: Theme.Colors.accent2
        case .shaky: Theme.Colors.processYellow
        case .nailed: Theme.Colors.text
        case nil: Theme.Colors.neutral300
        }
    }

    private func front(for card: InterviewQuestion) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                EyebrowLabel(card.category)
                Spacer()
                Text("Card \(session.currentIndex + 1) / \(session.deck.count)")
                    .font(.system(size: 10)).foregroundStyle(Theme.Colors.neutral700)
            }
            .padding(.top, 22)

            Spacer()
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(card.difficulty).font(.system(size: 11))
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Theme.Colors.accent100).foregroundStyle(Theme.Colors.accent800)
                    EyebrowLabel(card.category)
                }
                Text(card.prompt).font(Theme.Fonts.heading(28)).padding(.top, 22)
                Text("Answer it out loud, then flip to compare.")
                    .font(Theme.Fonts.body(14)).foregroundStyle(Theme.Colors.neutral700).padding(.top, 18)
            }
            .padding(24)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.Colors.text))
            Spacer()

            HStack(spacing: 12) {
                Button("Skip") { session.skip() }
                    .frame(minHeight: 44)
                Button {
                    session.flip()
                } label: {
                    Text("Flip the card").font(.system(size: 17))
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                }
                .background(Theme.Colors.accent).foregroundStyle(Theme.Colors.bg)
            }
        }
    }

    private func back(for card: InterviewQuestion) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                EyebrowLabel("Talking points")
                VStack(spacing: 0) {
                    ForEach(Array(card.talkingPoints.enumerated()), id: \.offset) { index, point in
                        RuledRow(showBottomRule: index == card.talkingPoints.count - 1, minHeight: 0) {
                            Text(String(format: "%02d", index + 1))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.Colors.accent700)
                            Text(point).font(Theme.Fonts.body(14))
                        }
                        .padding(.vertical, 8)
                    }
                }
                .padding(.top, 10)
            }
            .padding(20)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.Colors.text))
            .padding(.top, 22)

            EyebrowLabel("How did that go?").padding(.top, 20)
            HStack(spacing: 9) {
                ratingButton("Missed it", fill: Theme.Colors.accent2, foreground: Theme.Colors.bg) { session.rate(.missed) }
                ratingButton("Shaky", fill: Theme.Colors.processYellow, foreground: Theme.Colors.text) { session.rate(.shaky) }
                ratingButton("Nailed it", fill: Theme.Colors.text, foreground: Theme.Colors.bg) { session.rate(.nailed) }
            }
            .padding(.top, 11)
        }
    }

    private func ratingButton(_ title: String, fill: Color, foreground: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 15))
                .frame(maxWidth: .infinity).padding(.vertical, 15)
        }
        .background(fill).foregroundStyle(foreground)
    }
}

#Preview {
    let repo = InterviewRepository.preview()
    return NavigationStack {
        FlashcardSessionView(category: "Swift fundamentals", level: "Junior", repo: repo)
    }
    .environment(repo)
    .environment(AuthRepository(isPreview: true, signedIn: true))
}
```

- [ ] **Step 2: Create `SessionSummaryView.swift`**

```swift
import SwiftUI

struct SessionSummaryView: View {
    let session: FlashcardSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RuledMasthead(left: session.category, right: "\(session.deck.count) cards")

                HStack(alignment: .lastTextBaseline, spacing: 20) {
                    PlateNumeral("\(session.nailedCount)", font: Theme.Fonts.heading(76))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("nailed").font(Theme.Fonts.heading(19))
                        Text("\(session.shakyCount) shaky · \(session.missedCount) missed")
                            .font(.system(size: 13.5)).foregroundStyle(Theme.Colors.neutral700)
                    }
                }
                .padding(.top, 26)

                sessionBar.padding(.top, 20)

                if !session.cardsToReview.isEmpty {
                    EyebrowLabel("Review these \(session.cardsToReview.count)", color: Theme.Colors.accent2800)
                        .padding(.top, 30)

                    VStack(spacing: 0) {
                        ForEach(Array(session.cardsToReview.enumerated()), id: \.element.id) { index, card in
                            NavigationLink {
                                InterviewQuestionDetailView(
                                    question: card, reviewQueue: session.cardsToReview, indexInQueue: index
                                )
                            } label: {
                                RuledRow(showBottomRule: index == session.cardsToReview.count - 1, minHeight: 0) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(card.prompt).font(Theme.Fonts.heading(15))
                                        Text(session.ratings[card.id] == .missed ? "Missed" : "Shaky")
                                            .font(.system(size: 12.5)).foregroundStyle(Theme.Colors.neutral700)
                                    }
                                    Spacer()
                                    Text("→").foregroundStyle(Theme.Colors.accent700)
                                }
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 12)
                }

                HStack(spacing: 12) {
                    Button("Back to bank") {}
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.Colors.divider))
                    if let first = session.cardsToReview.first {
                        NavigationLink {
                            InterviewQuestionDetailView(question: first, reviewQueue: session.cardsToReview, indexInQueue: 0)
                        } label: {
                            Text("Review now").font(.system(size: 15.5))
                                .frame(maxWidth: .infinity).padding(.vertical, 15)
                        }
                        .background(Theme.Colors.accent).foregroundStyle(Theme.Colors.bg)
                    }
                }
                .padding(.top, 26)
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
        .navigationBarBackButtonHidden()
    }

    /// Three segments sized proportionally to their share of rated cards — `GeometryReader` sizing
    /// each `Rectangle`'s width directly (the same technique `ThinProgressBar` uses for its single
    /// fill), since `layoutPriority` does not produce flex-ratio-style proportional widths.
    private var sessionBar: some View {
        let total = session.nailedCount + session.shakyCount + session.missedCount
        return GeometryReader { geo in
            HStack(spacing: 3) {
                if total > 0 {
                    Rectangle().fill(Theme.Colors.text)
                        .frame(width: geo.size.width * Double(session.nailedCount) / Double(total))
                    Rectangle().fill(Theme.Colors.processYellow)
                        .frame(width: geo.size.width * Double(session.shakyCount) / Double(total))
                    Rectangle().fill(Theme.Colors.accent2)
                        .frame(width: geo.size.width * Double(session.missedCount) / Double(total))
                }
            }
        }
        .frame(height: 9)
    }
}

#Preview {
    let session = FlashcardSession(
        category: "Architecture patterns",
        deck: InterviewRepository.preview().sessionDeck(in: "Architecture patterns", level: "Mid")
    )
    session.rate(.nailed)
    return NavigationStack { SessionSummaryView(session: session) }
}
```

Note: this Preview's `NavigationLink`s to `InterviewQuestionDetailView(question:reviewQueue:indexInQueue:)` won't compile until Task 7 adds those parameters — that's expected; this task's build check (Step 3) targets `RepositoryTests`/`FlashcardSessionTests` only, not a full app build. The full app build comes back in Task 7's Step 6.

- [ ] **Step 3: Run `xcodegen generate` so the new files are picked up**

```bash
xcodegen generate
```

- [ ] **Step 4: Run the existing repository/session unit tests (unaffected by this task, confirms nothing broke)**

```bash
xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:SwiftUpTests/RepositoryTests -only-testing:SwiftUpTests/FlashcardSessionTests 2>&1 | tail -40
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add SwiftUp/Features/InterviewPrep/FlashcardSessionView.swift SwiftUp/Features/InterviewPrep/SessionSummaryView.swift
git add -A SwiftUp SwiftUpTests
git commit -m "$(cat <<'EOF'
Add flashcard session and session summary screens

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013qjjTWqmcJt7Z6N6odvUkp
EOF
)"
```

---

## Task 7: `InterviewQuestionDetailView` review-queue upgrade

Adds the `reviewQueue`/`indexInQueue` parameters `SessionSummaryView` (Task 6) already calls, replaces the "Mark reviewed"/"Next question" footer with "Card again"/"Next review", and adds the rating tag. This is the task that makes the full app build succeed again after Task 6.

**Files:**
- Modify: `SwiftUp/Features/InterviewPrep/InterviewQuestionDetailView.swift`

**Interfaces:**
- Consumes: `InterviewRepository.recordSession(_:for:)` (Task 5), `InterviewRepository.reviewState` (Task 5), `AuthRepository.currentUser?.uid` (already imported via Task 1's `@Environment(AuthRepository.self)`).

- [ ] **Step 1: Replace the whole file**

```swift
import SwiftUI

struct InterviewQuestionDetailView: View {
    @Environment(InterviewRepository.self) private var repo
    @Environment(AuthRepository.self) private var authRepo
    @Environment(\.dismiss) private var dismiss
    @State var question: InterviewQuestion
    var reviewQueue: [InterviewQuestion]? = nil
    var indexInQueue: Int = 0
    /// Tracks how far "Next review" has advanced past the initial `indexInQueue` — `indexInQueue`
    /// itself is a `var` parameter, not `@State`, so re-reading it after the first tap would always
    /// recompute the same "next" position instead of continuing to advance.
    @State private var currentQueueIndex: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("← \(question.category)").font(Theme.Fonts.body(15)).foregroundStyle(Theme.Colors.accent700)
                    Spacer()
                    Button {
                        guard let uid = authRepo.currentUser?.uid else { return }
                        Task { await repo.toggleBookmark(question, for: uid) }
                    } label: {
                        Text(repo.isBookmarked(question) ? "★ Bookmarked" : "☆ Bookmark")
                            .font(.system(size: 13)).foregroundStyle(Theme.Colors.accent700)
                    }
                }

                HStack(spacing: 8) {
                    if let rating = repo.reviewState[question.id]?.rating {
                        Text(rating == .missed ? "Missed" : "Shaky")
                            .font(.system(size: 11))
                            .padding(.horizontal, 10).padding(.vertical, 3)
                            .background(rating == .missed ? Theme.Colors.accent2100 : Theme.Colors.accent100)
                            .foregroundStyle(rating == .missed ? Theme.Colors.accent2800 : Theme.Colors.accent800)
                    } else {
                        Text(question.difficulty)
                            .font(.system(size: 11))
                            .padding(.horizontal, 10).padding(.vertical, 3)
                            .background(Theme.Colors.accent100).foregroundStyle(Theme.Colors.accent800)
                    }
                    if let position = repo.position(of: question) {
                        EyebrowLabel("Question \(position.index) of \(position.total)")
                    }
                }
                .padding(.top, 12)

                Text(question.prompt).font(Theme.Fonts.heading(27)).padding(.top, 14)

                EyebrowLabel("Model answer", color: Theme.Colors.accent700).padding(.top, 24)
                Text(question.modelAnswer).font(Theme.Fonts.body(15)).padding(.top, 10)

                EyebrowLabel("Talking points").padding(.top, 22)
                VStack(spacing: 0) {
                    ForEach(Array(question.talkingPoints.enumerated()), id: \.offset) { index, point in
                        RuledRow(showBottomRule: index == question.talkingPoints.count - 1, minHeight: 0) {
                            Text(String(format: "%02d", index + 1))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.Colors.accent700)
                            Text(point).font(Theme.Fonts.body(14))
                        }
                        .padding(.vertical, 6)
                    }
                }
                .padding(.top, 10)

                EyebrowLabel("Follow-ups they ask next").padding(.top, 22)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(question.followUps, id: \.self) { followUp in
                        Text("— \(followUp)").font(Theme.Fonts.body(14)).foregroundStyle(Theme.Colors.neutral800)
                    }
                }
                .padding(.top, 10)

                if let reviewQueue {
                    reviewActions(queue: reviewQueue)
                }
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
    }

    /// "Card again" re-rates the current card at its existing rating, refreshing `dueDate` to
    /// tomorrow without relabeling a `.missed` card as `.shaky` (both map to the same +1-day
    /// offset). "Next review" advances the queue in place; on the last card, it pops back to the
    /// bank — "Review now" is a closed loop over exactly this session's weak cards.
    @ViewBuilder
    private func reviewActions(queue: [InterviewQuestion]) -> some View {
        HStack(spacing: 12) {
            Button {
                guard let uid = authRepo.currentUser?.uid else { return }
                let existingRating = repo.reviewState[question.id]?.rating ?? .shaky
                Task { await repo.recordSession([question.id: existingRating], for: uid) }
            } label: {
                Text("Card again").font(.system(size: 15.5))
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
            }
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.Colors.divider))

            Button {
                let nextIndex = (currentQueueIndex ?? indexInQueue) + 1
                currentQueueIndex = nextIndex
                if nextIndex < queue.count {
                    question = queue[nextIndex]
                } else {
                    dismiss()
                }
            } label: {
                Text("Next review").font(.system(size: 15.5))
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
            }
            .background(Theme.Colors.accent).foregroundStyle(Theme.Colors.bg)
        }
        .padding(.top, 26)
    }
}

#Preview {
    let repo = InterviewRepository.preview()
    return NavigationStack {
        InterviewQuestionDetailView(question: repo.questions[0], reviewQueue: [repo.questions[0]], indexInQueue: 0)
    }
    .environment(repo)
    .environment(AuthRepository(isPreview: true, signedIn: true))
}
```

- [ ] **Step 2: Run `xcodegen generate`**

```bash
xcodegen generate
```

- [ ] **Step 3: Build the full app target**

```bash
xcodebuild -scheme SwiftUp -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -30
```
Expected: `** BUILD SUCCEEDED **` (this is the first full build since Task 6 added `SessionSummaryView`'s forward references).

- [ ] **Step 4: Run the full test suite**

```bash
xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -60
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add SwiftUp/Features/InterviewPrep/InterviewQuestionDetailView.swift
git commit -m "$(cat <<'EOF'
Turn interview question detail into the review-queue screen

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013qjjTWqmcJt7Z6N6odvUkp
EOF
)"
```

---

## Task 8: `InterviewBankView` — go live

Final integration: wires the user-state load, real reviewed counts, and switches category-row navigation from the old direct-to-article flow to the new flashcard session. Once this lands, the whole refactored flow is reachable from the Prep tab.

**Files:**
- Modify: `SwiftUp/Features/InterviewPrep/InterviewBankView.swift`

**Interfaces:**
- Consumes: `InterviewRepository.loadUserState(for:)` (Task 1/5), `InterviewRepository.hasBeenReviewed(_:)` (Task 5), `FlashcardSessionView(category:level:repo:)` (Task 6).

- [ ] **Step 1: Add the `authRepo` environment and extend `.task`**

In `SwiftUp/Features/InterviewPrep/InterviewBankView.swift`, add alongside the existing `@Environment(InterviewRepository.self) private var repo`:

```swift
    @Environment(AuthRepository.self) private var authRepo
```

Replace the `.task` modifier:

```swift
        .task {
            async let content: Void = repo.categories.isEmpty ? repo.load() : ()
            if let uid = authRepo.currentUser?.uid {
                async let userState: Void = repo.loadUserState(for: uid)
                _ = await (content, userState)
            } else {
                _ = await content
            }
        }
```

- [ ] **Step 2: Make the category row's count real, and navigate into the session**

Replace `categoryRow(_:isLast:)`:

```swift
    @ViewBuilder
    private func categoryRow(_ category: InterviewCategoryContent, isLast: Bool) -> some View {
        let questions = category.questions(for: levelFilter)
        if !questions.isEmpty {
            NavigationLink {
                FlashcardSessionView(category: category.name, level: levelFilter, repo: repo)
            } label: {
                RuledRow(showBottomRule: isLast, minHeight: 56) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.name).font(Theme.Fonts.heading(16.5))
                        Text(reviewedLabel(for: questions))
                            .font(.system(size: 12.5)).foregroundStyle(Theme.Colors.neutral700)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        } else {
            RuledRow(showBottomRule: isLast, minHeight: 56) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.name).font(Theme.Fonts.heading(16.5))
                        .foregroundStyle(Theme.Colors.neutral400)
                    Text(emptyLabel(for: levelFilter))
                        .font(.system(size: 12.5)).foregroundStyle(Theme.Colors.neutral400)
                }
                Spacer()
            }
        }
    }

    private func reviewedLabel(for questions: [InterviewQuestion]) -> String {
        let reviewed = questions.filter(repo.hasBeenReviewed).count
        return "\(reviewed) of \(questions.count) reviewed"
    }
```

(This removes `countLabel(for:)`, now unused — delete that method.)

- [ ] **Step 3: Run `xcodegen generate`**

```bash
xcodegen generate
```

- [ ] **Step 4: Build the full app target**

```bash
xcodebuild -scheme SwiftUp -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -30
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Run the full test suite**

```bash
xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -60
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add SwiftUp/Features/InterviewPrep/InterviewBankView.swift
git commit -m "$(cat <<'EOF'
Route interview prep categories into flashcard sessions

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013qjjTWqmcJt7Z6N6odvUkp
EOF
)"
```

---

## Task 9: Deploy Firestore rules and manual end-to-end verification

No new Swift code — deploys the rule changes from Tasks 1 and 5, then verifies the full flow against real Firestore per spec §10 ("Firestore reads/writes aren't unit-testable in this project — verified by manual run-through").

**Files:** none (deploy + manual verification only).

- [ ] **Step 1: Deploy the updated Firestore rules**

```bash
firebase deploy --only firestore:rules
```
Expected: deploy succeeds, confirming the `bookmarks` and `flashcardReviews` match blocks are live.

- [ ] **Step 2: Run the app on a signed-in simulator/device and complete one full flashcard session**

Manual steps:
1. Open the Prep tab, tap a category with more than one question at the selected level.
2. Flip through all cards, rating a mix of Missed/Shaky/Nailed (rate at least one Missed or Shaky so the review list is non-empty).
3. Confirm the session summary shows the right nailed/shaky/missed counts and the review list.
4. In the Firebase console (or `firebase firestore:get`), confirm `users/{uid}/flashcardReviews/{questionId}` documents exist for every rated card, with `dueDate` 4 days out for `nailed` and 1 day out for `missed`/`shaky`.

- [ ] **Step 3: Verify the review loop**

Tap "Review now", confirm the rating tag and "Card again"/"Next review" buttons appear, tap through to the end of the queue, confirm it returns to the bank. Confirm the bank's "N of M reviewed" count went up for the category just rated.

- [ ] **Step 4: Verify bookmarking**

From the review-queue detail screen, tap the bookmark star; confirm `users/{uid}/bookmarks/{questionId}` is created. Tap again; confirm the document is deleted (not set to `false`). Relaunch the app and confirm the star's state survives (proves `loadUserState` is wired from Task 8).

- [ ] **Step 5: Note the result**

No commit for this task — it's verification only. If any step fails, open a follow-up fix as its own small task rather than amending an already-committed task.
